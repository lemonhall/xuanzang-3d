extends Node

## 影片录制用的入口场景。
##
## 和 capture.gd 的区别：它不截图、也不退出——画面交给 `--write-movie` 去录，
## 录制长度交给 `--quit-after`。它只负责把场景准备好：让沙暴起来、体力见底，
## 这样幻影是以"最该出现"的状态被录下来，而不是开局那种淡到几乎看不见。
##
##   godot --path . --write-movie D:\out.avi --quit-after 450 --fixed-fps 30 tools/record.tscn

var _main: Node
var _elapsed := 0.0


func _ready() -> void:
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	_main = main_scene.instantiate()
	add_child(_main)

	# 起手就把沙暴推到"起风"阶段，并把体力压低：幻影由"累 + 沙暴"共同驱动，
	# 两样都上来，它才会以接近最实的状态出现。
	var storm: Node = _main.get("storm")
	if storm != null:
		storm.set("_phase", 1)
		storm.set("_timer", 6.0)
	GameState.stamina = 0.22


func _process(delta: float) -> void:
	_elapsed += delta
	# 想拍"走近也走不近"，就让玩家一直往前走。录制十几秒足够看出
	# 幻影跟着后退、两者距离不变。
	var player: Node3D = _main.get("player")
	if player != null:
		player.global_position.x += player.walk_speed * delta
