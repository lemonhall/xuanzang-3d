class_name Mirage
extends Node3D

## 楼兰幻影：沙尘里升起的一座巨城，宽 4.4 km、主塔 1500 m。
##
## 尺寸是真实佛塔的四十倍。既然放大了，**细节也必须配得上这个尺度**：
## 一百多个部件堆出来的轮廓只有六七个转折，一看就是"几个圆柱摞起来"；
## 真实建筑在远处显得复杂，是因为它有几百个转折。所以这里的目标是
## 三千多个部件，全部合成单个 mesh。
##
## 细节都花在**剪影**上，因为两千五百米外真正能被看见的只有轮廓：
##   方台五层递收 + 上下线脚 + 每边三十六个壁龛 + 四角角柱
##   台顶一圈栏杆望柱
##   塔身七十二道竖壁柱 + 十二道腰线（每道五十六个凸块）+ 三圈佛龛带
##   覆钵圆顶 + 一圈莲瓣
##   十三层相轮，每层边缘三十二颗珠串 + 华盖
##   四角各一座小窣堵坡
##
## 巨物恐怖不靠"占满画面"。这一版把上一版的教训写在这儿，别改回去：
##
##   **把东西塞满屏幕，得到的是天花板，不是巨物。**
##
## 上一版把幻影放到玩家前方 250 m、整体 0.55 倍，城郭横着切出画外、
## 城门楼顶到 63°。角度上它已经"装不下"了，但玩家抬头一看是**穹顶**：
## 城墙像一圈护墙板、角楼的攒尖顶像天花板的梁、天光从地平线（也就是
## 房间地面的灯槽）打上来。因为"围着人"和"压着人"在视觉上是同一件事，
## 而"围"就等于"室内"。
##
## 巨物恐怖真正的来源是**量不出来**，而量不出来有三条路，和"占满画面"无关：
##   1. **横向量不出来**：墙的左右两端都在画面之外（±57°，半视角只有 48°）；
##   2. **纵深量不出来**：近墙 1.4 km、远墙 5.8 km，后半座城化在沙尘里；
##   3. **顶量不出来**：主塔 1500 m、顶端 32° 还在画面内，但上半截**溶进天空**。
## 三条都成立时，玩家知道它很大，却找不到任何一条可以量的边——而头顶
## 30° 以上全是干净的天。这才是"巨物"，不是"屋顶"。
##
## 距离与高度的配比（本版的核心数字，改任何一个都要重新验算）：
##   正面城墙 1400 m 外、400 m 高 → 16°（贴着地平线站起来的一条横带）
##   城门楼   1400 m 外、620 m 高 → 24°（画面正中的第二个高点）
##   主塔     2400 m 外、1500 m 高 → 32°（最高点，顶端溶进天空）
##   角楼     2600 m 外、520 m 高  → 11°、方位 ±57°（转头的瞬间才进场）
## 换句话说：**真身比上一版大 2~3.5 倍，看出去的角度反而小了**——
## 挪远不是缩小，是把"贴脸"换成"远到量不出来"。

## 主塔整体放大倍率（塔的造型代码按 820 m 写，乘完是 1500 m）。
const TOWER_SCALE := 1.83
## 主塔中心离**正面城墙**的距离（米）。塔必须在城的前半部：
## 城正中心离玩家 3600 m，同样 1500 m 只能顶到 22.6°，会被 620 m 的城门楼压住；
## 放在城墙后 1000 m 处（离玩家 2400 m）才够 32°，而且是画面里唯一的最高点。
const TOWER_BEHIND_WALL := 1000.0

## --- 弥勒大像 ---
##
## 幻景里唯一的人形。塔再高也只是"一根柱子"，人形一立起来，玩家会本能地
## 拿自己去比——这是整套尺度感里最便宜也最狠的一招。
##
## 为什么是弥勒：玄奘一生念弥勒、求生兜率天，《大唐西域记》里他亲笔记下
## 梵衍那国（巴米扬）"高百四五十尺"的立佛石像。他是在沙漠里抬头看过巨像、
## 并且把它写进书里的人。所以这尊像不是装饰，是**他自己的执念**——
## 幻景本来就由"渴"和"沙暴"驱动，他渴到极点时看见的，当然是他念了一辈子的那位。
##
## 人形高度就是它自己的尺度参照，所以它必须是全场的顶点。
##
## 它**站在城墙前面**，不是在城里：背后有城郭做底、脚下有沙脊切边，
## 剪影才立得住。埋在城里的像只会和城墙糊成一团——第一版就是这么糊的。
##
## 高度是**巴米扬大佛的二十倍**（那尊"高百四五十尺"的立佛，玄奘亲笔记过），
## 也就是 1080 m。这个数字不是随便定的：玩家对"像"的尺度判断全靠人形比例，
## 而"二十倍"正好是原案里楼兰建筑的量级。
##
##   像身 1080 m、离玩家约 1290 m → 头顶 37.1°，**水平前视时刚好在画面之外**
##   （画面顶 34°），得抬头才看得见脸；肩 33.5° 正好卡在画面上沿。
##   举身光顶点 1318 m → 45.7°。脚下 0.075h ≈ 81 m 落在沙脊线以下——
##   它是从沙里站起来的。
const STATUE_HEIGHT := 1080.0
## 举身光顶点 / 全场天际线：着色器的冷暖渐变按它归一化。
const STATUE_TOP := STATUE_HEIGHT * 1.22
const SKYLINE_HEIGHT := maxf(STATUE_TOP, 820.0 * TOWER_SCALE)
## 像身站位：在正面城墙**之前** STATUE_FRONT_OF_WALL 米。
const STATUE_FRONT_OF_WALL := 300.0
## 横向偏移（米，负 = 玩家左手边）。
## 两尊巨物不能压在同一根轴线上：叠在一起只剩一团分不清的轮廓。
## 错开 31°，才能一眼读出"一尊像"和"一座塔"是两个量级的东西。
const STATUE_SIDE := -700.0

