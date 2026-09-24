shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, fog_disabled;

// 举身光：弥勒身后那圈光。
//
// 【为什么形状要重做一遍】
//
// 上一版是：一根 TorusMesh 管子（管壁 = 外径 − 内径 = 0.07h）+ 28 根
// 等长等宽的方条当光焰。1 倍时那根管子只有 76 m 粗、方条是几个像素，
// 看着还行；**4 倍之后管壁变成 302 m 宽的一条亮带**，方条变成一圈整齐的
// 齿——截图里就是"一圈发光的塑料管套着一圈齿轮"。需求方的话是
// 「那个光环有点不自然」。
//
// 这不是强度没调好，是**形状本身机械**：管子有明确的内缘和外缘（两条硬边），
// 28 根方条等长等宽等间隔（眼睛一眼数得出周期）。再怎么调 softness，
// 那两条边和那个周期都还在。所以这一版改成"光的画法"：
//
//   几何 —— 一枚**平的圆环面**（内径 = 洞，外径 = 光焰尖）。中间的洞原样
//           保留（像身要从洞里透出来，这是硬约束）；外缘不参与成形，
//           整圈形状全部交给 fragment 画，几何只提供"光能落在哪里"。
//
//   径向 —— 亮度是到环心线的**高斯**（σ = ring_sigma），不是一条带。
//           内缘、外缘都是它自己淡到 0 的，所以任何角度下都找不到一条硬边。
//           "环有多粗"从此是 ring_sigma 一个数，跟几何无关。
//
//   光焰 —— 改成**角度上的周期噪声**：每一根的亮度都不同，而往外的光雾尾巴
//           越远越淡，于是"亮度"直接决定了它伸出去多长——长的亮、短的暗，
//           不需要另外画形状。周期噪声（`_ring_noise`）首尾相接，
//           环上不会有接缝。
//
//   溶解 —— 和城郭、像身用同一条 fbm（域尺度 0.0025）。一圈光在沙尘里
//           和一座城一起被啃出缺口，而不是一张贴在沙暴上的贴图。
//
//   HDR —— 颜色越过 1.0，靠 glow 起辉。光是漏出去的，不是画上去的。
//
// 最后仍然是加色（blend_add）：光只能往画面里加亮度，不能遮挡。
// 上一版把光做成实心半透明白盘，和像身叠成"一坨带刺的棉花糖"，
// 那才是"看不出是弥勒"的根因——这一条别再改回去。

uniform vec3 halo_color : source_color = vec3(1.35, 1.10, 0.74);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.82, 0.55);
uniform vec3 sun_direction = vec3(0.5, 0.3, 0.0);
// 0..1：越接近 1，整圈光越亮（由 mirage.gd 按 presence 写）
uniform float strength : hint_range(0.0, 3.0) = 0.0;
uniform float intensity : hint_range(0.0, 3.0) = 1.20;

// --- 环的径向标尺（米）---
// 环面躺在 mesh 本地坐标的 YZ 平面上（轴顺着 X），所以半径都在 YZ 里量。
// 这几个数由 mirage.gd 按**当前倍率**写进来——4 倍时它们全是 1 倍时的 4 倍，
// 环才不会在放大之后变成一根细线。写完就不该再手动改。
uniform vec2 ring_center = vec2(0.0); // 环心（本地 YZ）
uniform float ring_inner = 1.0;       // 洞的边缘：几何从这里开始
uniform float ring_core = 1.0;        // 环心线：最亮的一圈
uniform float ring_tip = 1.0;         // 光焰尖：光的尽头
uniform float ring_sigma = 1.0;       // 主亮带的标准差——"环有多粗"

// --- 光焰 ---
// gain    0 = 一圈均匀的光，1 = 长短不齐
// sectors 一圈上有多少簇（不是"多少根"：噪声是连续的，簇之间是渐变）
uniform float flame_gain : hint_range(0.0, 2.0) = 0.90;
uniform float flame_sectors = 17.0;
// 光雾尾巴的峰值与衰减指数：尾巴越短越"一圈光带"，越长越"一片光雾"
uniform float flame_veil : hint_range(0.0, 1.0) = 0.34;
uniform float flame_power : hint_range(0.5, 6.0) = 2.2;

