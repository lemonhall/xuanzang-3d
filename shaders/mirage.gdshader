shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, fog_disabled;

// 海市蜃楼材质。
//
// 第一版做成了"均匀的白色半透明"，结果像一块亚克力：不透明的地方没有体积，
// 透明的地方又只是淡淡一层。真正让它"诡异"的是下面这几件事：
//
//   1. **连续折射** —— 水平位移是一个随高度缓慢变化的连续场，并且整场沿高度
//      往上漂。热空气把光路折断时就是这个样子：一座塔被切成几十段，每段各偏
//      一点。这是海市蜃楼最标志性的特征，也是"它不是实体"最直接的证据。
//
//      这一条被改过两次，两次的教训都写在这儿：
//        v1 每层整体偏移、按 `floor(TIME)` 到点重排 —— 读起来是**幻灯片**，
//           不是折射。整层瞬移没有中间态，眼睛一眼就认出"这是动画的离散帧"。
//        v2（本版）把位移换成二维噪声：纵向按高度取、横向按时间漂移。
//           同一时刻的相邻高度永远连续，随时间的演化也永远连续——
//           "丝滑"不是调出来的，是**用连续的量替换离散的量**换来的。
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
//
// 同一个着色器被三个 mesh 共用（城郭 / 像身 / 举身光），差别全靠 uniform：
// 城郭要扭得凶（它是"一片建筑"，切开也认得出），像身要几乎不扭（它是
// **唯一的人形**，切一刀就从"一个人"变成"一摞盘子"，认不出是弥勒）、
// 举身光要亮而且是环。见 mirage.gd 的三份材质。

uniform vec3 tint_top : source_color = vec3(0.34, 0.62, 0.93);
uniform vec3 tint_base : source_color = vec3(0.90, 0.75, 0.52);
uniform vec3 haze_tint : source_color = vec3(0.86, 0.68, 0.47);
uniform float strength : hint_range(0.0, 1.5) = 0.0;
uniform float low_fade : hint_range(0.0, 1.0) = 0.10;
uniform float high_fade : hint_range(0.5, 1.0) = 0.95;
uniform float shimmer : hint_range(0.0, 60.0) = 7.0;

// --- 折射场（替代原来的 layer_height / layer_shift 台阶）---
// shear 是位移峰值（米）；shear_scale 让不同材质各自缩放。
uniform float shear : hint_range(0.0, 240.0) = 90.0;
uniform float shear_scale : hint_range(0.0, 1.5) = 1.0;
// 折射场往上漂的速度（格/秒 的倒数口径，见 _refract）。
uniform float shear_rate : hint_range(0.0, 0.20) = 0.035;
// 竖直拉伸：热空气里越高的地方被拉得越开。0 = 关掉。
uniform float stretch : hint_range(0.0, 0.30) = 0.05;

// --- 观感缩放（三个 mesh 各调各的）---
// 1 = 该溶解就溶解；0 = 轮廓保持完整（像身用这个保住人形）。
uniform float dissolve_amount : hint_range(0.0, 1.0) = 1.0;
uniform float brightness : hint_range(0.0, 2.0) = 1.0;
uniform float alpha_scale : hint_range(0.0, 3.0) = 1.0;

// 逆光：太阳在幻影背后时，眼前的沙尘被照亮，幻影会被糊上一层光雾。
// 注意这只是**一层薄纱**（0.3 封顶）——糊过头，逆光的剪影就没了，
// 而剪影正是"一眼认出是尊像"的全部依据。
uniform vec3 sun_direction = vec3(0.5, 0.3, 0.0);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.84, 0.58);
uniform float veil : hint_range(0.0, 0.6) = 0.30;

uniform vec2 y_range = vec2(0.0, 1500.0);
uniform vec3 camera_pos = vec3(0.0);
// 空气衰减系数（1/m）。0.00032 → 1.4 km 处透射 64%、5.8 km 处 16%。
uniform float haze_density : hint_range(0.0, 0.002) = 0.00032;
// 全雾时剩下的比例：留一点，让它不至于彻底消失成"看不见"。
uniform float haze_floor : hint_range(0.0, 1.0) = 0.15;

varying vec3 v_local;
varying float v_h;
varying float v_dist;
// 折射场在这一点的取值，传给 fragment 让色带跟着位移一起走——
// 只挪几何、不挪明暗，看起来就是"贴图在滑动"；两样一起挪才是光路在动。
varying float v_warp;

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

