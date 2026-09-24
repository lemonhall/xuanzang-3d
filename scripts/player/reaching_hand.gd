class_name ReachingHand
extends Node3D

## 玄奘伸向大佛的**右臂**（第一人称）。
##
## 为什么只做一只手：整尊人像在这个机位里是一坨看不清的东西，而电影里那个
## 动作读的是三样——**手、袖、指向**。别的都是多余的。
##
## 为什么是程序化基本体而不是外部模型：这只手在整个镜头里是**逆光的**，
## 太阳就在佛的背后。逆光下能看见的只有剪影，高模和低模在这套光里长得一样。
## 换来的是它可以跟着"眼 → 佛"的连线实时摆——玩家站在哪儿、佛在哪个方位，
## 手就伸向哪儿。钉死一个姿态做不到这件事。
##
## 挂载：作为 Camera3D 的子节点。于是它的局部坐标就是**眼睛坐标**，
## 姿态直接在相机空间里算，不用过一遍左右手约定的坑。
##
## 姿态是三条曲线的合成：
##   1. 位移：从画面外下方（垂着）收进到"斜向前上方"的定势；
##   2. 朝向：垂手指地 → 直指佛胸，用四元数 slerp（欧拉插值会绕着走弯路）；
##   3. 颤：两个不互为整数倍的频率，幅度随"伸到位"衰减——快死了的人手是抖的。

## 僧衣的坏色（袈裟是"坏色"，不是正黄）。逆光下它得比皮肤暗一档，
## 否则袖子和手糊成一块。
const SLEEVE_COLOR := Color(0.40, 0.19, 0.10)
const CUFF_COLOR := Color(0.30, 0.14, 0.08)
## 皮肤比袖子亮一档就够了：亮太多就成了贴在镜头上的贴纸。
## 这一格是逆光——太阳在佛的背后，伸出去的那只手本来就该大半是剪影。
const SKIN_COLOR := Color(0.58, 0.38, 0.26)

## 腕点离眼睛多远（米）。0.72 是"手臂伸直但没绷住"的位置：
## 再近，手会占掉半个画面；再远，逆光里就只剩下一个模糊的小点。
const WRIST_DISTANCE := 0.76

## 腕点相对视线的横向/纵向偏移（米）。手从右下方进来——右手。
##
## ⚠️ 这两个数不是构图偏好，是**这只手能不能被认出来**的唯一开关。
## 手指指向佛，而相机的视线也指向佛——腕点一靠近画面中心，眼睛、手、
## 佛就成了一条直线，我们等于从**正后方**看这只手：手指全部朝向画面深处，
## 剪影里只剩两三个小凸起（上一版就是这样，需求方的原话是"有点抽象"）。
## 把腕点推到右下角之后，"眼→腕"和"腕→佛"这两条线成 ~70°，
## 手才第一次以侧面出现在画面里：手指是分开的、手背是能看见的。
const WRIST_OFFSET := Vector3(0.36, -0.32, 0.0)

## 手背朝镜头还是掌心朝镜头。
##
## **这个开关决定"看不看得出是手"**：手是扁的，从正后方看永远是一条边
## （上一版就是这样，需求方说"有点抽象"）。把扁平的那一面解到朝向镜头，
## 手指的扇形展开才会落在画面平面里。
## false = 手背朝我们（越过肩膀看过去的经典机位，指节清楚）；
## true = 掌心朝我们（"接引"的手势，但更像在拦人）。
const PALM_TOWARD_CAMERA := false
## 手面向镜头"解到几成"。1.0 = 那一面正对镜头（最清楚，但会有点摆拍）。
## 0.75 是留一点侧转：手仍然是伸向佛的，只是刚好也转到了镜头这边。
const HAND_FACE_SOLVE := 0.66
## 解完之后再随手拧一点点：让手指的扇形稍微斜着切过画面，
## 完全正对反而像一张贴在镜头上的贴纸。
const HAND_STYLE_TILT_DEG := 12.0
## 起手（还没伸出来时）腕点的位置与朝向。
const REST_POSITION := Vector3(0.52, -1.10, 0.0)
const REST_AIM := Vector3(0.35, -1.0, -1.0)

var _clock := 0.0


func _ready() -> void:
	_build()
	visible = false


