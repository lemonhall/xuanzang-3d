class_name SoliloquyLines
extends RefCounted

## 玄奘的自言自语 —— 话是**他自己后来写下的那些字**。
##
## 需求方 2026-09-24："应该给主角加点自言自语啊……大唐西域记里，弄一点？"
##
## 每句话的来历都写在 `source` 里，**没有出处的不许进来**：编一句文言很容易，
## 编一句**有来历**的文言才难。测试 [自言自语] 守着这一条。
##
## 一个便宜但重要的设定：这一局是**回忆**（倒下之后还要出题记），而回忆里的人
## 当然知道自己后来写了什么。于是"自言自语"和"引文"在这儿成了同一件事——
## 不用为了"像人说话"去编白话，也不用把文言装成随口一说。
##
## 出处（都是这一关已经在用的东西）：
##   * 《大唐西域记》卷十二·瞿萨旦那国 大流沙：
##     "沙则流漫，聚散随风，人行无迹，遂多迷路。四远茫茫，莫知所指……
##      乏水草，多热风，风起则人畜惛迷，因以成病。时闻歌啸，或闻号哭……
##      是以往来者聚遗骸以记之。"
##     —— 这一关的沙、风、幻影、幻听，史料里一条不缺。
##   * 《大慈恩寺三藏法师传》卷一·莫贺延碛："四夜五日无一滴水沾喉，口腹干焦，
##     几将殒绝"、"宁可就西而死，岂归东而生"。
##   * 《大慈恩寺三藏法师传》卷十·临终：愿"同生睹史多天弥勒内眷属中"——
##     他这辈子最后想见的是弥勒。所以这一关的巨像是弥勒，不是随便挑的一尊像。

## 台词表。**顺序就是优先权**：due() 返回第一句"该说且没说"的。
##
## 倒下之后那两句排在最前面，是故意的：它们是这一局的落点，
## "该说而没说"比顺序好看重要得多——万一前面还有一句没来得及说
## （间隔没到），倒下那一句也必须按时到。
const LINES: Array[Dictionary] = [
	{
		"id": "down",
		"text": "愿生睹史多天，见弥勒。",
		"source": "《大慈恩寺三藏法师传》卷十·临终发愿",
		"when": "down",
		"gap": 0.0,
	},
	{
		"id": "relics",
		"text": "往来者聚遗骸以记之。",
		"source": "《大唐西域记》卷十二·大流沙",
		"when": "relics",
		"gap": 0.0,
	},
	{
		"id": "far_off",
		"text": "四远茫茫，莫知所指。",
		"source": "《大唐西域记》卷十二·大流沙",
		"when": "opening",
	},
	{
		"id": "tracks",
		"text": "人行无迹，遂多迷路。",
		"source": "《大唐西域记》卷十二·大流沙",
		"when": "tracks",
	},
	{
		"id": "dunes",
		"text": "沙则流漫，聚散随风。",
		"source": "《大唐西域记》卷十二·大流沙",
		"when": "dunes",
	},
	{
		"id": "heat_wind",
		"text": "乏水草，多热风。",
		"source": "《大唐西域记》卷十二·大流沙",
		"when": "heat_wind",
	},
	{
		"id": "daze",
		"text": "风起则人畜惛迷，因以成病。",
		"source": "《大唐西域记》卷十二·大流沙",
		"when": "daze",
	},
	{
		"id": "mirage",
		"text": "时闻歌啸，或闻号哭。",
		"source": "《大唐西域记》卷十二·大流沙（记幻听）",
		"when": "mirage",
	},
	{
		"id": "dry",
		"text": "口腹干焦，几将殒绝。",
		"source": "《大慈恩寺三藏法师传》卷一·莫贺延碛",
		"when": "dry",
	},
	{
		"id": "vow",
		"text": "宁可就西而死，岂归东而生。",
		"source": "《大慈恩寺三藏法师传》卷一·莫贺延碛",
		"when": "vow",
	},
]

## 两句之间至少隔多久（秒）。**自言自语不是弹幕**：挨得太近就不像"心里的话"，
## 像界面在报数。个别句子可以用 `gap` 覆盖它（只给落下那两句用过）。
const MIN_GAP := 11.0

## 一句话最多几个字。文言要短，长句一出来就成了字幕组。
const MAX_CHARS := 18

