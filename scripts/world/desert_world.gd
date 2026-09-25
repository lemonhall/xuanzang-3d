class_name DesertWorld
extends Node3D

## 沙漠世界：地形网格 + 沙尘天空 + 雾 + 太阳。
##
## 全部由代码建出来，没有 .tscn 里手拉的节点，也没有外部素材。
## 参数与 Blender 端一一对应，改一处两边能互相印证。

## 地形边长（米）。**这个数字是算出来的，不是拍的。**
##
## 需求方 2026-09-24 把话说明白了："倒也不必无限沙漠，就计算好 4-5 个沙丘、
## 以及翻越的时间，让'我'走不出去就行了。"——所以这里不做无限地形，
## 只把"走不出去"这件事算清楚：
##
##   一局能走多远   体力基准 195 s，实际结算约 175 s；步速 2.6 m/s → 450 m 上下。
##                  顺风时沙暴额外推（PEAK_PUSH × 风向的 x 分量，最多 2.45 m/s），
##                  所以最坏是"顺风走满一局"：约 600 m。
##   出生点能有多偏  find_viewpoint 在 ±VIEWPOINT_SPAN（400 m）里挑。
##   于是           |最远到达| ≤ 400 + 600 = 1000 m。
##
## 4096（半边长 2048）留了一倍余量：**离最近的边至少还有 1000 m**。
## 而深度雾在 1 km 处只剩 25% 的透射、2 km 处 6%——这个边既走不到，也看不见。
## 也就是说"绵延不断"不需要无限地形，一块 4 km 见方的沙丘就够了，
## 而且比铺 25 块便宜得多。上面那两个数由 tests 里的 [地形够不够大] 实测。
##
## 网格 8 m（512 段），上一版是 5.33 m（384 段）。可以粗一档的原因：沙丘剖面
## 是 pow(cos, 3.4)，**脊顶和谷底都是平的**，最陡处才在腰上——8 m 步长在最陡
## 那一点的插值误差约 0.2 m（30 m 高的沙丘），画面上看不出来。
## 顶点 263k、三角形 525k，和上一版同一量级。
@export var ground_size := 4096.0
## 每边分段数。
@export var ground_segments := 512
## 沙面基色。从 `_sand_material()` 里提出来，是因为它现在有两个读点：
## 材质（shader 的 sand_albedo）和测试（"这片沙还是不是那个沙色"）。
const SAND_ALBEDO := Color(0.80, 0.58, 0.34)

@export_group("太阳")
## 低角度是关键：太阳越高，沙丘越平，影子越短，画面越像儿童插画。
## 18° 是"逆光够狠、沙丘还留得住起伏"的折中：再高，像的剪影就散了；
## 再低，太阳会被城墙和近处沙脊吃掉，画面上只剩一片压暗的沙。
@export_range(-10.0, 90.0, 0.5) var sun_elevation_deg := 18.0
## 方位角。**这个值由 main.gd 按"太阳必须落在弥勒像身后"反解出来**
## （set_sun_behind_bearing），这里的数字只是脱离主场景单独跑世界时的兜底。
##
## 方位角的约定容易搞反，写清楚：`_sync_sky_sun` 算出的 to_sun 水平分量是
## `(sin a, -cos a)`，所以"玩家朝向 +X"时 a=90° 是正前方偏 +Z、
## a=58.7° 才落在弥勒像（在玩家左前方 31°）的正后方。
##
## 原案是 298°（在玩家背后），结果是看向幻影时整片沙丘全是顺光——
## 近坡全亮、没有一道暗脊，画面下部塌成一张奶油色纸。
## 118°（正前方偏右）也不是要的方向：那时太阳在像的**右边 59°**，
## 像身是侧光，谈不上"佛前一片逆光"。
@export_range(0.0, 360.0, 1.0) var sun_azimuth_deg := 58.7
## 3.2 会把 0.86 反照率的沙面直接顶成白纸（ACES 之后一片奶油色），
## 沙丘的形状、风纹、明暗全被吃掉——而"看不出远近"正是室内感的来源之一。
@export_range(0.0, 12.0, 0.05) var sun_energy := 2.2

@export_group("沙尘")
@export_range(0.0, 0.02, 0.0001) var fog_density := 0.0040
@export var fog_color := Color(0.85, 0.65, 0.44)
@export_range(0.0, 1.0, 0.01) var cloud_amount := 0.30

var dune: DuneField

var _environment: Environment
var _sun: DirectionalLight3D
var _sky_material: ShaderMaterial
var _terrain: MeshInstance3D
var _sand_mat: ShaderMaterial


