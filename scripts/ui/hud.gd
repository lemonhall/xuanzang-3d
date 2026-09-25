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

## 打包字体（Noto Sans SC 的子集，见 tools/font_subset.py）。
##
## **Web 上必须有它**：浏览器里没有系统字体，只用 SystemFont 的话整个界面
## 都是豆腐块（2026-09-24 第一次部署 Web 就是这个问题）。所以顺序反过来：
## 打包字体优先、各平台一致；SystemFont 降级成 fallback，只负责兜住
## 子集里没收录的字（改了台词忘了重跑子集脚本时，桌面上还能救回来）。
const BUNDLED_FONT := "res://assets/fonts/noto-sans-sc-subset.otf"

## 倒下之后那句题记。《大慈恩寺三藏法师传》记玄奘在莫贺延碛"四夜五日无一滴水
## 沾喉"、卧于沙中，夜梦一神人，身长数丈，执戟麾之曰——就是这一句。
## 放在这里是有理由的：这一关的幻影本来就是他念了一辈子的那尊像，
## 而他真在沙漠里倒下过，也真被这一声呵着继续往西走了。
const EPILOGUE := "「何不强行，而更卧也。」"
const EPILOGUE_NOTE := "——《大慈恩寺三藏法师传》记他在莫贺延碛的梦里，有神人这样呵他"
const RESTART_HINT := "R　再走一次"

## 自言自语（台词表在 scripts/ui/soliloquy_lines.gd）：浮上来、停一会儿、沉回去。
##
## 位置在画面下三分之一居中：上三分之一是幻影（抬头就是弥勒），左上角是体力，
## 正上方是沙暴状态——只剩这一块是空的，而**字幕本来就该在那儿**。
##
## 停留时长按字数给：一句话读得快，"风起则人畜惛迷"这种就要多留一会儿。
## 上下两端都是淡入淡出，不是"啪"地出现——这一关里没有任何东西是硬切的。
const SOLILOQUY_FADE_IN := 1.2
const SOLILOQUY_FADE_OUT := 1.6
const SOLILOQUY_HOLD_MIN := 2.0
const SOLILOQUY_HOLD_PER_CHAR := 0.16
## 离画面下沿多高。别贴着边：下沿有暗角，字会沉进去；也要让开手机上的
## 平台 UI（抖音横屏片子的用户名/音乐条就压在底部那条带上）。
const SOLILOQUY_BOTTOM_MARGIN := 150.0

## 字幕字号。**这个数不是"看着差不多"，是从手机屏上反推的**：
##
##   1. 我们出的是 1600×900 的 16:9。抖音竖屏信息流里，16:9 的片子按**宽度**
##      铺满——1080 宽的屏上，缩放比 = 1080 / 1600 = 0.675，所以**屏上字号 = 字号 × 0.675**。
##   2. 抖音自己的字幕在 1080p 屏上大约 40 px 高。要落进这个量级：
##      40 / 0.675 ≈ 59 → **取 60**。
##   3. 上限被最长的那句顶着：「风起则人畜惛迷，因以成病。」14 个字（汉字是方框，
##      一行的宽 ≈ 14 × 字号）＝ 840 px，占 1600 的 53%——还留着一半空。
##   4. 换成比例说：60 / 900 = **屏高的 6.7%**。判据就是这一条——
##      字幕要占屏高的 5%~7%；上一版只有 19 px（2.1%），手机上当然看不清。
##
## （`project.godot` 是 `canvas_items` + 1600×900 基准，所以这个比例在任何窗口
## 尺寸下都成立，不会在用户的大屏上缩水。）
const SOLILOQUY_FONT_SIZE := 60
## 描边。**这一条和字号一样重要**：暖白的字压在被太阳照亮的沙面上，对比度本来就
## 不够——19 px 那版在手机上看不清，一半是太小，另一半是没边。暗褐色（而不是纯黑）
## 是为了不把字从画面里抠出来，只给它一圈"脚"。
const SOLILOQUY_OUTLINE := 8
const SOLILOQUY_OUTLINE_COLOR := Color(0.10, 0.06, 0.04, 0.78)

