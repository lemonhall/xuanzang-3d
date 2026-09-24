extends Node

## 截图工具：跑真实渲染（不能是 --headless，dummy 渲染器没有帧缓冲），
## 等场景稳定后存 PNG 再退出。窗口只会出现两三秒。
##
## 用法：
##   godot --path . tools/capture.tscn -- --out D:\shot.png --frames 130 [--storm] [--tired]
##       [--pitch 40] [--yaw 90]
##       [--statue-scale 10] [--statue-dist 1300] [--statue-probe]
##       [--collapsed 6.5] [--player-x 3000]
##
## `--pitch` / `--yaw` 是视角探针：抬头、转身各拍一张，用来判断"看到的天空
## 到底是什么形状"。默认（都不给）就是开局那个水平正前方的机位。
##
## `--walk <米/秒>` 让行者真的走起来。**走路那一身晃（每一脚的下陷、左右摆、
## 滚转）只在移动时才存在**——站着拍，每一格都是同一个姿势，
## 而"走路时左摇右摆太过"这种毛病恰恰只在走动里看得出来。
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
## 体力探针（--tired）。**必须在每一帧写**，不能在 _ready 里写一次：
## main 的 _ready 会调 GameState.reset()，把体力恢复成满的——上一版就是
## 这么静默失效的，`--tired` 拍出来和开局一模一样（连 strength 都是 0.57）。
var _tired_probe := false
## 倒下之后第几秒（秒）。>=0 就把这一局的体力直接打到 0、并把倒下之后的时间
## 钉在这一刻上，用来拍"摔倒 / 伸手 / 闭眼"这几格。不填 = 站着。
var _collapse_probe := -1.0
## 把玩家沿 +X 挪多远（米）。用来验证"沙漠没有边"。
var _player_x := 0.0
## 走路探针：让行者以这个速度一直向前。0 = 站着（默认）。
##
## 这里不碰 Wanderer 的输入逻辑，只是每帧把 velocity 写回去——行者自己的
## _physics_process 会把它朝"没有输入"的方向拉，所以必须每帧重写一次
## （和 _apply_hold 同一个道理）。
var _walk_speed := 0.0
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
	print(
		"DIAG aim yaw=%.1f deg pitch=%.1f deg"
		% [rad_to_deg(-PI * 0.5) + _yaw_offset_deg, _pitch_deg]
	)
	# 探针场景**不接受输入**。不关掉的话，桌面上的鼠标事件会把行者的
	# _yaw / _pitch 改掉——同一组参数两次拍出来构图完全不一样，
	# 而"截图对不上"是最难查的那类问题（2026-09-24 实测踩到）。
	var pawn: Node = _main.get("player")
	if pawn != null:
		pawn.set_process_unhandled_input(false)
	if _player_x != 0.0:
		# 沿 +X 挪出去，验"这块沙漠够不够大、还有没有边"。地形是一整块，
		# 挪过去不用等任何东西，第一帧就该是完整的沙丘。
		var body := pawn as Node3D
		if body != null:
			body.global_position += Vector3(_player_x, 0.0, 0.0)
	if _collapse_probe >= 0.0:
		GameState.stamina = 0.0
		GameState.is_collapsed = true
		GameState.collapse_elapsed = _collapse_probe
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
		GameState.stamina = 0.18
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
	_pin_collapse()
	_pin_stamina()
	# 朝向每帧重设：参数说了算，鼠标说了不算（见 _aim 的注释）。
	_aim()
	_drive_walk()
	_frames_done += 1
	if _frames_done < _frames_needed:
		return
	_capturing = false
	# 诊断要贴在**这一帧真正拿去渲染的状态**上：先跑完 _apply_hold 再量，
	# 角度和屏幕坐标才和截图对得上。
	_diagnose()
	_save_and_quit()


## 把"倒下之后第几秒"钉住。
##
## main 的 _process 每帧都在推进 `collapse_elapsed`（那是倒下之后的时间线），
## 不钉住的话，--frames 110 = 1.8 秒里镜头会自己往前走一段，
## 同一组参数两次拍出来的就不是同一格。探针要的是**定格**。
func _pin_collapse() -> void:
	if _collapse_probe < 0.0:
		return
	GameState.is_collapsed = true
	GameState.stamina = 0.0
	GameState.collapse_elapsed = _collapse_probe


