class_name Breath
extends AudioStreamPlayer

## 喘气。程序化合成，不带素材。
##
## 为什么不用一份录音：喘气的物理本质就是**带限噪声 + 一条包络**——气流过喉，
## 吸的时候声门开着（亮），呼的时候收紧（暗）。录音能好听，但它是一条死的波形：
## 频率、深浅、还有"越到后面越撑不住"，全都连不动。这几十行能连。
##
## 频率与幅度都取自模型层（`GameState.pant_rate` / `pant_depth`），
## 所以镜头里的呼吸起伏和耳朵里的喘气**是同一条曲线**——两处各写一条，
## 迟早会出现"镜头喘得厉害、声音很平静"这种露馅。
##
## 音量是**唯一**在这里定的事：越累越响（-20 dB → -12 dB），
## 眼睑合上的过程中一路退到静音——合眼就是意识退场，喘气该跟着走。

const MIX_RATE := 22050.0
const BUFFER_LENGTH := 0.3
const BASE_DB := -20.0
const STRAIN_DB := -12.0
## 一阶低通的两个截止点。吸气亮、呼气暗——**这一段是"像人"的关键**，
## 两个方向共用一个滤波就会变成风扇声。
const CUTOFF_INHALE := 0.34
const CUTOFF_EXHALE := 0.085

var _playback: AudioStreamGeneratorPlayback
var _rng := RandomNumberGenerator.new()
var _phase := 0.0
var _low := 0.0
var _low2 := 0.0


func _ready() -> void:
	_rng.seed = 20260924
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = BUFFER_LENGTH
	stream = gen
	volume_db = BASE_DB
	play()
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback


func _process(_delta: float) -> void:
	if _playback == null:
		return
	var fatigue := clampf(GameState.fatigue(), 0.0, 1.0)
	volume_db = lerpf(BASE_DB, STRAIN_DB, fatigue)
	if GameState.collapse_elapsed >= 0.0:
		# linear_to_db(0) 是 -inf，给一个地板，免得把混音器写成 NaN。
		var fade := maxf(1.0 - GameState.eye_close_at(GameState.collapse_elapsed), 0.0008)
		volume_db += linear_to_db(fade)
	_fill(_playback.get_frames_available())


func _fill(frames: int) -> void:
	if frames <= 0:
		return
	var rate := GameState.pant_rate(GameState.stamina, GameState.collapse_elapsed)
	for i in range(frames):
		var v := next_sample(rate / MIX_RATE)
		_playback.push_frame(Vector2(v, v))


## 走一个采样并推进相位。抽出来是为了**能被测试直接量**：
## headless 下没有声卡，听不到声音，但波形本身是可以断言的
## （峰值不削顶、有实际能量、包络在两个方向上不一样）。
func next_sample(delta_phase: float) -> float:
	var env := envelope_at(_phase)
	var cut := lerpf(CUTOFF_EXHALE, CUTOFF_INHALE, inhale_share(_phase))
	var noise := _rng.randf() * 2.0 - 1.0
	_low += (noise - _low) * cut
	_low2 += (_low - _low2) * cut
	# 一阶低通的输出幅度随截止点一起缩，得补回来——不然呼气那半句轻到听不见。
	var value := _low2 * (1.3 / sqrt(cut)) * env
	_phase = fposmod(_phase + delta_phase, 1.0)
	return clampf(value, -0.98, 0.98)


## 一次呼吸（一个周期）的气流包络。0..1 的相位 → 0..1 的响度。
##
##   0.00~0.34  吸气，起得慢
##   0.34~0.40  换气的那一瞬
##   0.40~0.90  **呼气——这一声才是"粗气"**，比吸气响
##   0.90~1.00  收干净（留一小段静，两次呼吸之间才有间隙）
static func envelope_at(phase: float) -> float:
	var p := fposmod(phase, 1.0)
	if p < 0.34:
		return 0.78 * sin(p / 0.34 * PI * 0.5)
	if p < 0.40:
		return 0.78
	if p < 0.90:
		return lerpf(1.0, 0.10, pow((p - 0.40) / 0.50, 0.75))
	return 0.0


## 相位落在"吸气"这一侧的程度 1..0。用它把低通的截止点从呼气的暗连到吸气的亮。
static func inhale_share(phase: float) -> float:
	var p := fposmod(phase, 1.0)
	if p < 0.36:
		return 1.0
	if p < 0.46:
		return 1.0 - (p - 0.36) / 0.10
	return 0.0


func _exit_tree() -> void:
	stop()
