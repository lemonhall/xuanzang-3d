extends Node

## 一局西行的账本：体力还剩多少、走了多远、沙暴来了没有、倒下之后过了多久。
##
## 所有数值都能在 headless 测试里直接断言，不依赖渲染。
##
## 这是**模型层**：镜头怎么晃、喘气多快、眼睑什么时候合上，都从这里取数。
## 它自己不碰任何节点，所以"倒下之后那 12 秒"整条时间线可以脱离场景单独验。

signal stamina_changed(remaining: float)
signal collapsed()

## 体力见底所需秒数（正常步速、无风）。冲刺和沙暴都会让它更快。
##
## 215 这个数不是拍的，是从需求方要的画面反推的：**"够翻 4 道沙丘、走 3 分钟"**。
## 沙丘间距 95 m，4 道是 380 m——但**"间距 380 m"不等于"翻过 4 道脊"**：
## 每座沙丘的高度本身就带 0.55 的随机起伏（见 dune_field.gd 的 vary），
## 出生点往 +X 的第四道脊恰好长在低谷上（显著度不到 8 m），
## 所以要真的数到 4 道脊，得走到约 490 m 之外、那道脊之后 100 m 处。
## 加上沙暴周期平均再啃掉 11% 左右，基准就定在 215 s：
## 实测结算约 192 s（3 分 12 秒）、500 m 出头——**两条都满足**。
## 两组数都写进了 tests 里的 [体力契约]，改坏了会报红。
const ENDURANCE_SECONDS := 215.0

## 冲刺的额外消耗系数。全速冲 1.9 倍耗、只快 1.7 倍速——**跑反而走不远**。
## 这是故意的：在沙里跑是亏的，玩家得自己发现。
const SPRINT_DRAIN := 0.9

## 沙暴的额外消耗系数。0.35 是压下来的：原来的 1.4 会让玩家在 115 s 就倒下、
## 只走 300 m（不到 4 道沙丘），把"三分钟、四道沙丘"整条契约吃掉。
const STORM_DRAIN := 0.35

# ---------------------------------------------------------------------------
# 倒下之后的时间线
# ---------------------------------------------------------------------------

## 膝盖先软，整个人侧倒下去。
const FALL_SECONDS := 2.6
## 倒地之后还喘几口粗气才闭眼。跳过这一段，"闭眼"就退化成了"淡出"。
const GASP_SECONDS := 1.6
## 眼睑合拢的时长。5.5 s 是**慢**的：濒死不是眨眼。
const CLOSE_SECONDS := 5.5
## 彻底黑掉之后多久出那句题记。
const EPILOGUE_SECONDS := 12.0

var stamina := 1.0
var elapsed := 0.0
var distance_travelled := 0.0
var is_collapsed := false
## 倒下之后过了多少秒。-1 = 还站着。tick() 每帧推进它。
var collapse_elapsed := -1.0

## 沙暴强度 0..1，由天气系统每帧写入，同时驱动体力消耗与能见度。
var storm_intensity := 0.0


func reset() -> void:
	stamina = 1.0
	elapsed = 0.0
	distance_travelled = 0.0
	is_collapsed = false
	collapse_elapsed = -1.0
	storm_intensity = 0.0
	stamina_changed.emit(stamina)


## 把剩下的体力换算成"累"：0 = 刚出发，1 = 就站在倒下的边上。
func fatigue() -> float:
	return 1.0 - stamina


## 每帧推进。`exertion` 0..1：站着不动 0，冲刺 1。
func tick(delta: float, exertion: float) -> void:
	if is_collapsed:
		# 倒下之后体力不再变（测试守着这条），但**时间要继续走**：
		# 摔倒、喘气、闭眼、题记全挂在这条时间线上。
		collapse_elapsed += delta
		return
	elapsed += delta
	var drain := 1.0 / ENDURANCE_SECONDS
	drain *= 1.0 + exertion * SPRINT_DRAIN
	drain *= 1.0 + storm_intensity * STORM_DRAIN
	stamina = maxf(0.0, stamina - drain * delta)
	stamina_changed.emit(stamina)
	if stamina <= 0.0:
		is_collapsed = true
		collapse_elapsed = 0.0
		collapsed.emit()


func add_distance(delta: float) -> void:
	distance_travelled += delta


## 沙暴期间的能见度（米）。晴朗时看得见几百米外的沙脊，沙暴压顶时只剩二十来米。
func visibility_meters() -> float:
	return lerpf(900.0, 22.0, clampf(storm_intensity, 0.0, 1.0))


# ---------------------------------------------------------------------------
# 倒下之后的曲线
#
# 三个静态函数，全部是 (秒) → (0..1) 的纯映射。镜头、呼吸、眼睑三处各取一处，
# 谁都不许自己再写一条——"闭眼"和"喘气放缓"必须是同一条时间线上的两条读数，
# 否则画面里会露出两个互不相干的节奏。
# ---------------------------------------------------------------------------


## 摔倒进度 0..1（膝盖软 → 侧倒）。缓出：倒下去先是加速，落地前一瞬最慢。
static func fall_at(t: float) -> float:
	if t < 0.0:
		return 0.0
	return 1.0 - pow(1.0 - clampf(t / FALL_SECONDS, 0.0, 1.0), 2.0)


## 眼睑合拢 0..1。摔倒 + 喘气之后才开始，而且用 smoothstep 而不是线性——
## 闭合是**两头慢、中间快**的，线性会显得像有人在拉幕布。
static func eye_close_at(t: float) -> float:
	if t < 0.0:
		return 0.0
	var x := clampf((t - FALL_SECONDS - GASP_SECONDS) / CLOSE_SECONDS, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## 呼吸频率（Hz）。走着喘：0.24（刚出发）→ 0.90（快倒下）。
## 倒下之后：先急喘 1.25，再一路慢到 0.30——濒死的呼吸是**先快后慢**，
## 一条单调递增的曲线读起来就不对了。
static func pant_rate(stamina: float, collapse_t: float) -> float:
	if collapse_t >= 0.0:
		return lerpf(1.25, 0.30, clampf(collapse_t / 9.0, 0.0, 1.0))
	return lerpf(0.24, 0.90, clampf(1.0 - stamina, 0.0, 1.0))


## 呼吸的幅度（米，胸口起伏折算到视点位移）。
static func pant_depth(stamina: float, collapse_t: float) -> float:
	if collapse_t >= 0.0:
		return lerpf(0.055, 0.012, clampf((collapse_t - 2.0) / 8.0, 0.0, 1.0))
	return lerpf(0.014, 0.052, clampf(1.0 - stamina, 0.0, 1.0))
