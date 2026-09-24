extends Node

## 输入映射在代码里注册。
##
## 不写进 project.godot 是有意的：`InputEventKey` 的序列化格式很脆
## （keycode / physical_keycode / location / unicode 各版本都动过），
## 手写错一个字段整个项目都起不来。这里用 physical_keycode，
## 顺便也不受输入法布局影响。

const BINDINGS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"interact": [KEY_E, KEY_ENTER],
	"chant": [KEY_Q],
	"rest": [KEY_R],
}


func _ready() -> void:
	for action: String in BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for key: int in BINDINGS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			if not InputMap.action_has_event(action, event):
				InputMap.action_add_event(action, event)
