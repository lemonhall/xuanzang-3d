shader_type canvas_item;
render_mode unshaded;

// 全屏后处理：这一层是"卡通感 → 照片感"的关键。
//
// 单靠调整材质和灯光很难摆脱塑料味，因为问题不在颜色而在**光的结构**：
//   1. 暗角 —— 把注意力压到画面中心，四周沉下去
//   2. 冷暖分离 —— 暗部推向冷蓝（天空的散射），亮部推向暖黄（直射日光）
//   3. 颗粒 —— 一点点噪声破坏纯色块，数字感立刻减弱
// 这三样加起来，画面才开始像"被相机拍到"而不是"被引擎渲染出来"。

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

uniform float vignette_strength : hint_range(0.0, 2.0) = 0.9;
uniform float vignette_softness : hint_range(0.1, 3.0) = 1.5;
uniform float grain_amount : hint_range(0.0, 0.2) = 0.035;
uniform float contrast : hint_range(0.5, 2.0) = 1.14;
uniform float warmth : hint_range(-0.5, 0.5) = 0.07;
uniform vec3 shadow_tint : source_color = vec3(0.78, 0.84, 1.0);

// --- 风里的沙（全画面的一层）---
// 这一层是"整个场景一直飘着带状沙尘"的那一层：沙丘、天空、幻影它都盖。
uniform float dust_amount : hint_range(0.0, 1.0) = 0.42;
uniform vec3 dust_tint : source_color = vec3(1.0, 0.86, 0.62);
// 一屏几条带 (dust_bands) 和带的横向拉伸 (dust_stretch)。
uniform float dust_bands : hint_range(1.0, 16.0) = 5.0;
uniform float dust_stretch : hint_range(0.2, 6.0) = 1.5;
// 把带掰弯的力度。**调到 0 就退回旧版那种直尺一样的效果**——这个数是
// "不笔直"的全部来源，别再拿它当美工旋钮随手关掉。
uniform float dust_warp : hint_range(0.0, 3.0) = 1.2;
uniform float dust_gain : hint_range(0.0, 1.5) = 0.42;
uniform vec2 wind_direction = vec2(1.0, 0.35);
uniform vec3 sun_direction_world = vec3(0.5, 0.3, 0.0);
// 相机自己的三个基向量 + 视野的半张角正切。每帧由 PostProcess.set_view 写入。
// 用基向量而不是自己算 yaw/pitch 的三角函数：省掉一次左右手约定的踩坑。
uniform vec3 cam_right = vec3(1.0, 0.0, 0.0);
uniform vec3 cam_up = vec3(0.0, 1.0, 0.0);
uniform vec3 cam_forward = vec3(0.0, 0.0, -1.0);
uniform vec2 tan_half_fov = vec2(1.24, 0.67);

// --- 眼睑 ---
// 倒下之后合上眼皮。**不是淡出**：淡出是从四周往中间糊，而眼皮是上下两道
// 从中间合拢，最后剩下一条缝（缝里还看得见那尊大佛），再全黑。
// 缝在**屏幕空间**里是横的——眼睛长在头上，画面就是眼睛看到的，
// 所以镜头侧翻时这条缝要跟着一起斜（这是对的，不是 bug）。
uniform float lid_close : hint_range(0.0, 1.0) = 0.0;
// 缝沿的软硬（屏幕高度比例）。0.018 在 900 px 上是 16 px——
// 够软，不至于像一条画上去的黑边，也不至于糊成一坨。
uniform float lid_softness : hint_range(0.002, 0.2) = 0.018;
// 合上之后**不是纯黑**：光透过眼皮，眼下是一片暗红。
// 纯黑是"关机"，暗红才是"闭眼"。
uniform vec3 lid_color : source_color = vec3(0.16, 0.045, 0.030);

float _rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

