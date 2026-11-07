// Çakıl alanı, "yerden çıkan hava dalgaları" tasarımı (eklemeli, yarı saydam).
// 0: yere yatık zemin (yuvarlak köşeli, yumuşak kenarlı; ortadan dışa yayılan halkalar)
// 1: dik perde (yerden yükselip kıvrılan, yükseldikçe sönen dalga çizgileri)
// Birim düzlem ölçeklenerek kurulur; boyut MODEL_MATRIX'ten okunur (desen metre cinsinden).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

// Uzakta sisle aynı mesafede söner (eklemeli parıltı sise karışamaz; game.gd _apply_fog)
global uniform float far_fog_begin;
global uniform float far_fog_end;

float far_fade(vec3 view_pos) {
	return 1.0 - smoothstep(far_fog_begin, far_fog_end, length(view_pos));
}

uniform int pattern = 0;
uniform vec4 color : source_color = vec4(0.86, 0.92, 1.0, 1.0);
uniform float strength = 0.5;
uniform float t = 0.0;
uniform float seed = 0.0;

varying vec3 lp;
varying vec3 hs;

void vertex() {
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	hs = sc * 0.5;
	lp = VERTEX * sc;
}

// Yuvarlak köşeli dikdörtgenin içinde 1, kenara doğru yumuşakça 0
float rounded_mask(vec2 p, vec2 h, float r, float fade) {
	vec2 q = abs(p) - (h - vec2(r));
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
	return 1.0 - smoothstep(-fade, 0.0, d);
}

void fragment() {
	vec2 uv = lp.xy;
	vec2 h = hs.xy;
	float a = 0.0;
	if (pattern == 0) {
		float m = rounded_mask(uv, h, min(1.2, min(h.x, h.y)), 0.9);
		// Ortadan (yol boyunca) dışa yayılan halkalar: hafifçe dalgalı
		float d = abs(uv.y) + 0.12 * sin(uv.x * 2.3 + t * 2.0 + seed);
		float ph = fract(d / 1.1 - t * 0.9);
		float ring = exp(-pow((ph - 0.5) * 9.0, 2.0));
		a = m * (0.10 + 0.55 * ring);
	} else {
		// Dik perde: alt kenar yolda; yükselen, kıvrılan yatay dalga çizgileri
		float y = uv.y + h.y;  // 0 (yer) .. 2h (tepe)
		float k = clamp(y / (2.0 * h.y), 0.0, 1.0);
		float wob = 0.07 * sin(uv.x * 3.1 + t * 3.3 + seed * 2.0) + 0.04 * sin(uv.x * 7.7 - t * 2.1 + seed);
		float ph = fract((y + wob * (0.4 + k)) / 0.34 - t * 1.1 - seed * 0.37);
		float line = exp(-pow((ph - 0.5) * 11.0, 2.0));
		float side = 1.0 - smoothstep(h.x - 0.8, h.x, abs(uv.x));
		a = line * pow(1.0 - k, 1.6) * side * smoothstep(0.0, 0.08, y);
	}
	ALBEDO = color.rgb * a * strength;
	ALBEDO *= far_fade(VERTEX);
}
