class_name Wanderer
extends CharacterBody3D

## 第一人称行走 + 一颗会累的身体。
##
## 玄奘不是运动员：默认步速 2.6 m/s，冲刺 4.4 m/s，且冲刺烧体力更快。
## 贴地不用物理地形，直接对高度场采样——沙丘是连续光滑曲面，
## 采样比 trimesh 碰撞又快又稳，也不会在 4 m 网格上踩出棱角。
##
## 这一版多出来的东西全都是**身体**：走路的晃、喘气的起伏、倒下之后的侧翻、
## 临终那一眼和伸出去的那只手。四样都写在同一个 `_update_camera` 里，
## 因为它们抢的是同一台相机——分成四处各写一句 `_camera.position = ...`，
## 谁最后写谁赢，另外三样会静默失效。
## （这不是假设：上一版只有走路的晃，站着不动时镜头是钉死的，就是这么来的。）

@export var walk_speed := 2.6
@export var sprint_speed := 4.4
@export var acceleration := 9.0
@export var eye_height := 1.66
@export var mouse_sensitivity := 0.0022
@export_range(0.2, 1.0, 0.05) var pitch_limit := 1.35

## 倒下之后视线落到离地多高（米）。0.38 = 半撑着、脸几乎贴在沙面上。
##
## 不能给 0：视点贴到 0 会钻进沙丘的坡面里（沙面是起伏的），画面里会突然
## 出现一片穿模的沙；也不能给到站姿的一半——那读起来只是"蹲下了"。
const EYE_DOWN_HEIGHT := 0.38

## 倒下去时头连带滚转的角度。**不能给到 90°**：真侧躺下来，画面里的大佛也
## 跟着横过来，而这一格要的是"半撑着、抬头看佛"。24° 够读出"人已经歪了"，
## 又让地平线斜着挂在画面里——那点斜，就是"站不起来"的全部信息。
const FALL_ROLL_DEG := 24.0
## 躺定之后头转向佛要用的秒数。
const GAZE_SECONDS := 2.8
## 倒下时视线落在"佛的胸怀"再压低多少度。
##
## 抬着看（正值）会把画面下缘抬到沙丘以上，最后那一格就只剩佛和天，
## 人躺在哪儿、手从哪儿伸出来全丢了。压低 6°，画面下缘才留得住沙和手。
const GAZE_LIFT_DEG := -6.0
## 右臂伸出去用多久，以及比倒下晚多久开始。
## 人先倒下去，手才跟着抬起来——反过来就成了"他在打人"。
const REACH_SECONDS := 3.2
const REACH_DELAY := 0.4

# ---------------------------------------------------------------------------
# 步态：一脚一步地算
#
# 上一版是两条正弦叠出来的——需求方的原话："左摇右摆的感觉太过了……
# 摇摆也不够随机，太机械了"。两条都对，而且是同一个原因：**正弦波天生就是
# 周期性的、天生就是对称的**，而人走路两样都不是。
#
# 沙丘里的走法更具体：
#   1. 脚下**陷**，不是左右摇。沙是软的，每一步踩下去先沉一下，这是"沙地"
#      在第一人称里最直接的读数。上一版这一项只有 5 cm 的上下，却给了
#      3.4 cm 的左右 + 2.6° 的滚转——**那一版把"陷"和"摇"的轻重搞反了**。
#   2. 两只脚的步子不一样大。真人走路左右是不对称的，完全对称的摆动
#      一眼就是机器；
#   3. 频率也不固定。踩到软沙会拖一下，踩到脊上会轻快一点。
#
# 所以：沉降/左右/滚转/头的小转**每一步重取一次**，取值由"第几步"哈希出来。
# 哈希而不是 randf——同样的输入必须走出同样的路，否则截图探针每次拍出来的
# 构图都不一样（"同参数出同图"是探针的第一条契约）。
# ---------------------------------------------------------------------------

## 一步跨多远（米）。沙地上步子偏小：2.6 m/s 时约两步一秒。
const STRIDE := 1.30
## 每一步陷下去多深（米），以及它在步与步之间的变化。
const SINK_BASE := 0.030
const SINK_VARY := 0.026
## 左右摆的幅度（米）。真实走路头部左右摆只有两三厘米，这里连变化一起
## 压在 2.2 cm 以内——**而且是把下面那项平衡漂移也算在预算里的**：
## 只算每步的摆、不算漂移，实测就会漏掉 1 cm（[步态] 那条测试当场抓住过）。
const SWAY_BASE := 0.007
const SWAY_VARY := 0.011
## 滚转幅度（度）。**这一项才是"左摇右摆"的主犯**：镜头一歪，整个世界都歪。
## 1.4° 顶格，比上一版的 2.6° 收了一半。
const ROLL_BASE := 0.5
const ROLL_VARY := 0.9

