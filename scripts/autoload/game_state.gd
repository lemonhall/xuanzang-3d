extends Node

## 一局西行的账本：水还剩多少、走了多远、沙暴来了没有。
##
## 所有数值都能在 headless 测试里直接断言，不依赖渲染。

signal water_changed(remaining: float)
signal collapsed()

## 水囊见底所需秒数（正常步速）。冲刺和顶风都会让它更快。
const FULL_DRAIN_SECONDS := 190.0

var water := 1.0
var elapsed := 0.0
var distance_travelled := 0.0
var in_storm := false
var is_collapsed := false

## 沙暴强度 0..1，由天气系统每帧写入，同时驱动耗水与能见度。
var storm_intensity := 0.0


func reset() -> void:
	water = 1.0
	elapsed = 0.0
	distance_travelled = 0.0
	in_storm = false
	is_collapsed = false
	storm_intensity = 0.0
	water_changed.emit(water)


## 每帧推进。`exertion` 0..1：站着不动 0，冲刺 1。
func tick(delta: float, exertion: float) -> void:
	if is_collapsed:
		return
	elapsed += delta
	var drain := 1.0 / FULL_DRAIN_SECONDS
	drain *= 1.0 + exertion * 0.9
	drain *= 1.0 + storm_intensity * 1.4
	water = maxf(0.0, water - drain * delta)
	water_changed.emit(water)
	if water <= 0.0:
		is_collapsed = true
		collapsed.emit()


func add_distance(delta: float) -> void:
	distance_travelled += delta


## 沙暴期间的能见度（米）。晴朗时看得见几百米外的沙脊，沙暴压顶时只剩二十来米。
func visibility_meters() -> float:
	return lerpf(900.0, 22.0, clampf(storm_intensity, 0.0, 1.0))
