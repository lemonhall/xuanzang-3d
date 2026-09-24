class_name Bgm
extends AudioStreamPlayer

## 背景音乐：《壁上观》(DeathNov Remix 剪辑版）。
##
## 就三件事：载入、循环、一直播。**它不掺任何状态**——不跟沙暴变调、
## 不跟渴度变响、不做总线滤波。氛围的底子该是稳的，调大小就改 VOLUME_DB。
##
## 循环开在 `.import` 的 `loop=true` 里，不在代码里改：那是这份素材自己的
## 属性，改共享资源（load() 拿的是缓存里那一份）会变成隐式的全局副作用。
##
## 它为什么接得住：剪辑版头尾本是硬切的，但切得巧——开头 0.4 s 是数字静音，
## 结尾是一条 -24.7 → -43.9 dB 的淡出，尾巴接回开头几乎听不出缝。
## 实测数据见 docs/design/bgm.md。

const TRACK_PATH := "res://assets/audio/bgm/bishangguan-deathnov-remix.mp3"

## 这首歌母带是做满的（峰值 0 dB、整曲均值 -9.9 dB，实测），推到满刻度会顶穿
## 后处理的高光，所以基准压 6 dB。
const VOLUME_DB := -6.0


func _ready() -> void:
	var track := load(TRACK_PATH) as AudioStreamMP3
	if track == null:
		push_error("BGM 载不到：%s" % TRACK_PATH)
		return
	stream = track
	volume_db = VOLUME_DB
	play()


## 离开场景树就收声。不然被拆掉的场景会把活的播放实例留在混音器上，
## 录制工具和测试反复进出关卡时会一路攒着。
func _exit_tree() -> void:
	stop()
