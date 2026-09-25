class_name Sandstorm
extends Node

## 沙暴循环：平静 → 起风 → 压顶 → 退去。
##
## 这是这一关的主旋律。它同时改四样东西，而且四样都指向同一个感受——
## "看不清、走不动、心里发慌"：
##   1. 雾浓度（能见度）
##   2. 天光（天顶压低、地平线变脏）
##   3. 风力推挤（玩家被动位移，方向感被夺走）
##   4. 耗水速度（GameState 里按 storm_intensity 加成）

const CALM_SECONDS := 22.0
const BUILD_SECONDS := 16.0
const PEAK_SECONDS := 18.0
const FADE_SECONDS := 12.0

## 平静时的深度雾。0.0022 会把 300 m 外的沙丘糊掉，沙海就没了起伏；
## 0.0014 在 1 km 处仍有 25% 透射——"看不见边"够用，
## 而 100~400 m 那几道脊线还看得见。
const CALM_FOG := 0.0014
const PEAK_FOG := 0.042
## 沙暴峰值时推在玩家身上的力（米/秒）。**方向比大小重要**，见 wind_direction。
const PEAK_PUSH := 2.6

var world: DesertWorld
var player: Wanderer

## 0..1，当前沙暴强度。测试与 HUD 都读它。
var intensity := 0.0
## 风向（水平面上的单位向量）：**几乎横着抽过来**，只带一点点逆风。
##
## 上一版是 (1, 0.35)——和"走向弥勒"（+X）只差 19°。于是那股 2.6 m/s 的推力
## 的绝大部分变成了**顺风加速**：玩家只觉得自己走得快了一点，完全读不出"被风
## 吹"（需求方 2026-09-24："大风吹的感觉不是很明显，视觉和行走上"）。
##
## 现在横向分量占 97%：人得侧着身子顶，才读得出风；沙也横着流过画面，
## 一眼就看得见风往哪边刮。剩下那 3% 的逆风（-X）是"顶着风走脚下会慢"，
## 只给一点点——给多了，三分钟就翻不够四道沙丘了（[风里的一局] 测试守着）。
var wind_direction := Vector3(-0.22, 0.0, 0.98).normalized()

var _phase := 0
var _timer := 0.0
## 单调时钟。**不能用 _timer**：它每一相位都归零，阵风的相位会跟着跳，
## "一阵一阵"立刻变成"每过一关抖一下"。
var _clock := 0.0


func _physics_process(delta: float) -> void:
	advance(delta)


## 推进一帧：先走相位机，再把结果落到世界和玩家身上。
##
## 抽成一个公开方法，是为了让测试能**按真实相位走**（而不是自己凑一个
## 强度曲线）：[体力契约] 和 [地形够不够大] 两条都要拿真实的沙暴算账。
func advance(delta: float) -> void:
	_clock += delta
	_advance_phase(delta)
	_apply()


## 阵风包络 0.55..1.0。风不是一条稳定的曲线，"大风吹"读起来是**一阵一阵**：
## 一波扑上来、缓一缓、又一波。两个不可通约的慢频率相乘得到包络，再取幂把
## 波峰削尖——正弦的推背感是规律的，规律的东西不像风。
##
## **三处共用这一个包络**：玩家的推力、镜头的晃动、后处理里沙的浓淡。
## 各写一份的话，"沙正好扑上来的那一刻人也被推了一下"这种同步立刻散掉，
## 而这三样同步起来才是"一场风"而不是"三个效果"。
func gust(time: float) -> float:
	var a := 0.5 + 0.5 * sin(time * 0.63)
	var b := 0.5 + 0.5 * sin(time * 0.29 + 1.7)
	return 0.55 + 0.45 * pow(clampf(a * b * 2.0, 0.0, 1.0), 1.6)


## 这一帧的风力 0..1：强度 × 阵风。0 = 完全没风。
##
## 它是**唯一出口**：推力、镜头、沙子都读它。别再各自去乘 intensity——
## 那样阵风就只作用在其中一样上。
func wind_force() -> float:
	return intensity * gust(_clock)


func _advance_phase(delta: float) -> void:
	_timer += delta
	match _phase:
		0:
			intensity = 0.0
			if _timer >= CALM_SECONDS:
				_next_phase()
		1:
			intensity = pow(clampf(_timer / BUILD_SECONDS, 0.0, 1.0), 1.6)
			if _timer >= BUILD_SECONDS:
				_next_phase()
		2:
			# 峰值不是一条直线：留一点起伏，风才有"扑上来"的感觉
			intensity = clampf(0.88 + 0.12 * sin(_timer * 2.1), 0.0, 1.0)
			if _timer >= PEAK_SECONDS:
				_next_phase()
		3:
			intensity = pow(maxf(0.0, 1.0 - _timer / FADE_SECONDS), 1.4)
			if _timer >= FADE_SECONDS:
				_next_phase()


func _next_phase() -> void:
	_phase = (_phase + 1) % 4
	_timer = 0.0
	phase_changed.emit(_phase)


signal phase_changed(phase: int)


func _apply() -> void:
	var force := wind_force()
	if world != null:
		world.set_fog_density(lerpf(CALM_FOG, PEAK_FOG, intensity))
		world.set_storm_look(intensity)
	if player != null:
		player.external_push = wind_direction * (PEAK_PUSH * force)
	# 风力和风向各写一处，镜头（Wanderer 自己读）和后处理（main 转发）
	# 都从这里取。风的强弱和沙的浓淡因此永远是同一个数。
	GameState.wind_force = force
	GameState.wind_direction = wind_direction
	GameState.storm_intensity = intensity


## 直接跳到某个强度，供测试与调试使用（跳过等待）。
func force_intensity(value: float) -> void:
	intensity = clampf(value, 0.0, 1.0)
	_apply()


## 重走一次时把天气打回平静。
##
## **必须连 _apply() 一起走**：只把 _phase / intensity 归零的话，雾浓度、
## 天光和那个把玩家往一边推的力，还停在上一局最后一帧的状态上——
## 新的一局会从"平静但是被推着走"开始，而这种错误在画面上很难认出来。
func reset() -> void:
	_phase = 0
	_timer = 0.0
	_clock = 0.0
	intensity = 0.0
	_apply()


func phase_name() -> String:
	match _phase:
		0:
			return "平静"
		1:
			return "起风"
		2:
			return "沙暴压顶"
		_:
			return "风势渐弱"