// 折射场：以高度为纵轴、时间为横轴的 value noise。
// 第二个坐标用 `y * 0.0006` 掺一点进深，让同一高度在不同进深处不是一条死平的
// 带——否则整座城会像被一把看不见的刀切成"千层饼"，那正是要躲开的东西。
float _refract(float y, float phase) {
	return _vnoise(vec2(
		y * 0.0020 + phase * 0.017,
		phase + y * 0.0006 - TIME * shear_rate
	)) - 0.5;
}

void vertex() {
	// 溶解用的噪声必须取**位移之前**的坐标：位移每帧都在变，
	// 拿位移后的坐标会让溶解图案跟着一起抖，结构又糊掉。
	v_local = VERTEX;
	v_dist = distance((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, camera_pos);

	// 连续折射场：三个尺度叠起来。
	//   a —— 500 m 一块的大尺度：整座城缓缓左右游，像隔着一层热气看
	//   b —— 130 m 一块的中尺度：塔身被切成几十段，每段各偏一点（蜃景的签名）
	//   c ——  40 m 一块的小尺度：热抖动，贴边的地方发毛
	// 三者都是 y 的连续函数，所以相邻高度永远连得上：这就是"丝滑"的来源。
	float a = _refract(VERTEX.y, 0.0);
	float b = _refract(VERTEX.y, 137.0);
	float c = _refract(VERTEX.y, 311.0);
	v_warp = a + b * 0.45 + c * 0.16;
	float slip = v_warp * shear * shear_scale;
	VERTEX.x += slip;
	VERTEX.z += slip * 0.55;

	// 竖直拉伸：越高的地方被拉得越开（热空气里"上面那截被抻长了"）。
	// 以沙面（本地 y=0）为支点，所以底座不会离地。
	VERTEX.y *= 1.0 + (b * 0.6 + c * 0.25) * stretch * shear_scale * 2.0;

	// 层内再叠一点连续扭动，避免看起来像整齐的切片
	VERTEX.x += sin(TIME * 0.55 + VERTEX.y * 0.010) * shimmer * shear_scale;
	VERTEX.z += cos(TIME * 0.41 + VERTEX.y * 0.007) * shimmer * 0.6 * shear_scale;

	v_h = clamp((VERTEX.y - y_range.x) / max(y_range.y - y_range.x, 0.001), 0.0, 1.0);
}

void fragment() {
	// 下缘不着地、上缘溶进天空：两条都是"它不是实体"的证据。
	// 下缘化开：幻影的底卡在沙脊线上，一条干净的硬边会像贴纸。
	// 上缘**不做高度淡出**：归一化高度同时管着两座不同高的东西（主塔 1501 m、
	// 弥勒 1177 m），任何一条按高度切的线都会把其中一个的顶切掉。
	// "看不到顶"交给空气衰减（越远越淡）：主塔的上半截就是靠它溶进天空的。
	// 注意**不要再把"头顶出画"当成手段**——上一版拿它切弥勒的头，
	// 结果是一尊没有头的像（见 mirage.gd 文件头）。
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
	// dissolve_amount = 0 时轮廓保持完整：像身必须走这一条，
	// 否则一团 400 m 的噪声会在像身上啃出几个洞，人形当场就没了。
	dissolve = mix(1.0, dissolve, dissolve_amount);

	// 竖直色带：像被沙尘一层层滤过。
	// 相位里带上 v_warp（本点的折射量），色带就跟着几何一起漂——
	// 几何动、明暗不动，看起来是"贴图在滑动"；两样一起动才是光路在抖。
	float streak = 0.85 + 0.15 * sin(v_local.y * 0.03 + TIME * 1.3 + v_warp * 6.0);

	// 逆光薄纱：视线越接近太阳，幻影前面那层被照亮的沙尘越亮。
	vec3 to_sun = normalize((VIEW_MATRIX * vec4(sun_direction, 0.0)).xyz);
	float back = pow(clamp(dot(normalize(VIEW), to_sun), 0.0, 1.0), 6.0);
	col = mix(col, sun_tint, back * veil);

	// 空气衰减：近的实、远的淡，5.8 km 外的远墙几乎只剩沙色
	float haze = 1.0 - exp(-v_dist * haze_density);

	ALBEDO = mix(col * brightness, haze_tint, haze * 0.85);
	ALPHA = clamp(
		band * strength * alpha_scale * streak * (0.20 + 0.80 * dissolve), 0.0, 1.0
	) * mix(1.0, haze_floor, haze);
}
