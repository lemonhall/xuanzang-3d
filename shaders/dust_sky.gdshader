shader_type sky;

// 沙尘天空。这一版的目标只有一个：**抬头必须是天，不是天花板**。
//
// 上一版的天顶是暗褐色（0.22, 0.16, 0.13）、地平线是亮沙色，再叠一层低频
// value noise 当"翻涌的沙云"。参数单独看都不离谱，但玩家一抬头就出事了：
//   亮在下 + 暗在上 + 平滑渐变 + 没有方向 + 无尺度斑块 == 室内穹顶被地灯照亮。
//
// 户外天空靠三件事和穹顶区分开，缺一样就会往室内滑：
//   1. **有光源**：太阳得真在天上（同时有紧的光斑和很大的散射晕），
//      抬头看得到它，"光从哪来"这件事就不会落到画面外的地平线上；
//   2. **有方向**：朝着太阳的一半天空更亮更暖，背过去更冷更暗。
//      穹顶没有方位性，天空有——这一条是最关键的分界线；
//   3. **有层次**：沙尘贴着地平线堆，越高越薄，天顶是干净的。
//      天顶一旦又脏又暗，它就成了一块刷成棕色的顶棚。
//
// 另外两个踩过的坑：
//   - 天空噪声**不做透视除法**（dir.xz / dir.y）。地平线附近 uv 冲到无穷大，
//     噪声在极小角度内剧烈变化，天上会浮出一块块三角分面。
//   - value noise 的低频八度必须**逐层旋转**。不旋转时四个八度共用同一套
//     格点，"翻涌的沙云"会先露出方格，再退化成一块块拼接的方斑——那正是
//     上一版天顶看起来像"斑驳天花板"的直接原因。

uniform vec3 horizon_color : source_color = vec3(0.90, 0.70, 0.45);
uniform vec3 zenith_color : source_color = vec3(0.46, 0.47, 0.53);
uniform float horizon_power : hint_range(0.2, 4.0) = 0.9;

uniform vec3 sun_tint : source_color = vec3(1.0, 0.86, 0.60);
uniform float sun_strength : hint_range(0.0, 6.0) = 2.2;
uniform float sun_focus : hint_range(2.0, 400.0) = 110.0;
uniform float sun_halo : hint_range(0.0, 4.0) = 0.85;
uniform float sun_halo_focus : hint_range(1.0, 40.0) = 5.0;
// 光刺：太阳周围那一圈放射状的芒。
// 逆光走向弥勒时，像身剪影正好立在芒的中心——"佛光"最便宜也最直接的一笔。
uniform float ray_strength : hint_range(0.0, 3.0) = 0.85;
uniform float ray_count : hint_range(0.0, 32.0) = 10.0;
// 太阳方向由 GDScript 每帧写入，不依赖内置光照变量：
// Godot 的 sky shader 里没有 SUN_DIR，LIGHT0_DIR 的方向约定也容易搞反，
// 自己传一个向量最省事，还能和 DirectionalLight3D 严格对齐。
uniform vec3 sun_direction = vec3(0.5, 0.8, 0.3);

uniform float cloud_amount : hint_range(0.0, 1.0) = 0.30;
uniform float cloud_scale : hint_range(0.1, 24.0) = 9.0;
// 风向决定沙尘条纹往哪边拉。和沙暴推力用同一个风向，两边才对得上。
uniform vec2 wind_direction = vec2(1.0, 0.35);