const TIER_WIDTHS := [320.0, 292.0, 266.0, 242.0, 220.0]
const TIER_HEIGHTS := [34.0, 32.0, 30.0, 28.0, 26.0]
const TIER_BASES := [0.0, 34.0, 66.0, 96.0, 124.0]
const TERRACE_Y := 150.0
const TERRACE_HALF := 110.0

const NICHE_PER_SIDE := 36
const BALUSTRADE_POSTS := 44
const BODY_RIB_COUNT := 72
const BODY_BAND_COUNT := 12
const BODY_BAND_STUDS := 56
const SHRINE_BANDS := 3
const SHRINE_PER_BAND := 72
const FINIAL_COUNT := 13
const BEADS_PER_RING := 32

const CORNER_TOWER_OFFSET := 100.0
const BODY_BOTTOM_R := 100.0
const BODY_TOP_R := 76.0
const BODY_HEIGHT := 290.0
const DOME_R := 76.0
const DOME_H := 100.0
const TOTAL_HEIGHT := 820.0 * TOWER_SCALE

# --- 城郭 ---
# 只有一座塔是"一根柱子"，一座城才有"回不去的地方"的意思。
# 城墙把主塔围在中间，也让轮廓从"竖着的一根"变成"铺开的一片"。
## 城郭半宽。这个数字和 main 里的缩放一起决定"横向能不能切出画外"——
## 只要城墙的左右两端还留在画面里，大脑就会量出它的尺寸，
## 那它就只是"一座大一点的城"，而不是"大到你量不出来"。
const CITY_HALF := 2200.0
const WALL_H := 400.0
const WALL_T := 260.0
const BATTLEMENTS := 96
const BASTION_TIERS := [560.0, 440.0]
const BASTION_H := 200.0
const GATE_HEIGHT := 620.0

var presence := 0.0

var _material: ShaderMaterial
var _parts: Array[Dictionary] = []
var _base_y := 0.0
## 当前正在拼装的部件用的整体缩放 / 平移。主塔用它放大并前移，
## 城郭保持 1:1（真实米）。
var _part_scale := 1.0
var _part_offset := Vector3.ZERO


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/mirage.gdshader")
	# 归一化高度取的是**全场天际线**（弥勒像的顶端 2714 m），不是主塔。
	# 主塔 1500 m 于是落在 0.55 处，像头 0.85 处、背光顶 1.0 处——
	# 冷暖渐变和上缘溶解才有地方落。
	_material.set_shader_parameter("y_range", Vector2(0.0, SKYLINE_HEIGHT))
	_material.set_shader_parameter("strength", 0.0)
	# 下缘：幻影的底正好卡在前方沙丘脊线上，那里若是一条干净的硬边，
	# 看起来就像贴着地平线的贴纸。让它化进沙尘里，才像"从沙里凝出来的"。
	_material.set_shader_parameter("low_fade", 0.045)
	# 上缘不做高度淡出：归一化高度要把两座不同高的东西装进同一个刻度，
	# 任何按高度切的一刀都会把其中一个的顶切掉（像头 vs 主塔宝顶）。
	# "看不到顶"由"头顶出画 + 空气衰减"负责，见 mirage.gdshader。
	_material.set_shader_parameter("high_fade", 1.0)
	# 下暗上亮、下暖上冷。
	#
	# 这是踩出来的：上一版底色是暖沙色（0.90, 0.75, 0.52），而地平线也是
	# 亮沙色（0.90, 0.70, 0.45）。同一档颜色叠上去，alpha 0.25 只把背景
	# 从 0.90 拉到 0.82——差值 9%，经过 ACES 和暗角之后，**整座城看不见**。
	# 幻影再淡也得有对比：底部压到暗褐（贴着沙面的一道暗影），顶上转冷亮
	# （像被天空吸走）。这样"下暗上亮"本身就是一条纵深线索。
	_material.set_shader_parameter("tint_base", Color(0.34, 0.30, 0.26))
	_material.set_shader_parameter("tint_top", Color(0.72, 0.84, 1.00))
	# 分层错位是按 250 m 的观距调出来的；现在观距 1.4 km（5.6 倍），
	# 位移量不跟着放大就完全看不出来了。
	_material.set_shader_parameter("layer_height", 70.0)
	_material.set_shader_parameter("layer_shift", 90.0)
	_material.set_shader_parameter("haze_tint", Color(0.86, 0.68, 0.47))
	# 1.3 km 处透射 0.75、5.8 km 处 0.28：近处的城郭站得住，
	# 后半个城先褪色再消失。
	_material.set_shader_parameter("haze_density", 0.00022)

	_design()

	var instance := MeshInstance3D.new()
	instance.name = "Loulan"
	instance.mesh = _merge_parts()
	instance.material_override = _material
	# 幻影在两公里外，要保证它不会被视锥当成"太远"剔掉
	instance.extra_cull_margin = 400.0
	add_child(instance)

	visible = false


