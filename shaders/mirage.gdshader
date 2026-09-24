shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, fog_disabled;

// 海市蜃楼材质。
//
// 第一版做成了"均匀的白色半透明"，结果像一块亚克力：不透明的地方没有体积，
// 透明的地方又只是淡淡一层。真正让它"诡异"的是下面这几件事：
//
//   1. 分层错位 —— 每 layer_height 米一层整体水平错开，且随时间缓慢重排。
//      热空气把光路折断时就是这个样子：一座塔被切成几十段，每段各偏一点。
//      这是海市蜃楼最标志性的特征，也是"它不是实体"最直接的证据。
//   2. 冷暖渐变 —— 底部被沙尘染成暖褐、顶部是天空的冷青。
//      单一颜色无论深浅都会显得像塑料；有色彩走向才像"滤过空气的光"。
//   3. 朝向明暗 —— unshaded 也能用 NORMAL 和 VIEW 的夹角给一点体积暗示，
//      正对镜头的面亮、掠过视线的地方暗，塔才有"转过去"的感觉。
//   4. **空间溶解** —— 轮廓被一个连续的空间噪声啃掉，而不是一条干净的边。
//
// 第 4 条踩过一次大坑，记在这儿：上一版拿 UV 去采样噪声，而这个 mesh 是
// 三千多个基本体合并出来的，**每个盒子的每个面 UV 都是 0..1**。于是"溶解"
// 退化成了"每个小面各随机一次透明度"——整座城看上去就是一团没有结构、
// 均匀发白的雾。这正是"像亚克力""看不清"的根因：不是噪声太重，
// 是噪声根本没有空间连续性。现在一律用**顶点的局部坐标**做噪声域，
// 同一个位置永远得到同一个值，结构才留得住。
//
// 空气衰减是自己算的（fog_disabled 把 Godot 的雾关掉了，因为幻影必须能
// 站在 1.4 km 外还看得见）。距离从这里来：camera_pos 由 main.gd 每帧写入，
// 距离近的地方实、远的地方先褪色再消失——5.8 km 外的城墙几乎化进沙尘，
// 于是"这座城有多深"也就不可能量出来了。

uniform vec3 tint_top : source_color = vec3(0.34, 0.62, 0.93);
uniform vec3 tint_base : source_color = vec3(0.90, 0.75, 0.52);
uniform vec3 haze_tint : source_color = vec3(0.86, 0.68, 0.47);
uniform float strength : hint_range(0.0, 1.5) = 0.0;
uniform float low_fade : hint_range(0.0, 1.0) = 0.10;
uniform float high_fade : hint_range(0.5, 1.0) = 0.95;
uniform float shimmer : hint_range(0.0, 60.0) = 7.0;
uniform float layer_height : hint_range(4.0, 200.0) = 70.0;
uniform float layer_shift : hint_range(0.0, 240.0) = 90.0;
uniform vec2 y_range = vec2(0.0, 1500.0);
uniform vec3 camera_pos = vec3(0.0);
// 空气衰减系数（1/m）。0.00032 → 1.4 km 处透射 64%、5.8 km 处 16%。
uniform float haze_density : hint_range(0.0, 0.002) = 0.00032;
// 全雾时剩下的比例：留一点，让它不至于彻底消失成"看不见"。
uniform float haze_floor : hint_range(0.0, 1.0) = 0.15;

varying vec3 v_local;
varying float v_h;
varying float v_dist;

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

void vertex() {
	// 溶解用的噪声必须取**位移之前**的坐标：位移每帧都在变，
	// 拿位移后的坐标会让溶解图案跟着一起抖，结构又糊掉。
	v_local = VERTEX;
	v_dist = distance((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, camera_pos);

	// 分层错位：整座城被切成一叠薄片，每片各自横向偏移。
	// 时间取整后重排，所以它不是"流动"，而是每隔一会儿就换一种断法——
	// 这种不连续比平滑扭曲更像光路本身在抖。
	float band = floor(VERTEX.y / layer_height);
	float tick = floor(TIME * 0.45 + band * 0.37);
	// 不是每层都偏：只有三分之一的层大幅断裂，其余几乎不动。
	// 均匀错位会读成"千层饼"，偶尔断一次才像光路真的折了一下。
	float rarity = _hash(vec2(band * 3.7, tick * 1.3));
	float magnitude = (rarity > 0.62) ? layer_shift : layer_shift * 0.18;
	float slip = (_hash(vec2(band, tick + 17.0)) - 0.5) * magnitude;
	VERTEX.x += slip;
	VERTEX.z += slip * 0.55;

	// 层内再叠一点连续扭动，避免看起来像整齐的切片
	VERTEX.x += sin(TIME * 0.55 + VERTEX.y * 0.010) * shimmer;
	VERTEX.z += cos(TIME * 0.41 + VERTEX.y * 0.007) * shimmer * 0.6;

	v_h = clamp((VERTEX.y - y_range.x) / max(y_range.y - y_range.x, 0.001), 0.0, 1.0);
}

void fragment() {
	// 下缘不着地、上缘溶进天空：两条都是"它不是实体"的证据。
	// 下缘化开：幻影的底卡在沙脊线上，一条干净的硬边会像贴纸。
	// 上缘**不做高度淡出**：归一化高度同时管着两座不同高的东西（主塔 1501 m、
	// 弥勒 1300 m），任何一条按高度切的线都会把其中一个的顶切掉。
	// "看不到顶"交给两件更硬的事——头顶出画（水平前视时像头就在画面之外）
	// 和空气衰减（越远越淡）。
	float band = smoothstep(0.0, low_fade, v_h);

	// 正对镜头的地方亮，掠射的地方暗——给一个"它是个立体的东西"的暗示
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	// 冷暖过渡压在真正看得见的那一段里：城墙在总高的 0.27 处、城门楼 0.41、
	// 主塔塔顶 1.0。这样"下暖上冷"是在城墙到塔顶之间走完的，
	// 主塔上半截本身就带天空色——它就是在溶化。
	vec3 tint = mix(tint_base, tint_top, smoothstep(0.10, 0.55, v_h));
	vec3 col = tint * (0.58 + 0.42 * facing);

	// 空间溶解：用局部坐标，同一个位置永远同一个值，所以结构的边界能留住。
	// 尺度 0.0025 → 约 400 m 一块，正好是"几千个部件的轮廓开始化掉"的尺度。
	vec2 domain = vec2(v_local.x + v_local.z * 1.7, v_local.y * 1.3 + v_local.z * 0.4);
	float n = _fbm(domain * 0.0025 - vec2(0.0, TIME * 0.06));
	float dissolve = smoothstep(0.30, 0.80, n);

	// 竖直色带：像被沙尘一层层滤过
	float streak = 0.85 + 0.15 * sin(v_local.y * 0.03 + TIME * 1.3);

	// 空气衰减：近的实、远的淡，5.8 km 外的远墙几乎只剩沙色
	float haze = 1.0 - exp(-v_dist * haze_density);

	ALBEDO = mix(col, haze_tint, haze * 0.85);
	ALPHA = clamp(
		band * strength * streak * (0.20 + 0.80 * dissolve), 0.0, 1.0
	) * mix(1.0, haze_floor, haze);
}
