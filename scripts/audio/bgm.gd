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

## Web 上把这首歌交给**浏览器自己的音频线程**播（sample 播放）。
##
## 桌面端不走这条路，也不该走：桌面有独立音频线程，混音不吃渲染的时间，
## Stream 播放原生循环、内存也小。**Web 不是这样**——4.7 的 web 音频驱动
## 除非开 Thread Support，混音就落在**主线程**上（`platform/web/audio_driver_web.cpp`
## 里 `_process_callback` 直接调 `audio_server_process`，一个 render quantum
## （128 帧）一次，靠 AudioWorklet 的 postMessage 往返喂数据）。走动时主线程一忙，
## 先喂不上，worklet 就丢掉那个 quantum：音乐当场表现为**被拖慢、发飘——
## 像磁带被人按住**。这不是"缓冲调大点"能根治的，是把音乐放在了竞争激烈的
## 那条线程上。
##
## sample 播放走的是浏览器原生的 AudioBufferSourceNode：解码在**加载时一次做完**
## （74 s 立体声 ≈ 26 MB 的 AudioBuffer），播放期间主线程一次都不插手，
## 结构上就不可能被渲染拖慢。代价是循环交给 JS 在 `ended` 事件里重启，
## 接缝比原生循环略明显——这首歌头尾本来就有静音和淡出，接得住（见
## docs/design/bgm.md）。
const WEB_SAMPLE_PLAYBACK := true


func _ready() -> void:
	var track := load(TRACK_PATH) as AudioStreamMP3
	if track == null:
		push_error("BGM 载不到：%s" % TRACK_PATH)
		return
	stream = track
	volume_db = VOLUME_DB
	if OS.has_feature("web") and WEB_SAMPLE_PLAYBACK:
		# 必须在 play() 之前：播放类型决定 play() 走哪条实例化路径。
		playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE
	play()


## 离开场景树就收声。不然被拆掉的场景会把活的播放实例留在混音器上，
## 录制工具和测试反复进出关卡时会一路攒着。
func _exit_tree() -> void:
	stop()
