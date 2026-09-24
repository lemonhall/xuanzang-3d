extends Node

## 截图工具：跑真实渲染（不能是 --headless，dummy 渲染器没有帧缓冲），
## 等场景稳定后存 PNG 再退出。窗口只会出现两三秒。
##
## 用法：
##   godot --path . tools/capture.tscn -- --out D:\shot.png --frames 130 [--storm] [--thirsty]
##       [--pitch 40] [--yaw 90]
##       [--statue-scale 10] [--statue-dist 1300] [--statue-probe]
##
## `--pitch` / `--yaw` 是视角探针：抬头、转身各拍一张，用来判断"看到的天空
## 到底是什么形状"。默认（都不给）就是开局那个水平正前方的机位。
##
## `--statue-scale` 覆盖弥勒像的倍率（城郭不动）。**不填就跟随设计态**，
## 当前设计态是 4 倍（见 Mirage.statue_scale 的注释）。`--statue-dist`
## 把它摆到正前方多少米。两个一起用就能拍"放大 N 倍、观距不变"和
## "放大 N 倍、观距也乘 N"的对照——后者是**保角**的，画面里的像一模一样大，
## 只是地面和沙丘的相对尺度变了。

var _main: Node
## 相对开局朝向的偏航角（度），正值向右转。
var _yaw_offset_deg := 0.0
## 俯仰角（度），正值抬头。
var _pitch_deg := 0.0
## 像身倍率。落到 Mirage.statue_scale 上，必须在实例化场景**之前**写。
##
## 初值**不能**写死 1.0：那样截图工具会静默地把设计态（4 倍）按回原尺寸，
## 拍出来的东西和游戏里看到的不是一回事——而"截图和游戏不一致"是最难查的
## 那类问题。默认跟随设计态，只有显式给 `--statue-scale` 才覆盖。
var _statue_scale := Mirage.statue_scale
## 像身离玩家的水平距离（米）。INF = 不摆位，按 main 的默认构图。
var _statue_dist := INF
## 沙暴探针 / 素材质探针：解析阶段记下来，场景有了再应用。
var _force_storm := false
var _mirage_debug := false
var _statue_debug := false
## 幻影被"按住"的世界坐标（Vector3.INF 表示不按住）。
## main._update_mirage 每帧都会把幻影拽回玩家正前方，所以调试用的摆位
## 必须每帧重设一次——一次性赋值活不过一帧。上一版的 --mirage-near 就
## 是这么失效的：它设了位置，然后被下一帧覆盖，截图里什么都没变。
var _hold_position := Vector3.INF
## 截图输出路径。参数解析时填，_save_and_quit 里用。
var _out_path := "user://capture.png"
## 等多少帧再截图：头几十帧用来生成地形、编译着色器、让雾和光照稳定下来。
var _frames_needed := 90
var _frames_done := 0
## 参数解析、摆位都做完之后才允许 _process 干活。
var _capturing := false
## --statue-probe 把弥勒像摆在正前方多少米。1300 m 时整尊（含举身光）
## 从脚到光顶占 ~34°，抬头 20° 正好把它整整齐齐装进画面。
const STATUE_PROBE_DIST := 1300.0