## 题记（倒下之后那张字幕卡）的字号。**它是这一关最大的一行字**：
## 字幕 60，题记就得到 54~60 这个量级，不然"最后一句话"比途中的自言自语还小。
const EPILOGUE_FONT_SIZE := 54
const EPILOGUE_NOTE_SIZE := 30
const EPILOGUE_HINT_SIZE := 26

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


## 界面字体：打包子集优先，系统字体兜底。见 FONT_NAMES / BUNDLED_FONT 上面那段。
func _ui_font() -> Font:
	var system := SystemFont.new()
	system.font_names = PackedStringArray(FONT_NAMES)
	var bundled := load(BUNDLED_FONT)
	if bundled is Font:
		(bundled as Font).fallbacks = [system]
		return bundled
	return system

## 自言自语：**单槽位**，同一时刻只可能有一句话在屏幕上。
## （上一轮"文字交叠"被需求方点过一次名，这里不留任何重叠的余地：
## 新句子直接接管旧的，题记一出现就把话收掉。）
var _soliloquy: Label
var _sol_playing := false
var _sol_age := 0.0
var _sol_hold := 0.0
## 已经说过的 id（soliloquy_lines.gd 的表里那一个个 id）。
var _sol_said: Dictionary = {}
## 上一句是在第几秒说的（用秒数单调推进的时钟，倒下之后也继续走）。
var _sol_last_spoken_at := -1.0e9