// 空间溶解要压着来：它是光，啃得太碎就变成一圈噪点
uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.30;
// 呼吸（不是呼吸灯，是"热空气里的光在抖"）
uniform float flicker : hint_range(0.0, 1.0) = 0.30;
// 环面是平的，正对镜头时最亮、掠射时最暗。**只给一点点**：
// 它是光不是镜面，仰头看时不该整圈暗下去。
uniform float tilt_shade : hint_range(0.0, 1.0) = 0.15;

uniform vec3 camera_pos = vec3(0.0);
uniform float haze_density : hint_range(0.0, 0.002) = 0.00022;
uniform float haze_floor : hint_range(0.0, 1.0) = 0.40;
// 最小的折射：光背跟着热空气飘，但幅度必须小——它是像身"还认得出"的框
uniform float shear : hint_range(0.0, 60.0) = 14.0;
uniform float shear_rate : hint_range(0.0, 0.20) = 0.035;

varying vec3 v_local;
// 到环心线的径向距离（米，**位移之前**量的）与环面上的角
varying float v_radius;
varying float v_angle;
varying float v_dist;
varying float v_facing;
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

// 一维**周期性** value noise：在环上取样，`u` 是 0..1 的环形坐标。
// 必须首尾相接——否则环上会出现一条接缝，而且那条接缝会跟着时间走，
// 比"整齐"更难看。
float _ring_noise(float u, float sectors, float phase) {
	float x = u * sectors + phase;
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	float a = _hash(vec2(mod(i, sectors), 0.0));
	float b = _hash(vec2(mod(i + 1.0, sectors), 0.0));
	return mix(a, b, f);
}

void vertex() {
	// 噪声域取**位移之前**的坐标：位移每帧都在变，拿位移后的坐标会让
	// 溶解图案跟着一起抖，结构又糊掉（这条和城郭那边是同一个教训）。
	v_local = VERTEX;

	vec2 d = VERTEX.yz - ring_center;
	v_radius = length(d);
	// -PI..PI，转成 0..1 的环形坐标
	v_angle = atan(d.y, d.x);

	// 折射：**二维**的噪声场，不是"按高度分层"。
	//
	// 上一版这里只喂 VERTEX.y 一个坐标——同一高度的所有顶点拿到同一个数，
	// 于是整圈光**刚性平移**，看起来像一块被推着走的表盘。这一版场在环面上
	// 二维连续，相邻的点各自偏一点，轮廓才是"化开"而不是"滑动"。
	float n1 = _vnoise(d * 0.0016 + vec2(0.0, -TIME * 0.021)) - 0.5;
	float n2 = _vnoise(d * 0.0042 + vec2(11.0, -TIME * 0.047)) - 0.5;
	float n3 = _vnoise(d * 0.0091 + vec2(61.0, -TIME * 0.083)) - 0.5;
	v_warp = n1 + n2 * 0.45 + n3 * 0.16;

	VERTEX.x += v_warp * shear;
	// 环面上也飘一点：光背的轮廓本身要抖，不然它还是一根钢丝。
	// 幅度刻意小于 shear——径向抖大了，环就变成一条毛边。
	VERTEX.yz += normalize(d + vec2(0.0001)) * (v_warp * shear * 0.35);

	// `VIEW` 是 **fragment 专属**的内建量，vertex 里取不到（取到就是编译报错
	// "Unknown identifier in expression: 'VIEW'"）。所以视线方向自己算：
	// 相机位置是 main.gd 每帧写进来的 uniform，法线用 MODEL_MATRIX 提到世界空间。
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 to_eye = normalize(camera_pos - world_pos);
	vec3 world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_dist = distance(world_pos, camera_pos);
	v_facing = abs(dot(world_normal, to_eye));
}

