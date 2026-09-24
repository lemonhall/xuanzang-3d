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

float _rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
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

	// 暗角
	vec2 d = SCREEN_UV - 0.5;
	float v = 1.0 - vignette_strength * pow(clamp(length(d) * 1.42, 0.0, 1.0), vignette_softness);
	col *= clamp(v, 0.0, 1.0);

	// 颗粒
	float g = _rand(SCREEN_UV * 2048.0 + fract(TIME) * 137.0) - 0.5;
	col += g * grain_amount;

	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
