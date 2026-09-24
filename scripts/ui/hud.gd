class_name Hud
extends CanvasLayer

## HUD：一条体力，一句风。
##
## **这里没有水囊，也没有里程。** 需求方 2026-09-24 明确划掉的两样：
##   1. "不应该是水囊的概念" —— 玩家带的是自己的身体，不是一只水壶；
##   2. "也不要给玩家显示走了多少米" —— 报出里程的那一刻，沙漠就有了刻度，
##      而这一关全部的氛围都建立在"量不出来"上。
## 所以体力条只剩一条**没有数字**的条：看得见在掉，但不知道还剩多少秒。
##
## 沙暴提示同理，只报状态（起风 / 沙暴压顶），不报能见度几米。
## 能见度那个数仍然在模型层（GameState.visibility_meters），它是给天气系统
## 自己用的，不是给玩家看的仪表。
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

## 倒下之后那句题记。《大慈恩寺三藏法师传》记玄奘在莫贺延碛"四夜五日无一滴水
## 沾喉"、卧于沙中，夜梦一神人，身长数丈，执戟麾之曰——就是这一句。
## 放在这里是有理由的：这一关的幻影本来就是他念了一辈子的那尊像，
## 而他真在沙漠里倒下过，也真被这一声呵着继续往西走了。
const EPILOGUE := "「何不强行，而更卧也。」"
const EPILOGUE_NOTE := "——《大慈恩寺三藏法师传》记他在莫贺延碛的梦里，有神人这样呵他"
const RESTART_HINT := "R　再走一次"

var _root: Control
## 会随"倒下"淡出的一整组（体力条 + 沙暴提示 + 准星）。
var _body: Control
var _crosshair_holder: Control
var _stamina_bar: ProgressBar
var _stamina_label: Label
var _storm_label: Label
var _epilogue: Control
var _body_alpha := 1.0
var _body_target := 1.0


func _ready() -> void:
	layer = 10

	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(FONT_NAMES)
	theme.default_font = font
	theme.default_font_size = 17

	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = theme
	add_child(_root)

	_body = Control.new()
	_body.name = "Body"
	_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_body)

	_stamina_label = _make_label(_body, Vector2(24, 20), "体力")
	_stamina_bar = ProgressBar.new()
	_stamina_bar.position = Vector2(24, 48)
	_stamina_bar.size = Vector2(232, 16)
	_stamina_bar.max_value = 1.0
	_stamina_bar.value = 1.0
	# show_percentage = false 不只是排版选择：**条上没有数**才是这一版的要求。
	_stamina_bar.show_percentage = false
	_stamina_bar.add_theme_stylebox_override("background", _bar_style(Color(0, 0, 0, 0.32)))
	_stamina_bar.add_theme_stylebox_override(
		"fill", _bar_style(Color(0.88, 0.64, 0.34, 0.9))
	)
	_body.add_child(_stamina_bar)

	_storm_label = _make_label(_body, Vector2(0, 20), "")
	_storm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# **必须用 set_anchors_and_offsets_preset**，不能只用 set_anchors_preset：
	# 后者保留"当前矩形"去反推偏移量，而 Label 当前的矩形只有几个字符宽，
	# 于是这条"顶部通栏居中"的提示会缩成一个贴左上角的小块，
	# 正好压在"体力"两个字上（2026-09-24 需求方截图抓到）。
	_storm_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	# 通栏之后再把纵向位置摆回来（preset 会把偏移量清成 0）。
	_storm_label.position = Vector2(0, 20)
	_storm_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.66))

	# 一个几乎看不见的点：有它才知道自己在看哪儿，没它画面会晃得发飘。
	# 用 CenterContainer 而不是自己算坐标——CanvasLayer 不是 Control，
	# 既没有 size 也没有 NOTIFICATION_RESIZED，手动居中是走不通的。
	_crosshair_holder = CenterContainer.new()
	_crosshair_holder.name = "CrosshairCenter"
	_crosshair_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_crosshair_holder)
	var crosshair := ColorRect.new()
	crosshair.color = Color(1.0, 0.95, 0.85, 0.35)
	crosshair.size = Vector2(3, 3)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair_holder.add_child(crosshair)

	# 题记：彻底黑掉之后才出现，所以一开始就隐藏。
	_epilogue = Control.new()
	_epilogue.name = "Epilogue"
	_epilogue.set_anchors_preset(Control.PRESET_FULL_RECT)
	_epilogue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_epilogue.visible = false
	_root.add_child(_epilogue)
	# 三行文字用 VBox 摞起来再整体居中。不用"给每个 Label 设 PRESET_CENTER
	# 再挪 position"那种写法：Label 的尺寸由文本决定，锚点居中那一下用的是
	# **当时的**尺寸（0），最后会变成三行各自从屏幕中心往右排。
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 整块往下挪一点：合眼那一格里，画面上半部留给大佛。
	holder.offset_top = 150.0
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_epilogue.add_child(holder)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	holder.add_child(box)

	var line := _make_label(box, Vector2.ZERO, EPILOGUE)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_theme_font_size_override("font_size", 27)
	line.add_theme_color_override("font_color", Color(0.93, 0.86, 0.78))
	var note := _make_label(box, Vector2.ZERO, EPILOGUE_NOTE)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 15)
	note.add_theme_color_override("font_color", Color(0.72, 0.62, 0.52))
	var hint := _make_label(box, Vector2.ZERO, RESTART_HINT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.55, 0.48, 0.42))


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


## 倒下之后把体力条那一组收掉。**淡出而不是咔嚓隐藏**：人是在几秒里
## 看不清的，界面跟着一起退才不突兀。准星也一起收——它是"还玩得下去"的标志。
func set_body_visible(value: bool) -> void:
	_body_target = 1.0 if value else 0.0


## 彻底黑掉之后出题记。
func set_epilogue(value: bool) -> void:
	if _epilogue != null:
		_epilogue.visible = value


func _process(delta: float) -> void:
	_body_alpha = lerpf(_body_alpha, _body_target, clampf(delta * 2.2, 0.0, 1.0))
	_body.modulate = Color(1.0, 1.0, 1.0, _body_alpha)
	_body.visible = _body_alpha > 0.01

	_stamina_bar.value = GameState.stamina

	# 体力见底之前先把条变红；到 25% 以下才是真的该慌了。
	var low := GameState.stamina < 0.25
	_stamina_bar.add_theme_stylebox_override(
		"fill",
		_bar_style(Color(0.86, 0.30, 0.20, 0.92) if low else Color(0.88, 0.64, 0.34, 0.9))
	)
	_stamina_label.add_theme_color_override(
		"font_color", Color(1.0, 0.62, 0.45) if low else Color(1.0, 0.94, 0.85)
	)

	# 沙暴只报状态，不报米数。
	var storm := GameState.storm_intensity
	if storm > 0.5:
		_storm_label.text = "沙暴压顶"
	elif storm > 0.05:
		_storm_label.text = "起风了"
	else:
		_storm_label.text = ""