func _ready() -> void:
	dune = DuneField.new()
	_build_terrain()
	_build_environment()
	_build_sun()


## 取沙面高度，玩家控制器用它贴地。
func height_at(x: float, z: float) -> float:
	return dune.sample(x, z)


func set_fog_density(value: float) -> void:
	fog_density = value
	if _environment != null:
		_environment.fog_density = value


## 沙暴来临时的天光：天顶压低、地平线变脏、雾色转向浊黄。
## `intensity` 0..1。
func set_storm_look(intensity: float) -> void:
	var t := clampf(intensity, 0.0, 1.0)
	if _sky_material != null:
		# 注意这里压的是**整片天**：沙暴来时天顶暗、地平线脏，但它必须和晴天
		# 是同一套布光逻辑（有太阳、有方向），否则沙暴一来又变回顶棚。
		_sky_material.set_shader_parameter(
			"zenith_color", Color(0.46, 0.47, 0.53).lerp(Color(0.31, 0.26, 0.22), t)
		)
		_sky_material.set_shader_parameter(
			"horizon_color", Color(0.90, 0.70, 0.45).lerp(Color(0.62, 0.45, 0.30), t)
		)
		_sun_storm(t)
		_sky_material.set_shader_parameter("cloud_amount", lerpf(cloud_amount, 0.85, t))
	if _environment != null:
		_environment.fog_light_color = Color(0.85, 0.65, 0.44).lerp(
			Color(0.60, 0.46, 0.32), t
		)
		_environment.fog_sky_affect = lerpf(0.45, 0.85, t)
	if _sun != null:
		# 沙尘把直射光糊掉，太阳只剩方向感
		_sun.light_energy = lerpf(sun_energy, sun_energy * 0.45, t)


## 沙暴里的太阳：光斑还在，只是被沙尘糊成一大团、并且快看不见了。
## 太阳一旦被完全删掉，天就退化成一块均匀的板。
func _sun_storm(t: float) -> void:
	_sky_material.set_shader_parameter("sun_strength", lerpf(2.2, 0.55, t))
	_sky_material.set_shader_parameter("sun_halo", lerpf(0.85, 0.20, t))


# ---------------------------------------------------------------------------
# 地形
# ---------------------------------------------------------------------------


func _build_terrain() -> void:
	var n := ground_segments + 1
	var step := ground_size / float(ground_segments)
	var half := ground_size * 0.5

	# 先算高度，再算顶点法线——否则每个顶点要重复采样 5 次噪声。
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	for j in range(n):
		var z := -half + float(j) * step
		for i in range(n):
			heights[j * n + i] = dune.sample(-half + float(i) * step, z)

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(n * n)
	normals.resize(n * n)
	uvs.resize(n * n)

	for j in range(n):
		var z := -half + float(j) * step
		for i in range(n):
			var x := -half + float(i) * step
			var idx := j * n + i
			verts[idx] = Vector3(x, heights[idx], z)
			uvs[idx] = Vector2(x * 0.25, z * 0.25)

			# 边上一圈用单边差分（夹到自己的邻居）——那里离玩家 2 km、
			# 早被雾吃掉，不值得为它多采一遍高度。
			var hl := heights[j * n + maxi(i - 1, 0)]
			var hr := heights[j * n + mini(i + 1, n - 1)]
			var hd := heights[maxi(j - 1, 0) * n + i]
			var hu := heights[mini(j + 1, n - 1) * n + i]
			normals[idx] = Vector3(hl - hr, 2.0 * step, hd - hu).normalized()

	var indices := PackedInt32Array()
	indices.resize(ground_segments * ground_segments * 6)
	var k := 0
	for j in range(ground_segments):
		for i in range(ground_segments):
			var a := j * n + i
			var b := a + 1
			var c := a + n
			var d := c + 1
			indices[k] = a
			indices[k + 1] = c
			indices[k + 2] = b
			indices[k + 3] = b
			indices[k + 4] = c
			indices[k + 5] = d
			k += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	_terrain = MeshInstance3D.new()
	_terrain.name = "Dunes"
	_terrain.mesh = mesh
	_terrain.material_override = _sand_material()
	add_child(_terrain)


