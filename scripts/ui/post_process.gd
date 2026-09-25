class_name PostProcess
extends CanvasLayer

## 全屏后处理层。用 ColorRect 铺满 + 采样屏幕纹理。
##
## 参数暴露成方法，方便沙暴期间动态加强（沙暴越大，暗角越重、颗粒越多）。
##
## 除了调色，这一层还负责**风里的沙**——那层盖住沙丘、天空、幻影的飘带。
## 它必须在这里做，因为它要的是"每个像素在世界里朝哪个方向"，
## 而不是"这个像素属于哪个物体"：沙是空气，不属于任何网格。

## 常驻的沙尘浓度。**不能是 0**：要的是"整个场景一直飘着"，
## 沙暴只是把它推浓。0.50 是"看得见、又不挡路"的位置——
## 早先写 0.42 时那一层其实**几乎看不见**（门槛落在 +1σ 以外，见 shader 里的注释），
## 改成按 σ 定门槛之后，同样的数才真的在画面上有东西；0.50 是照新的门槛配的。
const DUST_CALM := 0.50
const DUST_STORM := 1.0

var _rect: ColorRect
var _material: ShaderMaterial

## 风向（世界坐标的水平单位向量）。三个系统的沙必须往同一边走。
var wind_direction := Vector3(1.0, 0.0, 0.35).normalized()


func _ready() -> void:
	# 夹在世界和 HUD 之间：后处理要作用于画面，但不能把 HUD 也一起压暗、
	# 加颗粒。HUD 在更上层（layer 10），所以它采样不到。
	layer = 5
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/desert_post.gdshader")

	_rect = ColorRect.new()
	_rect.name = "Full"
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _material
	add_child(_rect)


func set_storm(intensity: float) -> void:
	var t := clampf(intensity, 0.0, 1.0)
	_material.set_shader_parameter("vignette_strength", lerpf(0.9, 1.5, t))
	_material.set_shader_parameter("grain_amount", lerpf(0.035, 0.09, t))
	_material.set_shader_parameter("contrast", lerpf(1.14, 0.92, t))
	_material.set_shader_parameter("dust_amount", lerpf(DUST_CALM, DUST_STORM, t))
	# 沙的"含沙量"和"有没有在跑"是两件事：amount 跟着**沙暴**（长曲线），
	# wind_force 跟着**阵风**（几秒一个来回，见 set_wind_force）。
	_material.set_shader_parameter("dust_gain", lerpf(0.85, 1.15, t))


## 风力 0..1（沙暴强度 × 阵风）。沙的浓淡和飞行的快慢都挂在它上面——
## 和推着人走、歪镜头的那个数是**同一个**，所以"沙扑上来"和"人被推了"
## 永远同时发生。
func set_wind_force(force: float) -> void:
	if _material == null:
		return
	_material.set_shader_parameter("dust_wind_force", clampf(force, 0.0, 1.0))


## 把相机交给后处理。
##
## 天空之外的所有像素都得还原成**世界方向**，后处理才知道该去空气里的哪个
## 位置采样沙尘：贴在屏幕上的沙尘是"镜头脏了"，长在方位角/仰角里的才是空气。
## 每帧调一次（就三个向量 + 一个二维角，开销可忽略）。
##
## 用相机自己的基向量，不自己算 yaw/pitch 的三角函数：省掉一次左右手约定的
## 踩坑。`tan_half_fov` 也照相机自己算：fov 属性是**竖直**视角
## （Godot 默认 KEEP_HEIGHT），横向那张角由视口宽高比推出来。
func set_view(camera: Camera3D) -> void:
	if _material == null or camera == null:
		return
	var basis := camera.global_transform.basis
	_material.set_shader_parameter("cam_right", basis.x)
	_material.set_shader_parameter("cam_up", basis.y)
	_material.set_shader_parameter("cam_forward", -basis.z)
	# 基向量是给沙用的：一、把视线还原成世界方向（沙要长在方位角里，不贴在屏幕上）；
	# 二、把**世界风向**投到画面的横轴上——风横着刮时沙横着淌，风反过来沙就反着淌。
	var size := get_viewport().get_visible_rect().size
	var tan_v := tan(deg_to_rad(camera.fov * 0.5))
	_material.set_shader_parameter("tan_half_fov", Vector2(tan_v * size.x / maxf(size.y, 1.0), tan_v))


## 太阳方向：沙尘被点亮的那一侧，必须和天空、幻影的逆光同源——
## 同一束光照在城上、照在沙上，不该是两套颜色。
func set_sun(direction: Vector3) -> void:
	if _material == null:
		return
	_material.set_shader_parameter("sun_direction_world", direction.normalized())


## 风向。沙往哪边淌由它定，别在 shader 里写死一个正号。
func set_wind(direction: Vector3) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.000001:
		return
	wind_direction = flat.normalized()
	if _material != null:
		_material.set_shader_parameter("wind_world", wind_direction)


## 眼睑合拢 0..1（0 = 睁着）。倒下之后由 `GameState.eye_close_at()` 驱动。
##
## 这一层不在场景里：它是**眼皮**，不占世界坐标，所以只能挂在后处理上。
## 竖着的缝、上下两条边的节奏、透过眼皮的那团暗红，全在着色器的 lid_* 里。
func set_eye_close(value: float) -> void:
	if _material == null:
		return
	_material.set_shader_parameter("lid_close", clampf(value, 0.0, 1.0))
