extends Node

## 影片录制用的入口场景。
##
## 和 capture.gd 的区别：它不截图、也不退出——画面交给 `--write-movie` 去录，
## 录制长度交给 `--quit-after`。它只负责把场景准备好：让沙暴起来、体力见底，
## 这样幻影是以"最该出现"的状态被录下来，而不是开局那种淡到几乎看不见。
##
##   godot --path . --write-movie D:\out.avi --quit-after 450 --fixed-fps 30 tools/record.tscn
##
## 参数（`--` 之后的才是给这个脚本的）：
##   --walk <米/秒>  一直往前走。**走的是真实的物理**（只写 velocity，不搬坐标），
##                   所以风推得动他——横风一刮就偏，偏了才会拐回来。
##   --peak          起手就把沙暴钉在"压顶"，而不是慢慢起风。
##   --look          抬头看佛头的时间表（见 LOOK_KEYS）。不填就是一直平视。

var _main: Node
var _elapsed := 0.0
var _walk_speed := 0.0
var _peak := false
var _look := false

## 镜头时间表（秒 → 俯仰角，度）。中间按 smoothstep 过渡：
## 人抬头是"先慢、后快、再收住"，线性插值读起来是机械臂。
##
## **为什么写在工具里、不写进游戏**：这是镜头调度，不是玩法。玩法里抬头只由
## 鼠标决定；多一条自动时间表，玩家就会觉得有人在抢他的脖子。
##
## ### 一镜到底的分镜（配合 BGM 的实测结构排的）
##
## 音乐《壁上观》剪辑版 74 s 循环，**通篇是一堵音墙**（-8~-12 dB），
## 唯一的结构点在 **34.5~35.5 s 掉下去（-20→-24 dB）、36 s 撞回来**——
## 就是需求方说的"36 秒才算高潮"。所以整条片子按这个点倒排：
##
##   | 时刻 | 画面 | 声音 |
##   |---|---|---|
##   | 0~5 s | 平视，佛在正前方，走着 | 曲子从 0.4 s 的静音里起拍 |
##   | 4 s | 「四远茫茫，莫知所指。」 | |
##   | 5~8.2 s | **第一次抬头**（→60°）：看佛头 + 举身光那一圈 | |
##   | 11.2~13.6 s | 低头，继续走 | |
##   | ~14 s | 「乏水草，多热风。」 | |
##   | 17.6~21 s | **第二次抬头**（→52°，抬得更慢）：换构图，多出肩膀和城 | |
##   | 24.4~26 s | 只落回 12°——**他再没有真正低下头** | |
##   | ~26.5 s | 腿软、侧倒；头自己转向佛的胸怀（_turn_to_focus，2.8 s） | |
##   | 31.7~36 s | 眼睑合拢（5.5 s）；音乐在 35 s 掉下去 | |
##   | **36.2 s** | **全黑的那一刻，音乐撞回来** | 高潮 |
##   | ~38.5 s | 题记 + 「R　再走一次」出现（倒下后 12 s） | |
##   | 48 s | 收（题记之后留 ~9 s 给人读） | 尾声 |
##
## 三条"宿命感"的规矩，都落在这个表里：
##   1. **一镜到底，没有剪辑**——命运不给你换镜头；
##   2. **只抬头看他，从不回头**。两次抬头是"看了一眼"到"看上瘾了"，
##      第二次之后镜头再没真正落回地平线；
##   3. **倒下之后头还在往上抬**——摔的是身体，视线一直往上够那尊佛。
##
## 60° 和 52° 两个数是照着佛头定的：像头在仰角 66.7°（见 main.gd 的注释），
## 竖直半视角 34°，所以镜头抬到 60° 出头，佛头落在画面中上部、
## 举身光那一圈从它背后绕过去；第二次抬到 52°，画面里多出肩膀和城。
##
## 倒下之后立刻停手（_apply_look 里判断 is_collapsed）：那时候头要自己转向佛，
## 再去写 `_pitch`，"临终那一格"就永远拍不到了。
const LOOK_KEYS: Array = [
	[0.0, 0.0],
	[5.0, 0.0],
	[8.2, 60.0],
	[11.2, 60.0],
	[13.6, 0.0],
	[17.6, 0.0],
	[21.0, 52.0],
	[24.4, 52.0],
	[26.0, 12.0],
]


func _ready() -> void:
	_parse_args()
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	_main = main_scene.instantiate()
	add_child(_main)
	# 录片期间不接受鼠标输入：桌面上的鼠标一动，`_pitch` 就被改掉，
	# 同一组参数两次录出来的片子不是一个机位（截图探针踩过同一个坑）。
	var pawn: Node = _main.get("player")
	if pawn != null:
		pawn.set_process_unhandled_input(false)

	# 起手就把沙暴推到"压顶"阶段，并把体力压低：幻影由"累 + 沙暴"共同驱动，
	# 两样都上来，它才会以接近最实的状态出现。
	var storm: Node = _main.get("storm")
	if storm != null:
		storm.set("_phase", 2 if _peak else 1)
		storm.set("_timer", 0.0 if _peak else 6.0)
	# 0.25 这个起点是**照着音乐倒排的**，不是随手压的：它最影响一件事——
	# 什么时候倒下。倒下的那一刻起，眼睑用 4.2 + 5.5 s 合拢，"全黑"因此落在
	# 倒下之后约 9.7 s。要让它正好压在 36 s 那句音乐撞回来上，倒下就得在
	# 26.3 s 左右；这局里体力实测掉约 0.0094/s（两遍录片量出来的），
	# 0.25 / 0.0094 ≈ 26.6 s。分镜表见 LOOK_KEYS 上面那一段——
	# 这一点点对齐，是整条片子里唯一"刻意"的地方。
	GameState.stamina = 0.25


func _process(delta: float) -> void:
	_elapsed += delta
	_drive_walk()
	if _look:
		_apply_look()


## 按时间表写相机的俯仰角。倒下之后立刻停手。
func _apply_look() -> void:
	var player: Node = _main.get("player")
	if player == null or GameState.is_collapsed:
		return
	player.set("_pitch", deg_to_rad(_look_pitch(_elapsed)))


## 时间表在第 t 秒的俯仰角（度）。相邻两个关键帧之间走 smoothstep。
func _look_pitch(t: float) -> float:
	var keys := LOOK_KEYS
	for i in range(keys.size() - 1):
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		var from_t := float(a[0])
		var to_t := float(b[0])
		if t < from_t:
			return float(a[1])
		if t <= to_t:
			var span := maxf(to_t - from_t, 0.0001)
			var x := clampf((t - from_t) / span, 0.0, 1.0)
			return lerpf(float(a[1]), float(b[1]), x * x * (3.0 - 2.0 * x))
	return float(keys[keys.size() - 1][1])


## 让玩家一直往前走。
##
## **只写 velocity，不搬坐标**：搬坐标会绕过沙暴的推力，录出来的片子就没有
## "被风吹偏"这件事——而这一段要给人看的就是这个。行者自己的 _physics_process
## 每帧都会把没有输入的速度往 0 拉，所以这里必须每帧写一次。
func _drive_walk() -> void:
	if _walk_speed <= 0.0 or GameState.is_collapsed:
		return
	var body := _main.get("player") as CharacterBody3D
	if body == null:
		return
	var forward := -body.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		return
	body.velocity = forward.normalized() * _walk_speed


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--walk" and i + 1 < args.size():
			_walk_speed = float(args[i + 1])
		elif args[i] == "--peak":
			_peak = true
		elif args[i] == "--look":
			_look = true
