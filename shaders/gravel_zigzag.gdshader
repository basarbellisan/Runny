// Çakıl, "kesik zikzak yarıklar" tasarımı: yere yatık düzlemde yatay zikzak sıraları; zikzağın her
// kolu ayrı bir yarık (köşelerde boşluk). Yarığın içi dipten ışıklı (ortası açık), kenarı koyu duvar;
// parlaklık üstündeki ışık perdesiyle aynı nabızda (gravel_curtain ile aynı faz).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec4 light : source_color = vec4(0.18, 0.36, 1.0, 1.0);
uniform vec4 core : source_color = vec4(0.77, 0.83, 1.0, 1.0);
uniform vec4 wall : source_color = vec4(0.05, 0.04, 0.10, 1.0);
// Kolun yatay boyu (yarım periyot), zikzak genliği, sıra aralığı
uniform float arm = 0.8;
uniform float amp = 0.32;
uniform float row_gap = 1.2;
uniform vec2 counts = vec2(8.0, 10.0);  // kol sayısı, sıra sayısı
uniform float radius = 0.135;
uniform float t0 = 0.2;
uniform float t1 = 0.8;
uniform float t = 0.0;

varying vec3 lp;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float breath(vec2 ci) {
	return 0.5 + 0.5 * sin(t * 2.2 - ci.y * 0.55 + hash(ci) * 2.0);
}

float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	float h = clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0);
	return length(p - a - ab * h);
}

void vertex() {
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	lp = VERTEX * sc;
}

void fragment() {
	float W = counts.x * arm;
	float H = counts.y * row_gap;
	float row = floor((lp.y + H * 0.5) / row_gap);
	float yc = (row + 0.5) * row_gap - H * 0.5;
	float xa = lp.x + W * 0.5;
	float a0 = floor(xa / arm);
	float best = 1e9;
	float bi = 0.0;
	for (int k = -1; k <= 1; k++) {
		float a = a0 + float(k);
		if (a < 0.0 || a > counts.x - 1.0 || row < 0.0 || row > counts.y - 1.0) {
			continue;
		}
		// k. nokta: x = a * arm, y = çift indekste -amp, tekte +amp
		float ys = mod(a, 2.0) < 0.5 ? -amp : amp;
		vec2 pa = vec2(a * arm, yc + ys);
		vec2 pb = vec2((a + 1.0) * arm, yc - ys);
		vec2 s0 = mix(pa, pb, t0);
		vec2 s1 = mix(pa, pb, t1);
		float dd = seg_dist(vec2(xa, lp.y), s0, s1);
		if (dd < best) {
			best = dd;
			bi = a;
		}
	}
	float r = best / radius;
	float inside = 1.0 - smoothstep(0.93, 1.0, r);
	float b = breath(vec2(bi, row));
	vec3 glow = mix(core.rgb, light.rgb, smoothstep(0.0, 0.55, r)) * mix(0.55, 1.0, b);
	ALBEDO = mix(glow, wall.rgb, smoothstep(0.62, 0.95, r));
	ALPHA = inside;
}
