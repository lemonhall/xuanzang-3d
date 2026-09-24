class_name Wanderer
extends CharacterBody3D

## 第一人称行走。
##
## 玄奘不是运动员：默认步速 2.6 m/s，冲刺 4.4 m/s，且冲刺会加快耗水。
## 贴地不用物理地形，直接对高度场采样——沙丘是连续光滑曲面，
## 采样比 trimesh 碰撞又快又稳，也不会在 4 m 网格上踩出棱角。

@export var walk_speed := 2.6
@export var sprint_speed := 4.4
@export var acceleration := 9.0
@export var eye_height := 1.66
@export var mouse_sensitivity := 0.0022
@export_range(0.2, 1.0, 0.05) var pitch_limit := 1.35

var world: DesertWorld

## 外部（沙暴）叠加到玩家身上的推力，米/秒。
var external_push := Vector3.ZERO

var _yaw := 0.0
var _pitch := 0.0
var _speed := 0.0
var _bob_phase := 0.0
var _camera: Camera3D


func _ready() -> void:
	_camera = Camera3D.new()
	_camera.name = "Eyes"
	_camera.current = true
	_camera.fov = 68.0
	# far 必须把幻影装下。默认的 4000 m 会在城郭中间切一刀：
	# 幻影的近墙 1.9 km、远墙 6.9 km，后半个城本来该"先褪色再消失"
	# （见 mirage.gdshader 的 haze），结果被远裁剪面直接切掉，留下一道硬边。
	# 远处的淡出交给幻影自己的空气衰减，不交给裁剪面。
	_camera.far = 12000.0
	_camera.position = Vector3(0.0, eye_height, 0.0)
	add_child(_camera)
	# headless 测试里没有窗口系统，抓鼠标会报错
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clampf(
			_pitch - event.relative.y * mouse_sensitivity, -pitch_limit, pitch_limit
		)
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)


func _physics_process(delta: float) -> void:
	rotation.y = _yaw
	_camera.rotation.x = _pitch

	var wish := _wish_direction()
	var wants_sprint := Input.is_action_pressed("sprint") and wish.length() > 0.01
	var target_speed := sprint_speed if wants_sprint else walk_speed

	var desired := wish * target_speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.lerp(desired, clampf(acceleration * delta, 0.0, 1.0))
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	# 沙暴推力：不等于输入，是被风推着走的部分
	global_position += external_push * delta

	global_position += Vector3(velocity.x, 0.0, velocity.z) * delta
	_stick_to_sand(delta)
	_update_head_bob(delta, horizontal.length())


func _wish_direction() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input.length() < 0.01:
		return Vector3.ZERO
	# 只在水平面内移动：抬头不会让人飞出去
	var forward := -transform.basis.z
	var right := transform.basis.x
	forward.y = 0.0
	right.y = 0.0
	return (right * input.x + forward * -input.y).normalized()


func _stick_to_sand(delta: float) -> void:
	if world == null:
		return
	var ground := world.height_at(global_position.x, global_position.z)
	# 指数平滑：比直接赋值稳，遇陡坡也不会一帧跳上去
	var blend := 1.0 - exp(-20.0 * delta)
	global_position.y = lerpf(global_position.y, ground, blend)


func _update_head_bob(delta: float, speed: float) -> void:
	var moving := speed > 0.15
	if moving:
		_bob_phase += delta * speed * 2.1
	var bob := sin(_bob_phase * 2.0) * 0.035 if moving else 0.0
	var sway := cos(_bob_phase) * 0.018 if moving else 0.0
	_camera.position = Vector3(sway, eye_height + bob, 0.0)


func camera() -> Camera3D:
	return _camera


## 眼睛所在的世界坐标。
func eye_position() -> Vector3:
	return _camera.global_position


## 当前水平速度（米/秒），用于耗水与里程统计。
func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## 设定朝向。main 用它把玩家摆成面朝沙丘层叠的方向。
func set_yaw(value: float) -> void:
	_yaw = value
	rotation.y = _yaw