float _hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float _vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(_hash(i), _hash(i + vec2(1.0, 0.0)), f.x),
		mix(_hash(i + vec2(0.0, 1.0)), _hash(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

// 八度逐层旋转的 fbm。不旋转时四个八度共用同一套格点，"沙云"会先露出方格、
// 再退化成一块块拼接的方斑（这条是从 dust_sky.gdshader 里搬过来的教训）。
float _fbm(vec2 p) {
	mat2 rot = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * _vnoise(p);
		p = rot * p * 2.07;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;

	col = (col - 0.5) * contrast + 0.5;

	// 冷暖分离。真实场景里阴影从来不是"更暗的日光"，而是被天空的冷光填过，
	// 这一步就是在补那件被实时渲染通常省掉的事。
	float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
	float t = smoothstep(0.12, 0.72, luma);
	vec3 cooled = col * shadow_tint;
	vec3 warmed = col * vec3(1.0 + warmth, 1.0, 1.0 - warmth * 1.6);
	col = mix(cooled, warmed, t);

	// --- 风里的沙：整个画面都飘着的一层 ---
	//
	// 坐标系是这一层的关键。贴在 SCREEN_UV 上最省事，但转头时沙会跟着转——
	// 那是镜头脏了，不是空气脏了。这里把每个像素还原成**世界方向**，在
	// (方位角, 仰角) 里取样：沙长在空气里，转头时它该待在原处，从画面里滑过去。
	//
	// 这个方向沙尘和"闭眼透光"都要用，所以在外面算一次。
	vec2 ndc = vec2(SCREEN_UV.x * 2.0 - 1.0, 1.0 - SCREEN_UV.y * 2.0);
	vec3 dir = normalize(
		cam_right * (ndc.x * tan_half_fov.x)
		+ cam_up * (ndc.y * tan_half_fov.y)
		+ cam_forward
	);
	if (dust_amount > 0.001) {
		float elev = asin(clamp(dir.y, -1.0, 1.0));
		// 方位角当 x、仰角当 y。x 上拉伸、y 上压实 → 一条条横着走的带
		vec2 uv = vec2(atan(dir.x, dir.z) * dust_stretch, elev * dust_bands);
		// 把带掰弯。低频慢噪声推着相位上下起伏，S 形就是从这儿来的
		float wob = _fbm(vec2(uv.x * 0.5 + TIME * 0.010, TIME * 0.006)) - 0.5;
		uv.y += wob * dust_warp;
		// 漂移：顺风走 + 缓缓上浮。两个速度不一样，才有层次。
		// "顺风"那一侧的符号取自风向量本身：风反过来沙就反着淌，
		// 而不是在这儿写死一个正号。
		vec2 wind = normalize(wind_direction);
		uv += vec2(TIME * 0.035 * sign(wind.x), -TIME * 0.045);
		float fine = _fbm(uv);
		float broad = _fbm(uv * 0.45 + vec2(TIME * 0.006, 0.0));
		// 取噪声的高处当"沙丝"，平方一下让带之间留出干净的空隙
		float band = clamp((fine - 0.46) * 1.7 + (broad - 0.46) * 0.9, 0.0, 1.0);
		float haze = band * band * dust_amount;
		// 逆着太阳看时沙被点着：越接近太阳方向越亮。这一条和天空、幻影的
		// 逆光同源——同一束光，照在城上、照在沙上，不该是两套颜色。
		float glow = pow(clamp(dot(dir, normalize(sun_direction_world)), 0.0, 1.0), 3.0);
		col = mix(col, dust_tint, haze * 0.13 * dust_gain);
		col += dust_tint * haze * (0.05 + 0.42 * glow) * dust_gain;
	}

	// 暗角
	vec2 d = SCREEN_UV - 0.5;
	float v = 1.0 - vignette_strength * pow(clamp(length(d) * 1.42, 0.0, 1.0), vignette_softness);
	col *= clamp(v, 0.0, 1.0);

	// 颗粒：**按像素取，不按 UV 取**。
	//
	// 旧版是 `_rand(SCREEN_UV * 2048.0 + ...)`：格距 = 2048 格摊到 1600 像素上
	// ≈ 1.28 像素，正好和像素网格打架，明亮平整的沙面上会浮出一排排竖向
	// 摩尔纹。摩尔纹是"图案"不是"颗粒"——一旦成了图案，眼睛立刻认得出是假的，
	// 而它偏偏只出现在最亮最平的那片沙上（2026-09-24 抓到的，与沙尘无关）。
	//
	// 换成 FRAGCOORD（像素坐标）：一格一像素，与分辨率无关，不可能出摩尔纹。
	// 时间上按 1/24 秒跳一次，像胶片颗粒那样闪，而不是每帧都换（后者会让人晕）。
	float g = _rand(FRAGCOORD.xy + floor(TIME * 24.0) * 137.0) - 0.5;
	col += g * grain_amount;

	// --- 眼睑：最后一道，压在颗粒之上 ---
	if (lid_close > 0.001) {
		// 两条边各走 0.5（屏幕高度的一半），所以 lid_close=1 时正好在屏幕中线合拢；
		// 而 lid_close 刚离开 0 时，缝恰好是整屏——**起点接得住，不会闪出一条黑边**。
		//
		// 上眼皮快、下眼皮慢（真人就是这样），靠幂次把两条边的节奏错开。
		// 注意不能让两条边交叉：0.5*p^0.80 + 0.5*p^1.35 永远小于 1。
		float top_edge = 0.5 * pow(lid_close, 0.80);
		float bottom_edge = 1.0 - 0.5 * pow(lid_close, 1.35);
		float upper = smoothstep(top_edge - lid_softness, top_edge + lid_softness, SCREEN_UV.y);
		float lower = 1.0 - smoothstep(
			bottom_edge - lid_softness, bottom_edge + lid_softness, SCREEN_UV.y
		);
		float open_mask = upper * lower;
		// 缝沿的暗影：眼皮是**有厚度**的，光在缝沿会掉下去，少了这一道，
		// 缝就只是一条几何切边。它随 lid_close 渐入，不然合眼的第一帧
		// 会在画面上下各闪一条灰边。
		col *= mix(1.0, mix(0.55, 1.0, open_mask), smoothstep(0.0, 0.15, lid_close));
		// 光透过眼皮：太阳那一侧透出来一团暗红——闭着眼也知道太阳在哪边。
		// 这正是"闭眼"和"淡出"的最后一点差别。
		float through = pow(clamp(dot(dir, normalize(sun_direction_world)), 0.0, 1.0), 6.0);
		col = mix(lid_color * (1.0 + 1.8 * through), col, open_mask);
	}

	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