var world: DesertWorld

## 外部（沙暴）叠加到玩家身上的推力，米/秒。
var external_push := Vector3.ZERO

## 临终那一眼要看、要伸手去够的那个**世界坐标**，由 main 每帧写入（佛的胸怀）。
## Wanderer 因此不需要认识 Mirage：它只知道"有一个点值得我最后伸一次手"。
var focus_point := Vector3.ZERO

var _yaw := 0.0
var _pitch := 0.0
var _breath_phase := 0.0
var _breath_lean := 0.0
var _clock := 0.0
## 步态：第几步、这一步走到哪儿了、这一步的四个参数。
var _step_index := 0
var _step_phase := 0.0
var _step_sink := SINK_BASE
var _step_lateral := 0.0
var _step_roll := 0.0
var _step_yaw := 0.0
var _prev_lateral := 0.0
var _prev_roll := 0.0
## 十几步才走完一次的平衡漂移（-1..1）：人在沙里走，重心一直在慢慢挪。
var _drift := 0.0
## 平滑后的实际位移。每一步的参数是跳变的，直接赋值镜头会顿一下。
var _bob_now := 0.0
var _sway_now := 0.0
var _roll_now := 0.0
var _wobble_now := 0.0
## 倒下那一瞬的朝向。转头从它出发，而不是从"当前值"出发——
## 后者会让每一帧都重新起步，头贴着目标慢慢爬。
var _gaze_yaw := 0.0
var _gaze_pitch := 0.0
var _gaze_started := false
var _camera: Camera3D
var _hand: ReachingHand


func _ready() -> void:
	_camera = Camera3D.new()
	_camera.name = "Eyes"
	_camera.current = true
	_camera.fov = 68.0
	# far 必须把幻影装下。默认的 4000 m 会在城郭中间切一刀：
	# 幻影的近墙 1.9 km、远墙 6.9 km，后半个城本来该"先褪色再消失"
	# （见 mirage.gdshader 的 haze），结果被远裁剪面直接切掉，留下一道硬边。
	# 远处的淡出交给幻影自己的空气衰减，不交给裁剪面。
	_camera.far = 12000.0
	_camera.position = Vector3(0.0, eye_height, 0.0)
	add_child(_camera)

	# 右手挂在相机上：它的局部坐标就是**眼睛坐标**，姿态不用再过一遍 yaw/pitch。
	_hand = ReachingHand.new()
	_hand.name = "RightHand"
	_camera.add_child(_hand)
	_begin_step(0)

	# headless 测试里没有窗口系统，抓鼠标会报错
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	# Esc 一直有效：倒下了也得能把鼠标放出来关窗口。
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)
		return
	# 倒下之后不再接受视线输入。人已经躺下了，鼠标不该还能替他把头拧过去；
	# 顺带也让"临终那一格画面"是确定的（截图探针 --collapsed 就靠这个）。
	if GameState.is_collapsed:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clampf(
			_pitch - event.relative.y * mouse_sensitivity, -pitch_limit, pitch_limit
		)


func _physics_process(delta: float) -> void:
	var down := GameState.is_collapsed

	var wish := Vector3.ZERO if down else _wish_direction()
	var wants_sprint := (
		(not down) and Input.is_action_pressed("sprint") and wish.length() > 0.01
	)
	var target_speed := sprint_speed if wants_sprint else walk_speed

	var desired := wish * target_speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.lerp(desired, clampf(acceleration * delta, 0.0, 1.0))
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if not down:
		# 沙暴推力：不等于输入，是被风推着走的部分。倒下之后风推不动他了。
		global_position += external_push * delta
	global_position += Vector3(velocity.x, 0.0, velocity.z) * delta
	_stick_to_sand(delta)

	_clock += delta
	if down:
		_turn_to_focus(delta)
	rotation.y = _yaw

	# 相机本帧的变换要先落地，手才能读到"眼睛在哪、佛在哪"。
	# 不 force 的话拿到的是上一帧的全局变换——1.8 m/s 时不明显，
	# 但倒下那一帧镜头正在"沉下去 + 侧翻"，手会明显甩一下。
	_camera.force_update_transform()
	_update_camera(delta, horizontal.length(), down)