# ---------------------------------------------------------------------------
# 造型
# ---------------------------------------------------------------------------


func _design() -> void:
	# 主塔：放大 TOWER_SCALE 倍，并整体前移到**城墙后 TOWER_BEHIND_WALL 米**。
	# 塔的造型代码全部按 820 m 高写，乘在变换上而不是乘进上百个常量里——
	# 常量里漏乘一个，轮廓上根本看不出来，只会变成一个悄悄变形的塔。
	_part_scale = TOWER_SCALE
	_part_offset = Vector3(-CITY_HALF + TOWER_BEHIND_WALL, 0.0, 0.0)
	_design_terraces()
	_design_parapet()
	_design_corner_towers()
	_design_main_body()
	_design_dome()
	_design_finial()

	# 弥勒大像：本身就用真实米写，所以只平移。放在城墙后面 1400 m、
	# 弥勒大像：本身就用真实米写，所以只平移。站在正面城墙**之前**
	# 300 m、横向偏到玩家左手边 700 m —— 和主塔错开约 31°。
	_part_scale = 1.0
	_part_offset = Vector3(-CITY_HALF - STATUE_FRONT_OF_WALL, 0.0, STATUE_SIDE)
	_design_statue()

	# 城郭：真实米，1:1
	_part_offset = Vector3.ZERO
	_design_city()


## 五层递收的方台。每层：主体 + 上下线脚 + 四边壁龛 + 四角角柱。
func _design_terraces() -> void:
	for i in range(TIER_WIDTHS.size()):
		var width: float = TIER_WIDTHS[i]
		var height: float = TIER_HEIGHTS[i]
		var base: float = TIER_BASES[i]
		var mid := base + height * 0.5

		_add_box(Vector3(width, height, width), Vector3(0.0, mid, 0.0))

		var lip := width + 14.0
		_add_box(Vector3(lip, 5.0, lip), Vector3(0.0, base + 3.5, 0.0))
		_add_box(Vector3(lip, 5.0, lip), Vector3(0.0, base + height - 3.5, 0.0))

		# 四角角柱：把方台的四个棱描出来，轮廓立刻变"结实"
		var corner := width * 0.5 - 4.0
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				_add_box(
					Vector3(18.0, height + 4.0, 18.0),
					Vector3(sx * corner, mid, sz * corner)
				)

		# 每边一排壁龛：轮廓上的细密锯齿，也是"这是建筑"的最直接证据
		_face_row(
			NICHE_PER_SIDE, width, mid, Vector3(14.0, height * 0.62, 7.0), 0
		)
		_face_row(
			NICHE_PER_SIDE, width, mid, Vector3(14.0, height * 0.62, 7.0), 1
		)


## 台顶栏杆：一圈望柱 + 四面横栏。
func _design_parapet() -> void:
	var rail_y := TERRACE_Y + 20.0
	for i in range(BALUSTRADE_POSTS):
		var t := (float(i) + 0.5) / float(BALUSTRADE_POSTS) * 2.0 - 1.0
		var offset := t * (TERRACE_HALF - 6.0)
		for side: float in [-1.0, 1.0]:
			_add_box(Vector3(9.0, 26.0, 9.0), Vector3(offset, rail_y, side * TERRACE_HALF))
			_add_box(Vector3(9.0, 26.0, 9.0), Vector3(side * TERRACE_HALF, rail_y, offset))

	var rail_len := TERRACE_HALF * 2.0
	for side: float in [-1.0, 1.0]:
		_add_box(
			Vector3(rail_len, 5.0, 7.0), Vector3(0.0, rail_y + 13.0, side * TERRACE_HALF)
		)
		_add_box(
			Vector3(7.0, 5.0, rail_len), Vector3(side * TERRACE_HALF, rail_y + 13.0, 0.0)
		)


func _design_corner_towers() -> void:
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_design_corner_tower(sx * CORNER_TOWER_OFFSET, sz * CORNER_TOWER_OFFSET)


## 四角的小窣堵坡：三层小台基 + 塔身（带壁龛）+ 覆钵 + 莲瓣 + 相轮 + 宝珠。
func _design_corner_tower(px: float, pz: float) -> void:
	var y := TERRACE_Y
	for i in range(3):
		var w := 52.0 - float(i) * 7.0
		_add_box(Vector3(w, 13.0, w), Vector3(px, y + 6.5, pz))
		y += 13.0

	_add_cylinder(23.0, 19.0, 76.0, Vector3(px, y + 38.0, pz), 20)
	for i in range(12):
		var a := TAU * float(i) / 12.0
		_add_box_rot(
			Vector3(8.0, 44.0, 5.0),
			Vector3(px + cos(a) * 22.0, y + 38.0, pz + sin(a) * 22.0),
			Vector3(0.0, -a, 0.0)
		)
	y += 76.0

	_add_sphere(23.0, 54.0, Vector3(px, y + 27.0, pz))
	for i in range(14):
		var a := TAU * float(i) / 14.0
		_add_box_rot(
			Vector3(11.0, 9.0, 6.0),
			Vector3(px + cos(a) * 21.0, y + 12.0, pz + sin(a) * 21.0),
			Vector3(0.0, -a, 0.0)
		)
	y += 54.0

	_add_cylinder(4.0, 4.0, 74.0, Vector3(px, y + 37.0, pz), 8)
	for i in range(7):
		var radius := lerpf(15.0, 7.0, float(i) / 6.0)
		_add_cylinder(radius, radius, 5.0, Vector3(px, y + 12.0 + float(i) * 11.0, pz), 16)
		for j in range(10):
			var a := TAU * float(j) / 10.0
			_add_box(
				Vector3(3.0, 3.0, 3.0),
				Vector3(
					px + cos(a) * radius,
					y + 12.0 + float(i) * 11.0,
					pz + sin(a) * radius
				)
			)
	_add_sphere(8.0, 16.0, Vector3(px, y + 81.0, pz))


