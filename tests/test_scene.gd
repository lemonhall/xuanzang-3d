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
	_test_statue_readability()
	await _test_backlight()
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


## 弥勒必须**能被读成一个人**。上一版认不出来，不是细节不够，是下面三条
## 每一条都被违反了：光把像吞了、像被切片了、像和城共用一份料。
##
##   1. 举身光是**环**：洞的内径必须大于肩宽，头肩才从环里透出来。
##      "看起来像环"这种事要落到几何上：这里直接去数 halo 那个 mesh 的顶点，
##      断言**没有任何一个顶点落在环心附近**——洞里是空的，不是"画上去的洞"。
##   2. 像身的折射被压到城郭的十分之一：人形经不起切片。
##   3. 像身另拿一份材质，而且是加色的光背 + 混色的像身两份。
##
## 这一版又多了一条：**像身的几何不再是自己拼的**，而是一份归一化过的外部
## 白膜。所以这里连白膜本身也一起验收——高矮、落点、朝向三样都断言，
## 因为这三样正是 `blender/build_maitreya.py` 负责的事，而它们错了画面
## 不一定看得出来（转 180° 的像远看也"是尊像"）。
func _test_statue_readability() -> void:
	print("[弥勒可读性]")
	var h := Mirage.STATUE_HEIGHT
	# 倍率**现在就是设计态**：4 倍（需求方 2026-09-24 明确指定"上放大 4 倍
	# 的那个"）。它不再是"实验旋钮"，而是构图契约的一部分——
	# "整尊装进水平前视"那条旧约束随之反转成"像头必须冲出画面上沿、
	# 但抬头够得着"（见 _test_scene_is_outdoors 的第 3 条）。
	#
	# 这条断言守的仍然是"出厂态 == 设计态"：改倍率必须是**显式**的编辑，
	# 连带重解构图约束和这里的数字，不能靠某个调试开关悄悄留在代码里。
	check(
		is_equal_approx(Mirage.statue_scale, 4.0),
		"像身倍率出厂态是 4.0（当前 %.2f）——改了它必须重解构图约束"
		% Mirage.statue_scale
	)
	# 台座必须整块埋进沙里，而且不能埋过头。
	#
	# 下界守的是"台座还在"：白膜的 0~16% 是博物馆的方墩子（量法见
	# STATUE_PEDESTAL_RATIO 的注释），露在沙脊线上就会把比例尺泄露出去。
	# 上界守的是"人还站着"：埋掉三分之一个像，剩下的就不是一尊立像了。
	check(
		Mirage.STATUE_PEDESTAL_RATIO >= 0.12 and Mirage.STATUE_PEDESTAL_RATIO <= 0.25,
		"台座埋深在合理区间（%.0f%% 像高）" % (Mirage.STATUE_PEDESTAL_RATIO * 100.0)
	)
	check(
		Mirage.statue_top_y() > Mirage.STATUE_HEIGHT * 0.6 * Mirage.statue_scale,
		"埋掉台座之后人还站着（沙面之上 %.0f m）" % Mirage.statue_top_y()
	)
	check(
		ResourceLoader.exists(Mirage.STATUE_MESH_PATH),
		"白膜在（%s）" % Mirage.STATUE_MESH_PATH
	)
	check(
		Mirage.HALO_INNER_RATIO > Mirage.STATUE_SHOULDER_RATIO,
		"举身光的洞比肩宽（内径 %.3fh > 肩半宽 %.3fh）"
		% [Mirage.HALO_INNER_RATIO, Mirage.STATUE_SHOULDER_RATIO]
	)
	check(
		Mirage.STATUE_SHEAR < Mirage.CITY_SHEAR * 0.2,
		"像身的折射远小于城郭（%.0f m vs %.0f m）——人形不切片"
		% [Mirage.STATUE_SHEAR, Mirage.CITY_SHEAR]
	)

	var mirage := Mirage.new()
	add_child(mirage)

	var statue := mirage.get_node_or_null("Statue") as MeshInstance3D
	var halo := mirage.get_node_or_null("Halo") as MeshInstance3D
	var city := mirage.get_node_or_null("Loulan") as MeshInstance3D
	check(city != null, "城郭 mesh 已建")
	check(statue != null, "像身是一份独立的 mesh")
	check(halo != null, "举身光是一份独立的 mesh")

	if statue != null:
		var verts: PackedVector3Array = statue.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		check(
			verts.size() > 20000,
			"像身是白膜而不是几个基本体（%d 个顶点）" % verts.size()
		)
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for v: Vector3 in verts:
			lo.x = minf(lo.x, v.x)
			lo.y = minf(lo.y, v.y)
			lo.z = minf(lo.z, v.z)
			hi.x = maxf(hi.x, v.x)
			hi.y = maxf(hi.y, v.y)
			hi.z = maxf(hi.z, v.z)
		var size := hi - lo
		check(
			absf(size.y - h) < h * 0.01,
			"像高就是 STATUE_HEIGHT（%.0f m vs %.0f m）" % [size.y, h]
		)
		check(
			absf(lo.y) < h * 0.01,
			"脚底落在 y=0（%.1f m）——不然它会浮在沙面上或者埋进去" % lo.y
		)
		# 朝向：转 90° 会把宽和厚换个个儿。人是**横着宽、前后薄**的。
		check(
			size.z > size.x * 1.15,
			"横向宽于前后（%.0f m vs %.0f m）——朝向没转过 90°" % [size.z, size.x]
		)
		# 朝向：转 180° 时宽厚不变，只有"脸冲哪边"反了，所以要拿一个**不对称**
		# 的局部特征去量。
		#
		# 上一版量的是肚子（大肚弥勒的签名，0.50h~0.60h 往 -X 鼓 192 m）。
		# 犍陀罗立佛没有肚子，但头部更好用：这尊是**低头前倾**的姿态，整颗头
		# 都落在轴线之前——鼻尖最前到 -142 m，后脑只到 +36 m。转 180° 就互换。
		var head_front := INF
		var head_back := -INF
		for v: Vector3 in verts:
			if v.y > h * 0.90 and v.y < h * 0.99:
				head_front = minf(head_front, v.x)
				head_back = maxf(head_back, v.x)
		check(
			-head_front > head_back,
			"脸朝 -X（头最前 %.0f m > 后脑 %.0f m）——脸朝着玩家" % [-head_front, head_back]
		)

		# 白膜换过一次（大肚弥勒 → 犍陀罗立佛），像身从"最宽 0.284h"瘦到
		# "最宽 0.177h"。下面两条把这个变化**钉在几何上**，而不是钉在注释里：
		# 常量写错了画面上看不出来（环还是那个环），只有量 mesh 才知道。
		var half_at_halo := 0.0
		var widest_half := 0.0
		var widest_y := 0.0
		for v: Vector3 in verts:
			var half := absf(v.z)
			if half > widest_half:
				widest_half = half
				widest_y = v.y
			if absf(v.y - h * Mirage.HALO_CENTER_RATIO) <= h * 0.012:
				half_at_halo = maxf(half_at_halo, half)
		var shoulder := h * Mirage.STATUE_SHOULDER_RATIO
		check(
			absf(half_at_halo - shoulder) < shoulder * 0.15,
			"肩半宽常量和白膜对得上（常量 %.0f m vs 量得 %.0f m）" % [shoulder, half_at_halo]
		)
		# 环的洞要比像身**最宽处**还宽——不只是肩。这条才是"环不埋进身体"的
		# 真正条件，肩只是它在环心那一层的样子。
		check(
			h * Mirage.HALO_INNER_RATIO > widest_half,
			"环的洞比像身最宽处还宽（内径 %.0f m > 最宽半宽 %.0f m @ %.2fh）"
			% [h * Mirage.HALO_INNER_RATIO, widest_half, widest_y / h]
		)
		# 像身读的是文件，拿不到 _xform 的偏移；漏了这一步的话，像身会留在
		# 城中心、只有举身光挪到城墙前，屏幕上是一枚**空心的发光圆环**
		# （这是真踩过的，不是假设）。
		check(
			statue.position.is_equal_approx(mirage.statue_offset()),
			"像身和举身光共用同一根轴线（像身在 %s）" % statue.position
		)
		var material := statue.material_override as ShaderMaterial
		check(
			float(material.get_shader_parameter("dissolve_amount")) < 0.5,
			"像身几乎不溶解（%.2f < 0.5）——溶解会在像身上啃出洞"
			% float(material.get_shader_parameter("dissolve_amount"))
		)
		check(
			float(material.get_shader_parameter("veil")) <= 0.3,
			"逆光薄纱收着（%.2f ≤ 0.30）——糊过头剪影就没了"
			% float(material.get_shader_parameter("veil"))
		)
		check(city != null and material != city.material_override, "像身和城郭**不共用**材质")

	if halo != null:
		var material := halo.material_override as ShaderMaterial
		check(
			material.shader.code.contains("blend_add"),
			"举身光是加色材质（blend_add）——光只能加亮，不能遮挡"
		)
		# 环心必须是**空的**。这不是美学，是"像身从洞里透出来"的物理前提。
		#
		# 注意尺度：举身光的 mesh 是**按当前倍率拼的**（_design_halo 里
		# `var h := statue_height()`），所以这一段必须走 statue_height()。
		# 上面那个 `h` 是**白膜本身**的尺寸，4 倍时两者差 4 倍——
		# 拿错了环心就跑到洞里，这条断言会假绿。
		var halo_h := Mirage.statue_height()
		var center := Vector3(
			halo_h * Mirage.HALO_BEHIND_RATIO, halo_h * Mirage.HALO_CENTER_RATIO, 0.0
		)
		# 用像身自己的偏移助手，不在这里重抄一遍常数：像身和光环必须
		# 落在同一根轴线上，而这个"同一根"只应该有一个出处。
		center += mirage.statue_offset()
		var verts: PackedVector3Array = halo.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var nearest := INF
		for v: Vector3 in verts:
			nearest = minf(nearest, Vector2(v.y - center.y, v.z - center.z).length())
		var hole := Mirage.HALO_INNER_RATIO * halo_h
		check(
			nearest > hole - 2.0,
			"环心是空的（最近的顶点离环心 %.0f m ≥ 内径 %.0f m）" % [nearest, hole]
		)
		# 光背的**径向标尺**：几何铺到哪、亮带画在哪一圈、光焰伸多远。
		#
		# 三个数各写一遍就会歪，而"亮带跑到洞里去了"在屏幕上只像"没调好"，
		# 不像出错——所以这里把材质的 uniform 和几何常数**对账**。
		var ring_material := halo.material_override as ShaderMaterial
		var r_inner := float(ring_material.get_shader_parameter("ring_inner"))
		var r_core := float(ring_material.get_shader_parameter("ring_core"))
		var r_tip := float(ring_material.get_shader_parameter("ring_tip"))
		var r_sigma := float(ring_material.get_shader_parameter("ring_sigma"))
		check(
			r_inner < r_core and r_core < r_tip,
			"亮带落在几何里（内径 %.0f < 环心线 %.0f < 光焰尖 %.0f）" % [r_inner, r_core, r_tip]
		)
		check(
			absf(r_inner - halo_h * Mirage.HALO_INNER_RATIO) < 1.0
			and absf(r_tip - halo_h * Mirage.HALO_TIP_RATIO) < 1.0,
			"环的标尺按当前倍率算（内径 %.0f / 尖 %.0f）" % [r_inner, r_tip]
		)
		# 着色器是在盘面上按半径取数的，所以它拿到的环心必须**就是几何的环心**
		# （本地坐标，含 statue_offset）。差一点点，亮带就整体偏心——
		# 屏幕上表现为"环的一边粗一边细"，很容易被当成透视。
		var ring_center_uv := ring_material.get_shader_parameter("ring_center") as Vector2
		check(
			absf(ring_center_uv.x - center.y) < 1.0 and absf(ring_center_uv.y - center.z) < 1.0,
			"着色器的环心 = 几何的环心（%.0f/%.0f vs %.0f/%.0f）"
			% [ring_center_uv.x, ring_center_uv.y, center.y, center.z]
		)
		# 圆环面必须一直铺到光焰尖：铺短了，最外那截光焰会**凭空截断**——
		# 屏幕上是"一圈光的外面糊了一圈整齐的切口"，比不画还难看。
		var far := 0.0
		for v: Vector3 in verts:
			far = maxf(far, Vector2(v.y - center.y, v.z - center.z).length())
		check(
			absf(far - r_tip) < r_tip * 0.02,
			"圆环面一直铺到光焰尖（最远顶点 %.0f vs 标尺 %.0f）" % [far, r_tip]
		)
		# **这一条是这一版的核心**：亮带必须比上一版那根管子的管壁细得多。
		# 上一版的"环"是一根 0.07h 粗的 TorusMesh 管子，4 倍之后 302 m 宽，
		# 屏幕上是一条 110 px 的亮带——"塑料管"就是从那儿来的。
		# 亮带现在是 σ（高斯标准差），只要它还明显小于半个管壁，
		# 那一版的样子就回不来。
		check(
			r_sigma < halo_h * (Mirage.HALO_OUTER_RATIO - Mirage.HALO_INNER_RATIO) * 0.5,
			"亮带比上一版的管壁细（σ %.0f m < 半个管壁 %.0f m）"
			% [r_sigma, halo_h * (Mirage.HALO_OUTER_RATIO - Mirage.HALO_INNER_RATIO) * 0.5]
		)

	mirage.queue_free()