func _ready() -> void:
	# 参数先解析：`--statue-scale` 必须在 Mirage 实例化**之前**落到静态变量上，
	# 因为像身和举身光的形状是在 Mirage._ready() 里按当时的倍率拼出来的。
	_parse_args()
	Mirage.statue_scale = _statue_scale

	var main_scene: PackedScene = load("res://scenes/main.tscn")
	_main = main_scene.instantiate()
	add_child(_main)
	# **必须比 main 晚跑**：main 的 _process 每帧都会把幻影拽回玩家正前方，
	# 赶在它前面写 _hold_position 等于没写。上一版的 --statue-probe 和
	# --mirage-near 就是这样静默失效的——截图拍出来还是默认机位的样子，
	# 而诊断又在"刚写完、还没被覆盖"的那一刻取数，于是连数字也是错的。
	# process_priority 越大越晚跑，main 是默认的 0。
	process_priority = 100
	_aim()
	if not is_inf(_statue_dist):
		# 按住之后 main 不再把幻影贴地形，脚底会浮在 y=0 上。这里手动取一次
		# 地面高度补回来——不然"像浮在沙面上/埋进沙丘里"会被误读成构图问题。
		var world: Node = _main.get("world")
		if world != null:
			_hold_position.y = world.call("height_at", _hold_position.x, _hold_position.z) + 10.0
	if _force_storm:
		# 把沙暴钉在峰值。直接改 Sandstorm 的内部阶段，因为它的
		# _physics_process 每帧都会按阶段重算强度。
		var storm: Node = _main.get("storm")
		if storm != null:
			storm.set("_phase", 2)
			storm.set("_timer", 0.0)
			storm.force_intensity(0.95)
		GameState.water = 0.18
	if _mirage_debug:
		_swap_mirage_material()
	if _statue_debug:
		_swap_mirage_material("Statue")
	var dist_text := "默认构图"
	if not is_inf(_statue_dist):
		dist_text = "%.0f m" % _statue_dist
	print("DIAG args: statue_scale=%.2f statue_dist=%s" % [_statue_scale, dist_text])
	_capturing = true


func _process(_delta: float) -> void:
	if not _capturing:
		return
	_apply_hold()
	_frames_done += 1
	if _frames_done < _frames_needed:
		return
	_capturing = false
	# 诊断要贴在**这一帧真正拿去渲染的状态**上：先跑完 _apply_hold 再量，
	# 角度和屏幕坐标才和截图对得上。
	_diagnose()
	_save_and_quit()


## 每帧把幻影按回探针指定处。main._update_mirage 每帧都会覆盖它，
## 所以重设也必须是每帧一次——一次性赋值活不过一帧。
func _apply_hold() -> void:
	if _hold_position == Vector3.INF:
		return
	var mirage: Node3D = _main.get("mirage")
	if mirage != null:
		mirage.global_position = _hold_position


## 存图并退出。
func _save_and_quit() -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(_out_path)
	if err == OK:
		print("CAPTURED: ", _out_path)
	else:
		print("CAPTURE FAILED (%d): %s" % [err, _out_path])
	get_tree().quit(0 if err == OK else 1)


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size():
			_out_path = args[i + 1]
		elif args[i] == "--frames" and i + 1 < args.size():
			_frames_needed = int(args[i + 1])
		elif args[i] == "--storm":
			_force_storm = true
		elif args[i] == "--thirsty":
			# 只把水囊压到低位：幻影会变实，但天是晴的，能看清细节
			GameState.water = 0.06
		elif args[i] == "--mirage-debug":
			# 换成最朴素的不透明品红材质，绕开自定义 shader：
			# 如果这样能看见，就是 shader 的问题；还看不见，就是 mesh 或节点的问题。
			_mirage_debug = true
		elif args[i] == "--statue-debug":
			# 同样的手法，但只涂像身。用来回答一个**眼睛答不了**的问题：
			# "像头到底有没有贴到画面上沿"——逆光下剪影和天空同色，
			# 靠肉眼在截图里找边界是不靠谱的，涂成品红一像素一像素地量。
			_statue_debug = true
		elif args[i] == "--mirage-near":
			_hold_position = Vector3(420.0, -30.0, 60.0)
		elif args[i] == "--statue-probe":
			# 把弥勒像搬到"整尊正好装进画面"的位置，单独看造像剪影：
			# 1300 m 时整尊（含举身光）从脚到光顶占 ~34°，抬头 20° 正好装下。
			_statue_dist = STATUE_PROBE_DIST
			_pitch_deg = 20.0
		elif args[i] == "--statue-scale" and i + 1 < args.size():
			_statue_scale = float(args[i + 1])
		elif args[i] == "--statue-dist" and i + 1 < args.size():
			_statue_dist = float(args[i + 1])
		elif args[i] == "--pitch" and i + 1 < args.size():
			_pitch_deg = float(args[i + 1])
		elif args[i] == "--yaw" and i + 1 < args.size():
			_yaw_offset_deg = float(args[i + 1])

	if not is_inf(_statue_dist):
		_hold_position = _statue_hold_position(_statue_dist)