## 沙面的材质。**唯一的沙面材质**，`set_wind` 改的也是它。
##
## 颜色和粗糙度写在 shader 的 uniform 里（不在这里），只有两处覆盖：
## 一是 CULL_DISABLED（三角形绕序在这个项目里没单独验证过，法线是自己算的，
## 只要面能看见光照就是对的），二是风向——沙纹垂直于它。
func _sand_material() -> ShaderMaterial:
	if _sand_mat != null:
		return _sand_mat

	# 风纹**不再是法线贴图**，改成 shaders/sand_ground.gdshader 里的解析沙纹。
	# 上一版这里挂的是一张 25 cm 的 Perlin 法线贴图，在逆光下等于不存在
	# （逆光里漫反射对法线几乎不敏感），而且它是各向同性的——怎么调都不像
	# "风做的"。新 shader 的注释里写着为什么：**脊线要有走向、沟里要有暗**。
	# 顺带把一张 1024² 的异步噪声纹理也去掉了（它首帧还没就绪，
	# 而"首帧的样子"正是截图探针要拍的东西——异步素材和探针天生打架）。
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = load("res://shaders/sand_ground.gdshader")
	shader_mat.set_shader_parameter("sand_albedo", SAND_ALBEDO)
	shader_mat.set_shader_parameter("sand_roughness", 0.95)
	shader_mat.set_shader_parameter("wind_dir", Vector2(1.0, 0.35).normalized())
	shader_mat.set_shader_parameter("wind_force", 0.0)
	_sand_mat = shader_mat
	return shader_mat


## 风向与风力。**沙纹是风做的**：脊线垂直于风，风越大纹越深。
## 和推人、歪镜头、后处理里的沙带读的是同一个数（GameState），
## 所以"风一阵扑上来"的时候，脚下的纹也一起变——不是四套效果，是一场风。
func set_wind(direction: Vector3, force: float) -> void:
	if _sand_mat == null:
		return
	var flat := Vector2(direction.x, direction.z)
	if flat.length_squared() > 0.000001:
		_sand_mat.set_shader_parameter("wind_dir", flat.normalized())
	_sand_mat.set_shader_parameter("wind_force", clampf(force, 0.0, 1.0))


# ---------------------------------------------------------------------------
# 环境
# ---------------------------------------------------------------------------


func _build_environment() -> void:
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = load("res://shaders/dust_sky.gdshader")
	# 天顶是**干净空气**的冷灰蓝，暖沙色只留在地平线那一薄层。
	# 上一版把天顶压成暗褐（0.22, 0.16, 0.13），抬手一看就是块顶棚。
	_sky_material.set_shader_parameter("horizon_color", Color(0.90, 0.70, 0.45))
	_sky_material.set_shader_parameter("zenith_color", Color(0.46, 0.47, 0.53))
	_sky_material.set_shader_parameter("horizon_power", 0.9)
	_sky_material.set_shader_parameter("sun_tint", Color(1.0, 0.85, 0.58))
	# 紧斑 + 大晕：抬头要看得见"光是从天上来的"。
	# 晕收窄了一点（focus 5 → 6.5、强度 0.85 → 0.62）：太阳现在压在弥勒身后，
	# 晕太大的话整片天都是过曝的白，像身的剪影就没了——**逆光要的是
	# "后面的光把前面的东西压成剪影"，晕一大就变成"后面和前面一样亮"**。
	_sky_material.set_shader_parameter("sun_strength", 2.2)
	_sky_material.set_shader_parameter("sun_focus", 110.0)
	_sky_material.set_shader_parameter("sun_halo", 0.62)
	_sky_material.set_shader_parameter("sun_halo_focus", 6.5)
	# 光刺（佛光的那一圈芒）。它绕太阳的方位角排布，太阳挪到像背后，
	# 芒就从像的背后射出来——这是"逆光"最直接的读法。
	_sky_material.set_shader_parameter("ray_strength", 0.90)
	_sky_material.set_shader_parameter("ray_count", 10.0)
	_sky_material.set_shader_parameter("cloud_amount", cloud_amount)
	# 频率高一点：value noise 在低频下会露出方格，看起来像低模分面。
	# 9.0 配逐层旋转的 fbm，才是"贴地的沙尘条纹"而不是"天花板上的方斑"。
	_sky_material.set_shader_parameter("cloud_scale", 9.0)
	_sky_material.set_shader_parameter("wind_direction", Vector2(1.0, 0.35))

	var sky := Sky.new()
	sky.sky_material = _sky_material

	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = sky
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# 环境光只留一点，而且要偏冷：阳光是暖的、阴影是冷的，
	# 这个冷暖差才是"照片感"的来源。环境光给足反而把明暗冲平，
	# 画面就变成了没有体积的卡通色块。
	_environment.ambient_light_sky_contribution = 0.55
	_environment.ambient_light_color = Color(0.42, 0.52, 0.72)
	# 环境光压到 0.40：逆光要留出"暗部"，环境光一给足，明暗差就被冲平了。
	_environment.ambient_light_energy = 0.40

	# ACES 比 AgX 更有对比和色彩厚度；AgX 在高动态下更"平"，
	# 这一关要的恰恰是不平的强光。
	_environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	_environment.tonemap_exposure = 1.0

	# 环境光遮蔽：沙丘的凹处与背风侧压暗，是廉价但有效的立体感来源
	_environment.ssao_enabled = true
	_environment.ssao_radius = 1.8
	_environment.ssao_intensity = 2.0
	_environment.ssao_power = 1.6
	_environment.ssao_light_affect = 0.35

	# 沙尘被阳光打透时的那点光晕
	_environment.glow_enabled = true
	_environment.glow_intensity = 0.28
	_environment.glow_bloom = 0.05
	_environment.glow_hdr_threshold = 1.1

	# 用 Godot 的深度雾，而不是体积雾：体积雾在 Blender 那边已经证明会
	# 把阳光一起吃掉，颜色雾只按距离把远处推成沙色，效果好且可控。
	_environment.fog_enabled = true
	_environment.fog_light_color = fog_color
	_environment.fog_light_energy = 1.0
	_environment.fog_density = fog_density
	_environment.fog_sky_affect = 0.35
	_environment.fog_aerial_perspective = 0.7
	# 0.55：逆光时相机和幻影之间那层沙尘被太阳打亮，就是画面里那道"光柱"。
	# 顺光时这个值看不出效果，逆光时它是免费的一层空气感。
	_environment.fog_sun_scatter = 0.55
	# 贴地沙雾：沙不是均匀悬在空中的，越贴近地面越浓
	_environment.fog_height = 6.0
	# 0.06 太重：视线贴着沙面走，200 m 外的沙丘就被糊平了，
	# 整片沙漠塌成一张没有起伏的纸。0.025 留下脊线的明暗，
	# 远处的"无边界"交给深度雾（fog_density）负责。
	_environment.fog_height_density = 0.025

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = _environment
	add_child(world_env)


