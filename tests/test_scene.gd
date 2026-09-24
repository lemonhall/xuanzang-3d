extends Node

## 场景跑法的 headless 测试。
##
## 必须用场景（`godot --headless --path . tests/test_scene.tscn`），
## 不能用 `--script`：后者不会注册 autoload，引用 GameState 的脚本连编译都过不了。

var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	print("=== 西行·玄奘 3D / 场景测试 ===")
	_test_dune_field()
	_test_ridge_orientation()
	_test_water_model()
	_test_storm_model()
	_test_ground_following()
	_test_mirage_detail()
	await _test_mirage_keeps_distance()
	await _test_scene_is_outdoors()
	await _test_main_scene_assembles()
	_report()


func check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS  %s" % message)
	else:
		_failures.append(message)
		print("  FAIL  %s" % message)


# ---------------------------------------------------------------------------


func _test_dune_field() -> void:
	print("[沙丘高度场]")
	var field := DuneField.new()

	var lowest := INF
	var highest := -INF
	for i in range(400):
		var x := float(i) * 7.0 - 1400.0
		var h := field.sample(x, x * 0.37)
		lowest = minf(lowest, h)
		highest = maxf(highest, h)

	check(highest > 8.0, "沙丘有实际高度（最高 %.1f m）" % highest)
	check(lowest > -40.0 and highest < 60.0, "高度落在合理区间（%.1f .. %.1f）" % [lowest, highest])

	# 确定性：同一坐标两次采样必须一致，否则地形没法复现
	check(
		is_equal_approx(field.sample(123.4, -56.7), field.sample(123.4, -56.7)),
		"同一坐标采样可复现"
	)

	# 连续性：1 m 步长的高度差不能跳变
	var max_jump := 0.0
	var x2 := -200.0
	var prev := field.sample(x2, 40.0)
	while x2 < 200.0:
		x2 += 1.0
		var h := field.sample(x2, 40.0)
		max_jump = maxf(max_jump, absf(h - prev))
		prev = h
	check(max_jump < 3.0, "沙面连续，无跳变（1 m 内最大差 %.2f m）" % max_jump)


func _test_ridge_orientation() -> void:
	print("[脊线方向]")
	var field := DuneField.new()

	# 脊线沿 Z 延伸、沿 X 排列：沿 X 走会遇到起伏，沿 Z 走基本是顺脊平走。
	var x_variation := 0.0
	var z_variation := 0.0
	var base := field.sample(0.0, 0.0)
	for i in range(1, 60):
		var d := float(i) * 2.0
		x_variation += absf(field.sample(base + d, 0.0) - base)
		z_variation += absf(field.sample(0.0, d) - base)

	check(
		x_variation > z_variation * 2.0,
		"沿 X 的起伏明显大于沿 Z（%.0f vs %.0f）——相机要朝 ±X 看" % [x_variation, z_variation]
	)


func _test_water_model() -> void:
	print("[水囊]")
	GameState.reset()
	check(is_equal_approx(GameState.water, 1.0), "开局水囊是满的")

	GameState.reset()
	GameState.storm_intensity = 0.0
	GameState.tick(GameState.FULL_DRAIN_SECONDS * 0.5, 0.0)
	var half := GameState.water
	check(half > 0.4 and half < 0.6, "平静走一半时间，水剩约一半（%.2f）" % half)

	GameState.reset()
	GameState.storm_intensity = 0.0
	GameState.tick(GameState.FULL_DRAIN_SECONDS, 0.0)
	check(GameState.water <= 0.001, "走到见底")
	check(GameState.is_collapsed, "水尽即倒下")

	GameState.reset()
	GameState.storm_intensity = 1.0
	GameState.tick(60.0, 0.0)
	var storm_water := GameState.water

	GameState.reset()
	GameState.storm_intensity = 0.0
	GameState.tick(60.0, 0.0)
	var calm_water := GameState.water
	check(storm_water < calm_water, "沙暴中耗水更快（%.3f < %.3f）" % [storm_water, calm_water])

	GameState.reset()
	GameState.storm_intensity = 0.0
	GameState.tick(60.0, 0.0)
	var walk_water := GameState.water
	GameState.reset()
	GameState.storm_intensity = 0.0
	GameState.tick(60.0, 1.0)
	check(GameState.water < walk_water, "冲刺耗水更快")

	# 倒下之后不再继续扣水
	GameState.reset()
	GameState.tick(GameState.FULL_DRAIN_SECONDS * 2.0, 0.0)
	var dead_water := GameState.water
	GameState.tick(100.0, 1.0)
	check(is_equal_approx(dead_water, GameState.water), "倒下后水不再变化")