## 主塔身：收分圆柱 + 竖壁柱 + 腰线凸块 + 佛龛带。
## 佛龛带是"这是座塔而不是根柱子"的关键——一圈圈规则的小龛，
## 远看就是塔身上连续的横向纹理。
func _design_main_body() -> void:
	_add_cylinder(
		BODY_BOTTOM_R, BODY_TOP_R, BODY_HEIGHT, Vector3(0.0, TERRACE_Y + BODY_HEIGHT * 0.5, 0.0), 48
	)

	# 竖向壁柱：绕塔身一圈，从底到顶
	for i in range(BODY_RIB_COUNT):
		var a := TAU * float(i) / float(BODY_RIB_COUNT)
		var radius := (BODY_BOTTOM_R + BODY_TOP_R) * 0.5 + 1.0
		_add_box_rot(
			Vector3(7.0, BODY_HEIGHT - 6.0, 5.0),
			Vector3(cos(a) * radius, TERRACE_Y + BODY_HEIGHT * 0.5, sin(a) * radius),
			Vector3(0.0, -a, 0.0)
		)

	# 腰线：每道一圈凸块
	for band in range(BODY_BAND_COUNT):
		var t := float(band) / float(BODY_BAND_COUNT - 1)
		var y := TERRACE_Y + 14.0 + t * (BODY_HEIGHT - 28.0)
		var radius := lerpf(BODY_BOTTOM_R, BODY_TOP_R, t) + 3.0
		_add_cylinder(
			radius, radius, 4.0, Vector3(0.0, y, 0.0), 48
		)
		for i in range(BODY_BAND_STUDS):
			var a := TAU * float(i) / float(BODY_BAND_STUDS)
			_add_box(
				Vector3(6.0, 9.0, 6.0),
				Vector3(cos(a) * radius, y, sin(a) * radius)
			)

	# 佛龛带：三圈，每圈两层小龛
	for band in range(SHRINE_BANDS):
		var t := (float(band) + 0.5) / float(SHRINE_BANDS)
		var y := TERRACE_Y + 24.0 + t * (BODY_HEIGHT - 48.0)
		var radius := lerpf(BODY_BOTTOM_R, BODY_TOP_R, t) + 2.0
		for i in range(SHRINE_PER_BAND):
			var a := TAU * float(i) / float(SHRINE_PER_BAND)
			var outward := Vector3(cos(a) * radius, y, sin(a) * radius)
			_add_box_rot(Vector3(11.0, 16.0, 6.0), outward, Vector3(0.0, -a, 0.0))
			_add_box_rot(
				Vector3(13.0, 4.0, 8.0),
				outward + Vector3(cos(a) * 2.0, 10.0, sin(a) * 2.0),
				Vector3(0.0, -a, 0.0)
			)


## 覆钵圆顶 + 一圈莲瓣。
func _design_dome() -> void:
	var dome_base := TERRACE_Y + BODY_HEIGHT
	_add_sphere(DOME_R, DOME_H, Vector3(0.0, dome_base + DOME_H * 0.5, 0.0))
	for i in range(36):
		var a := TAU * float(i) / 36.0
		var radius := DOME_R * 0.62
		_add_box_rot(
			Vector3(14.0, 26.0, 8.0),
			Vector3(cos(a) * radius, dome_base + 10.0, sin(a) * radius),
			Vector3(0.0, -a, 0.0)
		)
	_add_cylinder(30.0, 22.0, 18.0, Vector3(0.0, dome_base + DOME_H - 4.0, 0.0), 24)


## 塔刹：中心柱 + 十三层逐步递减的相轮，每层边缘挂三十二颗珠串 + 华盖。
##
## 相轮是佛塔最有辨识度的剪影，一层都不能省——少几层就从"塔"变成"柱子"。
## 珠串是这一版新加的：它让相轮边缘不再是光滑圆弧，而是毛茸茸的齿。
func _design_finial() -> void:
	var base := TERRACE_Y + BODY_HEIGHT + DOME_H
	_add_cylinder(9.0, 9.0, 236.0, Vector3(0.0, base + 118.0, 0.0), 12)

	for i in range(FINIAL_COUNT):
		var t := float(i) / float(FINIAL_COUNT - 1)
		var radius := lerpf(46.0, 15.0, t)
		var y := base + 26.0 + float(i) * 15.0
		_add_cylinder(radius, radius, 7.0, Vector3(0.0, y, 0.0), 28)
		for j in range(BEADS_PER_RING):
			var a := TAU * float(j) / float(BEADS_PER_RING)
			_add_box(
				Vector3(5.0, 7.0, 5.0),
				Vector3(cos(a) * radius, y, sin(a) * radius)
			)

	# 华盖：一圈下垂的饰件
	var canopy_y := base + 26.0 + float(FINIAL_COUNT - 1) * 15.0 + 26.0
	for i in range(20):
		var a := TAU * float(i) / 20.0
		_add_box_rot(
			Vector3(8.0, 22.0, 6.0),
			Vector3(cos(a) * 26.0, canopy_y, sin(a) * 26.0),
			Vector3(0.0, -a, 0.0)
		)

	_add_sphere(18.0, 36.0, Vector3(0.0, base + 254.0, 0.0))