void fragment() {
	float haze = 1.0 - exp(-v_dist * haze_density);

	// --- 径向剖面：这一版"不自然"的主药 ---
	//
	// 角度上的噪声：一次取数，**两处用**——光焰的亮度，和亮带的粗细。
	// 两处共用同一个数是有道理的：火舌长出来的地方，底下的光也厚一点。
	float u = v_angle / TAU + 0.5;
	float ray = _ring_noise(u, flame_sectors, TIME * 0.010);
	ray += _ring_noise(u, flame_sectors * 2.7, TIME * -0.017 + 13.0) * 0.45;

	// 亮带：到环心线的高斯。σ（ring_sigma）就是"环有多粗"，
	// 内缘外缘都由它自己淡到 0。
	//
	// 粗细**跟着角度变**（0.65~1.4 倍）：一条处处一样粗的环，无论多软，
	// 读出来还是"一个圈"。有起伏才像一团火在烧。下界大于 0，
	// 所以环不会断成一节一节——"断"是溶解那一项的事，不是这里的。
	float width_scale = 0.65 + 0.75 * ray;
	float axis = (v_radius - ring_core) / max(ring_sigma * width_scale, 1.0);
	float band = exp(-axis * axis);

	// 光雾：从环心线往外的长尾，到光焰尖为止。它不是"环"的一部分，
	// 是环背后那片被照亮的热空气——少了它，光就贴在几何上。
	float t = clamp((v_radius - ring_core) / max(ring_tip - ring_core, 1.0), 0.0, 1.0);
	float veil = flame_veil * pow(1.0 - t, flame_power);

	// 光焰：同一个噪声乘在**外侧**（外侧越远权重越大），
	// 所以亮带本身还是一条完整的环，长短不齐只发生在尾巴上。
	// 0.775 是"两根噪声都取到 0.5"时的中心值：减掉它，光焰才是围绕 1.0
	// 上下摆，而不是整体把光提亮一档。
	float flame = mix(1.0, 1.0 + flame_gain * (ray - 0.775), smoothstep(0.05, 0.75, t));

	// 洞里没有光：几何本来就从 ring_inner 开始，这里再压一道软坡，
	// 让"洞"读起来是光化开的地方，而不是剪刀剪出来的。
	float hole = smoothstep(ring_inner, ring_core, v_radius);

	// 烧得不匀：亮带本身的峰值也跟着同一个角度噪声起伏。
	//
	// 幅度**必须小**（±20%）：试过 ±40%，环当场散成一片糊——一条亮度处处
	// 相等的环会读成"一个圈"，但一条忽明忽暗的环会读成"没有形状"。
	// 它需要的是"有的地方亮得发白、有的地方薄一点"，不是"断断续续"。
	float burn = 0.85 + 0.30 * ray;

	float radial = max(band, veil) * hole * flame * burn;

	// 溶解：和城郭、像身同一条 fbm。域取**盘面坐标**（以环心为原点），
	// 所以图案跟着环心走，不会随幻影的位移在屏幕上滑动。
	vec2 domain = v_local.yz - ring_center;
	float n = _fbm(domain * 0.0025 - vec2(0.0, TIME * 0.06));
	float dissolve = smoothstep(0.30, 0.80, n);
	dissolve = mix(1.0, dissolve, dissolve_amount);

	// 逆光：视线越靠近太阳，光背越被太阳本身的散射吃掉，
	// 从"一圈清楚的光"变成"一片烧起来的光"。
	vec3 to_sun = normalize((VIEW_MATRIX * vec4(sun_direction, 0.0)).xyz);
	float back = pow(clamp(dot(normalize(VIEW), to_sun), 0.0, 1.0), 4.0);
	vec3 col = mix(halo_color, sun_tint, back * 0.65);
	// 环面的正对程度只给一点点权重：它是光，仰头看时不该整圈暗下去
	col *= mix(1.0, v_facing, tilt_shade);

	// 呼吸：一条空间噪声 + 一条慢波。两个不同尺度叠起来，才看不出周期。
	float breathe = 1.0 + flicker * (
		(n - 0.5) * 1.4 + 0.22 * sin(TIME * 0.71 + v_radius * 0.004)
	);

	float alpha = clamp(
		strength * intensity * radial * dissolve * breathe * (1.0 + back * 0.8),
		0.0, 1.0
	);
	// 空气衰减：1.3 km 外的光背也会褪，但它比城郭抗褪（光是会散射的）
	alpha *= mix(1.0, haze_floor, haze);

	ALBEDO = col;
	ALPHA = alpha;
}
