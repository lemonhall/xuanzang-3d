class_name Hud
extends CanvasLayer

## HUD：水囊、里程、沙暴状态。
##
## 刻意做得很少。这一关的压迫感来自"看见的沙"，不是来自界面上的数字；
## 水囊条是唯一的强提示，因为它直接对应"还走得动吗"。
##
## 中文字形走 SystemFont：Godot 默认主题字体不含 CJK，
## 不指系统字体的话界面上全是豆腐块。

const FONT_NAMES := [
	"Microsoft YaHei UI",
	"Microsoft YaHei",
	"SimHei",
	"Noto Sans CJK SC",
	"Sans-Serif",
]

var _water_bar: ProgressBar
var _water_label: Label
var _distance_label: Label
var _storm_label: Label
var _thirst_label: Label
var _crosshair: ColorRect


func _ready() -> void:
	layer = 10

	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(FONT_NAMES)
	theme.default_font = font
	theme.default_font_size = 17

	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme
	add_child(root)

	_water_label = _make_label(root, Vector2(24, 20), "水囊")
	_water_bar = ProgressBar.new()
	_water_bar.position = Vector2(24, 48)
	_water_bar.size = Vector2(232, 16)
	_water_bar.max_value = 1.0
	_water_bar.value = 1.0
	_water_bar.show_percentage = false
	_water_bar.add_theme_stylebox_override("background", _bar_style(Color(0, 0, 0, 0.32)))
	_water_bar.add_theme_stylebox_override(
		"fill", _bar_style(Color(0.88, 0.64, 0.34, 0.9))
	)
	root.add_child(_water_bar)

	_distance_label = _make_label(root, Vector2(24, 72), "已行 0 米")

	_storm_label = _make_label(root, Vector2(0, 20), "")
	_storm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_storm_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_storm_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.66))

	_thirst_label = _make_label(root, Vector2(0, 0), "")
	_thirst_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_thirst_label.set_anchors_preset(Control.PRESET_CENTER)
	_thirst_label.add_theme_font_size_override("font_size", 22)
	_thirst_label.add_theme_color_override("font_color", Color(0.95, 0.72, 0.55))

	# 一个几乎看不见的点：有它才知道自己在看哪儿，没它画面会晃得发飘。
	# 用 CenterContainer 而不是自己算坐标——CanvasLayer 不是 Control，
	# 既没有 size 也没有 NOTIFICATION_RESIZED，手动居中是走不通的。
	_crosshair = ColorRect.new()
	_crosshair.color = Color(1.0, 0.95, 0.85, 0.35)
	_crosshair.size = Vector2(3, 3)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	center.name = "CrosshairCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	center.add_child(_crosshair)


func _make_label(parent: Control, pos: Vector2, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_color_override("font_color", Color(1.0, 0.94, 0.85))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	parent.add_child(label)
	return label


func _bar_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style


func _process(_delta: float) -> void:
	_water_bar.value = GameState.water
	_water_label.text = "水囊  %d%%" % roundi(GameState.water * 100.0)
	_distance_label.text = "已行 %d 米" % roundi(GameState.distance_travelled)

	# 水越少，字越红；到 25% 以下开始明说
	var low := GameState.water < 0.25
	_water_bar.add_theme_stylebox_override(
		"fill",
		_bar_style(Color(0.86, 0.30, 0.20, 0.92) if low else Color(0.88, 0.64, 0.34, 0.9))
	)
	_water_label.add_theme_color_override(
		"font_color", Color(1.0, 0.62, 0.45) if low else Color(1.0, 0.94, 0.85)
	)
	_thirst_label.text = "水囊将尽" if low and not GameState.is_collapsed else ""
	if GameState.is_collapsed:
		_thirst_label.text = "倒下了"

	var storm := GameState.storm_intensity
	if storm > 0.05:
		_storm_label.text = "%s   %.0f 米可见" % [
			"沙暴" if storm > 0.5 else "起风",
			GameState.visibility_meters(),
		]
	else:
		_storm_label.text = ""