# ---------------------------------------------------------------------------
# 几何装配
# ---------------------------------------------------------------------------


## 城郭：四面城墙 + 垛口 + 四角楼 + 城门楼 + 城内小塔群与房屋。
##
## 主塔在城中心。城墙把它围起来之后，幻影的轮廓就从"竖着的一根"
## 变成"铺开的一片"——这是"一座城"和"一座塔"的区别所在。
func _design_city() -> void:
	_design_walls()
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_design_bastion(sx * CITY_HALF, sz * CITY_HALF)
	# 城门楼开在**朝玩家那一面**（-CITY_HALF）。上一版开在 +CITY_HALF，
	# 也就是背面的墙上——玩家永远只能从 3.6 km 外看到那座正门。
	_design_gatehouse(-CITY_HALF)
	_design_inner_town()


func _design_walls() -> void:
	var span := CITY_HALF * 2.0
	var mid := WALL_H * 0.5
	# 正面 / 背面（与 X 轴垂直），左 / 右（与 Z 轴垂直）
	_add_box(Vector3(WALL_T, WALL_H, span), Vector3(CITY_HALF, mid, 0.0))
	_add_box(Vector3(WALL_T, WALL_H, span), Vector3(-CITY_HALF, mid, 0.0))
	_add_box(Vector3(span, WALL_H, WALL_T), Vector3(0.0, mid, CITY_HALF))
	_add_box(Vector3(span, WALL_H, WALL_T), Vector3(0.0, mid, -CITY_HALF))

	# 墙基线脚与压顶线：轮廓上的两条横向亮线
	var lip := WALL_T + 26.0
	for sx: float in [-1.0, 1.0]:
		_add_box(Vector3(lip, 16.0, span), Vector3(sx * CITY_HALF, WALL_H - 6.0, 0.0))
		_add_box(Vector3(span, 16.0, lip), Vector3(0.0, WALL_H - 6.0, sx * CITY_HALF))
	for sz: float in [-1.0, 1.0]:
		_add_box(Vector3(lip, 12.0, span), Vector3(sz * CITY_HALF, 8.0, 0.0))
		_add_box(Vector3(span, 12.0, lip), Vector3(0.0, 8.0, sz * CITY_HALF))

	# 垛口：墙顶一排小方块，正面看就是细密的齿
	for i in range(BATTLEMENTS):
		var t := (float(i) + 0.5) / float(BATTLEMENTS) * 2.0 - 1.0
		var offset := t * (CITY_HALF - 24.0)
		var y := WALL_H + 28.0
		for side: float in [-1.0, 1.0]:
			_add_box(Vector3(WALL_T, 56.0, 40.0), Vector3(side * CITY_HALF, y, offset))
			_add_box(Vector3(40.0, 56.0, WALL_T), Vector3(offset, y, side * CITY_HALF))


## 角楼：城墙四角加高的方塔，让轮廓在四个角上立起来。
func _design_bastion(px: float, pz: float) -> void:
	var y := 0.0
	var width := 0.0
	for i in range(BASTION_TIERS.size()):
		width = BASTION_TIERS[i]
		var height := BASTION_H * (1.0 if i == 0 else 0.85)
		_add_box(Vector3(width, height, width), Vector3(px, y + height * 0.5, pz))
		_add_box(
			Vector3(width + 40.0, 26.0, width + 40.0), Vector3(px, y + height - 13.0, pz)
		)
		y += height
	# 攒尖顶：用四棱锥收头
	_add_cylinder(width * 0.5, 12.0, 220.0, Vector3(px, y + 110.0, pz), 4)


## 城门楼：正面中央的制高点，也是幻影里第一个能辨认出"这是建筑"的东西。
##
## 每一段的尺寸都是 GATE_HEIGHT 的比例，总高正好等于 GATE_HEIGHT。
## 上一版这里是写死的米数，加起来 882 m——比 GATE_HEIGHT 写的 900 差不多，
## 但和 620 m 的主塔配在一起就翻了个：**城门楼比主塔还高**，Hierarchy 一乱，
## 巨物就没有"顶点"了，只剩一大片高的东西。
func _design_gatehouse(px: float) -> void:
	var h := GATE_HEIGHT
	# 两座墩台，夹出门洞的位置
	for side: float in [-1.0, 1.0]:
		_add_box(
			Vector3(h * 0.26, h * 0.30, h * 0.26),
			Vector3(px, h * 0.15, side * h * 0.24)
		)
	# 门楣：把两座墩台连成一体，是"门"这个意思的唯一来源
	_add_box(Vector3(h * 0.26, h * 0.15, h * 0.74), Vector3(px, h * 0.375, 0.0))
	# 楼身 + 檐口
	_add_box(Vector3(h * 0.36, h * 0.22, h * 0.60), Vector3(px, h * 0.56, 0.0))
	_add_box(Vector3(h * 0.46, h * 0.03, h * 0.72), Vector3(px, h * 0.685, 0.0))
	# 攒尖顶 + 顶针
	_add_cylinder(h * 0.30, h * 0.03, h * 0.24, Vector3(px, h * 0.82, 0.0), 4)
	_add_cylinder(h * 0.02, h * 0.006, h * 0.06, Vector3(px, h * 0.97, 0.0), 8)
	# 门洞两侧的壁柱
	for side: float in [-1.0, 1.0]:
		_add_box(
			Vector3(h * 0.09, h * 0.30, h * 0.09),
			Vector3(px - h * 0.12, h * 0.15, side * h * 0.24)
		)