func _build_sun() -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.light_energy = sun_energy
	_sun.light_color = Color(1.0, 0.80, 0.54)
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 260.0
	_sun.shadow_blur = 2.0
	add_child(_sun)
	_apply_sun()


func _apply_sun() -> void:
	# 与 Blender 的 add_sun 同一套角度约定：默认朝 -Z 照射，绕 X 转出仰角。
	_sun.rotation = Vector3(
		deg_to_rad(90.0 - sun_elevation_deg),
		0.0,
		deg_to_rad(sun_azimuth_deg)
	)
	_sync_sky_sun()


## 把"指向太阳"的方向同步给天空着色器。
##
## 这里直接按角度算，而不是读 _sun.global_transform：节点刚 add_child 时
## 变换矩阵还没更新，读出来会是一帧前的旧值。
## 角度→方向的换算与 Blender 端 desert_lib.sun_direction() 一致
## （Blender 是 Z 朝上、Godot 是 Y 朝上，坐标顺次对应）。
func _sync_sky_sun() -> void:
	if _sky_material == null:
		return
	_sky_material.set_shader_parameter("sun_direction", sun_direction())


## 指向太阳的单位向量（世界坐标）。天空、幻影的逆光薄纱都读它，
## 所以它只有一个出口，免得两处各自算、算歪了还对不上。
func sun_direction() -> Vector3:
	var e := deg_to_rad(sun_elevation_deg)
	var a := deg_to_rad(sun_azimuth_deg)
	return Vector3(cos(e) * sin(a), sin(e), -cos(e) * cos(a)).normalized()


## 把太阳摆到某个**方位**（度）上。
##
## 方位角的定义和截图诊断里那个"方位 +X 偏 Z 为正"一致：
## `bearing = atan2(方向.z, 方向.x)`。玩家开局朝 +X，所以
## 弥勒像的方位就是 `atan2(像在玩家前方的 z, x)`。
##
## 反解：水平方向 = (sin a, -cos a) 要等于 (cos b, sin b)，
## 于是 a = atan2(cos b, -sin b)。
##
## 为什么要反解而不是直接写死一个角度：太阳必须在**弥勒背后**，
## 而弥勒的位置是 mirage.gd 里的一串常量（CITY_HALF / STATUE_FRONT_OF_WALL /
## STATUE_SIDE）。哪天像挪了 200 m，写死的方位角就会悄悄偏掉几度，
## 而"偏几度"在画面上完全看不出来——只有那一层逆光没了。
func set_sun_behind_bearing(bearing_deg: float) -> void:
	var b := deg_to_rad(bearing_deg)
	sun_azimuth_deg = fposmod(rad_to_deg(atan2(cos(b), -sin(b))), 360.0)
	_apply_sun()
