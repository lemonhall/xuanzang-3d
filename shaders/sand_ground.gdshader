shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// 脚下的沙面。
//
// 为什么要自己写：原来那片沙是一张 **25 cm 的 Perlin 法线贴图**（见
// desert_world._sand_material 的历史），可在这一关的布光下它等于不存在——
// **逆光里漫反射对法线几乎不敏感**（太阳在弥勒背后，几乎正对着视线，
// 沙面的明暗本来就趋平），而人眼认"沙"靠的恰恰是两样别的东西：
//
//   1. **脊线的走向**：风成沙纹是一道道**垂直于风**的横向小坡，
//      脊线弯、迎风面缓、背风面陡。各向同性的 Perlin 噪声长得像橡皮泥，
//      怎么调都不像风做的；
//   2. **沟里的暗**：沙纹的读数是"亮脊 + 暗沟"的交替。这是**环境光遮蔽**，
//      跟漫反射无关，所以逆光下它照样在。
//
// 所以这里不走贴图，用解析函数直接算高度场，再取有限差分得到法线：
// 远的一层（~60 cm，带弯曲）管大面，近的一层（~9 cm，顺风排列）管脚下，
// 再叠一点 3 cm 的颗粒。**近处才画细的那层**——9 cm 的纹在 20 m 外
// 一个像素都不到，画上去就是闪烁的摩尔纹。
//
// 尺度是量过的：塔克拉玛干的风成沙纹脊距多在 5~15 cm，脊高 1~2 cm。

const float RIPPLE_NEAR_SPACING = 0.09;
const float RIPPLE_FAR_SPACING = 0.62;
const float RIPPLE_NEAR_AMP = 0.008;
const float RIPPLE_FAR_AMP = 0.035;
// 近处那层在多少米内满强度、多少米外彻底没有。18 m 之外它的周期已经
// 小于一个像素（900 px 上竖直半视角 34°，18 m 处 1 px ≈ 1.3 cm）。
const float NEAR_FADE_IN = 3.0;
const float NEAR_FADE_OUT = 18.0;

uniform vec3 sand_albedo : source_color = vec3(0.80, 0.58, 0.34);
uniform float sand_roughness = 0.95;
/// 世界风向（水平单位向量）。**沙纹垂直于它**——风把沙推成一道道横坡。
uniform vec2 wind_dir = vec2(1.0, 0.0);
/// 风力 0..1。风越大，沙纹越深、越清楚（新沙纹被吹出来）。
uniform float wind_force = 0.0;

varying vec3 world_pos;


// 整数哈希（Hoskins 的 hash13 变形）。沙面上的细颗粒用它。
//
// 用它不是审美：`fract(sin(dot(p, k)))` 那一族在大坐标下会退化成细网格
// （后处理里的颗粒踩过，就是 2026-09-24 那次；经过写在
// shaders/desert_post.gdshader 的 _grain_hash 上面）。整数哈希与平台无关：
// 不依赖 sin 的精度，GPU 和 CPU 给出同一片沙——而"能在 CPU 上照抄着对答案"
// 是这个仓库里所有 shader 契约的基础。
float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}


/// 一层风成沙纹的**脊值** 0..1（0 = 沟底，1 = 脊顶）。`per` = 脊距（米）。
///
/// 脊线是一道道**横坡**：沿风向取相位；再用一层低频噪声沿脊线方向推相位，
/// 脊线就弯了（真沙纹没有直的）。剖面用 `pow` 削尖——
/// **尖脊 + 平缓的迎风面**才是风做的，正弦剖面看起来像水波。
float ripple_crest(vec2 p, float per, float warp) {
	vec2 w = normalize(wind_dir);
	float along = dot(p, w);
	float across = dot(p, vec2(-w.y, w.x));
	float bend = vnoise(vec2(across * 0.35, along * 0.06)) * 2.0 - 1.0;
	// 脊距本身也起伏：真沙田不是梳过的，有粗一片细一片。少了这一项，
	// 整片沙会像一块印花布（放大看尤其明显）。
	float per_local = per * (0.72 + 0.60 * vnoise(p * 0.017));
	float phase = along / per_local + bend * warp;
	float t = fract(phase);
	// 0..1 的三角波削尖：脊窄、沟宽，且**不对称**（背风面更陡）
	return pow(1.0 - abs(2.0 * t - 1.0), 1.8);
}


/// 沙面相对高度（米）。`near` 0..1 是近处那一层的强度。
float sand_height(vec2 p, float near) {
	float h = (ripple_crest(p, RIPPLE_FAR_SPACING, 1.6) - 0.45) * RIPPLE_FAR_AMP;
	h += (ripple_crest(p, RIPPLE_NEAR_SPACING, 0.9) - 0.45) * RIPPLE_NEAR_AMP * near;
	// 3 cm 的颗粒：沙不是面粉，近处要有砂粒感（只给色调，不进法线——
	// 3 cm 的坡度在 2 m 外就是噪声，画进法线只会脏）
	h += (hash21(floor(p * 34.0)) - 0.5) * 0.004 * near;
	return h;
}


/// 这一点的"脊/沟"读数 0..1。色调的明暗用它——**不能用法线的 y 分量去代**：
/// 沙丘自己就有坡度，那样整片坡面都会被判成"沟"，一坡的沙全黑下去。
/// （2026-09-24 试过一次，先在这里记下来。）
float sand_crest(vec2 p, float near) {
	float far_c = ripple_crest(p, RIPPLE_FAR_SPACING, 1.6);
	float near_c = ripple_crest(p, RIPPLE_NEAR_SPACING, 0.9);
	return clamp(mix(far_c, near_c, clamp(near, 0.0, 1.0)), 0.0, 1.0);
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	vec2 p = world_pos.xz;
	float dist = distance(world_pos, CAMERA_POSITION_WORLD);
	float near = (1.0 - smoothstep(NEAR_FADE_IN, NEAR_FADE_OUT, dist))
		* clamp(1.0 + wind_force * 0.6, 0.0, 1.6);

	// 有限差分求坡度。步长按**最细那一层的 1/8** 取，够采样又不抖。
	float e = RIPPLE_NEAR_SPACING * 0.125;
	float h0 = sand_height(p, near);
	float hx = sand_height(p + vec2(e, 0.0), near);
	float hz = sand_height(p + vec2(0.0, e), near);
	vec2 slope = vec2(hx - h0, hz - h0) / e;

	// 世界法线（片元里的 NORMAL 是**视图空间**的，沙面几乎是平面，
	// 所以先把基法线转回世界、加上坡度、再转回去）。
	vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	n_world = normalize(n_world + vec3(-slope.x, 0.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	// 沟里的暗：沙纹真正的读数。跟漫反射无关（是遮蔽），所以逆光下也在。
	float crest = sand_crest(p, near);
	float trough = 1.0 - crest;
	float grain = hash21(floor(p * 34.0)) - 0.5;
	// 明暗的**强度也随距离收**：远处那一层（62 cm）在 100 m 外还有 9 个像素宽，
	// 全强度会变成一片"扇骨"（2026-09-24 第一次拍就是这样）。真沙纹越远越糊，
	// 因为中间隔着空气——这里用距离代掉那层空气。
	float tone = 0.17 * mix(0.32, 1.0, near);
	ALBEDO = sand_albedo * (1.0 - tone * trough) * (1.0 + grain * 0.05 * near);
	ROUGHNESS = mix(sand_roughness, sand_roughness - 0.12, trough);
	SPECULAR = 0.4;
}