## 每帧摆一次。`target` 是世界坐标里那个"要指过去"的点（这里是佛的胸怀），
## `reach` 0..1 是伸出去的进度，`delta` 只用来走颤动的时钟。
func update_pose(target: Vector3, reach: float, delta: float) -> void:
	var amount := clampf(reach, 0.0, 1.0)
	visible = amount > 0.002
	_clock += delta
	if not visible:
		return
	var cam := get_parent() as Camera3D
	if cam == null:
		return

	# 眼睛坐标下的"佛在哪儿"。整只手就在这个坐标系里摆，
	# 不需要知道相机的 yaw/pitch 各是多少。
	var aim := cam.to_local(target).normalized()
	var origin := (
		REST_POSITION
		+ (aim * WRIST_DISTANCE + WRIST_OFFSET - REST_POSITION) * amount
	)

	var rest_q := _hand_basis(REST_AIM.normalized(), REST_POSITION).get_rotation_quaternion()
	var aim_q := _hand_basis(aim, origin).get_rotation_quaternion()
	# 两个朝向之间走四元数插值：欧拉插值在这里会绕远路（"垂手"和"指佛"之间
	# 差着一次几乎 180° 的翻转），中途会甩出一个不相干的姿态。
	transform = Transform3D(Basis(rest_q.slerp(aim_q, amount)), origin)

	# 解完之后再拧一点点（见 HAND_STYLE_TILT_DEG）。绕前臂轴，不碰"指佛"。
	rotate_object_local(Vector3.BACK, deg_to_rad(HAND_STYLE_TILT_DEG) * amount)

	# 腕子先抬起来一点（掌心朝天），再走颤动。逆光里那点抖是"快撑不住了"的
	# 唯一读数——幅度必须小，大了就像在演。
	rotate_object_local(Vector3.RIGHT, deg_to_rad(4.0) * amount)
	var shake := (
		sin(_clock * 11.0) * 0.65 + sin(_clock * 27.0 + 1.7) * 0.35
	) * deg_to_rad(1.5) * (1.0 - amount * 0.55)
	rotate_object_local(Vector3.RIGHT, shake)
	rotate_object_local(Vector3.UP, shake * 0.7)


## 让局部 -Z 指向 `dir` 的基。Godot 的 `looking_at` 就是这个约定，
## 直接用它而不是自己拧三个欧拉角。
## 手的姿态：**手指指向 `dir`，同时把扁平的那一面（掌/背）解到朝向镜头。**
##
## 为什么不能只用 `looking_at`：那样"哪一面朝镜头"是由"世界朝上"决定的，
## 而手是扁的——从上往下看它，它就是一条边。这里改成在"垂直于手指的平面"里
## 取"眼 → 手"的投影方向当作法线：那一面自然就转向镜头了。
## （投影在退化时会落回 `looking_at` 的 up，不会出 NaN。）
func _hand_basis(dir: Vector3, origin: Vector3) -> Basis:
	var face := Basis.looking_at(dir, Vector3.UP)
	var fallback := face.y
	var to_eye := -origin
	var flat := to_eye - dir * to_eye.dot(dir)
	if PALM_TOWARD_CAMERA:
		flat = -flat
	if flat.length() < 0.05:
		return face
	# Basis 的列是 x/y/z 三个轴：z 是"手指的反方向"，y 是掌心那一面，
	# x = y × z 保证右手系（手指扇形的展开方向）。
	var y_axis := fallback.lerp(flat.normalized(), HAND_FACE_SOLVE).normalized()
	var z_axis := -dir
	var x_axis := y_axis.cross(z_axis).normalized()
	y_axis = z_axis.cross(x_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)


# ---------------------------------------------------------------------------
# 几何：袖 + 袖口 + 腕 + 掌 + 四指（两节） + 拇指（两节）
#
# 局部约定：**-Z 是手指指出去的方向**（和相机的朝向约定一致），
# 掌心朝 +Y。于是"指佛"就等于把 -Z 摆到佛的方向上。
#
# 比例按**真手**来：成年男性手长约 19 cm、掌宽 9 cm、前臂粗 5~9 cm。
# 上一版把这些全放大了快一倍（袖根 r=0.132、掌 r=0.05 但整条袖子 0.95 m 长），
# 于是离眼睛最近的那截袖子先糊住了半个画面，真正读得出"手"的部分反而最小。
# ---------------------------------------------------------------------------


