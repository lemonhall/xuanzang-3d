class_name DuneField
extends RefCounted

## 塔克拉玛干沙丘高度场。
##
## 公式与 Blender 端 `blender/desert_lib.py::dune_height` 同源，参数也一致。
## 这样概念图和 3D 场景是**同一片沙漠**，不是两次各自想象出来的沙漠——
## 调参时两边可以互相印证。
##
## 坐标约定：X 为脊线间距方向，Z 沿脊线延伸，Y 是高度（Godot 里 Y 朝上）。
## 相机朝 +X 看时，才能看到一道道叠过来的沙丘；朝 Z 看只会看到一条条平线。

## 沙丘高度（米）。站在 1.66 m 眼高的人面前，这个数字直接决定"渺小感"。
var height := 30.0
## 脊线尖锐度。越大，脊越像刀刃，丘间越平。
var sharp := 3.4
## 脊线间距（米）。
var spacing := 95.0
## 脊线蜿蜒幅度。**平直脊线会让第一人称画面塌成一条水平线**，这是关键参数。
var bend := 5.0
## 底层大尺度起伏（米）。
var swell := 10.0
## 每座沙丘各自的高度系数，0..1。远近脊线能错开就靠它。
var vary := 0.55

var _wander := FastNoiseLite.new()
var _scale := FastNoiseLite.new()
var _swell := FastNoiseLite.new()
var _detail := FastNoiseLite.new()


func _init() -> void:
	_setup(_wander, 101)
	_setup(_scale, 202)
	_setup(_swell, 303)
	_setup(_detail, 404)


static func _setup(noise: FastNoiseLite, noise_seed: int) -> void:
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	# frequency 固定为 1：下面的采样坐标已经是"噪声空间"里的频率，
	# 与 Blender 的 mathutils.noise.noise(p) 口径一致。
	noise.frequency = 1.0
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	noise.fractal_gain = 0.5
	noise.fractal_lacunarity = 2.0
	noise.seed = noise_seed


## 取 (x, z) 处的沙面高度。
func sample(x: float, z: float) -> float:
	var lane := x / spacing
	var wander := _wander.get_noise_2d(x * 0.0012, z * 0.0017) * bend
	var phase := (lane + wander) * PI
	var profile := (cos(phase) + 1.0) * 0.5

	var per_dune := 1.0 - vary * (0.5 + 0.5 * _scale.get_noise_2d(x * 0.0048, z * 0.0048))
	var h := pow(profile, sharp) * height * per_dune

	h += _swell.get_noise_2d(x * 0.00085, z * 0.0011) * swell
	h += _detail.get_noise_2d(x * 0.0042, z * 0.0060) * 0.55
	return h


## 用有限差分取沙面法线，用来摆放需要贴着沙面的东西。
func normal_at(x: float, z: float, step := 1.0) -> Vector3:
	var dx := sample(x + step, z) - sample(x - step, z)
	var dz := sample(x, z + step) - sample(x, z - step)
	return Vector3(-dx, 2.0 * step, -dz).normalized()


## 沙面坡度（弧度），用来判断"这里站得住吗"。
func slope_at(x: float, z: float, step := 1.0) -> float:
	return normal_at(x, z, step).angle_to(Vector3.UP)


## 挑一个"看得见沙丘"的立位：前方有一道**低**坡（切掉画面下部一小块），
## 更远处还有高于视线的高度——这两条合起来才是"一道道脊线叠过来"。
##
## 三种朴素做法都失败了：站脊顶（只能看到一片平沙）、
## 偏好低地（落进四面是沙的盆里）、数天际线拐点（噪声抖动在平坡上也能数出几十个"脊"）。
##
## Blender 端的 render_shot.find_viewpoint() 是同一套判据，但**只看 38 m 一处**。
## 那个版本漏掉了 50 m 处那道脊：它 14° 高，把画面下部 73% 全吃成一片平沙，
## 抬头只剩 27% 的一条天——第一人称下这就是"四面围合"，是"室内感"的一半来源。
## 这里改成扫一整段近场 [20, 70] m 取最高角，并把上限压到 6°：
## 沙脊只切掉画面最下面一小条，地平线和天都打开。
## （Blender 那边的构图是离线渲染、已经定稿，不改；这条分歧是故意的。）
func find_viewpoint(z := 0.0, span := 400.0, step := 3.0, eye := 1.66) -> Vector2:
	## 近场扫这一段：既要有东西压在画面下部，又不能压太多。
	const NEAR_FROM := 20.0
	const NEAR_TO := 70.0
	const NEAR_STEP := 5.0
	## 理想角 2.5°、硬上限 6°。上限不是审美偏好：超过 6° 的脊会开始遮住
	## 远处建筑的下半身，而"从沙里升起来"正是幻影必须有的一层。
	const NEAR_TARGET := 2.5
	const NEAR_LIMIT := 6.0
	## 远场（100~340 m）也要压。原版只要求"比视线高"，于是 150 m 处一道
	## 高 25 m 的脊就是 9.5°——画面下部被沙面吃掉六成，天际线顶到 10° 上下，
	## 幻影的城墙只剩最上面几个垛口露在外面。远脊理想 4°、上限 7°：
	## 留得住"一道道叠过来"，又不至于把地平线抬起来。
	const FAR_TARGET := 4.0
	const FAR_LIMIT := 7.0
	var far_probes := [100.0, 170.0, 250.0, 340.0]
	var best := Vector2.ZERO
	var best_score := -INF
	var x := -span
	while x <= span:
		var h := sample(x, z)
		var near_angle := -INF
		var probe_d := NEAR_FROM
		while probe_d <= NEAR_TO:
			near_angle = maxf(
				near_angle, rad_to_deg(atan2(sample(x + probe_d, z) - (h + eye), probe_d))
			)
			probe_d += NEAR_STEP
		var far := -INF
		var far_angle := -INF
		for d: float in far_probes:
			far = maxf(far, sample(x + d, z))
			far_angle = maxf(
				far_angle, rad_to_deg(atan2(sample(x + d, z) - (h + eye), d))
			)
		var far_lift := far - (h + eye)
		var score := (
			-absf(near_angle - NEAR_TARGET) * 6.0
			- absf(far_angle - FAR_TARGET) * 4.0
			+ far_lift * 0.4
		)
		if near_angle > NEAR_LIMIT:
			score -= (near_angle - NEAR_LIMIT) * 30.0
		if far_angle > FAR_LIMIT:
			score -= (far_angle - FAR_LIMIT) * 30.0
		if score > best_score:
			best_score = score
			best = Vector2(x, z)
		x += step
	return best