func _wish_direction() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input.length() < 0.01:
		return Vector3.ZERO
	# 只在水平面内移动：抬头不会让人飞出去
	var forward := -transform.basis.z
	var right := transform.basis.x
	forward.y = 0.0
	right.y = 0.0
	return (right * input.x + forward * -input.y).normalized()


func _stick_to_sand(delta: float) -> void:
	if world == null:
		return
	var ground := world.height_at(global_position.x, global_position.z)
	# 指数平滑：比直接赋值稳，遇陡坡也不会一帧跳上去
	var blend := 1.0 - exp(-20.0 * delta)
	global_position.y = lerpf(global_position.y, ground, blend)


## 临终那一眼：头慢慢转向佛。
##
## 走的是"倒下那一瞬的朝向 → 佛"的**固定时长缓动**，不是指数逼近：
## 指数逼近永远差最后一点点，而且目标每帧都在动时会爬得没完没了。
## 2.8 秒是"一个快没力气的人把头转过来"的时间——再快像甩头，再慢像没动。
func _turn_to_focus(delta: float) -> void:
	if focus_point == Vector3.ZERO:
		return
	var to := focus_point - eye_position()
	var flat := Vector2(to.x, to.z)
	if flat.length() < 1.0:
		return
	var want_yaw := atan2(-to.x, -to.z)
	var want_pitch := clampf(
		atan2(to.y, flat.length()) + deg_to_rad(GAZE_LIFT_DEG), -1.2, pitch_limit
	)
	if not _gaze_started:
		_gaze_started = true
		_gaze_yaw = _yaw
		_gaze_pitch = _pitch
	var t := clampf(GameState.collapse_elapsed / GAZE_SECONDS, 0.0, 1.0)
	var ease := t * t * (3.0 - 2.0 * t)
	_yaw = _gaze_yaw + angle_difference(_gaze_yaw, want_yaw) * ease
	_pitch = lerpf(_gaze_pitch, want_pitch, ease)


## 视点的全部运动：走路的晃、喘气的起伏、风吹、倒下侧翻。四样叠在一起算，
## 最后只写一次 `_camera.position / rotation`。
func _update_camera(delta: float, speed: float, down: bool) -> void:
	var t := GameState.collapse_elapsed
	var fall := GameState.fall_at(t)

	# --- 走路：一脚一步踩出来的晃 ---
	var moving := speed > 0.15 and not down
	var gait := clampf(speed / walk_speed, 0.0, 2.0) if moving else 0.0
	var bob := 0.0
	var lateral := 0.0
	var roll := 0.0
	var wobble := 0.0
	var nod := 0.0
	if moving:
		_step_phase += delta * speed / STRIDE
		while _step_phase >= 1.0:
			_step_phase -= 1.0
			_begin_step(_step_index + 1)
		# 落脚最深、抬到中段回正：**每一步**一个下沉（左右摆才是两步一个来回）。
		bob = -_step_sink * (0.5 + 0.5 * cos(TAU * _step_phase)) * gait
		# 左右这条要**跨过整步**才换到另一侧：脚一落，身子压向那只脚。
		var blend := smoothstep(0.0, 0.6, _step_phase)
		lateral = (lerpf(_prev_lateral, _step_lateral, blend) + _drift * 0.004) * gait
		roll = lerpf(_prev_roll, _step_roll, blend) * gait
		wobble = _step_yaw * gait
		nod = deg_to_rad(0.9) * gait * cos(TAU * _step_phase)

	# 每一步的参数是**跳变**的（这一步比上一步陷得深、摆得多）。直接赋值，
	# 镜头会在小数点上顿一下；用一个约 0.1 秒的时间常数追上目标，
	# 既保住了"每一步都不一样"，又不会抖。停步时目标回 0，也靠它平滑收住。
	var follow := clampf(delta * 10.0, 0.0, 1.0)
	_bob_now = lerpf(_bob_now, bob, follow)
	_sway_now = lerpf(_sway_now, lateral, follow)
	_roll_now = lerpf(_roll_now, roll, follow)
	_wobble_now = lerpf(_wobble_now, wobble, follow)

	# --- 喘气：站着也在喘 ---
	# 频率和幅度都从 GameState 取（模型层）。0.24 Hz 起步、0.90 Hz 顶格：
	# 越累喘得越快越深，而且**前后倾**要跟着一起走——只上下动像电梯。
	var rate := GameState.pant_rate(GameState.stamina, t)
	_breath_phase += TAU * rate * delta
	var depth := GameState.pant_depth(GameState.stamina, t)
	var chest := sin(_breath_phase) * depth
	var lean := cos(_breath_phase) * depth * 0.55
	_breath_lean = lerpf(_breath_lean, lean, clampf(delta * 6.0, 0.0, 1.0))

	# --- 沙暴：风推在镜头上。躺下之后就没有了 ---
	var storm := clampf(GameState.storm_intensity, 0.0, 1.0) * (1.0 - fall)
	var gust := (sin(_clock * 5.7) * 0.010 + sin(_clock * 2.3 + 1.0) * 0.006) * storm

	# --- 倒下：沉到沙面 + 侧翻 ---
	var eye_y := lerpf(eye_height + _bob_now + chest, EYE_DOWN_HEIGHT, fall)
	var head_x := _sway_now + gust + 0.34 * fall
	var cam_pitch := _pitch + nod + deg_to_rad(2.0) * fall
	var cam_roll := _roll_now + deg_to_rad(FALL_ROLL_DEG) * fall
	_camera.position = Vector3(head_x, eye_y, -_breath_lean)
	_camera.rotation = Vector3(cam_pitch, _wobble_now, cam_roll)

	# --- 临终那一只手 ---
	var reach := 0.0
	if down:
		reach = clampf((t - REACH_DELAY) / REACH_SECONDS, 0.0, 1.0)
		reach = reach * reach * (3.0 - 2.0 * reach)
	_hand.update_pose(focus_point, reach, delta)


