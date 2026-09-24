extends Node3D

## 组装一关：沙漠 + 行走的人 + 天气 + HUD。
##
## 全部用代码建，main.tscn 里只有一个根节点。理由和 Blender 端一样：
## 程序化的东西写在代码里才能一行改全局，手拉节点反而更难维护。

## 开局朝向（弧度）。绕 Y 轴 -90° 时视线指向 +X——
## 沙丘脊线沿 Z 延伸，只有朝 ±X 看才看得到一道道叠过来的沙丘。
const START_YAW := -PI * 0.5

var world: DesertWorld
var player: Wanderer
var storm: Sandstorm
var hud: Hud
var post: PostProcess
var mirage: Mirage

## 幻影的**正面城墙**保持在玩家前方 MIRAGE_FRONT_WALL 米处——**它走不近**。
##
## 这是海市蜃楼区别于"远处有个模型"的唯一要点。它是光的像，不是实体；
## 玩家朝它走，它就该同步后退，那段距离永远不变。第一版把幻影钉在固定
## 世界坐标上，结果走两百多米就穿模进去了，错觉当场就碎。
##
## 摆位按"正面城墙"算，不是按城的中心：城墙在玩家前方 1400 m，城的中心
## 再往后推 CITY_HALF。偏移必须算对，否则城墙会跑到玩家背后，变成"站在城里"。
##
## 为什么是 1400 m，而不是上一版的 250 m（那一版是"贴脸放大"）：
##
## 上一版城墙离玩家只有 250 m，城郭横着切出画外、城门楼顶到 63°。角度上
## 它当然"装不下"，但玩家抬头看到的是**穹顶**——城墙像一圈护墙板，角楼的
## 攒尖顶像天花板的梁，光从地平线打上来像地面的灯槽。原因很直接：
## **围住视点和压住视点，在视觉上是同一件事，而"围"就等于"室内"。**
##
## 巨物的压迫感不来自"占满画面"，来自**量不出来**：
##   横向  城墙两端在 ±57°，半视角只有 48° —— 转到哪边都看不到头；
##   纵深  近墙 1.4 km、远墙 5.8 km，后半座城先褪色再消失；
##   纵向  主塔顶 32° 还在画面里，但上半截溶进天空，找不到顶。
## 三条同时成立时它才"大到量不出来"，而头顶 30° 以上始终是干净的天。
## 远端有多远由幻影自己的空气衰减管（它关掉了 Godot 的雾，见 mirage.gdshader）。
const MIRAGE_FRONT_WALL := 1400.0


func _mirage_offset() -> Vector3:
	return Vector3(MIRAGE_FRONT_WALL + Mirage.CITY_HALF, 0.0, 30.0)

var _time := 0.0
var _mirage_height := 0.0


func _ready() -> void:
	GameState.reset()

	world = DesertWorld.new()
	world.name = "Desert"
	add_child(world)

	player = Wanderer.new()
	player.name = "Wanderer"
	player.world = world
	add_child(player)
	# 出生点选在"前方有坡、远处有脊"的位置，而不是原点：
	# 站在脊顶平视只能看到一片平沙，第一眼就把气氛丢了。
	var start := world.dune.find_viewpoint()
	player.global_position = Vector3(
		start.x, world.height_at(start.x, start.y), start.y
	)
	player.set_yaw(START_YAW)

	storm = Sandstorm.new()
	storm.name = "Sandstorm"
	storm.world = world
	storm.player = player
	add_child(storm)

	post = PostProcess.new()
	post.name = "PostProcess"
	add_child(post)

	mirage = Mirage.new()
	mirage.name = "Mirage"
	add_child(mirage)
	_mirage_height = world.height_at(player.global_position.x, player.global_position.z) + 10.0

	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)


func _process(delta: float) -> void:
	if player == null:
		return
	var exertion := clampf(player.horizontal_speed() / player.sprint_speed, 0.0, 1.0)
	GameState.tick(delta, exertion)
	GameState.add_distance(player.horizontal_speed() * delta)
	if post != null and storm != null:
		post.set_storm(storm.intensity)
	_time += delta
	_update_mirage(delta)


## 把幻影重新摆到玩家前方固定距离处。
##
## 高度跟着地形缓慢起伏（而不是硬贴沙面），否则玩家每翻一道沙丘，
## 幻影就跟着上下跳一次，那点"隔着热空气"的味道立刻没了。
func _update_mirage(delta: float) -> void:
	if mirage == null or player == null or world == null:
		return
	var offset := player.global_position + _mirage_offset()
	var ground := world.height_at(offset.x, offset.z) + 10.0
	_mirage_height = lerpf(_mirage_height, ground, 1.0 - exp(-1.2 * delta))
	mirage.global_position = Vector3(offset.x, _mirage_height, offset.z)
	mirage.set_camera_position(player.eye_position())
	mirage.set_presence(_mirage_presence())


## 幻影的浓度由"渴"和沙暴共同决定。
##
## 不是按时间表演出：渴是真实存在的（水囊在倒数），沙暴是真实存在的，
## 玩家能隐约意识到"我越难受，它越清楚"——这比单纯定时出现可怕得多。
## 保底 0.28 是让第一次抬头就能看见，否则玩家根本不知道有这东西。
func _mirage_presence() -> float:
	var thirst := 1.0 - GameState.water
	return clampf(
		0.28 + thirst * 0.7 + GameState.storm_intensity * 0.6, 0.0, 1.0
	)