func _ready() -> void:
	layer = 10

	var theme := Theme.new()
	theme.default_font = _ui_font()
	# HUD 的字也跟着字幕一起放大：同一块屏幕上，一行的字号是 60、另一行是 17，
	# 读起来像两个界面。17 → 22 是"跟着长大、但不抢画面"的位置。
	theme.default_font_size = 22

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
	# 字号长大之后，"体力"两个字的行高到了 ~50 px，条子跟着往下让一格，
	# 不然会贴上（Label 的高度由字体决定，不会自己告诉上面的调用方）。
	_stamina_bar.position = Vector2(24, 58)
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

	# 自言自语：底部通栏居中。先按 preset 摆好，再把上下两条偏移一起往上提——
	# 底锚的偏移量是相对**画面下沿**算的，所以减同一个数才是"整块上移"。
	_soliloquy = _make_label(_root, Vector2.ZERO, "")
	_soliloquy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_soliloquy.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_soliloquy.offset_top -= SOLILOQUY_BOTTOM_MARGIN
	_soliloquy.offset_bottom -= SOLILOQUY_BOTTOM_MARGIN
	_soliloquy.add_theme_font_size_override("font_size", SOLILOQUY_FONT_SIZE)
	_soliloquy.add_theme_color_override("font_color", Color(0.97, 0.90, 0.80))
	_add_outline(_soliloquy, SOLILOQUY_OUTLINE)
	_soliloquy.modulate = Color(1.0, 1.0, 1.0, 0.0)

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
	line.add_theme_font_size_override("font_size", EPILOGUE_FONT_SIZE)
	line.add_theme_color_override("font_color", Color(0.93, 0.86, 0.78))
	_add_outline(line, 6)
	var note := _make_label(box, Vector2.ZERO, EPILOGUE_NOTE)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", EPILOGUE_NOTE_SIZE)
	note.add_theme_color_override("font_color", Color(0.72, 0.62, 0.52))
	_add_outline(note, 4)
	var hint := _make_label(box, Vector2.ZERO, RESTART_HINT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", EPILOGUE_HINT_SIZE)
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


## 给一行字加描边。字号越大越需要它：字越大，笔画越粗，压在亮沙上就越像一团糊。
## 用暗褐色而不是纯黑——纯黑是从画面里"抠"出一行字，暗褐是让字落脚。
func _add_outline(label: Label, size: int) -> void:
	label.add_theme_color_override("font_outline_color", SOLILOQUY_OUTLINE_COLOR)
	label.add_theme_constant_override("outline_size", size)


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
	if value:
		# 题记一出来就把没说完的那句收掉：同一块屏幕上不许有两处文字。
		_stop_soliloquy()


## 自言自语复位（重走一次时用）。说过的那些话要能再说一遍。
func reset_soliloquy() -> void:
	_sol_said.clear()
	_sol_last_spoken_at = -1.0e9
	_stop_soliloquy()


## 当前屏幕上那句话（没有就是空串）。截图探针和测试用它问"这会儿在说什么"。
func current_soliloquy() -> String:
	return _soliloquy.text if _soliloquy != null else ""


## 这一局已经说了几句。
func said_count() -> int:
	return _sol_said.size()


func _stop_soliloquy() -> void:
	_sol_playing = false
	_sol_age = 0.0
	_sol_hold = 0.0
	if _soliloquy != null:
		_soliloquy.text = ""
		_soliloquy.modulate = Color(1.0, 1.0, 1.0, 0.0)


## 自言自语：每帧问一次"现在该不该说、该说哪句"。
##
## 判定在模型层（SoliloquyLines.due），这里只管**怎么出现**：
## 淡入 → 按字数停一会儿 → 淡出 → 空出槽位。判定和表现分开，
## 是因为前者要在 headless 测试里走完整的一局，后者只在有窗口时才有意义。
func _update_soliloquy(delta: float) -> void:
	if _soliloquy == null:
		return
	# 时钟必须是**单调**的：GameState.elapsed 在倒下那一刻就停住了，
	# 而落下之后还有两句要说（间隔得照样量得出来）。
	var clock := GameState.elapsed + maxf(GameState.collapse_elapsed, 0.0)
	if not _sol_playing:
		var state := {
			"clock": clock,
			"elapsed": GameState.elapsed,
			"stamina": GameState.stamina,
			"storm_intensity": GameState.storm_intensity,
			"wind_force": GameState.wind_force,
			# 幻影有多实：和幻影节点读的是同一个函数（模型层），不分家。
			"mirage_presence": GameState.mirage_presence(),
			"collapsed": GameState.is_collapsed,
			"collapse_elapsed": GameState.collapse_elapsed,
			"last_spoken_at": _sol_last_spoken_at,
		}
		var index := SoliloquyLines.due(state, _sol_said)
		if index < 0:
			return
		var line: Dictionary = SoliloquyLines.LINES[index]
		_sol_said[line["id"]] = true
		_sol_last_spoken_at = clock
		_soliloquy.text = String(line["text"])
		_sol_hold = SOLILOQUY_HOLD_MIN + SOLILOQUY_HOLD_PER_CHAR * float(
			_soliloquy.text.length()
		)
		_sol_age = 0.0
		_sol_playing = true
		return
	_sol_age += delta
	var alpha := 0.0
	var fade_out_at := SOLILOQUY_FADE_IN + _sol_hold
	if _sol_age < SOLILOQUY_FADE_IN:
		alpha = _sol_age / SOLILOQUY_FADE_IN
	elif _sol_age < fade_out_at:
		alpha = 1.0
	else:
		alpha = 1.0 - (_sol_age - fade_out_at) / SOLILOQUY_FADE_OUT
	if alpha <= 0.0:
		_stop_soliloquy()
		return
	_soliloquy.modulate = Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0))


func _process(delta: float) -> void:
	_body_alpha = lerpf(_body_alpha, _body_target, clampf(delta * 2.2, 0.0, 1.0))
	_body.modulate = Color(1.0, 1.0, 1.0, _body_alpha)
	_body.visible = _body_alpha > 0.01

	_update_soliloquy(delta)

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
