class_name PostProcess
extends CanvasLayer

## 全屏后处理层。用 ColorRect 铺满 + 采样屏幕纹理。
##
## 参数暴露成方法，方便沙暴期间动态加强（沙暴越大，暗角越重、颗粒越多）。

var _rect: ColorRect
var _material: ShaderMaterial


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
