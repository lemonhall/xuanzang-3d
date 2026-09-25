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
//
// 这一层是"整个场景一直飘着带状沙尘"的那一层：沙丘、天空、幻影它都盖。
//
// 采样坐标系是 (方位角, 仰角)。贴在 SCREEN_UV 上最省事，但转头时沙会跟着转——
// 那是镜头脏了，不是空气脏了；方位角是**绝对方位**，转头时沙从画面里滑过去。
//
// 它要同时满足两件听起来矛盾的事：
//   * **软**：用户认的就是这个版本——一条条柔软的、自己会慢慢变形的沙带。
//     所以带是噪声长出来的（fbm + 低频 warp），不是画上去的硬边。
//   * **像风**：静止不动的软带只是一层雾。让它变成"大风吹"的是三条，缺一不可：
//       1. **速度**：带顺风跑（dust_drift），沙暴里乘 (0.45 + 4.5×force)。
//          上一版不管刮多大风，沙的漂移都是同一个速度，所以"大风吹"在画面上
//          只剩"雾更浓了"。**速度比浓度更像风。**
//       2. **拖影**：风力越大，噪声沿流向叠得越开——快的东西一定被拖糊，
//          在一张静止的画面里，这是唯一读得出"速度"的线索。
//       3. **阵风**：浓度乘同一个包络（GameState.wind_force = 沙暴 × 阵风）。
//          沙扑上来的那一刻，人也正好被推了一下，这才是一场风，不是三个效果。
//
// 2026-09-24 的另一版把采样挪到**世界坐标的水平幕**上（想换来"顶着风走、沙迎面
// 扑过来"），结果是一条条**硬边**横丝划在佛像和城上，像镜头被划伤——用户否掉了。
// 世界坐标那条路不是不能走，但硬边不能用；这一版是用户认的那一版，只叠了上面三条。
uniform float dust_amount : hint_range(0.0, 1.0) = 0.42;
uniform vec3 dust_tint : source_color = vec3(1.0, 0.86, 0.62);
uniform float dust_gain : hint_range(0.0, 2.0) = 0.85;
// 风力 0..1 = 沙暴强度 × 阵风。**和推着人走、歪镜头的那个数是同一个**
// （Sandstorm.wind_force → GameState → PostProcess）：沙扑上来的那一刻，
// 人也正好被推了一下，这才是一场风，不是三个效果。
uniform float dust_wind_force : hint_range(0.0, 1.0) = 0.0;
// 平静时沙带的漂移速度（**弧度/秒**，0.023 ≈ 1.3°/s）。沙暴里另乘。
// 速度写在角度上、不写在采样坐标里：改 dust_bands / dust_along 时速度不受影响。
uniform float dust_drift : hint_range(0.0, 0.3) = 0.023;
// 采样频率。仰角方向一个单位 ≈ 一屏几条带；方位角方向**越小带越长**
// （0.40 ≈ 一条带横跨画面的四分之一），这是"一条条"而不是"一块块"的关键。
uniform float dust_bands : hint_range(1.0, 16.0) = 6.0;
uniform float dust_along : hint_range(0.05, 2.0) = 0.40;
// 把带掰弯的力度。**调到 0 就退回"直尺"**——这个数是"不笔直"的全部来源，
// 别再拿它当美工旋钮随手关掉（用户为"带太笔直"提过一次意见）。
uniform float dust_warp : hint_range(0.0, 3.0) = 1.2;
// 世界风向（水平单位向量）。沙往哪边淌由它定，不在 shader 里写死一个正号。
uniform vec3 wind_world = vec3(-0.22, 0.0, 0.98);
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