func _test_storm_model() -> void:
	print("[沙暴]")
	GameState.reset()
	var storm := Sandstorm.new()
	check(is_equal_approx(storm.intensity, 0.0), "初始强度为 0")

	storm.force_intensity(1.0)
	check(is_equal_approx(GameState.storm_intensity, 1.0), "强度写入 GameState")

	GameState.storm_intensity = 0.0
	var far := GameState.visibility_meters()
	GameState.storm_intensity = 1.0
	var near := GameState.visibility_meters()
	check(far > near * 5.0, "能见度随沙暴骤降（%.0f m → %.0f m）" % [far, near])

	# 阶段循环：推进足够长时间后必须回到平静
	var seen := {}
	for i in range(600):
		storm._advance_phase(1.0)
		seen[storm._phase] = true
	check(seen.size() == 4, "四个阶段都会出现（实际 %d 个）" % seen.size())
	storm.free()
	GameState.reset()


func _test_ground_following() -> void:
	print("[贴地]")
	var root := Node3D.new()
	add_child(root)

	var world := DesertWorld.new()
	world.ground_segments = 48
	world.ground_size = 320.0
	root.add_child(world)

	var player := Wanderer.new()
	player.world = world
	root.add_child(player)

	var x := 30.0
	var z := -12.0
	player.global_position = Vector3(x, 999.0, z)
	for i in range(90):
		player._physics_process(1.0 / 60.0)

	var expected := world.height_at(player.global_position.x, player.global_position.z)
	check(
		absf(player.global_position.y - expected) < 0.35,
		"玩家被沙面接住（y=%.2f，地面 %.2f）" % [player.global_position.y, expected]
	)
	check(
		player.eye_position().y > player.global_position.y,
		"视点高于脚底"
	)
	root.queue_free()


func _test_mirage_detail() -> void:
	print("[楼兰幻影]")
	var started := Time.get_ticks_msec()
	var mirage := Mirage.new()
	add_child(mirage)
	var build_ms := Time.get_ticks_msec() - started

	var parts := mirage.part_count()
	check(parts > 2000, "细节部件数足够（%d 个）" % parts)
	print("  （构建耗时 %d ms）" % build_ms)

	var instance := mirage.get_node_or_null("Loulan") as MeshInstance3D
	check(instance != null, "幻影 mesh 已建")
	if instance != null and instance.mesh != null:
		var arrays := instance.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		check(verts.size() > 20000, "合并后顶点数合理（%d）" % verts.size())

	# 高度必须撑得起"二十倍"，否则巨物感无从谈起
	check(Mirage.TOTAL_HEIGHT > 600.0, "幻影高 %.0f m" % Mirage.TOTAL_HEIGHT)

	mirage.set_presence(1.0)
	check(mirage.visible, "强度足够时幻影可见")
	mirage.set_presence(0.0)
	check(not mirage.visible, "强度归零时幻影隐藏")
	mirage.queue_free()


