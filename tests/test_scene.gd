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
	_test_endurance_model()
	_test_endurance_contract()
	# 主场景组装放在**最前面**（紧跟在几个纯模型的测试之后）：它要在进程最干净的
	# 时候建一遍完整的世界。放在末尾时，前面几节拆过好几次重场景（每拆一次
	# Mirage 就是几千个 MeshInstance3D），实测有约一半概率直接崩在
	# add_child 上（0xC0000005，连汇总行都来不及打）——那是 headless 下
	# "拆了又建"的时序问题，不是被测代码的问题。顺序换过来之后连跑 5 次全绿。
	await _test_main_scene_assembles()
	_test_gait()
	_test_storm_model()
	_test_gust()
	_test_wind_is_crosswind()
	_test_wind_in_a_run()
	_test_wind_on_the_camera()
	_test_headwind_slows_you()
	_test_stride_shortens_in_wind()
	_test_mouse_step_gate()
	_test_dust_bands_are_visible()
	_test_grain_is_white_noise()
	_test_soliloquy()
	_test_wind_sound()
	_test_ground_following()
	_test_ground_is_big_enough()
	_test_collapse_timeline()
	await _test_breath()
	await _test_hud_meters()
	_test_mirage_detail()
	_test_statue_readability()
	await _test_backlight()
	await _test_mirage_keeps_distance()
	await _test_scene_is_outdoors()
	await _test_bgm()
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


## 体力模型。**这里没有水囊**：需求方明确划掉了那个概念（"不应该是水囊的概念"），
## 玩家消耗的是自己的身体，不是壶里的水。
func _test_endurance_model() -> void:
	print("[体力]")
	GameState.reset()
	check(is_equal_approx(GameState.stamina, 1.0), "开局体力是满的")
	check(is_equal_approx(GameState.fatigue(), 0.0), "刚出发时一点都不累")

	GameState.reset()
	GameState.storm_intensity = 0.0
	GameState.tick(GameState.ENDURANCE_SECONDS * 0.5, 0.0)
	var half := GameState.stamina
	check(half > 0.4 and half < 0.6, "平静走一半时间，体力剩约一半（%.2f）" % half)

	GameState.reset()
	GameState.storm_intensity = 0.0
	GameState.tick(GameState.ENDURANCE_SECONDS, 0.0)
	check(GameState.stamina <= 0.001, "走到见底")
	check(GameState.is_collapsed, "体力耗尽即倒下")
	check(is_equal_approx(GameState.fatigue(), 1.0), "倒下时是最累的一刻")

	GameState.reset()
	GameState.storm_intensity = 1.0
	GameState.tick(60.0, 0.0)
	var storm_stamina := GameState.stamina

	GameState.reset()
	GameState.storm_intensity = 0.0
	GameState.tick(60.0, 0.0)
	var calm_stamina := GameState.stamina
	check(
		storm_stamina < calm_stamina,
		"沙暴里体力掉得更快（%.3f < %.3f）" % [storm_stamina, calm_stamina]
	)

	GameState.reset()
	GameState.storm_intensity = 0.0
	GameState.tick(60.0, 0.0)
	var walk_stamina := GameState.stamina
	GameState.reset()
	GameState.storm_intensity = 0.0
	GameState.tick(60.0, 1.0)
	check(GameState.stamina < walk_stamina, "冲刺掉得更快")

	# 倒下之后不再继续扣体力
	GameState.reset()
	GameState.tick(GameState.ENDURANCE_SECONDS * 2.0, 0.0)
	var dead_stamina := GameState.stamina
	GameState.tick(100.0, 1.0)
	check(is_equal_approx(dead_stamina, GameState.stamina), "倒下后体力不再变化")
	GameState.reset()


## 需求方给的是两个数：**"够翻 4 次沙丘"、"走个 3 分钟左右"**。
## 它们不能只写在注释里当承诺，得是能跑出来的数——所以这条测试把一局走一遍：
## 拿真实的沙暴相位机推进，玩家一直走，记录倒下的时刻和走过的距离，
## 再去高度场上数他真正翻过了几道沙脊。
func _test_endurance_contract() -> void:
	print("[体力契约：三分钟 / 四道沙丘]")
	var field := DuneField.new()
	var walk := 2.6
	var start := field.find_viewpoint()
	GameState.reset()
	var storm := Sandstorm.new()

	var t := 0.0
	var step := 0.05
	var x := start.x
	while not GameState.is_collapsed and t < 900.0:
		storm.advance(step)
		GameState.tick(step, 0.0)
		GameState.add_distance(walk * step)
		x += walk * step
		t += step

	var distance := GameState.distance_travelled
	var crests := _count_crests(field, start.x, x, start.y)
	var ridges := 4.0 * field.spacing
	print("  （实测：%.0f s 倒下，走了 %.0f m，翻过 %d 道沙脊）" % [t, distance, crests])
	check(t > 165.0 and t < 205.0, "一局约三分钟（%.0f s 落在 165~205 s）" % t)
	check(
		distance > ridges,
		"够翻 4 道沙丘的距离（%.0f m > 4 × 间距 %.0f m）" % [distance, ridges]
	)
	check(crests >= 4, "真的翻过了 4 道沙脊（实测 %d 道）" % crests)
	storm.free()
	GameState.reset()


## 数一数从 x0 走到 x1 翻过了几道沙脊。
##
## 判据是**局部极大 + 一段显著度**，不是"跨过某个高度阈值"：高度场里还叠着
## 大尺度的 swell 噪声（±10 m），固定阈值在起伏高低不同的沙丘上会多算或漏算。
## ±40 m 的窗口比半个周期（95/2 = 47.5 m）窄，所以一道脊只可能被数到一次。
func _count_crests(field: DuneField, x0: float, x1: float, z: float) -> int:
	const STEP := 1.0
	const WINDOW := 40
	const PROMINENCE := 8.0
	var samples := PackedFloat32Array()
	var x := x0
	while x <= x1 + float(WINDOW) * STEP:
		samples.append(field.sample(x, z))
		x += STEP
	var crests := 0
	for i in range(1, samples.size() - WINDOW):
		var h := samples[i]
		if h <= samples[i - 1] or h < samples[i + 1]:
			continue
		var low := h
		for k in range(maxi(i - WINDOW, 0), mini(i + WINDOW, samples.size() - 1) + 1):
			low = minf(low, samples[k])
		if h - low >= PROMINENCE:
			crests += 1
	return crests


## 步态契约。需求方对上一版的判词是两句：**"左摇右摆的感觉太过了"**、
## **"摇摆也不够随机，太机械了"**。两句都是能量出来的：
##
##   1. "太过" = 幅度。滚转和左右摆各有上限，而且**下陷必须大于左右摆**——
##      沙地里走路，最先读到的是"每一步踩下去"，不是"左右摇"；
##   2. "太机械" = 周期性。两条正弦叠出来的步态，同侧两步的幅度必然相等；
##      真实的步子是一步一个样的。
##
## 这里直接驱动 `_update_camera`（而不是靠引擎的物理帧）：步态是纯函数式的
## 时间推进，脱离帧率单独走一遍，量出来的数才是可复现的。
func _test_gait() -> void:
	print("[步态：一脚一步]")
	var player := Wanderer.new()
	add_child(player)
	# 引擎自己的物理帧会按"没有输入"把速度拉回 0，和这里的推进打架。
	player.set_physics_process(false)
	GameState.reset()
	var cam := player.camera()
	var dt := 1.0 / 60.0
	var frames := 1200
	var heights := PackedFloat32Array()
	var laterals: Array[float] = []
	var sinks: Array[float] = []
	var last_index := 0
	var max_sway := 0.0
	var max_roll := 0.0
	for i in range(frames):
		player._update_camera(dt, player.walk_speed, false)
		heights.append(cam.position.y)
		max_sway = maxf(max_sway, absf(cam.position.x))
		max_roll = maxf(max_roll, absf(cam.rotation.z))
		if player._step_index != last_index:
			last_index = player._step_index
			laterals.append(absf(player._step_lateral))
			sinks.append(player._step_sink)

	var steps := laterals.size()
	var sink_min := INF
	var sink_max := -INF
	for sink in sinks:
		sink_min = minf(sink_min, sink)
		sink_max = maxf(sink_max, sink)
	var sway_max := 0.0
	var sway_min := INF
	for lateral in laterals:
		sway_max = maxf(sway_max, lateral)
		sway_min = minf(sway_min, lateral)

	print(
		"  （%.0f 秒走了 %d 步：下陷 %.3f~%.3f m、左右 %.1f~%.1f cm、滚转峰值 %.2f°、镜头横向峰值 %.1f cm）"
		% [
			float(frames) * dt,
			steps,
			sink_min,
			sink_max,
			sway_min * 100.0,
			sway_max * 100.0,
			rad_to_deg(max_roll),
			max_sway * 100.0,
		]
	)
	check(steps > 30, "真的走了这么多步（%d 步）" % steps)
	# 1) 幅度
	check(max_roll <= deg_to_rad(1.5), "滚转收在 1.5° 以内（峰值 %.2f°）" % rad_to_deg(max_roll))
	check(max_sway <= 0.025, "镜头左右摆收在 2.5 cm 以内（峰值 %.1f cm）" % (max_sway * 100.0))
	check(
		sink_min > 0.028 and sink_max < 0.058,
		"每一步都会陷下去，且深浅有变化（%.1f~%.1f cm）"
		% [sink_min * 100.0, sink_max * 100.0]
	)
	check(
		sink_max > sway_max * 1.5,
		"下陷比左右摆明显（%.1f cm vs %.1f cm）——沙地里先读到的是踩下去"
		% [sink_max * 100.0, sway_max * 100.0]
	)
	# 2) 随机（要的是"不机械"，不是"真随机"：同一个哈希，同一条路）
	check(
		_stddev(laterals) > 0.002,
		"左右摆一步一个样，不是两条正弦（同一步幅度的标准差 %.1f mm）"
		% (_stddev(laterals) * 1000.0)
	)
	check(
		_stddev(sinks) > 0.004,
		"每步陷的深浅也不一样（标准差 %.1f mm）" % (_stddev(sinks) * 1000.0)
	)
	# 3) 一脚一下沉：起伏的频率是**步频**，不是两步一次（正弦版就是两步一次）
	var dips := _count_dips(heights, int(1.5 / dt))
	check(
		dips > steps * 0.85 and dips < steps * 1.4,
		"上下起伏跟着每一步走（%d 次下沉 / %d 步）——两步一次就是摇，不是走" % [dips, steps]
	)
	player.free()
	GameState.reset()