## 开场下限（秒）：这十几秒属于第一句话，别的句子一律等它说完。
##
## 不加这条会怎样——2026-09-24 录片时抓到的：`--storm` 那种一上来就满风的局里，
## "乏水草，多热风"在第 **0.03 秒**就说了出来，而"四远茫茫，莫知所指"（开场白）
## 得等到 11 秒之后才轮到。**台词表的顺序管得住同时到期的句子，管不住谁先到期**：
## 风那一条的条件是"风够大"，满风的局里它从第一帧就成立。
##
## 三句不受它管：开场白自己，和倒下之后的两句（它们的时机由倒下那一刻定，
## 和这一局过了几秒无关——截图探针 `--collapsed` 就是一条开局即倒下的时间线）。
const OPENING_FLOOR := 12.0


## 这一帧该说哪一句：返回 LINES 的下标，没有要说的话就返回 -1。
##
## `said` 是"已经说过的 id"（字典，id → true），由调用方持有——
## "每句只说一次"因此不需要在这里存状态，测试里也好摆布。
##
## `state` 需要这些键（都能在模型层拿到，见 hud.gd 的调用处）：
##   clock            单调推进的秒数（倒下之后还要走），只用来量间隔
##   elapsed          这一局的秒数（倒下之后停住），用来量"什么时候开场"
##   stamina          0..1
##   storm_intensity  0..1
##   wind_force       0..1（沙暴 × 阵风）
##   mirage_presence  0..1
##   collapsed        倒下了没有
##   collapse_elapsed 倒下之后过了多久（-1 = 还站着）
##   last_spoken_at   上一句说出来的 clock，还没说过就给一个很小的数
static func due(state: Dictionary, said: Dictionary) -> int:
	var clock := float(state.get("clock", 0.0))
	var last := float(state.get("last_spoken_at", -1.0e9))
	for i in range(LINES.size()):
		var line: Dictionary = LINES[i]
		if said.has(line["id"]):
			continue
		var when := String(line["when"])
		if clock < OPENING_FLOOR and when != "opening" and when != "down" and when != "relics":
			continue
		if not _met(line["when"], state):
			continue
		# 间隔**按句子看**，不是开头一道总闸门。
		# 2026-09-24 就是写成总闸门的：`if clock - last < MIN_GAP: return -1`
		# 摆在函数最前面，于是落下那两句被推到 11 秒之后——它们在表里特意写了
		# gap = 0，结果一次都没生效（测试当场抓到：临终那一愿迟到了 12 秒才说）。
		if clock - last < float(line.get("gap", MIN_GAP)):
			continue
		return i
	return -1


## 触发条件。每个 `when` 是**一个状态问题**，不是一段时序脚本：
## 时序（沙暴相位、体力曲线、倒下的十几秒）全在别处已经有了，
## 这里只问"现在是什么样"——两处各写一份时序，迟早会对不上。
static func _met(rule: String, state: Dictionary) -> bool:
	var elapsed := float(state.get("elapsed", 0.0))
	var stamina := float(state.get("stamina", 1.0))
	var storm := float(state.get("storm_intensity", 0.0))
	var wind := float(state.get("wind_force", 0.0))
	var presence := float(state.get("mirage_presence", 0.0))
	var collapsed := bool(state.get("collapsed", false))
	var since := float(state.get("collapse_elapsed", -1.0))
	match rule:
		"opening":
			# 开局那几十秒里说出来就够了：再晚，"刚踏上这片碛"就不像了。
			return elapsed >= 4.0 and elapsed <= 60.0
		"tracks":
			return elapsed >= 45.0
		"dunes":
			return elapsed >= 80.0 and stamina < 0.75
		"heat_wind":
			# wind_force 是"这一阵风有多大"：第一阵扑上来就够格说话了。
			return wind >= 0.30
		"daze":
			return storm >= 0.80
		"mirage":
			return presence >= 0.45
		"dry":
			return stamina <= 0.28
		"vow":
			return stamina <= 0.12
		"down":
			return collapsed and since >= 1.0
		"relics":
			# 6.5 s：眼睑合到四成左右、题记（12 s）还没出来——念完正好闭眼。
			return collapsed and since >= 6.5
	return false