## 海市蜃楼的核心行为：**走不近**。
##
## 它是光的像，不是实体——玩家朝它走，它必须同步后退，那段距离永远不变。
## 这条断言守的就是这件事：一旦有人把幻影改回固定世界坐标，玩家走两百多米
## 就会穿模进城，错觉当场碎掉，而这个测试会立刻报红。
func _test_mirage_keeps_distance() -> void:
	print("[幻影走不近]")
	var scene: PackedScene = load("res://scenes/main.tscn")
	var instance: Node = scene.instantiate()
	add_child(instance)
	# 幻影的位置是在 main._process 里每帧重算的，得多等两帧它才就位
	for i in range(3):
		await get_tree().process_frame

	var player: Node3D = instance.get("player")
	var mirage: Node3D = instance.get("mirage")
	if player == null or mirage == null:
		check(false, "玩家或幻影缺失")
		instance.queue_free()
		return

	var before := _horizontal_gap(player, mirage)
	# 玩家朝幻影方向走 180 m——远超"走进去"所需的距离
	player.global_position += Vector3(180.0, 0.0, 0.0)
	for i in range(3):
		await get_tree().process_frame
	var after := _horizontal_gap(player, mirage)

	check(before > 150.0, "幻影在远处（初始 %.0f m）" % before)
	check(
		absf(after - before) < 20.0,
		"走了 180 m，距离几乎没变（%.0f m → %.0f m）" % [before, after]
	)
	check(after > 150.0, "走近之后依然够不着（%.0f m）" % after)
	instance.queue_free()


func _horizontal_gap(a: Node3D, b: Node3D) -> float:
	return Vector2(
		a.global_position.x - b.global_position.x,
		a.global_position.z - b.global_position.z
	).length()


## 这一关最容易走错的地方，是"巨物"和"室内"在视觉上只差一线：
## **把东西塞满画面，得到的是天花板。** 上一版幻影就在玩家前方 250 m、
## 城门楼顶到 63°，把头顶封了——玩家抬头看见的是穹顶。
##
## 所以这条测试守的是三条几何契约，它们同时也是"巨物感"的来源：
##   1. 横向量不出来 —— 城墙两端切出画外；
##   2. 头顶必须留空 —— 全场最高点也压在天顶之下；
##   3. 顶得看不见 —— 弥勒像的头顶要出画面（水平前视时看不到脸，得抬头）。
##
## 顺带守天空本身：天顶不能是暗的（暗天顶 = 天花板），而且抬头要有光源。
func _test_scene_is_outdoors() -> void:
	print("[幻影不是穹顶 / 天空不是天花板]")
	var scene: PackedScene = load("res://scenes/main.tscn")
	var instance: Node = scene.instantiate()
	add_child(instance)
	for i in range(3):
		await get_tree().process_frame

	var player: Node3D = instance.get("player")
	var mirage: Node3D = instance.get("mirage")
	var world: Node = instance.get("world")
	if player == null or mirage == null or world == null:
		check(false, "玩家 / 幻影 / 世界缺失")
		instance.queue_free()
		return

	var eye: Vector3 = player.call("eye_position")
	var origin: Vector3 = mirage.global_position
	var cam: Camera3D = player.call("camera")
	# 半视角：Godot 的 Camera3D.fov 是**垂直**视角
	var half_v := cam.fov * 0.5
	var half_h := rad_to_deg(atan(tan(deg_to_rad(half_v)) * cam.get_viewport().get_visible_rect().size.aspect()))

	# 1) 横向量不出来：正面城墙的角楼必须在半水平视角之外
	var corner := Vector3(
		origin.x - Mirage.CITY_HALF,
		origin.y + Mirage.WALL_H,
		origin.z + Mirage.CITY_HALF
	)
	var corner_azimuth := rad_to_deg(
		atan2(absf(corner.z - eye.z), corner.x - eye.x)
	)
	check(
		corner_azimuth > half_h,
		"城墙两端切出画外（角楼方位 %.0f° > 半视角 %.0f°）" % [corner_azimuth, half_h]
	)

	# 2) 头顶留空：全场最高点是弥勒的举身光尖，它也得压在天顶之下
	var statue_x := origin.x - Mirage.CITY_HALF - Mirage.STATUE_FRONT_OF_WALL
	var statue_z := origin.z + Mirage.STATUE_SIDE
	var halo_top := Vector3(
		statue_x, origin.y + Mirage.STATUE_HEIGHT * 1.22, statue_z
	)
	var halo_elev := _elevation(eye, halo_top)
	check(halo_elev < 50.0, "全场最高点也压在天顶之下（%.1f° < 50°）" % halo_elev)

	# 3) 顶看不见：像头出画面，必须抬头才看得见脸
	var head := Vector3(statue_x, origin.y + Mirage.STATUE_HEIGHT * 0.902, statue_z)
	var head_elev := _elevation(eye, head)
	check(
		head_elev > half_v,
		"水平前视时看不见像的脸（像头 %.1f° > 画面上沿 %.0f°）" % [head_elev, half_v]
	)

	# 城郭本体（主塔）不该比弥勒更高，主次一乱就只剩"一片高的东西"
	var tower_top := Vector3(
		origin.x - Mirage.CITY_HALF + Mirage.TOWER_BEHIND_WALL,
		origin.y + Mirage.TOTAL_HEIGHT,
		origin.z
	)
	var tower_elev := _elevation(eye, tower_top)
	check(
		tower_elev < head_elev,
		"主塔低于弥勒（%.1f° < %.1f°）——巨物要有唯一的顶点" % [tower_elev, head_elev]
	)

	# 天空：天顶不能是暗的。暗天顶 + 亮地平线 == 室内被地灯照亮的天花板。
	var env_node := instance.get_node_or_null("Desert/WorldEnvironment")
	check(env_node != null, "世界环境已建")
	if env_node != null:
		var env: Environment = env_node.environment
		var sky_mat: ShaderMaterial = env.sky.sky_material
		var zenith: Color = sky_mat.get_shader_parameter("zenith_color")
		var horizon: Color = sky_mat.get_shader_parameter("horizon_color")
		check(
			zenith.get_luminance() > horizon.get_luminance() * 0.55,
			"天顶不比地平线暗太多（%.2f vs %.2f）" % [zenith.get_luminance(), horizon.get_luminance()]
		)
		check(zenith.b > zenith.r, "天顶偏冷（b %.2f > r %.2f）——暖棕天顶就是顶棚" % [zenith.b, zenith.r])
		check(
			float(sky_mat.get_shader_parameter("sun_halo")) > 0.2,
			"抬头看得见太阳（散射晕 %.2f）" % float(sky_mat.get_shader_parameter("sun_halo"))
		)

	# 近处那道沙脊不能把画面下部吃掉：它一高，加上幻影就是"四面围合"
	var crest := 0.0
	for d in [20.0, 35.0, 50.0, 70.0, 100.0, 200.0, 340.0]:
		var px: float = player.global_position.x + d
		crest = maxf(
			crest,
			rad_to_deg(atan2(
				world.call("height_at", px, player.global_position.z) - eye.y, d
			))
		)
	check(crest < 9.0, "前方沙脊压在视线下方（最高 %.1f° < 9°）——地平线要打开" % crest)

	instance.queue_free()