## 把体力钉在低位，让幻影**变实**（天还是晴的，能看清城的细节）。
##
## GameState.tick() 每帧都在恢复体力，所以这里也得每帧写回去；写成一次性的
## 初始化代码，`--tired` 会静默变成"和开局一样"（见 _tired_probe 的注释）。
func _pin_stamina() -> void:
	if not _tired_probe:
		return
	# stamina 是**比例**（0 空 / 1 满），不是秒数——别拿 ENDURANCE_SECONDS 去乘。
	GameState.stamina = 0.06


## 每帧把幻影按回探针指定处。main._update_mirage 每帧都会覆盖它，
## 所以重设也必须是每帧一次——一次性赋值活不过一帧。
func _apply_hold() -> void:
	if _hold_position == Vector3.INF:
		return
	var mirage: Node3D = _main.get("mirage")
	if mirage != null:
		mirage.global_position = _hold_position


## 走路探针：把行者按给定速度推着走。倒下之后不推（人已经不走了）。
func _drive_walk() -> void:
	if _walk_speed <= 0.0 or GameState.is_collapsed:
		return
	var player: Node = _main.get("player")
	var body := player as CharacterBody3D
	if body == null:
		return
	var forward := -body.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		return
	body.velocity = forward.normalized() * _walk_speed


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
		elif args[i] == "--tired":
			# 只把体力压到低位：幻影会变实，但天是晴的，能看清细节
			_tired_probe = true
		elif args[i] == "--collapsed" and i + 1 < args.size():
			_collapse_probe = float(args[i + 1])
		elif args[i] == "--player-x" and i + 1 < args.size():
			_player_x = float(args[i + 1])
		elif args[i] == "--walk" and i + 1 < args.size():
			_walk_speed = float(args[i + 1])
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
## 这里给的是**相对值**，不填就是"开局那个水平正前方的机位"。
##
## **每帧都要摆**（`_process` 里调）。只在启动时摆一次是不够的：
## 之后任何一次鼠标移动都会改掉行者的 _pitch，构图整个变样。
## 截图工具的第一条契约是"同样的参数拍出同样的图"，所以朝向由这里说了算。
func _aim() -> void:
	var player: Node = _main.get("player")
	if player == null:
		print("DIAG: player missing, cannot aim")
		return
	# 倒下之后**不许插手**：那时候的朝向是身体自己算的（头慢慢转向佛），
	# 探针一覆盖，"临终那一格"就永远拍不到了。这一格必须和游戏里一模一样。
	if _collapse_probe >= 0.0:
		return
	# 与 main.gd 的 START_YAW 一致：绕 Y 轴 -90° 时视线指向 +X。
	var yaw := -PI * 0.5 + deg_to_rad(_yaw_offset_deg)
	var pitch := deg_to_rad(_pitch_deg)
	player.set("_yaw", yaw)
	player.set("_pitch", pitch)
	player.set("rotation", Vector3(0.0, yaw, 0.0))
	var cam: Camera3D = player.call("camera")
	if cam != null:
		cam.rotation.x = pitch


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
		# 城郭整体右移 CITY_SIDE（让开被弥勒像挡住的那根轴线，见 Mirage.CITY_SIDE）。
		# 城里的点一律带上这个偏移，不然诊断报的方位比画面上看到的偏左 800 m。
		"城墙顶": Vector3(o.x - Mirage.CITY_HALF, o.y + Mirage.WALL_H, o.z + Mirage.CITY_SIDE),
		"城门楼顶": Vector3(
			o.x - Mirage.CITY_HALF, o.y + Mirage.GATE_HEIGHT, o.z + Mirage.CITY_SIDE
		),
		"主塔顶": Vector3(tower_x, o.y + Mirage.TOTAL_HEIGHT, o.z + Mirage.CITY_SIDE),
		# "佛塔有没有被佛挡住"这一条只能靠两个边缘量：塔的最左缘 vs 像的最右缘。
		# 像的右缘取肩半宽（0.152h）——白膜在**画面看得见的那一段**（0~0.3h）
		# 最右到 0.156h，两者差 4 m，够用；用整个包围盒会得到 0.35h（那是
		# 画面上沿之外的举臂），把整座城都逼出画面。
		"主塔左缘": Vector3(
			tower_x,
			o.y + Mirage.TOTAL_HEIGHT * 0.5,
			o.z + Mirage.CITY_SIDE - Mirage.TIER_WIDTHS[0] * Mirage.TOWER_SCALE * 0.5
		),
		"弥勒右缘": Vector3(
			statue_x, o.y + Mirage.STATUE_HEIGHT * 0.2, statue_z + Mirage.statue_height() * Mirage.STATUE_SHOULDER_RATIO
		),
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