## 城内：几座小窣堵坡 + 一片房屋。城市必须"有内容"，
## 否则从城墙后面看过去只是一堵光墙。
##
## 门槛是**城墙高度**：站在 1.4 km 外看，只有高过 400 m 城墙的东西才露得出来。
## 上一版的城内建筑是 46~360 m，全部埋在墙后——那几百个部件一个都看不见。
func _design_inner_town() -> void:
	var shrines := [
		Vector3(-1500.0, 0.0, 1250.0),
		Vector3(-1350.0, 0.0, -1450.0),
		Vector3(1100.0, 0.0, -1300.0),
		Vector3(1500.0, 0.0, 1400.0),
		Vector3(-520.0, 0.0, 1780.0),
		Vector3(430.0, 0.0, -1820.0),
		Vector3(1850.0, 0.0, -280.0),
	]
	for i in range(shrines.size()):
		var position: Vector3 = shrines[i]
		_design_mini_stupa(position.x, position.z, lerpf(700.0, 520.0, float(i) / 6.0))

	# 黄金角散布，避免看出规律。高矮参差才是"一片城"，等高就成了一道墙。
	var tower_x := -CITY_HALF + TOWER_BEHIND_WALL
	for i in range(96):
		var angle := float(i) * 2.39996
		var radius := 380.0 + fmod(float(i) * 173.0, 1700.0)
		var hx := cos(angle) * radius
		var hz := sin(angle) * radius
		# 主塔的台基占地很大，别把房子塞进塔里
		if absf(hx - tower_x) < 420.0 and absf(hz) < 420.0:
			continue
		var height := 300.0 + fmod(float(i) * 53.0, 220.0)
		var width := 200.0 + fmod(float(i) * 31.0, 170.0)
		_add_box(Vector3(width, height, width), Vector3(hx, height * 0.5, hz))
		_add_box(
			Vector3(width + 40.0, 26.0, width + 40.0),
			Vector3(hx, height - 13.0, hz)
		)


# ---------------------------------------------------------------------------
# 弥勒大像
# ---------------------------------------------------------------------------