func _stddev(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sum := 0.0
	for value in values:
		sum += value
	var mean := sum / float(values.size())
	var acc := 0.0
	for value in values:
		acc += (value - mean) * (value - mean)
	return sqrt(acc / float(values.size()))


## 数一数信号里的下沉次数。先减掉 1.5 秒的滑动均值——**喘气是慢的**
## （0.24 Hz 起步），减掉它之后剩下的基本就只有走路那一层了。
func _count_dips(values: PackedFloat32Array, window: int) -> int:
	var slow := PackedFloat32Array()
	for i in range(values.size()):
		var from: int = maxi(0, i - window)
		var to: int = mini(values.size() - 1, i + window)
		var sum := 0.0
		for k in range(from, to + 1):
			sum += values[k]
		slow.append(sum / float(to - from + 1))
	var dips := 0
	for i in range(1, values.size() - 1):
		var a := values[i] - slow[i]
		var prev := values[i - 1] - slow[i - 1]
		var next := values[i + 1] - slow[i + 1]
		if a < prev and a <= next:
			dips += 1
	return dips


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


## 阵风：风不是一条稳定的曲线，是"一阵一阵"的。
##
## 需求方 2026-09-24 的判词是"大风吹的感觉不是很明显，视觉和行走上"。风的
## **强度**好办（乘一个系数就行），难的是**节奏**：一条常数的风推着人走，人
## 只会觉得"这关的速度调过了"；一阵一阵地扑上来，人才会觉得是风。
##
## 这里守三条：包络有上下限（不吹出界）、真的在起伏（不是常数）、
## 风力 = 强度 × 阵风（平静时必须是 0——平静的沙漠不该有推力）。
func _test_gust() -> void:
	print("[阵风]")
	var storm := Sandstorm.new()
	var lo := INF
	var hi := -INF
	var sum := 0.0
	var n := 0
	var t := 0.0
	while t < 240.0:
		var g := storm.gust(t)
		lo = minf(lo, g)
		hi = maxf(hi, g)
		sum += g
		n += 1
		t += 0.25
	var mean := sum / float(n)
	check(lo >= 0.5 and hi <= 1.001, "阵风包络收在 0.5~1.0（%.2f~%.2f）" % [lo, hi])
	check(hi - lo > 0.3, "阵风真的在起伏（%.2f~%.2f，不是一条直线）" % [lo, hi])
	check(
		mean > 0.6 and mean < 0.95,
		"阵风的均值在中间（%.2f）——风是「扑上来」和「缓一下」的混合" % mean
	)

	GameState.reset()
	storm.intensity = 0.0
	check(is_equal_approx(storm.wind_force(), 0.0), "平静时没有风（0.0）")
	storm.intensity = 1.0
	storm._clock = 0.0
	var f0 := storm.wind_force()
	storm._clock = 7.0
	var f1 := storm.wind_force()
	check(f0 > 0.4 and f1 > 0.4, "沙暴里一直有风（%.2f / %.2f）" % [f0, f1])
	check(not is_equal_approx(f0, f1), "风的大小每一刻都不一样（%.2f → %.2f）" % [f0, f1])
	storm.free()
	GameState.reset()


## 风推在人身上：**横着抽**才是风，顺风只是走得快。
##
## 上一版的风向 (1, 0.35) 和"走向弥勒"只差 19°，那股 2.6 m/s 的推力绝大部分
## 变成了顺风加速——玩家读不出"被风吹"。所以这条测试量的是**方向**：
## 横向分量必须是纵向分量的两倍以上。
func _test_wind_is_crosswind() -> void:
	print("[风是横着抽的]")
	var storm := Sandstorm.new()
	var wind := storm.wind_direction
	check(
		is_equal_approx(wind.y, 0.0),
		"风是水平的（y = %.2f）——竖直分量会让沙往天上飞" % wind.y
	)
	# 玩家默认朝 +X 走：纵向 = x，横向 = z。
	check(
		absf(wind.z) > absf(wind.x) * 2.0,
		"风是横着抽过来的（横向 %.2f vs 纵向 %.2f）——顺风只让人走得快，不叫风"
		% [absf(wind.z), absf(wind.x)]
	)
	check(wind.x < 0.0, "带一点点逆风（%.2f < 0）——顶着风走脚下会慢一点" % wind.x)
	check(absf(wind.length() - 1.0) < 0.001, "风向是单位向量")

	# 推力：峰值要够大（人真的被推着走），而且方向就是这个风向。
	storm.force_intensity(1.0)
	storm._clock = 2.0
	var player := Wanderer.new()
	add_child(player)
	player.set_physics_process(false)
	storm.player = player
	storm._apply()
	var push := player.external_push
	check(
		push.length() > 1.5,
		"推力的量级够（%.2f m/s）——小于半个步速就只是「有点飘」" % push.length()
	)
	check(
		absf(push.z) > absf(push.x) * 2.0,
		"推力也是横着推的（横向 %.2f vs 纵向 %.2f m/s）" % [absf(push.z), absf(push.x)]
	)
	check(
		GameState.wind_force > 0.4,
		"风力写进了 GameState（%.2f）——镜头那一侧读的就是它" % GameState.wind_force
	)
	player.queue_free()
	storm.free()
	GameState.reset()


## 风里的一局：被吹得走不直，但**还翻得过四道沙丘**。
##
## 这是"大风吹"和"三分钟四道沙丘"两条需求撞在一起的地方：风要是给太大，
## 人就被吹在原地打转，一局翻不过四道脊——前面那条 [体力契约] 会绿着，
## 因为它压根没把风算进去。所以这里把真实的推力也代进去走一局。
func _test_wind_in_a_run() -> void:
	print("[风里的一局]")
	var field := DuneField.new()
	var walk := 2.6
	var start := field.find_viewpoint()
	GameState.reset()
	var player := Wanderer.new()
	add_child(player)
	player.set_physics_process(false)
	var storm := Sandstorm.new()
	storm.player = player

	var t := 0.0
	var step := 0.05
	var x := start.x
	var z := start.y
	var drift := 0.0
	var peak := 0.0
	var scale_sum := 0.0
	var samples := 0
	while not GameState.is_collapsed and t < 900.0:
		storm.advance(step)
		var push := player.external_push
		peak = maxf(peak, push.length())
		# 玩家一直朝 +X 走（对着弥勒），风一直在推他——推出来的横向位移
		# 就是"走不成直线"这件事的读数。
		#
		# 步速也要过一遍**风里的阻力**（Wanderer.wind_speed_scale）：顶着风走
		# 脚下是会慢的，这一条现在也是"三分钟、四道沙丘"的一部分——
		# 少了它，测试里走的一局会比玩家真走的那一局更远，契约就成了空头支票。
		var wish := Vector3(1.0, 0.0, 0.0)
		var scale := Wanderer.wind_speed_scale(storm.wind_direction, GameState.wind_force, wish)
		scale_sum += scale
		x += (walk * scale + push.x) * step
		z += push.z * step
		drift = maxf(drift, absf(z - start.y))
		GameState.tick(step, 0.0)
		GameState.add_distance(walk * scale * step)
		samples += 1
		t += step

	var crests := _count_crests(field, start.x, x, z)
	var mean_scale := scale_sum / float(maxi(samples, 1))
	print(
		"  （实测：%.0f s 倒下，往前 %.0f m、被吹偏 %.0f m，翻过 %d 道沙脊，推力峰值 %.1f m/s，顶风把步速拖到平均 %.3f 倍）"
		% [t, x - start.x, drift, crests, peak, mean_scale]
	)
	check(drift > 25.0, "风把人吹得走不直（横向漂了 %.0f m）" % drift)
	check(
		crests >= 4,
		"顶着风还是翻过了 4 道沙脊（实测 %d 道，往前 %.0f m）" % [crests, x - start.x]
	)
	check(peak > 2.0, "推力峰值够大（%.1f m/s）" % peak)
	check(
		mean_scale < 0.995,
		"顶风真的拖了后腿（一局平均 %.3f 倍步速）——不是只有位移被推" % mean_scale
	)
	player.queue_free()
	storm.free()
	GameState.reset()


## 风推在**镜头**上：脑袋被吹偏、地平线被吹斜、而且还在抖。
##
## 走路那一半（推力）由上面的 [风里的一局] 守着；这一条守视觉那一半。
## 两者是同一阵风的两面，所以读的是同一个 `GameState.wind_force`——
## 分开算的话会出现"人被推了一下、镜头却没动"。
##
## 量的都是**幅度**，不是"好不好看"：镜头不偏、地平线不歪，就是上一版那副
## 样子（需求方原话："大风吹的感觉不是很明显"）。
func _test_wind_on_the_camera() -> void:
	print("[风推在镜头上]")
	var player := Wanderer.new()
	add_child(player)
	# 引擎自己的物理帧会把速度拉回 0，和这里的推进打架（和 [步态] 同一个理由）。
	player.set_physics_process(false)
	player.set_yaw(-PI * 0.5)  # 和 main.START_YAW 一致：面朝 +X（朝着弥勒）
	GameState.reset()

	# 无风：镜头必须是干净的。这一步是"上一条测试没被别的东西污染"的对照。
	GameState.wind_force = 0.0
	GameState.wind_direction = Vector3(0.0, 0.0, 1.0)
	var calm_x := 0.0
	var calm_roll := 0.0
	for i in range(120):
		player._update_camera(1.0 / 60.0, 0.0, false)
		calm_x = maxf(calm_x, absf(player.camera().position.x))
		calm_roll = maxf(calm_roll, absf(player.camera().rotation.z))
	check(calm_x < 0.01, "没风时镜头不偏（最大 %.3f m）" % calm_x)
	check(calm_roll < deg_to_rad(0.2), "没风时地平线是平的（最大 %.2f°）" % rad_to_deg(calm_roll))

	# 横风拉满：面朝 +X 时 +Z 就是右手边，所以"横向分量 = +1"。
	GameState.wind_force = 1.0
	var x_lo := INF
	var x_hi := -INF
	var roll := 0.0
	for i in range(900):
		player._update_camera(1.0 / 60.0, 0.0, false)
		var px := player.camera().position.x
		x_lo = minf(x_lo, px)
		x_hi = maxf(x_hi, px)
		roll = maxf(roll, absf(player.camera().rotation.z))
	check(
		x_hi > Wanderer.WIND_LEAN_METERS * 0.9,
		"脑袋被吹向下风侧（%.3f m，标尺 %.2f）" % [x_hi, Wanderer.WIND_LEAN_METERS]
	)
	check(
		rad_to_deg(roll) > 2.5,
		"地平线被吹斜（峰值 %.2f°，标尺 %.1f°）" % [rad_to_deg(roll), Wanderer.WIND_ROLL_DEG]
	)
	check(
		x_hi - x_lo > 0.03,
		"风在抖，不是钉死的一个偏移（摆动幅度 %.3f m）" % (x_hi - x_lo)
	)
	player.queue_free()
	GameState.reset()


## 顶着风走，**脚下要有阻力**。
##
## 只验方向，不验"好不好玩"：风顺着你吹时略快、顶着你吹时明显慢、横着吹时
## 一点不吃速度（横风吃的是站位，那是 Sandstorm 的位移推力，上面两条测试守着）。
## 这一条是"行走那一半"的读数——上一版只有被动位移，玩家按着前进时脚下
## 是空的，"被平移了半个身位"和"走不动"是两回事。
func _test_headwind_slows_you() -> void:
	print("[顶风走得慢]")
	var i := Vector3(1.0, 0.0, 0.0)
	var side := Vector3(0.0, 0.0, 1.0)

	check(
		is_equal_approx(Wanderer.wind_speed_scale(i, 0.0, i), 1.0),
		"没风时步速不变（乘 1.0）"
	)
	# 风往 +X 吹：**朝 +X 走是顺风**（风在后背），朝 -X 走才是顶风。
	# 上一版这条测试把两头写反了，断言全红——写反的不是代码，是"顶风"这两个字。
	var tail := Wanderer.wind_speed_scale(i, 1.0, i)
	var head := Wanderer.wind_speed_scale(i, 1.0, -i)
	var across := Wanderer.wind_speed_scale(i, 1.0, side)
	check(head < 0.90, "满风顶着头走要慢下来（乘 %.2f）" % head)
	check(tail > 1.0, "顺风才借得上力（乘 %.2f）" % tail)
	check(
		tail - 1.0 < 1.0 - head,
		"借到的比输掉的少（顺风 +%.2f vs 顶风 -%.2f）——风能推着你走，推不了你的腿"
		% [tail - 1.0, 1.0 - head]
	)
	check(absf(across - 1.0) < 0.001, "横风不吃速度（乘 %.2f）——它吃的是站位" % across)
	check(
		Wanderer.wind_speed_scale(i, 0.5, -i) > head + 0.05,
		"风越小阻力越小（半风 %.2f > 满风 %.2f）"
		% [Wanderer.wind_speed_scale(i, 0.5, -i), head]
	)

	# 默认那阵风 (-0.22, 0, 0.98) 里，逆风只有 22%——玩家朝弥勒走（+X）时
	# 该慢一点，但不该慢到翻不过四道沙丘。这两个数是绑在一起的，见 WIND_DRAG。
	var storm := Sandstorm.new()
	var real := Wanderer.wind_speed_scale(storm.wind_direction, 1.0, i)
	print("  （默认风、满风力、朝着弥勒走：步速乘 %.3f）" % real)
	check(real < 0.95, "默认风里朝着弥勒走确实费劲（乘 %.3f）" % real)
	check(real > 0.88, "但没有费劲到把「三分钟四道沙丘」吃掉（乘 %.3f）" % real)
	storm.free()


## 鼠标那一道闸门。
##
## **必须在这里量**：真正吃它的分支在 `_unhandled_input` 里，而那个分支要求
## `Input.mouse_mode == CAPTURED`——headless 没有窗口系统，拿不到指针锁定，
## 那条分支永远跑不到。测不到的分支等于没写，所以把闸门抽成了纯函数。
##
## 量三件事：小位移原样过（不伤口感）、离谱位移被按在上限（不会一帧顶到穹顶）、
## 连续事件叠起来仍然能扫满一圈（闸门不是把视角锁死）。
func _test_mouse_step_gate() -> void:
	print("[鼠标步长闸门]")
	var small := Vector2(12.0, -7.0)
	check(
		Wanderer.limit_look_step(small).is_equal_approx(small),
		"手正常的一点点位移原样过（%s）" % Wanderer.limit_look_step(small)
	)

	var absurd := Vector2(4000.0, -3000.0)
	var gated := Wanderer.limit_look_step(absurd)
	check(
		is_equal_approx(gated.length(), Wanderer.MOUSE_STEP_LIMIT),
		"离谱的一次位移被按到 %.0f 像素（原来是 %.0f）" % [
			Wanderer.MOUSE_STEP_LIMIT, absurd.length()
		]
	)

	var player := Wanderer.new()
	var per_event_deg := rad_to_deg(Wanderer.MOUSE_STEP_LIMIT * player.mouse_sensitivity)
	check(
		per_event_deg < rad_to_deg(player.pitch_limit),
		"一次事件最多转 %.1f°，到不了 pitch 钳位 %.0f°——抬不到穹顶" % [
			per_event_deg, rad_to_deg(player.pitch_limit)
		]
	)

	var frames := 0
	var yaw := 0.0
	while frames < 120 and absf(yaw) < TAU:
		yaw -= Wanderer.limit_look_step(Vector2(Wanderer.MOUSE_STEP_LIMIT * 4.0, 0.0)).x \
				* player.mouse_sensitivity
		frames += 1
	check(
		absf(yaw) >= TAU,
		"%d 帧扫过一整圈——闸门限的是单次事件，不是把视角锁死" % frames
	)
	check(
		Wanderer.CAPTURE_GRACE_MS >= 50 and Wanderer.CAPTURE_GRACE_MS <= 500,
		"抓取宽限窗口是 %d ms（够长到跨过「指针被挪到窗口中央」那一跳，"
		% Wanderer.CAPTURE_GRACE_MS
		+ "又不至于让玩家点完半天转不了头）"
	)
	player.free()


## 风里步子要**变碎**：只改步频，不改位移。
##
## 位移是 speed 说了算，步长只决定"这一步跨多大"——满风时步长缩 15%，
## 同样的速度就会多踩约 18% 的步子。这是"顶着风走"最便宜的一条身体语言：
## 不用改模型，只改相位推进的速度。
func _test_stride_shortens_in_wind() -> void:
	print("[风里步子更碎]")
	var player := Wanderer.new()
	add_child(player)
	player.set_physics_process(false)
	GameState.reset()
	var dt := 1.0 / 60.0
	var seconds := 10.0
	var frames := int(seconds / dt)

	GameState.wind_force = 0.0
	var calm_from := player._step_index
	for i in range(frames):
		player._update_camera(dt, player.walk_speed, false)
	var calm := player._step_index - calm_from

	GameState.wind_force = 1.0
	var windy_from := player._step_index
	for i in range(frames):
		player._update_camera(dt, player.walk_speed, false)
	var windy := player._step_index - windy_from

	print("  （同样 %.0f 秒、同样 %.1f m/s：无风 %d 步，满风 %d 步）" % [seconds, player.walk_speed, calm, windy])
	check(calm > 15, "无风时步频正常（%d 步 / %.0f s）" % [calm, seconds])
	check(
		windy > calm * 1.12 and windy < calm * 1.4,
		"满风时步子变碎（%d 步 vs %d 步）——位移没变，只多踩了几步" % [windy, calm]
	)
	player.queue_free()
	GameState.reset()


## 从 shader 源码里读一个 `uniform float` 的默认值。
##
## **不另抄一份常数**：抄一份就会漂——shader 改了、测试里的副本没改，
## 于是测试绿着、画面对不上，而这正是最难查的那类问题。
func _shader_float(code: String, name: String) -> float:
	var re := RegEx.new()
	re.compile("uniform float %s[^=]*= *([0-9.]+)" % name)
	var m := re.search(code)
	if m == null:
		check(false, "shader 里找不到 uniform %s（改名了？）" % name)
		return NAN
	return float(m.get_string(1))


## 和 shader 里 `_hash` / `_vnoise` / `_fbm` 逐行对应的副本。
##
## 分布在**统计意义**上是对的就行：GLSL 和 GDScript 的 sin 末位不同，
## 逐点对比本来就不可能相等，这一节量的是均值、标准差和覆盖面积。
func _dust_fbm(p: Vector2) -> float:
	var v := 0.0
	var amp := 0.5
	for i in range(4):
		var i_cell := Vector2(floorf(p.x), floorf(p.y))
		var f := p - i_cell
		f = Vector2(f.x * f.x * (3.0 - 2.0 * f.x), f.y * f.y * (3.0 - 2.0 * f.y))
		var c00 := fposmod(sin(i_cell.dot(Vector2(127.1, 311.7))) * 43758.5453, 1.0)
		var c10 := fposmod(sin((i_cell + Vector2(1.0, 0.0)).dot(Vector2(127.1, 311.7))) * 43758.5453, 1.0)
		var c01 := fposmod(sin((i_cell + Vector2(0.0, 1.0)).dot(Vector2(127.1, 311.7))) * 43758.5453, 1.0)
		var c11 := fposmod(sin((i_cell + Vector2(1.0, 1.0)).dot(Vector2(127.1, 311.7))) * 43758.5453, 1.0)
		v += amp * lerpf(lerpf(c00, c10, f.x), lerpf(c01, c11, f.x), f.y)
		# 八度之间转 37°：四个八度共用一套格点的话，"沙云"会先露出方格。
		p = Vector2(p.x * 0.80 - p.y * 0.60, p.x * 0.60 + p.y * 0.80) * 2.07
		amp *= 0.5
	return v


## 风推在**沙**上：这一层"一直飘着的沙带"到底看不看得见？
##
## 这是本仓库里最难用眼睛发现的一类 bug：**一层画不出来的沙**。
## 2026-09-24 就是这么栽的——门槛写在 fbm 的 +1σ 以外，画面上一个像素都够不着，
## 而"看不见"和"没写"在截图上是同一个样子，靠看图 review 根本抓不住。
##
## 所以这一节不看图、不调参数，**照着 shader 源码里的常数算一遍分布**：
## 抠出 ①噪声的均值/标准差（那句按 σ 归一化的式子）②σ 门槛 ③采样频率，
## 再用同一套噪声量一次覆盖面积。任何一边被改歪（门槛挪进尾巴、
## 归一化的常数和噪声对不上），这条就会红。
##
## 量的都是**平静那一档**（拖影长度 = 0，两次取样完全重合），再加一次
## "满风时拖影会不会把沙带抹平"的对照——拖影是这一层新加的东西，
## 它最容易犯的错不是不够，而是**糊成一团、带全没了**。
func _test_dust_bands_are_visible() -> void:
	print("[风里的沙带看得见吗]")
	var shader := load("res://shaders/desert_post.gdshader") as Shader
	check(shader != null, "后处理 shader 能加载")
	if shader == null:
		return
	var code := shader.code

	# ① "z 分数"那句：(fine * A + broad * B - 均值) / 标准差
	var z_re := RegEx.new()
	z_re.compile("\\(fine \\* ([0-9.]+) \\+ broad \\* ([0-9.]+) - ([0-9.]+)\\) / ([0-9.]+)")
	var z := z_re.search(code)
	check(z != null, "shader 里有那句按 σ 归一化的式子（式子重写了这条也要跟着改）")
	if z == null:
		return
	var w_fine := float(z.get_string(1))
	var w_broad := float(z.get_string(2))
	var claimed_mean := float(z.get_string(3))
	var claimed_sd := float(z.get_string(4))

	# ② 门槛：smoothstep(lo, hi, v)，两个数都是 σ 分数
	var s_re := RegEx.new()
	s_re.compile("smoothstep\\((-?[0-9.]+), (-?[0-9.]+), v\\)")
	var s := s_re.search(code)
	check(s != null, "shader 里有把噪声切成沙带的门槛")
	if s == null:
		return
	var lo := float(s.get_string(1))
	var hi := float(s.get_string(2))
	check(hi > lo, "门槛是从下往上爬的（%.2fσ → %.2fσ）" % [lo, hi])

	# ③ 采样频率：方位角方向压扁、仰角方向压实
	var along := _shader_float(code, "dust_along")
	var bands_freq := _shader_float(code, "dust_bands")

	# 铺满"一屏看得到的那些方位/仰角"：水平 ±51°、竖直 ±34°（68° 的竖直视角）。
	# 网格要够密：最细那一个八度的周期是 0.48，一行四五个采样才量得准 σ。
	var nx := 200
	var ny := 100
	var count := nx * ny
	var visible := 0
	var core := 0
	var storm_core := 0
	var sum := 0.0
	var sum_sq := 0.0
	var storm_sum := 0.0
	var storm_sum_sq := 0.0
	for ix in range(nx):
		for iy in range(ny):
			var az := lerpf(-0.89, 0.89, float(ix) / float(nx - 1))
			var el := lerpf(-0.59, 0.59, float(iy) / float(ny - 1))
			var p := Vector2(az * along, el * bands_freq)
			var fine := _dust_fbm(p)
			var broad := _dust_fbm(p * 0.45)
			var raw := fine * w_fine + broad * w_broad
			var band := smoothstep(lo, hi, (raw - claimed_mean) / claimed_sd)
			sum += raw
			sum_sq += raw * raw
			if band > 0.05:
				visible += 1
			if band > 0.9:
				core += 1
			# 满风时的拖影：把 fine 换成两个取样点的平均。两个点相隔约 0.5 个
			# 特征尺度——这就是 shader 里"默认机位 + 默认横风 + 满风力"算出来的
			# 那个偏移量（(0.98×0.40, 0.18×6.0) × 0.45）。公式改了这里也要改。
			var smeared := (_dust_fbm(p) + _dust_fbm(p - Vector2(0.18, 0.50))) * 0.5
			var storm_raw := smeared * w_fine + broad * w_broad
			var storm_band := smoothstep(lo, hi, (storm_raw - claimed_mean) / claimed_sd)
			storm_sum += storm_raw
			storm_sum_sq += storm_raw * storm_raw
			if storm_band > 0.9:
				storm_core += 1

	var measured_mean := sum / float(count)
	var measured_sd := sqrt(maxf(sum_sq / float(count) - measured_mean * measured_mean, 0.0))
	var storm_mean := storm_sum / float(count)
	var storm_sd := sqrt(maxf(storm_sum_sq / float(count) - storm_mean * storm_mean, 0.0))
	var visible_frac := float(visible) / float(count)
	var core_frac := float(core) / float(count)
	var storm_frac := float(storm_core) / float(count)
	print(
		"  （实测：噪声均值 %.3f / σ %.3f；薄沙 %.0f%%、实心沙丝 %.1f%%；满风 σ %.3f、实心 %.1f%%）"
		% [
			measured_mean, measured_sd, visible_frac * 100.0, core_frac * 100.0,
			storm_sd, storm_frac * 100.0,
		]
	)

	check(
		absf(measured_mean - claimed_mean) < 0.02,
		"归一化用的均值是真的（写 %s，实测 %.3f）" % [z.get_string(3), measured_mean]
	)
	check(
		absf(measured_sd - claimed_sd) < 0.02,
		"归一化用的标准差是真的（写 %s，实测 %.3f）" % [z.get_string(4), measured_sd]
	)
	check(
		visible_frac > 0.2 and visible_frac < 0.9,
		"大部分画面有一层薄沙（%.0f%%）——不是几根孤零零的丝" % (visible_frac * 100.0)
	)
	check(
		core_frac > 0.01 and core_frac < 0.35,
		"有实心的沙带但不是半个画面（%.1f%%）——上一版 0.50→0.68 那档是满屏硬线" % (core_frac * 100.0)
	)
	check(
		storm_frac > core_frac * 0.4,
		"满风拖影把沙带拉软了、但没抹平（%.1f%% vs 平静 %.1f%%）" % [storm_frac * 100.0, core_frac * 100.0]
	)
	check(
		storm_sd <= measured_sd + 0.001,
		"拖影只会压低起伏、不会抬高（σ %.3f → %.3f）" % [measured_sd, storm_sd]
	)


## 颗粒是**白噪**，不是一层布纹。
##
## 这一条守的是"颗粒必须真的是颗粒"。判据是**相邻像素的相关性**：
## 白噪 ≈ 0，规则条纹 ≈ 1。
##
## 它还有一段来历，值得留着：2026-09-24 成片放大 1:1 时，沙面、佛像、天空上
## 全盖着一层细网格。第一反应是 shader 里那句 `fract(sin(dot(p, k)))` 在整数
## 像素格上退化成条纹——于是写了这一条测试，**顺手把旧写法当对照组**，
## 满以为它会红。结果它测出 0.016：**旧的写法在 double 下是白噪，假设当场被
## 证伪**，我一度把凶手改判成"录片的 MJPEG 压缩"。
##
## 那个改判也是错的。真正分开两个嫌疑的是一次 **A/B 录片**：同一个 1600×900、
## 同一条 MJPEG 管线、同一组参数，**只换哈希**——旧哈希那版有网格，新哈希那版
## 干净。管线一样，所以凶手还是哈希：它在 **float32** 下会退化成纲格
## （输入 `12.9898x + 78.233y` 到这里已经 ~10^5，float32 把 sin 的输入量化了，
## 相邻像素被系统性拉在一起）。
##
## 于是这条测试也留下一个教训，比它守的那条更重要：
## **把 shader 抄到 CPU 上做统计，测不出 float32 的毛病**——GDScript 是 double。
## 所以下面那个"对照组"不能再拿旧哈希（它在 double 下真的会通过），
## 只能拿一个**故意做出来的条纹**：得先证明这把尺子量得出条纹，
## 再用它去量颗粒。
func _test_grain_is_white_noise() -> void:
	print("[颗粒是白噪，不是布纹]")
	var shader := load("res://shaders/desert_post.gdshader") as Shader
	check(shader != null, "后处理 shader 能加载")
	if shader == null:
		return
	var code := shader.code
	check(
		code.contains("p3 += dot(p3, p3.yzx + 33.33)"),
		"颗粒用的是整数哈希（Hoskins 那一支）"
	)
	check(not code.contains("_rand("), "旧的 sin 哈希连名字一起清掉了")

	var fresh := _grain_neighbour_correlation(true)
	var stripe := _grain_neighbour_correlation(false)
	print("  （相邻像素相关性：现在的颗粒 %.3f，故意做的条纹 %.3f）" % [fresh, stripe])
	check(absf(fresh) < 0.2, "新哈希的相邻像素不相关（%.3f）——这才是颗粒" % fresh)
	check(stripe > 0.6, "对照组：故意做的条纹被抓住（%.3f）——说明这条测试有牙" % stripe)


## 一层 64×64 的颗粒里，相邻像素的相关性（lag-1）。取 x、y 两个方向里更差的那个。
func _grain_neighbour_correlation(use_current_hash: bool) -> float:
	var w := 64
	var h := 64
	var vals := PackedFloat32Array()
	vals.resize(w * h)
	for y in range(h):
		for x in range(w):
			vals[y * w + x] = _grain_value(float(x), float(y), use_current_hash)
	return maxf(absf(_lag1_correlation(vals, w, h, 1, 0)), absf(_lag1_correlation(vals, w, h, 0, 1)))


## 现在的颗粒哈希（从 shader 里照抄），以及一个**故意成纹**的对照信号。
func _grain_value(x: float, y: float, use_current_hash: bool) -> float:
	if not use_current_hash:
		# 沿 x 方向缓慢起伏 → 一列一列地成纹。相关性应当接近 1。
		return 0.5 + 0.5 * sin(x * 0.55 + y * 0.02)
	var p := Vector3(x, y, x) * 0.1031
	p = Vector3(fposmod(p.x, 1.0), fposmod(p.y, 1.0), fposmod(p.z, 1.0))
	p += Vector3.ONE * p.dot(Vector3(p.y, p.z, p.x) + Vector3.ONE * 33.33)
	return fposmod((p.x + p.y) * p.z, 1.0)


func _lag1_correlation(vals: PackedFloat32Array, w: int, h: int, dx: int, dy: int) -> float:
	var pairs := 0
	var sa := 0.0
	var sb := 0.0
	var sa2 := 0.0
	var sb2 := 0.0
	var sab := 0.0
	for y in range(h - dy):
		for x in range(w - dx):
			var a := vals[y * w + x]
			var b := vals[(y + dy) * w + (x + dx)]
			pairs += 1
			sa += a
			sb += b
			sa2 += a * a
			sb2 += b * b
			sab += a * b
	var n := float(pairs)
	var cov := sab / n - (sa / n) * (sb / n)
	var va := sa2 / n - (sa / n) * (sa / n)
	var vb := sb2 / n - (sb / n) * (sb / n)
	if va < 0.0000001 or vb < 0.0000001:
		return 0.0
	return cov / sqrt(va * vb)


## 自言自语：一局里真的会说出来吗？说出来的是不是有来历的话？
##
## "好不好听"验不了，但下面四件事坏了都很难看，而且都能验：
##   1. **每句都有出处**——编一句文言容易，编一句有来历的文言难；
##   2. 拿真实的状态曲线走一局，话会自己说出来、不重复、不刷屏；
##   3. 该来的那几句一定会来：起风有话说、幻影有话说、快死了有话说、倒下有话说；
##   4. 落点那两句要**落在该落的那一秒上**：倒下之后 1~2.5 秒说出临终那一愿，
##      闭眼之前念完最后一句（题记 12 秒才出来，不能撞车）。
##
## 判定在模型层（SoliloquyLines.due），这一节验的就是它——**不碰 HUD**，
## 因为"什么时候该说话"和"怎么淡入淡出"是两件事，后者只在有窗口时才看得到。
func _test_soliloquy() -> void:
	print("[自言自语]")
	# 1) 先记账：每条都有出处，而且不许长成一段字幕。
	var quoted := 0
	var too_long := 0
	for line: Dictionary in SoliloquyLines.LINES:
		var source := String(line["source"])
		if source.is_empty():
			print("  （没有出处的台词：%s）" % line["text"])
		elif source.begins_with("《"):
			quoted += 1
		if String(line["text"]).length() > SoliloquyLines.MAX_CHARS:
			too_long += 1
	check(quoted >= 8, "至少八句直接取自史书（%d 句）" % quoted)
	check(too_long == 0, "没有一句长到像字幕（上限 %d 字）" % SoliloquyLines.MAX_CHARS)

	# 2) 拿**真实**的一局走一遍：沙暴按真相位推、体力按真模型掉，
	#    每 0.25 秒问一次"现在该说哪句"。
	var storm := Sandstorm.new()
	var said := {}
	var spoken: Array[String] = []
	var spoken_at: Array[float] = []
	var clock := 0.0
	var last := -1.0e9
	var step := 0.25
	var collapse_clock := -1.0
	GameState.reset()
	while true:
		if not GameState.is_collapsed:
			if clock > 900.0:
				break
			storm.advance(step)
			GameState.tick(step, 0.0)
			clock += step
		else:
			if collapse_clock < 0.0:
				collapse_clock = clock
			if clock >= collapse_clock + 12.0:
				break
			GameState.tick(step, 0.0)
			clock += step
		var index := SoliloquyLines.due(_soliloquy_state(clock, last), said)
		if index < 0:
			continue
		var line: Dictionary = SoliloquyLines.LINES[index]
		said[line["id"]] = true
		spoken.append(String(line["id"]))
		spoken_at.append(clock)
		last = clock

	print("  （%d s 里说了 %d 句：%s）" % [clock, spoken.size(), ", ".join(spoken)])
	check(spoken.size() >= 8, "一局里至少说出 8 句（实测 %d 句）" % spoken.size())
	check(
		spoken.size() == said.size(),
		"每句只说一次（说了 %d 句 / 不同的 %d 句）" % [spoken.size(), said.size()]
	)
	var first_at := -1.0
	if not spoken_at.is_empty():
		first_at = spoken_at[0]
	check(first_at >= 4.0, "开局那几秒不说话（第一句在第 %.1f s）" % first_at)

	# 3) 不刷屏：两句之间至少隔 MIN_GAP，允许两条例外——
	#    落下那两句的间隔是 0（它们必须落在该落的那一秒上）。
	var tight := 0
	for i in range(1, spoken_at.size()):
		if spoken_at[i] - spoken_at[i - 1] < SoliloquyLines.MIN_GAP:
			tight += 1
	check(
		tight <= 2,
		"话不刷屏（只有 %d 处挨得比 %.0f s 近）" % [tight, SoliloquyLines.MIN_GAP]
	)

	# 4) 该来的都要来，而且落在该落的地方。
	var down_at := _spoken_time(spoken, spoken_at, "down")
	var relics_at := _spoken_time(spoken, spoken_at, "relics")
	print(
		"  （倒下在第 %.1f s；临终那句 +%.1f s，最后一句 +%.1f s）"
		% [collapse_clock, down_at - collapse_clock, relics_at - collapse_clock]
	)
	check(spoken.has("heat_wind") or spoken.has("daze"), "起风时他有话说（风、熱风）")
	check(spoken.has("mirage"), "幻影浮出来时他有话说（歌啸号哭）")
	check(spoken.has("vow"), "快走不动时他有话说（宁可就西而死）")
	check(
		down_at >= collapse_clock + 0.9 and down_at < collapse_clock + 2.5,
		"临终那一愿落在倒下之后 1~2.5 s（实测 +%.1f s）" % (down_at - collapse_clock)
	)
	check(
		relics_at > collapse_clock + 6.0 and relics_at < collapse_clock + 8.5,
		"最后一句在闭眼前后念完（实测 +%.1f s，题记 %.0f s 才出来）"
		% [relics_at - collapse_clock, GameState.EPILOGUE_SECONDS]
	)
	storm.free()

	# 5) 开场白必须真的**开场**。
	#
	#    这一条是录片时抓到的：`--storm` 那种一开局就满风的局里，"乏水草，多热风"
	#    在第 0.03 秒就抢在"四远茫茫"前面说了出来——因为风那条的条件是"风够大"，
	#    满风的局里它从第一帧就成立。台词表的顺序管得住同时到期的句子，
	#    管不住**谁先到期**，所以另有一条开场下限（OPENING_FLOOR）。
	var said2 := {}
	var storm2 := Sandstorm.new()
	storm2.set("_phase", 2)
	storm2.force_intensity(0.95)
	var clock2 := 0.0
	var last2 := -1.0e9
	var first2 := ""
	GameState.reset()
	while clock2 < 60.0 and first2.is_empty():
		storm2.advance(step)
		GameState.tick(step, 0.0)
		clock2 += step
		var index2 := SoliloquyLines.due(_soliloquy_state(clock2, last2), said2)
		if index2 >= 0:
			first2 = String(SoliloquyLines.LINES[index2]["id"])
			said2[first2] = true
			last2 = clock2
	print("  （一开局就满风：第一句在第 %.1f s 说出来，是 %s）" % [clock2, first2])
	check(first2 == "far_off", "一开局就满风，第一句仍然是开场白（%s）" % first2)
	check(
		clock2 >= 4.0 and clock2 <= SoliloquyLines.OPENING_FLOOR,
		"开场白在 %.1f s 说出来（4 s 之后、%d s 之前）"
		% [clock2, int(SoliloquyLines.OPENING_FLOOR)]
	)
	storm2.free()
	GameState.reset()


## 摆一份自言自语要的状态出来。**和 hud.gd 里那份逐字对应**：
## 两处的键名一旦分家，模型层会读到默认值、然后静默地什么都不说。
func _soliloquy_state(clock: float, last: float) -> Dictionary:
	return {
		"clock": clock,
		"elapsed": GameState.elapsed,
		"stamina": GameState.stamina,
		"storm_intensity": GameState.storm_intensity,
		"wind_force": GameState.wind_force,
		"mirage_presence": GameState.mirage_presence(),
		"collapsed": GameState.is_collapsed,
		"collapse_elapsed": GameState.collapse_elapsed,
		"last_spoken_at": last,
	}


func _spoken_time(spoken: Array[String], at: Array[float], id: String) -> float:
	var index := spoken.find(id)
	if index < 0:
		return -1.0e9
	return at[index]


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


## 玩家走不出去吗？——把"最坏的一局"真的走一遍，看他能到哪。
##
## 需求方的话是"计算好 4-5 个沙丘以及翻越的时间，让'我'走不出去就行了"。
## 所以这里不假设、不估算：四个最坏组合各跑一遍真实模拟（含沙暴推力），
## 取最远的落点，要求它离地形边还留着一大段余量——
## 那段余量同时也要够雾把边藏起来（1 km 处透射 25%）。
func _test_ground_is_big_enough() -> void:
	print("[地形够不够大]")
	var world := DesertWorld.new()
	var half := world.ground_size * 0.5
	var cases := {
		"走·顺风往 +X": _worst_reach(1.0, false),
		"走·逆风往 -X": _worst_reach(-1.0, false),
		"冲·顺风往 +X": _worst_reach(1.0, true),
		"冲·逆风往 -X": _worst_reach(-1.0, true),
	}
	var farthest := 0.0
	for label: String in cases:
		var reach: float = cases[label]
		print("  （%s：最远到 x=%.0f m）" % [label, reach])
		check(reach < half, "%s 仍在场内（%.0f m < 半边长 %.0f m）" % [label, reach, half])
		farthest = maxf(farthest, reach)
	check(
		half - farthest > 900.0,
		"离最近的边还剩 %.0f m（> 900 m，雾盖得住）" % (half - farthest)
	)
	world.free()


## 让"最坏的一局"真的跑一遍：出生点摆在**要去的方向的另一端**，
## 一路上沙暴该推就推，直到倒下。返回全程里离原点最远的那个 |x|（米）。
##
## 返回的是**全程最大值**而不是终点：出生点本身离原点就有 400 m，
## 只看到没到终点，会把"出生就在边上"这种情况漏掉。
func _worst_reach(direction: float, sprint: bool) -> float:
	var walk := 2.6
	var run := 4.4
	GameState.reset()
	var storm := Sandstorm.new()
	# 出生点最坏位置：朝 +X 走就生在 -400，朝 -X 走就生在 +400。
	var x := -direction * DuneField.VIEWPOINT_SPAN
	var farthest := absf(x)
	var t := 0.0
	var step := 0.05
	var speed := run if sprint else walk
	var exertion := 1.0 if sprint else 0.0
	while not GameState.is_collapsed and t < 900.0:
		storm.advance(step)
		GameState.tick(step, exertion)
		# 沙暴推力和 main 里给玩家的是同一个式子（PEAK_PUSH × intensity）。
		var push := storm.wind_direction * Sandstorm.PEAK_PUSH * storm.intensity
		x += (direction * speed + push.x) * step
		farthest = maxf(farthest, absf(x))
		t += step
	storm.free()
	GameState.reset()
	return farthest


## 倒下之后那条时间线：摔倒 → 喘几口 → 闭眼 → 黑 → 题记。
##
## 全部是纯函数（GameState 上的静态映射），所以这条测试不需要场景：
## 镜头怎么沉、喘气多快、眼睑什么时候合，读的都是同一条曲线上的不同点。
func _test_collapse_timeline() -> void:
	print("[倒下之后的时间线]")
	var fall := GameState.FALL_SECONDS
	var gasp := GameState.GASP_SECONDS
	var close := GameState.CLOSE_SECONDS

	check(is_equal_approx(GameState.fall_at(-1.0), 0.0), "没倒下就是站着的")
	check(is_equal_approx(GameState.fall_at(0.0), 0.0), "倒下那一瞬还没摔下去")
	check(
		is_equal_approx(GameState.fall_at(fall), 1.0),
		"%.1f s 之后摔定（膝盖软 → 侧倒）" % fall
	)
	check(
		GameState.fall_at(fall * 0.5) > 0.6 and GameState.fall_at(fall * 0.5) < 0.85,
		"摔到一半时进度 %.2f（缓出，不是匀速）" % GameState.fall_at(fall * 0.5)
	)

	# 闭眼必须**晚于**摔倒 + 那几口粗气：先喘，再合眼。
	check(is_equal_approx(GameState.eye_close_at(0.0), 0.0), "倒下那一瞬眼睛还睁着")
	check(is_equal_approx(GameState.eye_close_at(fall), 0.0), "摔倒的过程中还睁着")
	check(
		is_equal_approx(GameState.eye_close_at(fall + gasp), 0.0),
		"喘完那几口才合眼（%.1f s 时还睁着）" % (fall + gasp)
	)
	var mid := GameState.eye_close_at(fall + gasp + close * 0.5)
	check(mid > 0.3 and mid < 0.7, "合到一半时开合度 %.2f" % mid)
	check(
		is_equal_approx(GameState.eye_close_at(fall + gasp + close), 1.0),
		"%.1f s 之后眼睛合上" % (fall + gasp + close)
	)
	var monotone := true
	var prev := -1.0
	for i in range(400):
		var v := GameState.eye_close_at(float(i) * 0.05)
		if v < prev - 0.0001:
			monotone = false
		prev = v
	check(monotone, "眼睑只会越合越紧，不会自己睁开")

	# 呼吸：越累越快越深；倒下之后先急喘，再一路慢下来。
	check(
		GameState.pant_rate(1.0, -1.0) < GameState.pant_rate(0.0, -1.0),
		"越累喘得越快（%.2f → %.2f Hz）"
		% [GameState.pant_rate(1.0, -1.0), GameState.pant_rate(0.0, -1.0)]
	)
	check(
		GameState.pant_rate(0.0, 0.0) > GameState.pant_rate(0.0, 9.0),
		"倒下之后先急喘、再慢下来（%.2f → %.2f Hz）"
		% [GameState.pant_rate(0.0, 0.0), GameState.pant_rate(0.0, 9.0)]
	)
	check(
		GameState.pant_depth(0.0, -1.0) > GameState.pant_depth(1.0, -1.0),
		"累的时候喘得更深（%.3f → %.3f m）"
		% [GameState.pant_depth(1.0, -1.0), GameState.pant_depth(0.0, -1.0)]
	)
	check(
		GameState.pant_depth(0.0, 12.0) < GameState.pant_depth(0.0, 0.0),
		"最后那几口气越来越浅"
	)

	# 时间线本身要由 tick 推着走（不然闭眼永远停在第一帧）
	GameState.reset()
	check(GameState.collapse_elapsed < 0.0, "没倒下时没有倒下计时")
	GameState.tick(GameState.ENDURANCE_SECONDS * 2.0, 0.0)
	check(GameState.is_collapsed, "体力耗尽即倒下")
	check(is_equal_approx(GameState.collapse_elapsed, 0.0), "倒下那一刻计时从 0 起步")
	GameState.tick(3.0, 0.0)
	check(GameState.collapse_elapsed > 2.9, "倒下之后时间继续走（%.1f s）" % GameState.collapse_elapsed)
	GameState.reset()


## 喘气的声音层。headless 里没有声卡，听不到声音，但**波形本身**是可以量的：
## 包络形状、两个方向的亮度、峰值不削顶、有实际能量。
func _test_breath() -> void:
	print("[喘气]")
	check(
		Breath.envelope_at(0.05) < Breath.envelope_at(0.25),
		"吸气是渐起的（%.2f → %.2f）" % [Breath.envelope_at(0.05), Breath.envelope_at(0.25)]
	)
	check(
		Breath.envelope_at(0.45) > Breath.envelope_at(0.30),
		"呼气比吸气响（%.2f > %.2f）——这一声才是粗气"
		% [Breath.envelope_at(0.45), Breath.envelope_at(0.30)]
	)
	check(Breath.envelope_at(0.95) < 0.001, "两次呼吸之间收干净（留出间隙）")
	var peak := 0.0
	for i in range(400):
		peak = maxf(peak, Breath.envelope_at(float(i) / 400.0))
	check(peak <= 1.0 and peak > 0.9, "包络峰值在 1 以内、也不虚（%.2f）" % peak)
	check(
		Breath.inhale_share(0.1) > 0.9 and Breath.inhale_share(0.6) < 0.1,
		"吸气的声门亮、呼气收紧（滤波器截止跟着相位走）"
	)

	var breath := Breath.new()
	add_child(breath)
	await get_tree().process_frame
	check(breath.stream != null, "喘气挂上了流")
	check(breath.playing, "进关就开始喘")
	var peak_sample := 0.0
	var energy := 0.0
	var n := 8192
	for i in range(n):
		var v := breath.next_sample(0.6 / Breath.MIX_RATE)
		peak_sample = maxf(peak_sample, absf(v))
		energy += v * v
	var rms := sqrt(energy / float(n))
	check(peak_sample <= 1.0, "不削顶（峰值 %.2f）" % peak_sample)
	check(rms > 0.02 and rms < 0.6, "有实际气流能量（RMS %.3f）" % rms)
	breath.stop()
	breath.free()
	check(not is_instance_valid(breath), "喘气节点已析构")


## 风声。和 [喘气] 同一路：headless 里没有声卡，但波形可以量。
##
## 这一条要守的**不是"有没有声音"，而是"风大了是不是真的更像风"**：
## 只把同一个噪声调响，听上去是"音量变了"；风压上来的时候，
## **频谱是往上抬的**——低频的滚动里冒出沙粒打在空气里的高频。
## 所以量两样：能量（更响）和过零率（更亮）。
func _test_wind_sound() -> void:
	print("[风声]")
	var wind := Wind.new()
	add_child(wind)
	await get_tree().process_frame
	check(wind.stream != null, "风声挂上了流")
	check(wind.playing, "进关就开始吹")
	GameState.reset()

	GameState.wind_force = 0.0
	var calm := _sample_stats(wind, 12000)
	GameState.wind_force = 0.35
	var breeze := _sample_stats(wind, 12000)
	GameState.wind_force = 1.0
	var gale := _sample_stats(wind, 12000)
	print(
		"  （噪声 RMS：无风 %.4f / 半风 %.4f / 满风 %.4f；过零率 %.3f / %.3f / %.3f）"
		% [
			calm["rms"], breeze["rms"], gale["rms"],
			calm["zcr"], breeze["zcr"], gale["zcr"],
		]
	)
	check(float(calm["peak"]) <= 1.0 and float(gale["peak"]) <= 1.0, "不削顶（峰值 %.2f）" % gale["peak"])
	check(float(calm["rms"]) < 0.02, "无风时几乎静音（RMS %.4f）——不能有一条常驻的'白噪底'" % calm["rms"])
	check(float(breeze["rms"]) > float(calm["rms"]) * 3.0, "起风就听得出来（RMS %.4f）" % breeze["rms"])
	check(
		float(gale["rms"]) > float(breeze["rms"]) * 1.8,
		"压顶时更响（RMS %.4f → %.4f）" % [breeze["rms"], gale["rms"]]
	)
	check(
		float(gale["zcr"]) > float(calm["zcr"]) * 1.3,
		"风越大越亮（过零率 %.3f → %.3f）——不是把同一个声音调大" % [calm["zcr"], gale["zcr"]]
	)

	# 合眼之后一路退到静音：和喘气同一条规矩，也和眼睑同一条时间线。
	GameState.is_collapsed = true
	GameState.collapse_elapsed = 9.0
	check(wind.fade_level() < 0.2, "眼睑合上时风声退下去（%.2f）" % wind.fade_level())
	GameState.collapse_elapsed = 20.0
	check(wind.fade_level() < 0.001, "彻底黑掉之后是静音（%.4f）" % wind.fade_level())
	GameState.reset()
	wind.stop()
	wind.free()


## 量一段噪声：峰值、RMS、过零率（过零率是"亮不亮"的粗读数）。
func _sample_stats(wind: Wind, n: int) -> Dictionary:
	var peak := 0.0
	var energy := 0.0
	var crossings := 0
	var previous := 0.0
	for i in range(n):
		var v := wind.next_sample(1.0 / Wind.MIX_RATE)
		peak = maxf(peak, absf(v))
		energy += v * v
		if i > 0 and ((v >= 0.0) != (previous >= 0.0)):
			crossings += 1
		previous = v
	return {
		"peak": peak,
		"rms": sqrt(energy / float(n)),
		"zcr": float(crossings) / float(n),
	}


## HUD：**不许有水囊，也不许有里程**。
##
## 这两条是需求方点名的（"不应该是水囊的概念"、"也不要给玩家显示走了多少米"），
## 而"界面上没有某个词"这件事只有把文本全捞出来看才算验过——
## 靠肉眼在截图里找，改代码的人随手加回一行也不会有人发现。
func _test_hud_meters() -> void:
	print("[HUD：没有水囊，没有里程]")
	var hud := Hud.new()
	add_child(hud)
	await get_tree().process_frame

	var texts: Array[String] = []
	_collect_text(hud, texts)
	var joined := "｜".join(texts)
	check(not joined.contains("水囊"), "界面上没有水囊（当前：%s）" % joined)
	check(not joined.contains("米"), "界面上不报米数（当前：%s）" % joined)
	check(not joined.contains("已行"), "界面上没有里程（当前：%s）" % joined)
	check(joined.contains("体力"), "掉的是体力（当前：%s）" % joined)

	var bars: Array[ProgressBar] = []
	_collect_bars(hud, bars)
	check(bars.size() == 1, "只有一条体力条（%d 条）" % bars.size())
	if bars.size() == 1:
		check(not bars[0].show_percentage, "条上不带百分比——不报数字才是这一版的要求")

	hud.free()


func _collect_text(node: Node, out: Array[String]) -> void:
	var label := node as Label
	if label != null and not label.text.is_empty():
		out.append(label.text)
	for child in node.get_children():
		_collect_text(child, out)


func _collect_bars(node: Node, out: Array[ProgressBar]) -> void:
	var bar := node as ProgressBar
	if bar != null:
		out.append(bar)
	for child in node.get_children():
		_collect_bars(child, out)


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

	# 1) 横向量不出来：正面城墙的角楼必须在半水平视角之外。
	#
	# **两端都要查**，而且两端的 z 不一样：城郭整体右移了 CITY_SIDE（让开被
	# 弥勒像挡住的那根轴线，见 Mirage.CITY_SIDE），于是它是**不对称**的——
	#   左端 = CITY_LEFT_END（钉死不动，它才是"量不出来"的那条线）
	#   右端 = CITY_SIDE + CITY_HALF（跟着城一起往右长）
	# 只查一头的话，把 CITY_SIDE 往左调就会悄悄放左端进画面，而测试还是绿的。
	var corners := {
		"左端": Vector3(origin.x - Mirage.CITY_HALF, origin.y + Mirage.WALL_H, origin.z + Mirage.CITY_LEFT_END),
		"右端": Vector3(
			origin.x - Mirage.CITY_HALF,
			origin.y + Mirage.WALL_H,
			origin.z + Mirage.CITY_SIDE + Mirage.CITY_HALF
		),
	}
	for label: String in corners:
		var corner: Vector3 = corners[label]
		var corner_azimuth := rad_to_deg(atan2(absf(corner.z - eye.z), corner.x - eye.x))
		check(
			corner_azimuth > half_h,
			"城墙%s切出画外（角楼方位 %.0f° > 半视角 %.0f°）" % [label, corner_azimuth, half_h]
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
		origin.z + Mirage.CITY_SIDE
	)
	var tower_elev := _elevation(eye, tower_top)
	check(
		tower_elev < head_elev,
		"主塔低于弥勒（%.1f° < %.1f°）——巨物要有唯一的顶点" % [tower_elev, head_elev]
	)

	# 4) **佛塔不能让佛挡住**（需求方 2026-09-24 的红框截图）。
	#
	# 弥勒像站在城墙之前 480 m、横向偏到玩家左手边，从玩家看过去它占了画面
	# 左半边；城郭原来的中轴在方位 0°，主塔和城门楼正好**贴着像的右缘**立
	# 起来，被挡掉一半。修法是把城整体右移 CITY_SIDE——不是把像挪走（像一动，
	# 逆光的太阳也得跟着动，那张构图是定下来的）。
	#
	# 这条断言把"让开多少"变成可量的数：地标的最左缘必须比像的剪影右缘再往
	# 右 CITY_CLEARANCE_DEG 度。**像的右缘必须按画面上看得见的那一段量**，
	# 不能用包围盒：像身最宽处在 0.55h 的举臂那一层，而它已经在画面上沿之外，
	# 用包围盒会量出 +31°，把整座城都逼出画面。
	var statue := mirage.get_node_or_null("Statue") as MeshInstance3D
	if statue == null:
		check(false, "像身缺失，验不了“佛塔不能被佛挡住”")
	else:
		var scale := Mirage.statue_scale
		var flat := Vector2(statue_x - eye.x, statue_z - eye.z).length()
		var band_top := eye.y + flat * tan(deg_to_rad(half_v))
		var verts: PackedVector3Array = statue.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var statue_right := -INF
		for v: Vector3 in verts:
			if origin.y + v.y * scale - Mirage.statue_sink() > band_top:
				continue
			statue_right = maxf(statue_right, statue_z + v.z * scale)
		var statue_right_az := rad_to_deg(atan2(statue_right - eye.z, statue_x - eye.x))
		# 两个地标都量：主塔（最靠左、也最高）和城门楼（最近、第一个认得出的
		# 建筑）。各自的"左缘"= 中心方位减去自身半宽。
		var marks := {
			"主塔": Vector3(
				tower_top.x,
				0.0,
				origin.z
				+ Mirage.CITY_SIDE
				- Mirage.TIER_WIDTHS[0] * Mirage.TOWER_SCALE * 0.5
			),
			"城门楼": Vector3(
				origin.x - Mirage.CITY_HALF,
				0.0,
				origin.z + Mirage.CITY_SIDE - Mirage.GATE_HEIGHT * 0.46 * 0.5
			),
		}
		for label: String in marks:
			var mark: Vector3 = marks[label]
			var left_az := rad_to_deg(atan2(mark.z - eye.z, mark.x - eye.x))
			check(
				left_az - statue_right_az >= Mirage.CITY_CLEARANCE_DEG,
				"%s的左边没被弥勒挡住（让出 %.1f° ≥ %.0f°：%s左缘 %.1f° vs 像右缘 %.1f°）"
				% [
					label,
					left_az - statue_right_az,
					Mirage.CITY_CLEARANCE_DEG,
					label,
					left_az,
					statue_right_az
				]
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


func _test_bgm() -> void:
	print("[背景音乐]")
	check(ResourceLoader.exists(Bgm.TRACK_PATH), "BGM 文件在库里")
	var track: AudioStreamMP3 = load(Bgm.TRACK_PATH) as AudioStreamMP3
	check(track != null, "BGM 能作为 AudioStreamMP3 载入")
	if track == null:
		return
	# 74 s 是 ffprobe 量出来的时长。断言写成一个区间：
	# 既挡住"文件是空的"，也挡住"哪天误换了另一段几秒的音频"。
	var length := track.get_length()
	check(
		length > 60.0 and length < 90.0,
		"曲子长度 %.1f s 落在剪辑版应有的区间（60~90 s）" % length
	)

	var music := Bgm.new()
	add_child(music)
	await get_tree().process_frame
	check(music.stream != null, "BGM 节点挂上了流")
	check(track.loop, "整曲循环（开在 .import 的 loop=true 里）")
	check(music.playing, "进关即播")
	check(
		is_equal_approx(music.volume_db, Bgm.VOLUME_DB),
		"音量就是基准（%.1f dB）" % music.volume_db
	)
	music.stop()
	check(not music.playing, "stop() 之后不再出声")
	# queue_free() + 等一帧，而不是当场 free()。这条断言的目的是"节点真的没了"，
	# 不是"它消失得有多年内"——而当场拆一枚刚停下的播放器，音频那一侧未必已经
	# 把播放实例收回去。一帧的代价，换确定的收尾。
	music.queue_free()
	await get_tree().process_frame
	check(not is_instance_valid(music), "BGM 节点已析构")
	#
	# 已知噪声（不是失败原因）：headless 退出时 Godot 会报
	#   WARNING: 2 ObjectDB instances were leaked at exit
	#   ERROR: 1 resources still in use at exit
	# 指的是这枚 AudioStreamMP3 和它的 playback。最小复现是**不跑任何测试、
	# 只跑 scenes/main.tscn** 也一样报，多等 10 秒也不消失——那是音频服务在
	# 没有音频设备时的收尾行为，和这一关的代码无关。判定仍看 ALL TESTS PASSED。


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

	# 再空三帧：这套测试拆过重场景又马上建新的，headless 下偶尔会崩在原生层。
	# 一帧不够（实测只把崩溃率从 ~50% 压到 ~20%），三帧干净。
	for i in range(3):
		await get_tree().process_frame
	var instance: Node = scene.instantiate()
	add_child(instance)
	# 地形是程序化生成的，给它一帧把 _ready 跑完
	await get_tree().process_frame

	check(instance.get("world") != null, "沙丘世界已建")
	check(instance.get("player") != null, "行者已建")
	check(instance.get("storm") != null, "沙暴系统已建")
	check(instance.get("hud") != null, "HUD 已建")
	check(instance.get("bgm") != null, "BGM 已建")
	check(instance.get("breath") != null, "喘气层已建")
	check(instance.get("wind") != null, "风声层已建")
	var world: Node = instance.get("world")
	check(world != null and world.get("dune") != null, "高度场已就绪")
	# 临终那只手挂在相机上。它平时是隐藏的，但**必须已经建好**——
	# 建在"倒下那一刻"是来不及的：那正是画面最不能卡的一帧。
	var player: Node = instance.get("player")
	var hand: Node = player.call("hand") if player != null else null
	check(hand != null, "右手已经挂在相机上")
	check(hand != null and not hand.visible, "平时藏着（只在倒下之后伸出来）")
	# 同上：带着 BGM 的场景必须立刻拆干净，不能留给帧末的延迟删除队列。
	instance.free()


# ---------------------------------------------------------------------------


## 汇总。
##
## ⚠️ **要看到这两行，请用 TTY 跑**（本仓库的 `--headless ... | Select-String`
## 会把 stdout 变成管道，Windows 版 Godot 在这个组合下退出时会丢尾、exit code
## 变成 0xC0000005）。曾在 `quit()` 前加 `await process_frame` 试过，
## 反而变成每次都崩。结论：**读测试结果要么走 TTY，要么看退出码**，
## 别把"缺汇总"当成"没跑完"。
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