float _hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float _vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = _hash(i);
	float b = _hash(i + vec2(1.0, 0.0));
	float c = _hash(i + vec2(0.0, 1.0));
	float d = _hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float _fbm(vec2 p) {
	// 每个八度都转一次：四个八度的格点不对齐，方格才长不出来。
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

void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = clamp(dir.y, 0.0, 1.0);
	// 注意：变量不能叫 `flat`——GLSL 里那是插值限定符，是保留字。
	vec2 level_dir = vec2(0.0, 0.0);
	if (abs(dir.x) + abs(dir.z) > 0.0001) {
		level_dir = normalize(vec2(dir.x, dir.z));
	}
	vec2 wind = normalize(wind_direction);

	// 高度渐变：暖色只贴着地平线。horizon_power < 1 让暖色那一层更薄，
	// 抬头十几度就脱离沙尘带——上一版是 1.15，暖棕一路糊到天顶。
	float t = pow(h, horizon_power);
	vec3 col = mix(horizon_color, zenith_color, t);

	// 风驱沙尘：沿风向拉长的条纹，越靠地平线越浓，天顶基本干净。
	//
	// 2026-09-24 改过一次，教训记在这儿：旧版的 uv 只有 `level_dir` 两个分量，
	// 而 `level_dir` 里**没有高度**——同一个方位上，从地平线到天顶是同一个
	// 噪声值，于是"带"全是笔直的，只有浓度随高度渐变。笔直 = 没有沙的灵动感。
	// 现在把高度放进 uv 的第二轴（带本身的走向），再用一层低频噪声把相位
	// 推弯、拿时间让它飘：带就一边弯一边走。
	//
	// 仍然**不做透视除法**（dir.xz / dir.y）——地平线附近 uv 冲到无穷，
	// 天上会浮出三角分面。这里用的是 h = sin(俯仰)，天生有界。
	float dust_band = 1.0 - smoothstep(0.03, 0.70, h);
	if (cloud_amount > 0.0) {
		vec2 uv = vec2(dot(level_dir, wind), h * 2.6);
		// 相位弯曲：一条低频慢噪声推着带上下起伏，S 形就是从这里来的
		float wob = _fbm(vec2(uv.x * 0.55 + TIME * 0.008, TIME * 0.003)) - 0.5;
		uv.y += wob * 2.2;
		// 漂移：顺风走 + 缓缓上浮。两个速度取得不一样，层次才出得来
		uv += vec2(TIME * 0.012, -TIME * 0.020);
		// 一细一粗两层：细的抽成丝，粗的是整片沙幕
		float fine = _fbm(uv * cloud_scale * 0.34);
		float broad = _fbm(uv * cloud_scale * 0.10 + vec2(TIME * 0.004, 0.0));
		float dust = ((fine - 0.5) * 0.8 + (broad - 0.5) * 0.6) * cloud_amount * dust_band;
		col *= clamp(1.0 + dust * 1.7, 0.58, 1.55);
	}

	// 方位明暗：朝阳一侧暖亮、背阳一侧冷暗。这一条是"天空"和"穹顶"的分界。
	float sun_side = clamp(
		dot(level_dir, normalize(vec2(sun_direction.x, sun_direction.z))), 0.0, 1.0
	);
	col = mix(col * vec3(0.74, 0.82, 1.00), col * vec3(1.06, 1.00, 0.92), pow(sun_side, 1.3));

	// 太阳：紧的小斑 + 很大的一圈散射晕。只做小斑的话，抬头看不到光源，
	// 光就"从画面外的地平线上来"——那正是室内顶灯的布光。
	float sun_dot = max(dot(dir, normalize(sun_direction)), 0.0);
	col += sun_tint * pow(sun_dot, sun_focus) * sun_strength;
	col += sun_tint * pow(sun_dot, sun_halo_focus) * sun_halo;

	// 光刺。关键在"用绕太阳方向的方位角去调制，而不是用屏幕坐标"：
	// 前者是芒从太阳射出来，后者是条纹贴在屏幕上——转头就能分辨。
	// 芒必须**跟着太阳走**，太阳一挪（比如把它挪到弥勒背后），芒也跟着挪。
	if (ray_strength > 0.0) {
		vec3 sd = normalize(sun_direction);
		vec3 t1 = normalize(cross(sd, vec3(0.0, 1.0, 0.0)));
		vec3 t2 = normalize(cross(sd, t1));
		float ang = atan(dot(dir, t2), dot(dir, t1));
		float ray = 0.5 + 0.5 * sin(ang * ray_count + TIME * 0.12);
		ray = ray * ray;
		col += sun_tint * pow(sun_dot, 14.0) * ray * ray_strength;
	}

	// 贴地的一层散射亮：沙尘被低角度光打透
	col += horizon_color * 0.10 * pow(1.0 - h, 6.0);

	COLOR = col;
}