## 弥勒立像，含莲台总高 STATUE_HEIGHT（2300 m）。
##
## 造像的每一处细节都只服务一件事：**三公里外还能认出来**。
## 所以细节全在剪影上——莲台的层、裙摆的转折、抬起的那只手、
## 宝冠的齿、垂到肩的耳垂；脸上什么都不做，反正看不见。
##
## 三个"一眼认出是人"的机关，按重要性排：
##   1. 举身光（身后那枚巨环）。它在沙尘里像一轮落日的光晕，
##      也是"这是尊造像而不是一座塔"的第一眼证据；
##   2. 抬起的那只手（施无畏印）。人形轮廓里最难伪造的一笔——
##      手臂一弯，整团剪影立刻从"柱子"变成"人"；
##   3. 头 + 宝冠 + 耳垂。头身比一旦接近人，尺度感就成立了。
##
## 朝向：**面朝 -X**，也就是玩家来的方向。像身、莲台、背光都按这条轴摆。
func _design_statue() -> void:
	var h := STATUE_HEIGHT
	# 莲台：两层仰覆莲 + 上下两道台线
	_add_cylinder(h * 0.200, h * 0.190, h * 0.018, Vector3(0.0, h * 0.009, 0.0), 48)
	_add_cylinder(h * 0.190, h * 0.172, h * 0.026, Vector3(0.0, h * 0.031, 0.0), 48)
	for layer in range(2):
		var ly := h * 0.018 + float(layer) * h * 0.026
		var lr := h * (0.192 - float(layer) * 0.014)
		for i in range(40):
			var a := TAU * float(i) / 40.0 + float(layer) * 0.0785
			_add_box_rot(
				Vector3(h * 0.014, h * 0.054, h * 0.010),
				Vector3(cos(a) * lr, ly + h * 0.025, sin(a) * lr),
				Vector3(0.0, -a, 0.0)
			)

	# 裙摆：三段收分 + 一圈衣纹竖棱。裙摆要做**宽**：立像的体量全在这里，
	# 收得太快就成了一根针。竖棱在沙尘里是裙边那排细齿，是"这块体量有褶"的
	# 唯一证据。
	_add_cylinder(h * 0.185, h * 0.158, h * 0.170, Vector3(0.0, h * 0.162, 0.0), 40)
	_add_cylinder(h * 0.158, h * 0.130, h * 0.150, Vector3(0.0, h * 0.322, 0.0), 40)
	_add_cylinder(h * 0.130, h * 0.104, h * 0.120, Vector3(0.0, h * 0.457, 0.0), 40)
	for i in range(30):
		var a := TAU * float(i) / 30.0
		_add_box_rot(
			Vector3(h * 0.011, h * 0.360, h * 0.009),
			Vector3(cos(a) * h * 0.150, h * 0.230, sin(a) * h * 0.150),
			Vector3(0.0, -a, 0.0)
		)

	# 腰带 + 结带
	_add_cylinder(h * 0.110, h * 0.110, h * 0.024, Vector3(0.0, h * 0.512, 0.0), 36)
	_add_box(Vector3(h * 0.022, h * 0.052, h * 0.044), Vector3(-h * 0.104, h * 0.505, 0.0))

	# 上身：两段收分 + 胸
	_add_cylinder(h * 0.106, h * 0.122, h * 0.150, Vector3(0.0, h * 0.600, 0.0), 36)
	_add_cylinder(h * 0.122, h * 0.140, h * 0.120, Vector3(0.0, h * 0.735, 0.0), 36)
	_add_sphere(h * 0.086, h * 0.170, Vector3(-h * 0.060, h * 0.700, 0.0))

	# 肩：一条横向体量，人形轮廓的"上边"
	_add_box(Vector3(h * 0.120, h * 0.082, h * 0.330), Vector3(0.0, h * 0.788, 0.0))

	# 右臂（+Z）：垂下 → 折起 → 手掌前伸，施无畏印。
	# 这条折线是人形剪影里最难伪造的一笔。
	_add_box_rot(
		Vector3(h * 0.052, h * 0.270, h * 0.052),
		Vector3(0.0, h * 0.660, h * 0.190),
		Vector3(0.22, 0.0, 0.0)
	)
	_add_box_rot(
		Vector3(h * 0.048, h * 0.250, h * 0.048),
		Vector3(0.0, h * 0.600, h * 0.262),
		Vector3(-0.06, 0.0, 0.0)
	)
	_add_box(Vector3(h * 0.052, h * 0.092, h * 0.068), Vector3(-h * 0.022, h * 0.728, h * 0.272))

	# 左臂（-Z）：垂手
	_add_box_rot(
		Vector3(h * 0.052, h * 0.270, h * 0.052),
		Vector3(0.0, h * 0.655, -h * 0.188),
		Vector3(-0.20, 0.0, 0.0)
	)
	_add_box_rot(
		Vector3(h * 0.046, h * 0.215, h * 0.046),
		Vector3(0.0, h * 0.482, -h * 0.216),
		Vector3(-0.05, 0.0, 0.0)
	)
	_add_sphere(h * 0.034, h * 0.096, Vector3(0.0, h * 0.362, -h * 0.218))

	# 璎珞（项饰）：两圈珠串。围胸一圈，是"菩萨装"和"佛装"分界的地方
	for ring in range(2):
		var ry := h * (0.746 - float(ring) * 0.080)
		var rr := h * (0.106 + float(ring) * 0.018)
		for i in range(24):
			var a := TAU * float(i) / 24.0
			_add_sphere(
				h * 0.011, h * 0.022, Vector3(cos(a) * rr, ry, sin(a) * rr)
			)

	# 颈 + 头
	_add_cylinder(h * 0.056, h * 0.052, h * 0.066, Vector3(0.0, h * 0.808, 0.0), 24)
	_add_sphere(h * 0.082, h * 0.210, Vector3(0.0, h * 0.902, 0.0))

	# 耳垂：长到肩，是佛像最容易被认出来的旁证
	for side: float in [-1.0, 1.0]:
		_add_box(
			Vector3(h * 0.017, h * 0.118, h * 0.028),
			Vector3(0.0, h * 0.888, side * h * 0.088)
		)

	# 螺发一圈 + 肉髻
	for i in range(20):
		var a := TAU * float(i) / 20.0
		_add_sphere(
			h * 0.013,
			h * 0.026,
			Vector3(cos(a) * h * 0.076, h * 0.968, sin(a) * h * 0.076)
		)
	_add_sphere(h * 0.048, h * 0.092, Vector3(0.0, h * 1.012, 0.0))

	# 宝冠：一圈冠带 + 正面五瓣（弥勒菩萨的标志，不是佛装）
	_add_cylinder(h * 0.090, h * 0.088, h * 0.050, Vector3(0.0, h * 0.954, 0.0), 32)
	for i in range(5):
		var z := (float(i) - 2.0) * h * 0.033
		_add_box(Vector3(h * 0.017, h * 0.076, h * 0.030), Vector3(-h * 0.060, h * 1.000, z))
		_add_sphere(h * 0.015, h * 0.032, Vector3(-h * 0.060, h * 1.048, z))
	# 宝缯：从冠侧垂下来的两条带子
	for side: float in [-1.0, 1.0]:
		_add_box(
			Vector3(h * 0.015, h * 0.158, h * 0.024),
			Vector3(h * 0.022, h * 0.860, side * h * 0.100)
		)

	# 举身光：身后一枚圆盘，盘心抬到头肩之间；上下各收一支尖。
	# 用"圆盘 + 尖"而不是叠一摞盘（叠盘的透明度会累加，中心迅速变成
	# 一块不透明的实心，那就不像光了），也不是一枚巨大的环（环太大就成了
	# 一个气泡，玩家的第一眼会读成"天上有座穹顶"——这正是要躲开的东西）。
	_add_cylinder(
		h * 0.260, h * 0.260, h * 0.018, Vector3(h * 0.140, h * 0.760, 0.0), 48,
		Vector3(0.0, 0.0, PI * 0.5)
	)
	_add_cylinder(h * 0.205, h * 0.012, h * 0.340, Vector3(h * 0.140, h * 1.050, 0.0), 40)
	_add_cylinder(h * 0.012, h * 0.205, h * 0.300, Vector3(h * 0.140, h * 0.310, 0.0), 40)
	for i in range(28):
		var a := TAU * float(i) / 28.0
		_add_box_rot(
			Vector3(h * 0.011, h * 0.058, h * 0.009),
			Vector3(h * 0.140, h * 0.760 + cos(a) * h * 0.282, sin(a) * h * 0.282),
			Vector3(a, 0.0, 0.0)
		)


