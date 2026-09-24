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
const PEAK_PUSH := 2.6

var world: DesertWorld
var player: Wanderer

## 0..1，当前沙暴强度。测试与 HUD 都读它。
var intensity := 0.0
## 风向（水平面上的单位向量）。走得越久，被吹偏得越远。
var wind_direction := Vector3(1.0, 0.0, 0.35).normalized()

var _phase := 0
var _timer := 0.0


func _physics_process(delta: float) -> void:
	advance(delta)


## 推进一帧：先走相位机，再把结果落到世界和玩家身上。
##
## 抽成一个公开方法，是为了让测试能**按真实相位走**（而不是自己凑一个
## 强度曲线）：[体力契约] 和 [地形够不够大] 两条都要拿真实的沙暴算账。
func advance(delta: float) -> void:
	_advance_phase(delta)
	_apply()


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
	if world != null:
		world.set_fog_density(lerpf(CALM_FOG, PEAK_FOG, intensity))
		world.set_storm_look(intensity)
	if player != null:
		player.external_push = wind_direction * (PEAK_PUSH * intensity)
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