func _build() -> void:
	var skin := _material(SKIN_COLOR, 0.86)
	var sleeve := _material(SLEEVE_COLOR, 1.0)
	var cuff := _material(CUFF_COLOR, 1.0)

	# 袖子：从腕口往后，越往后越粗，末端在画面外。0.40 m 是"前臂"的长度——
	# 上一版给了 0.95 m，那已经不是前臂而是整条胳膊，最近的那一截必然糊满画面。
	# 袖口单独一圈：逆光里"这是一截袖子，不是一根棍"全靠它。
	#
	# 分两段而不是一根长圆台：一根光滑的等锥度圆台在画面里就是一只交通锥。
	# 两段的锥度不一样（前段收得快、后段几乎不收），剪影上才有"布褶"的读法。
	# 一根，不分段：分出接头就会在胳膊上多出一道环（试过两段，反而更像水管）。
	_cyl(Vector3(0.0, 0.012, 0.030), Vector3(0.0, 0.028, 0.360), 0.052, 0.078, sleeve)
	_cyl(Vector3(0.0, 0.010, 0.026), Vector3(0.0, 0.014, 0.086), 0.058, 0.062, cuff)

	# 腕：比掌细一圈，这一收才有"腕"
	_cyl(Vector3(0.0, 0.008, 0.030), Vector3(0.0, 0.004, -0.030), 0.042, 0.037, skin)
	# 掌：压扁的球，不是方板——方板在逆光里的边太"干净"，一眼就是几何体。
	# 0.055 半径 × 压扁 0.34 = 掌厚 3.7 cm，宽 10 cm、长 11.5 cm，接近真手。
	#
	# 两枚球拼出一个**梯形**：腕侧窄、指节侧宽。一枚球就是一圆碟，
	# 而"圆碟边上长出四根棍"正是需求方说的"抽象"。
	_sphere(Vector3(0.0, 0.001, -0.050), Vector3(0.82, 0.36, 0.92), 0.056, skin)
	_sphere(Vector3(0.0, -0.001, -0.110), Vector3(1.12, 0.38, 0.72), 0.056, skin)

	# 四指：两节，指根分开、指尖更开，末节略抬——手是**伸**出去的，不是握着的。
	# 食指最长、小指最短（真手就是这样，一样长就成了耙子）。
	var finger_x: Array[float] = [-0.038, -0.0127, 0.0127, 0.038]
	var finger_len: Array[float] = [0.94, 1.00, 0.95, 0.82]
	for i in range(4):
		var x: float = finger_x[i]
		var len_scale: float = finger_len[i]
		# 指根粗、指梢细，而且**末节往掌心弯**（+Y 是掌心那一面）：
		# 一支全是直棍的手看起来像塑料叉子。
		var knuckle := Vector3(x, 0.000, -0.130)
		# 指尖只比指根张开一点点：真人伸手时手指是**近乎平行**的，
		# 张开太多就成了海星。
		var mid := Vector3(x * 1.18, 0.006, -0.130 - 0.058 * len_scale)
		var tip := Vector3(x * 1.38, 0.016, -0.130 - 0.104 * len_scale)
		# 指根补一颗小球：不然指头就是从掌的边缘"插"出来的，接缝一眼可见。
		_sphere(knuckle, Vector3(1.0, 0.78, 1.0), 0.0136, skin)
		_cyl(knuckle, mid, 0.0134, 0.0114, skin)
		_cyl(mid, tip, 0.0114, 0.0088, skin)

	# 拇指：两节，从掌根斜着张开。右手掌心朝天时拇指在**内侧**（画面里偏左）。
	_cyl(
		Vector3(-0.050, -0.004, -0.048),
		Vector3(-0.084, 0.000, -0.090),
		0.0158,
		0.0130,
		skin
	)
	_cyl(
		Vector3(-0.084, 0.000, -0.090),
		Vector3(-0.106, 0.008, -0.132),
		0.0130,
		0.0106,
		skin
	)


func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = 0.0
	# 这只手大半时候是逆光的：别的都不重要，粗糙度拉满、镜面压掉，
	# 剩下的明暗就全是剪影，而剪影正是这个镜头要的。
	mat.metallic_specular = 0.25
	return mat


## 在两点之间架一根圆台。`caps=false` 给袖子这类**首尾相连**的段用：
## 圆柱的端盖是一对正对镜头的圆盘，接头处留着它就会在胳膊上画出一道环。
func _cyl(
	a: Vector3, b: Vector3, r_a: float, r_b: float, mat: Material, caps := true
) -> void:
	var dir := b - a
	var mesh := CylinderMesh.new()
	# CylinderMesh 的 +Y 是 top：从 a 到 b 就是"bottom 在 a、top 在 b"。
	mesh.top_radius = r_b
	mesh.bottom_radius = r_a
	mesh.height = dir.length()
	mesh.radial_segments = 12
	mesh.rings = 1
	if not caps:
		mesh.cap_top = false
		mesh.cap_bottom = false
	_mount(mesh, Transform3D(Basis(Quaternion(Vector3.UP, dir.normalized())), (a + b) * 0.5), mat)


func _sphere(center: Vector3, scale: Vector3, radius: float, mat: Material) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	_mount(mesh, Transform3D(Basis.from_scale(scale), center), mat)


func _mount(mesh: Mesh, xform: Transform3D, mat: Material) -> void:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.transform = xform
	add_child(node)