// 整数哈希（Hoskins 的 hash13 变形），专门给颗粒用。
//
// 换掉 `fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453)`：
// 它**在这块 GPU 上不是白噪**，而是一片逐像素的花纹。
//
// 2026-09-24 的排查值得整段留着，因为它把结论推翻过两次，而且**两次错的
// 都是"证据"那一环**，不是推理那一环：
//
// ① 先怀疑它，又说服自己不是它。写了一条"相邻像素相关性"的测试，顺手把旧
//    写法当对照组，满以为它会红——结果测出 0.016（白噪），结论于是翻成
//    "哈希没问题，网格是录片的 MJPEG 压出来的"。**这一条是错的**，错在方法：
//    那条测试跑在 CPU 上，GDScript 和照抄用的 numpy 都能用 float64 算 sin，
//    而真正出图的那一份是 GPU 上的 float32。09-24 重测：同一段算式在 CPU 上
//    用 **float32** 铺满一屏，旧写法依旧是纯白噪（四个频带各 0.250、相邻相关
//    0.000）。所以这不是"float32 的乘法精度"问题，是 **GPU 那颗 sin 在大
//    自变量上的表现**：这里的自变量是 43758 × (12.9898x + 78.233y)，
//    1600×900 上到了 10⁹ 量级，硬件做周期化的精度已经不足以让相邻像素互相独立。
//    抄到 CPU 上测，这一层**根本不在场**。
// ② 再怀疑是 MJPEG 压出来的。也不成立：同一段片子里取天空那条带，
//    0.40–0.50 cyc/px 的能量占比只有 0.026，**比无损静帧（0.10）还低**——
//    编码器是把 1 px 颗粒抹平的那一个，不是造出它的那一个。这也是为什么
//    "在成片里找网格"定位不了问题：它出现在无损静帧上，成片里先被吃掉。
//
// 真正的判据是**无损静帧 + 同帧只换一处**（09-24 重做，1600×900、同一机位、
// 同一个摇法）。0.40–0.50 cyc/px 的能量占比——占比高＝能量挤进一个窄带
// ＝规则花纹，白噪应该摊平到各 0.25：
//
//     天空那条带： 关掉颗粒 0.024 ／ 新哈希 0.102 ／ 旧哈希 0.292
//     沙面带：     关掉颗粒 0.172 ／ 新哈希 0.213 ／ 旧哈希 0.486
//
// 新哈希和"关掉颗粒"同量级，旧哈希是它的三倍——那层网格就在这三倍里。
//
// 教训（别的地方也适用）：**shader 的白噪性质只能在 GPU 上量——抄到 CPU 上
// 得到的结论可能正好相反；而"同一条管线只换一处"必须用无损静帧，编码器会把
// 待查的那个频率先吃掉。**
//
// 这一支整数哈希还有一个附带好处：不依赖 sin 的精度，GPU 和 CPU 给出同一片沙。
float _grain_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
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
		// (方位角, 仰角)，单位是弧度。**一切速度、弯曲、拖影都定义在这个坐标系里**，
		// 采样频率只在最后一步才乘上去——改频率不会顺手改掉速度。
		float az = atan(dir.x, dir.z);
		float el = asin(clamp(dir.y, -1.0, 1.0));
		// 风向在画面里的横向分量：风横着刮过镜头时最大（±1），正对着刮时趋 0。
		// 用相机自己的基向量投出来——风反过来，沙就反着淌。
		vec3 wind_h = normalize(vec3(wind_world.x, 0.0, wind_world.z));
		vec3 right_h = normalize(vec3(cam_right.x, 0.0, cam_right.z) + vec3(0.0001, 0.0, 0.0001));
		float lateral = dot(wind_h, right_h);
		// 带在**画面上前进的方向**（弧度）：顺风横着走 + 缓缓上浮。
		// 两个分量速度不一样，层次就出来了；沙暴里整体乘 (0.45 + 4.5×force)，
		// 一阵扑上来，沙是**跑**起来的。
		// 采样点往上游挪 = 图案顺流走（- TIME × 流向），下面的拖影也用它。
		vec2 flow = vec2(lateral * (0.45 + 4.5 * dust_wind_force), 0.9 * (0.45 + 0.55 * dust_wind_force));
		az -= TIME * dust_drift * flow.x;
		el -= TIME * dust_drift * flow.y;
		// 把带掰弯。低频慢噪声推着相位上下起伏，S 形就是从这儿来的；
		// 它自己的形状也在慢慢变（第二个 TIME），这是"灵动"的来源。
		float wob = _fbm(vec2(az * 0.55 + TIME * 0.010 * (0.4 + 2.6 * dust_wind_force), TIME * 0.006)) - 0.5;
		el += wob * dust_warp * 0.10 * (0.55 + 0.75 * dust_wind_force);
		// 采样坐标：方位角方向压扁（带被拉长）、仰角方向压实（带一条压一条）。
		vec2 s = vec2(az * dust_along, el * dust_bands);
		// 拖影：沿**带自己刚才来的方向**再取一次噪声叠上去，就是这张图里的运动模糊。
		// 拖多远 = 0.45×force 弧度，方向先在角度里算好、再按同样的频率映射进 s，
		// 才是"沿流向"。风力 0 时两次完全重合：这一版就退回用户认的那一版，一点没动。
		vec2 flow_dir = flow / max(length(flow), 0.0001);
		vec2 smear = vec2(flow_dir.x * dust_along, flow_dir.y * dust_bands) * (0.45 * dust_wind_force);
		float fine = (_fbm(s) + _fbm(s - smear)) * 0.5;
		float broad = _fbm(s * 0.45 + vec2(TIME * 0.006, 0.0));
		//
		// 门槛一律用 **σ 分数**说，不用绝对数——这个 fbm 的实测分布是
		// 均值 0.415、σ 0.136（不是教科书上的 0.5 / 0.16：四个八度之间带旋转，
		// 分布会偏）。这两个数是 [风里的沙带看得见吗] 那条测试**量出来的**，
		// 改了 fbm 或者权重就要重跑那条测试对一遍。
		// 2026-09-24 就是在这里栽的：门槛写在 0.54→0.82，
		// 实际是 +1σ→+3σ，画面里几乎没有像素够得着，**整层沙等于不存在**，
		// 而"看不见"和"没写"在截图上是同一个样子。
		float v = (fine * 0.72 + broad * 0.28 - 0.415) / 0.136;
		// 取噪声的高处当"沙丝"，**软边**：-0.7σ 爬到 +1.3σ。低于 -0.7σ 的
		// （约四分之一的画面）干干净净，高过 +1.3σ 的（约一成）是实心的沙丝，
		// 中间是柔和的过渡——既不是一层均匀的雾，也不是一台划痕机
		// （上一版把整片压成 0.50→0.68 的硬边，半个画面都在带里，
		// 于是成了满屏平行的硬线，用户原话："很不自然"）。
		float band = smoothstep(-0.7, 1.3, v);
		// 阵风把沙**成片**推浓：和推力、镜头晃动共用同一个包络。
		float haze = band * dust_amount * (0.72 + 0.55 * dust_wind_force);
		// 逆着太阳看时沙被点着：越接近太阳方向越亮。这一条和天空、幻影的
		// 逆光同源——同一束光，照在城上、照在沙上，不该是两套颜色。
		float glow = pow(clamp(dot(dir, normalize(sun_direction_world)), 0.0, 1.0), 3.0);
		// 背光时沙是**挡光**的脏黄幕（把沙丘压暗、把远处抹掉），朝着太阳时是
		// 透光的金粉（提亮）。上一版只有"加亮"这半边——沙在暗背景上根本看不见。
		vec3 veil = dust_tint * mix(vec3(0.52), vec3(1.18), glow);
		col = mix(col, veil, clamp(haze * 0.34 * dust_gain, 0.0, 0.40));
		col += dust_tint * haze * (0.05 + 0.42 * glow) * dust_gain * 0.60;
	}

	// 暗角
	vec2 d = SCREEN_UV - 0.5;
	float v = 1.0 - vignette_strength * pow(clamp(length(d) * 1.42, 0.0, 1.0), vignette_softness);
	col *= clamp(v, 0.0, 1.0);

	// 颗粒：**按像素取，不按 UV 取**。
	//
	// 这里是两道坑叠在一起的地方，两道都踩过：
	//   1. 采样坐标必须走 FRAGCOORD（像素坐标），不能走 SCREEN_UV——
	//      旧版 `SCREEN_UV * 2048.0` 在 1600 像素上格距 1.28 px，和像素网格打架，
	//      明亮的沙面上会浮出一排竖向摩尔纹；
	//   2. 哈希本身要够白噪。这一条**当前是干净的**（实测相邻相关性 0.026），
	//      现在用的是整数哈希，见 _grain_hash 的注释。
	//
	// （一层逐像素的花纹确实出现过，**凶手就是旧的 `fract(sin(...))` 哈希**；
	//  MJPEG 反而是把它抹平的那一个。两版结论都被推翻过一遍，数据和经过都在
	//  _grain_hash 上面，别再顺着"是不是编码器"那条线查第二遍。）
	// 时间上按 1/24 秒跳一次，像胶片颗粒那样闪，而不是每帧都换（后者会让人晕）。
	//
	// 顺带一句给"出片"：1 px 的颗粒在 1600→720p 的缩放里会被平均掉一部分，
	// 这是正常的（胶片转数字也是这个结果），不要去把它加粗——
	// 加粗之后在原生分辨率下就成了一片麻点。
	float g = _grain_hash(FRAGCOORD.xy + floor(TIME * 24.0) * 137.0) - 0.5;
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