## 把幻影按住，使像身落在**正前方 `dist` 米、方位 0°、脚下就是沙面**。
##
## 幻影原点在城中心，像身在本地的
## (-CITY_HALF - STATUE_FRONT_OF_WALL, 0, STATUE_SIDE)。
## 节点摆到 (dist + CITY_HALF + STATUE_FRONT_OF_WALL, 0, -STATUE_SIDE) 时，
## 像身正好在正前方 dist 米处。机位全部由常数推出来，改了城或像的摆位
## 这里不用手改数字。
func _statue_hold_position(dist: float) -> Vector3:
	return Vector3(
		dist + Mirage.CITY_HALF + Mirage.STATUE_FRONT_OF_WALL,
		0.0,
		-Mirage.STATUE_SIDE
	)

## 把玩家摆到探针指定的朝向。开局朝向是 main.gd 里的 START_YAW，
## 这里给的是**相对值**，所以不填就是原样。
func _aim() -> void:
	if is_zero_approx(_yaw_offset_deg) and is_zero_approx(_pitch_deg):
		return
	var player: Node = _main.get("player")
	if player == null:
		print("DIAG: player missing, cannot aim")
		return
	# 与 main.gd 的 START_YAW 一致：绕 Y 轴 -90° 时视线指向 +X。
	var base := -PI * 0.5
	player.set("_yaw", base + deg_to_rad(_yaw_offset_deg))
	player.set("_pitch", deg_to_rad(_pitch_deg))
	player.set("rotation", Vector3(0.0, base + deg_to_rad(_yaw_offset_deg), 0.0))
	var cam: Camera3D = player.call("camera")
	if cam != null:
		cam.rotation.x = deg_to_rad(_pitch_deg)
	print(
		"DIAG aim yaw=%.1f deg pitch=%.1f deg"
		% [rad_to_deg(base) + _yaw_offset_deg, _pitch_deg]
	)


## 幻影"看不见"的时候，靠猜是没用的——把它的可见性、世界位置、
## 以及它顶端投影到屏幕的坐标全打出来，就能判断是没渲染还是不在画面里。
func _diagnose() -> void:
	var mirage: Node3D = _main.get("mirage")
	var player: Node = _main.get("player")
	if mirage == null or player == null:
		print("DIAG: mirage or player missing")
		return

	var cam: Camera3D = player.camera()
	# 雾在 2 km 处的透射率：这就是幻影"消失"的第一嫌疑
	var fog := _main.get_node_or_null("Desert/WorldEnvironment")
	if fog != null:
		var env: Environment = fog.environment
		print(
			"DIAG fog enabled=%s density=%.4f  transmittance@2km=%.5f"
			% [env.fog_enabled, env.fog_density, exp(-env.fog_density * 2000.0)]
		)
	# shader 编译失败时 uniform 列表会不完整，用它当编译状态的探针
	var mirage_mat: ShaderMaterial = mirage.get("_material")
	if mirage_mat != null and mirage_mat.shader != null:
		print(
			"DIAG shader uniforms=%d strength=%.2f"
			% [
				mirage_mat.shader.get_shader_uniform_list().size(),
				mirage_mat.get_shader_parameter("strength"),
			]
		)
	print(
		"DIAG mirage visible=%s presence=%.2f pos=%s"
		% [mirage.visible, mirage.get("presence"), mirage.global_position]
	)
	print(
		"DIAG cam pos=%s fwd=%s far=%.0f fov=%.1f"
		% [cam.global_position, -cam.global_transform.basis.z, cam.far, cam.fov]
	)
	var top := mirage.global_position + Vector3(0.0, 650.0, 0.0)
	print(
		"DIAG base in_frustum=%s screen=%s"
		% [
			cam.is_position_in_frustum(mirage.global_position),
			cam.unproject_position(mirage.global_position),
		]
	)
	print(
		"DIAG top  in_frustum=%s screen=%s"
		% [cam.is_position_in_frustum(top), cam.unproject_position(top)]
	)
	# 视线前方的地形剖面：用来判断"地平线被沙丘顶到几度"，
	# 幻影的可见区间就是由这条曲线决定的。
	print("DIAG cam rotation=%s" % cam.global_rotation_degrees)
	_diagnose_landmarks(cam, mirage)
	var world: Node = _main.get("world")
	if world != null:
		for d: float in [20.0, 50.0, 100.0, 200.0, 400.0]:
			var px := cam.global_position.x + d
			var ground: float = world.height_at(px, cam.global_position.z)
			print(
				"  +%.0f m: ground=%.1f  elev=%.1f deg"
				% [d, ground, rad_to_deg(atan2(ground - cam.global_position.y, d))]
			)