func _elevation(from: Vector3, to: Vector3) -> float:
	return rad_to_deg(atan2(to.y - from.y, Vector2(to.x - from.x, to.z - from.z).length()))


func _test_main_scene_assembles() -> void:
	print("[主场景组装]")
	# 显式标注类型：load() 返回 Variant，用 := 推断 instance 会直接解析失败，
	# 而解析失败后 Godot 没有主场景可跑，进程会一直挂着不退出——
	# 表面看像死锁，实际是脚本根本没加载起来。
	var scene: PackedScene = load("res://scenes/main.tscn")
	check(scene != null, "main.tscn 可以加载")
	if scene == null:
		return

	var instance: Node = scene.instantiate()
	add_child(instance)
	# 地形是程序化生成的，给它一帧把 _ready 跑完
	await get_tree().process_frame

	check(instance.get("world") != null, "沙丘世界已建")
	check(instance.get("player") != null, "行者已建")
	check(instance.get("storm") != null, "沙暴系统已建")
	check(instance.get("hud") != null, "HUD 已建")
	var world: Node = instance.get("world")
	check(world != null and world.get("dune") != null, "高度场已就绪")
	instance.queue_free()


# ---------------------------------------------------------------------------


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("ALL TESTS PASSED (%d 项)" % _checks)
		get_tree().quit(0)
	else:
		print("FAILED (%d / %d)" % [_failures.size(), _checks])
		for failure in _failures:
			print("  - %s" % failure)
		get_tree().quit(1)