func _design_mini_stupa(px: float, pz: float, height: float) -> void:
	# 每一个尺寸都按 height 成比例：同一座城里混进"瘦针"和"矮墩"，
	# 尺度感立刻就散了。
	var y := 0.0
	_add_box(
		Vector3(height * 0.34, height * 0.07, height * 0.34),
		Vector3(px, height * 0.035, pz)
	)
	y = height * 0.07
	_add_cylinder(
		height * 0.14, height * 0.115, height * 0.42, Vector3(px, y + height * 0.21, pz), 18
	)
	y += height * 0.42
	_add_sphere(height * 0.115, height * 0.26, Vector3(px, y + height * 0.13, pz))
	y += height * 0.26
	_add_cylinder(height * 0.016, height * 0.016, height * 0.24, Vector3(px, y + height * 0.12, pz), 8)
	for i in range(6):
		var radius := lerpf(height * 0.075, height * 0.032, float(i) / 5.0)
		_add_cylinder(
			radius, radius, height * 0.018, Vector3(px, y + height * 0.068 + float(i) * height * 0.040, pz), 14
		)
	_add_sphere(height * 0.032, height * 0.064, Vector3(px, y + height * 0.24 + height * 0.024, pz))


# ---------------------------------------------------------------------------
# 几何装配
# ---------------------------------------------------------------------------


## 沿方台的一对面各排一排小部件。`axis` 0 = 沿 X 排（面朝 ±Z），1 = 沿 Z 排。
func _face_row(count: int, width: float, y: float, size: Vector3, axis: int) -> void:
	var span := width * 0.5 - size.x
	for i in range(count):
		var t := (float(i) + 0.5) / float(count) * 2.0 - 1.0
		var offset := t * span
		var face := width * 0.5
		for side: float in [-1.0, 1.0]:
			if axis == 0:
				_add_box(size, Vector3(offset, y, side * face))
			else:
				_add_box(size, Vector3(side * face, y, offset))


func _add_box(size: Vector3, center: Vector3) -> void:
	_add_box_rot(size, center, Vector3.ZERO)


func _add_box_rot(size: Vector3, center: Vector3, euler: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_parts.append({
		"mesh": mesh,
		"xform": _xform(center, euler),
	})


func _add_cylinder(
	bottom_radius: float,
	top_radius: float,
	height: float,
	center: Vector3,
	segments: int,
	euler := Vector3.ZERO
) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom_radius
	mesh.top_radius = top_radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	_parts.append({"mesh": mesh, "xform": _xform(center, euler)})


func _add_sphere(radius: float, height: float, center: Vector3) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 20
	mesh.rings = 10
	_parts.append({"mesh": mesh, "xform": _xform(center, Vector3.ZERO)})


## 部件的局部变换：绕自身旋转 → 整体缩放 → 整体平移。
## 缩放在平移之前，所以 _part_offset 是"塔基落在城里的位置"，不受倍率影响。
func _xform(center: Vector3, euler: Vector3) -> Transform3D:
	var basis := Basis.from_euler(euler)
	if not is_equal_approx(_part_scale, 1.0):
		basis = basis.scaled(Vector3.ONE * _part_scale)
	return Transform3D(basis, center * _part_scale + _part_offset)


## 把两千多个基本体合成一个 mesh。
##
## 分开挂两千个 MeshInstance3D 就是两千次绘制调用，换一个两公里外、
## 半透明、还看不清的东西——没有道理。合并之后是一次绘制。
func _merge_parts() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part: Dictionary in _parts:
		tool.append_from(part["mesh"], 0, part["xform"])
	return tool.commit()


func part_count() -> int:
	return _parts.size()


# ---------------------------------------------------------------------------
# 表现
# ---------------------------------------------------------------------------


## 0..1：越接近 1，幻影越实。驱动它的是"渴"和"沙暴"，不是时间表。
func set_presence(value: float) -> void:
	presence = clampf(value, 0.0, 1.0)
	var shown := presence > 0.02
	visible = shown
	if shown:
		# 空气衰减先砍掉三成（1.4 km 处透射 0.72），溶解项再砍一成，
		# 所以 strength 要乘 2.0：presence=0.29 时近墙的实心部分约 0.38，
		# 是"沙尘里一道压得住画面的暗影"；渴到见底（presence→1）时 1.0，
		# 整座城几乎凝实——**幻影的浓淡就是玄奘还剩多少水**。
		_material.set_shader_parameter("strength", presence * 2.0)
		# 越淡的幻影扭得越厉害：快要散掉的东西才晃得凶
		_material.set_shader_parameter("shimmer", lerpf(26.0, 7.0, presence))


## 每帧告诉幻影"相机在哪"。
##
## 它的材质关掉 Godot 的雾（fog_disabled），所以空气衰减必须自己算，
## 而自己算就需要知道观察点的位置。相机位置只走这一个入口，
## 免得 shader 里再去猜 CAMERA_POSITION_WORLD 这类版本相关的东西。
func set_camera_position(value: Vector3) -> void:
	if _material != null:
		_material.set_shader_parameter("camera_pos", value)


## 让幻影极缓慢地上下浮动，像隔着热空气在看。
func drift(time: float) -> void:
	position.y = _base_y + sin(time * 0.17) * 7.0


var base_y := 0.0:
	set(value):
		_base_y = value
		position.y = value
	get:
		return _base_y