## 把幻影的关键点从**世界坐标**算到**高度角 / 方位角 / 屏幕像素**。
##
## 截图看"巨物感"是主观的，量高度角不是：城墙几度、像头几度、举身光顶点几度，
## 这三个数一摆出来，"它是不是盖住了头顶"就没有争论余地了。
## 屏幕像素同时算，是为了跟截图直接对上——对不上就说明代码和眼睛看到的不是一回事。
func _diagnose_landmarks(cam: Camera3D, mirage: Node3D) -> void:
	var o := mirage.global_position
	var eye := cam.global_position
	var statue_x := o.x - Mirage.CITY_HALF - Mirage.STATUE_FRONT_OF_WALL
	var statue_z := o.z + Mirage.STATUE_SIDE
	var tower_x := o.x + Mirage.TOWER_BEHIND_WALL - Mirage.CITY_HALF

	var points := {
		"城墙顶": Vector3(o.x - Mirage.CITY_HALF, o.y + Mirage.WALL_H, o.z),
		"城门楼顶": Vector3(o.x - Mirage.CITY_HALF, o.y + Mirage.GATE_HEIGHT, o.z),
		"主塔顶": Vector3(tower_x, o.y + Mirage.TOTAL_HEIGHT, o.z),
		# 像的高度一律走 statue_top_y()：它已经扣掉埋进沙里的台座。
		# 直接写 STATUE_HEIGHT 会把那 16% 的展台又算进去，量出来的仰角
		# 比画面上看到的偏高——这正是上一轮"诊断说头在画面里、
		# 截图里却贴着上沿"的那类错。
		"弥勒顶": Vector3(statue_x, o.y + Mirage.statue_top_y(), statue_z),
		"弥勒头": Vector3(statue_x, o.y + Mirage.statue_top_y(), statue_z),
		"弥勒脚": Vector3(statue_x, o.y - Mirage.statue_sink(), statue_z),
		"举身光顶": Vector3(
			statue_x + Mirage.statue_height() * Mirage.HALO_BEHIND_RATIO,
			o.y + Mirage.halo_top_y(),
			statue_z
		),
	}
	for label: String in points:
		var p: Vector3 = points[label]
		var flat := Vector2(p.x - eye.x, p.z - eye.z)
		var elevation := rad_to_deg(atan2(p.y - eye.y, flat.length()))
		# 方位角：正向 = 玩家默认朝向 +X，向 +Z 偏为正
		var azimuth := rad_to_deg(atan2(p.z - eye.z, p.x - eye.x))
		var on_screen := cam.is_position_in_frustum(p)
		print(
			"  %s: 距离 %.0f m  仰角 %.1f°  方位 %+.1f°  在画面内=%s  屏幕=%s"
			% [label, flat.length(), elevation, azimuth, on_screen, cam.unproject_position(p)]
		)


func _tint_mirage(color: Color) -> void:
	var mirage: Node3D = _main.get("mirage")
	if mirage == null:
		return
	var material: ShaderMaterial = mirage.get("_material")
	if material == null:
		print("DIAG: mirage material missing")
		return
	material.set_shader_parameter("tint", color)
	print("DIAG: mirage tint forced to %s" % color)


func _swap_mirage_material(node_name := "Loulan") -> void:
	var mirage: Node3D = _main.get("mirage")
	if mirage == null:
		return
	var instance: MeshInstance3D = mirage.get_node_or_null(node_name)
	if instance == null:
		print("DIAG: %s node missing" % node_name)
		return
	var plain := StandardMaterial3D.new()
	plain.albedo_color = Color(1.0, 0.0, 1.0)
	plain.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	instance.material_override = plain
	print(
		"DIAG: %s swapped to plain magenta; surfaces=%d aabb=%s"
		% [node_name, instance.mesh.get_surface_count(), instance.get_aabb()]
	)