## 开始第 k 步：这一步的沉降、左右偏移、滚转、头的小转，全由 k 哈希出来。
##
## **脚是交替的**（奇偶步压向不同的一侧），所以左右和滚转带一个 ±1；
## 幅度每一步都不同——真人两只脚的步子本来就不一样大。
func _begin_step(k: int) -> void:
	_step_index = k
	var foot := -1.0 if (k % 2) == 0 else 1.0
	_prev_lateral = _step_lateral
	_prev_roll = _step_roll
	_step_sink = SINK_BASE + SINK_VARY * _hash01(float(k) * 1.7)
	_step_lateral = foot * (SWAY_BASE + SWAY_VARY * _hash01(float(k) * 3.1 + 11.0))
	_step_roll = foot * deg_to_rad(ROLL_BASE + ROLL_VARY * _hash01(float(k) * 5.3 + 23.0))
	_step_yaw = deg_to_rad((_hash01(float(k) * 7.9 + 41.0) - 0.5) * 1.2)
	# 十几步才走完一次的漂移：0.4 的追赶系数让它是"慢慢挪"，不是每步重抽。
	_drift = lerpf(_drift, _hash01(float(k) * 2.3 + 7.0) * 2.0 - 1.0, 0.4)


## 第 k 步的第 n 个参数，0..1。确定性哈希，不是随机数——见文件头那段说明。
static func _hash01(key: float) -> float:
	return fposmod(sin(key * 12.9898 + 4.1) * 43758.5453, 1.0)


## 身体复位（重走一次时用）。相位、速度、那只手一起回零。
func reset_body() -> void:
	velocity = Vector3.ZERO
	external_push = Vector3.ZERO
	_breath_phase = 0.0
	_breath_lean = 0.0
	_clock = 0.0
	_step_phase = 0.0
	_step_lateral = 0.0
	_step_roll = 0.0
	_step_yaw = 0.0
	_prev_lateral = 0.0
	_prev_roll = 0.0
	_drift = 0.0
	_bob_now = 0.0
	_sway_now = 0.0
	_roll_now = 0.0
	_wobble_now = 0.0
	_begin_step(0)
	_gaze_started = false
	_pitch = 0.0
	_camera.position = Vector3(0.0, eye_height, 0.0)
	_camera.rotation = Vector3.ZERO
	_hand.visible = false


## 当前伸出去多少（0..1）。测试和截图探针用它问"这会儿手到哪儿了"。
func reach_amount() -> float:
	if not GameState.is_collapsed:
		return 0.0
	var raw := clampf(
		(GameState.collapse_elapsed - REACH_DELAY) / REACH_SECONDS, 0.0, 1.0
	)
	return raw * raw * (3.0 - 2.0 * raw)


func hand() -> ReachingHand:
	return _hand


func camera() -> Camera3D:
	return _camera


## 眼睛所在的世界坐标。
func eye_position() -> Vector3:
	return _camera.global_position


## 当前水平速度（米/秒），用于体力消耗与里程统计。
func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## 设定朝向。main 用它把玩家摆成面朝沙丘层叠的方向。
func set_yaw(value: float) -> void:
	_yaw = value
	rotation.y = _yaw
