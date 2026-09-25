class_name Wind
extends AudioStreamPlayer

## 风声。程序化合成，不带素材——和 breath.gd 是同一路数。
##
## 为什么要加它：整条片子里"大风吹"原来只有画面（沙带在跑、人走不直、镜头被吹歪），
## **耳朵里是空的**。风声是吹在观众身上的那一半，缺了它，风只发生在屏幕里面。
##
## 它读的是**同一个数**：`GameState.wind_force`（沙暴强度 × 阵风包络）——
## 推人、歪镜头、沙子浓淡、脚下沙纹的深浅，加上这一层风声，五样共用一个包络。
## 这也是这一关唯一让它"有状态"的地方：从"就一首 BGM"那条需求出发，
## 音乐仍然一个字都不掺（见 docs/design/bgm.md），风是另一条独立的层。
##
## 音色也是物理的，不是把同一个声音调大调小：
##   * **无风**：几乎静音（只剩一点空气的底噪）；
##   * **起风**：一个低频的"呼——"，像远处有东西在滚；
##   * **压顶**：高频的沙沙声压上来（沙粒打在空气里、打在衣服上），
##     而且**中频的抖动更密**。
## 所以风越大，不只是响，是**频谱整体往上抬**——低通的截止点跟着 force 走。

const MIX_RATE := 22050.0
const BUFFER_LENGTH := 0.4
## 混音基准。风声要压在 BGM（-6 dB）下面、和喘气（-20 ~ -12 dB）交叉，
## 所以取 -12 dB：大风的峰值大约和喘气的高点同量级，谁都不盖谁。
const BASE_DB := -12.0
## 低通的截止点（一阶系数，0..1，越小越暗）。无风时几乎只剩低频的"底噪"，
## 满风时抬到 0.42——沙粒的高频就在这一段里。
const CUT_CALM := 0.020
const CUT_GALE := 0.42
## 音量地板的线性系数。linear_to_db(0) 是 -inf，会把混音器写成 NaN。
const FLOOR := 0.0008

var _playback: AudioStreamGeneratorPlayback
var _rng := RandomNumberGenerator.new()
var _phase := 0.0
var _low := 0.0
var _low2 := 0.0
var _hiss := 0.0


func _ready() -> void:
	_rng.seed = 20260925
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = BUFFER_LENGTH
	stream = gen
	volume_db = BASE_DB
	if OS.has_feature("web"):
		# 和喘气同一条规矩，理由写在 breath.gd：生成器只能 Stream，
		# 而 web 的混音在主线程上。
		playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	play()
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback


func _process(_delta: float) -> void:
	if _playback == null:
		return
	volume_db = BASE_DB + linear_to_db(maxf(fade_level(), FLOOR))
	_fill(_playback.get_frames_available())


## 这一帧该有多响（0..1 的线性系数，最后转 dB）。眼睑合上时一路退到静音——
## 和喘气同一条规矩：合眼就是意识退场，风声也该跟着走。
func fade_level() -> float:
	if GameState.collapse_elapsed < 0.0:
		return 1.0
	return maxf(1.0 - GameState.eye_close_at(GameState.collapse_elapsed), 0.0)


func _fill(frames: int) -> void:
	if frames <= 0:
		return
	# 相位推进和"风声本身"无关（它是噪声），但保留一个相位是为了让低频起伏
	# 有个共同的时基——两声道将来要分开用时，这里就是那个分叉点。
	var step := 1.0 / MIX_RATE
	for i in range(frames):
		var v := next_sample(step)
		_playback.push_frame(Vector2(v, v))


## 走一个采样。抽出来是**为了能被测试直接量**：headless 下没有声卡，
## 听不到声音，但波形本身可以断言（不削顶、有能量、风越大频谱越亮）。
func next_sample(delta_phase: float) -> float:
	var force := clampf(GameState.wind_force, 0.0, 1.0)
	var cut := lerpf(CUT_CALM, CUT_GALE, pow(force, 0.7))
	var noise := _rng.randf() * 2.0 - 1.0
	# 两层：_low 是远处那一团滚动的低频，_hiss 是沙粒打在空气里的高频。
	_low += (noise - _low) * cut
	_low2 += (_low - _low2) * cut
	# 高频那一层单独走一个更亮的低通，并且**只在大风时抬起来**。
	_hiss += (noise - _hiss) * minf(cut * 2.6, 0.9)
	# 一阶低通的输出幅度随截止点缩，补回来（同 breath.gd）。
	var body := _low2 * (1.5 / sqrt(maxf(cut, 0.001)))
	var spray := _hiss * (0.9 * force * force)
	# 电平：无风几乎静音（0.02），满风到 1.0，中间用 1.3 次方压一压，
	# 让"起风"这一段是慢慢浮出来的，而不是一到 0.1 就吵起来。
	var level := 0.02 + 0.98 * pow(force, 1.3)
	# 极慢的起伏：风本身已经在抖了（阵风包络），这里只加一点点"呼吸"，
	# 免得长时间听下来像一条没有生命的白噪。
	var sway := 0.88 + 0.12 * sin(_phase * TAU)
	_phase = fposmod(_phase + delta_phase * 0.07, 1.0)
	return clampf((body + spray) * level * sway, -0.98, 0.98)


func _exit_tree() -> void:
	stop()