## 逆光：太阳必须压在弥勒像的**正后方**，而且贴得低。
##
## 这条守的是"逆光走向弥勒"那张画。上一版太阳方位 118°，像的方位是 -31°，
## 差了 59°——画面上"也有太阳、也有像"，但像身是侧光，那层佛性根本没发生。
## 更麻烦的是：这种错**在画面上看着还挺正常**，只有把两个方位角摆到一起才看得见。
func _test_backlight() -> void:
	print("[逆光]")
	var scene: PackedScene = load("res://scenes/main.tscn")
	var instance: Node = scene.instantiate()
	add_child(instance)
	await get_tree().process_frame

	var world: Node = instance.get("world")
	if world == null:
		check(false, "世界缺失")
		instance.queue_free()
		return

	var to_sun: Vector3 = world.call("sun_direction")
	# 方位角的口径与截图诊断一致：atan2(z, x)，玩家开局朝 +X 时为 0。
	var sun_bearing := rad_to_deg(atan2(to_sun.z, to_sun.x))
	var statue_bearing: float = instance.call("statue_bearing_deg")
	var gap := rad_to_deg(
		absf(angle_difference(deg_to_rad(sun_bearing), deg_to_rad(statue_bearing)))
	)
	check(
		gap < 3.0,
		"太阳压在弥勒的方位上（太阳 %+.1f° vs 像 %+.1f°，差 %.1f°）"
		% [sun_bearing, statue_bearing, gap]
	)
	check(to_sun.y > 0.0, "太阳在地平线之上")
	var elevation := rad_to_deg(asin(to_sun.y))
	check(elevation < 24.0, "太阳是低角度的（%.1f° < 24°）——逆光要压着地平线" % elevation)

	# 太阳的光刺也得跟着走：它按 sun_direction 绕方位角调制，
	# 忘了同步的话，转头就会发现芒从天上挪到了别处。
	var env_node := instance.get_node_or_null("Desert/WorldEnvironment")
	if env_node != null:
		var sky_mat: ShaderMaterial = env_node.environment.sky.sky_material
		var sky_sun: Vector3 = sky_mat.get_shader_parameter("sun_direction")
		check(
			sky_sun.distance_to(to_sun) < 0.01,
			"天空的太阳方向和世界的太阳方向一致"
		)
	instance.queue_free()


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
##   3. 顶得看不见 —— 弥勒像的头顶**必须**冲出画面上沿（4 倍之后的新契约：
##      "装不下"才是巨物），但抬头必须够得着佛头。
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

	# 2) 抬头有顶：全场最高点是弥勒的举身光尖——它必须**够得着**。
	#
	# 上一版这条写的是"最高点也得压在天顶之下（< 50°）"，那时像和光背都还
	# 装在画面里。4 倍之后两者一起冲出画面上沿（光尖 ~71°），于是这条的含义
	# 改成"仰到俯仰上限能看见顶"——再写"必须 < 50°"就等于把已经决定要
	# 溢出画面的东西又量回画面里，是自欺。
	#
	# 但"够得着"仍然是有分量的约束：它守的是**这不是一间屋子**。玩家仰到
	# 上限时画面上沿在 111° 以上，越过光尖还有几十度干净的天；哪天有人把像
	# 再放大到连上限都追不上，那才是回到了"穹顶"。
	var statue_x := origin.x - Mirage.CITY_HALF - Mirage.STATUE_FRONT_OF_WALL
	var statue_z := origin.z + Mirage.STATUE_SIDE
	var pitch_limit_deg := rad_to_deg(float(player.get("pitch_limit")))
	var halo_top := Vector3(statue_x, origin.y + Mirage.halo_top_y(), statue_z)
	var halo_elev := _elevation(eye, halo_top)
	check(
		halo_elev < pitch_limit_deg,
		"全场最高点够得着（举身光尖 %.1f° < 俯仰上限 %.1f°，余量 %.1f°）"
		% [halo_elev, pitch_limit_deg, pitch_limit_deg - halo_elev]
	)

	# 3) 逆光走向弥勒：**4 倍**之后这条反过来了，反转是需求方的明确指示
	#    （"佛还是不够巨物感……你能先放大个 4 倍看看？"）。
	#
	# 上一版守的是"像头必须进画面"：那时像头 30.3°、画面上沿 34°，
	# 读法是"看得见、但它是远处的一尊像"。这一版像头 ~67°，
	# **故意的**——巨物的第一读法就是装不下。
	#
	# 但"装不下"和"够不着"是两件事，上一版被骂过一次的正是后者：
	# 像顶 37.6° 而画面上沿 34°，抬头也追不上，那是一尊**没有头**的像。
	# 所以这里守三条：
	#
	#   a. 像头必须**明显**溢出画面上沿（> 上沿 + 10°）——刚好压在边上
	#      读起来像构图没对齐，不像巨物；
	#   b. 抬头必须够得着（像头仰角 < 俯仰上限 − 8°）——脸不能丢；
	#   c. 主塔仍然低于像头（下一条 check）。
	# 像头高度走 statue_top_y()：白膜原点在**台座底面**，埋掉台座之后
	# 沙面之上并没有 STATUE_HEIGHT 那么高（4 倍时这个差值是 691 m）。
	var head := Vector3(statue_x, origin.y + Mirage.statue_top_y(), statue_z)
	var head_elev := _elevation(eye, head)
	check(
		head_elev > half_v + 10.0,
		"像头明显溢出画面上沿（像头 %.1f° > 上沿 %.0f° + 10°）——装不下才是巨物"
		% [head_elev, half_v]
	)
	check(
		head_elev < pitch_limit_deg - 8.0,
		"抬头够得着佛头（像头 %.1f° < 俯仰上限 %.1f° − 8°，需抬头 %.1f°）"
		% [head_elev, pitch_limit_deg, head_elev - half_v]
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
