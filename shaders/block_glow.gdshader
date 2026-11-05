// Direkli blok tasarımlarının ışık parıltıları (eklemeli, yarı saydam düzlemler): tüp çevresindeki
// hale, yola vuran ışık, elektrik arkı, kuvvet alanı. Birim düzlem ölçeklenerek kurulur.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

// 0 yatay hale bandı, 1 elektrik arkı, 2 kuvvet alanı, 3 yerde ışık lekesi, 4 yerde yumuşak ışık,
// 5 yerde çizgi ışık (yatay çubukların altına düşen, çubuk boyunca uzanan dar şerit)
uniform int pattern = 0;
uniform vec4 color : source_color = vec4(1.0, 0.6, 0.15, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.95, 0.75, 1.0);
uniform float strength = 0.6;
uniform float t = 0.0;
uniform float seed = 0.0;
uniform float flicker = 0.0;
// 1: ışık veren çubukla (block_fx lazer, aynı seed) aynı anda nabız gibi atar
uniform int pulse = 0;

varying vec3 lp;
varying vec3 hs;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(float x, float s) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(vec2(i, s)), hash(vec2(i + 1.0, s)), f * f * (3.0 - 2.0 * f));
}

float flick(float s) {
	float f = hash(vec2(floor(t * 14.0), s));
	float k = f > 0.965 ? 0.3 : (f > 0.94 ? 0.7 : 1.0);
	return mix(1.0, k, flicker);
}

float pulse_k() {
	return pulse == 0 ? 1.0 : 0.85 + 0.15 * sin(t * 30.0 + seed * 7.0);
}

void vertex() {
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	hs = sc * 0.5;
	lp = VERTEX * sc;
}

void fragment() {
	vec2 uv = lp.xy;
	vec2 h = hs.xy;
	vec3 col = vec3(0.0);
	float ex = smoothstep(h.x, h.x - 0.25, abs(uv.x));
	if (pattern == 0) {
		float d = abs(uv.y) / h.y;
		col = color.rgb * exp(-d * d * 5.0) * ex * strength * flick(seed);
	} else if (pattern == 1) {
		// Üç titrek ark: uçlarda direklere bağlı, ortada savrulur; saniyede birkaç kez şekil değiştirir
		float env = sin(3.14159 * clamp(uv.x / h.x * 0.5 + 0.5, 0.0, 1.0));
		float a = 0.0;
		for (int i = 0; i < 3; i++) {
			float fi = float(i);
			float step_t = floor(t * 16.0 + fi * 0.37);
			float y = (noise(uv.x * 5.0 + fi * 17.0, step_t + seed) - 0.5) * 1.3 * h.y
				+ (noise(uv.x * 19.0 + fi * 5.0, step_t * 1.7) - 0.5) * 0.18 * h.y;
			y *= env;
			float d = abs(uv.y - y);
			float w = i == 0 ? 1.0 : 0.55;
			a += w * (exp(-d * 70.0) + 0.35 * exp(-d * 14.0));
		}
		col = mix(color.rgb, hot.rgb, clamp(a - 0.8, 0.0, 1.0)) * a * strength;
	} else if (pattern == 2) {
		// Kuvvet alanı: yukarı akan tarama çizgileri, alt ve üst kenarda parlama, ara sıra titreme
		float scan = step(0.55, fract((uv.y - t * 0.35) / 0.07));
		float rim = exp(-(h.y - abs(uv.y)) * 14.0);
		float wave = 0.5 + 0.5 * sin(uv.x * 9.0 - t * 4.0);
		float a = 0.12 + 0.16 * scan + 0.06 * wave + 0.7 * rim;
		col = color.rgb * a * ex * strength * flick(seed);
	} else if (pattern == 5) {
		// Çizgi ışık: düzlem yere yatık, ortası çubukların tam altı. Çubuk boyunca düz, uçlarda uzun
		// bir mesafede söner; çubuktan uzaklaştıkça yumuşakça azalır (ortada sivri tepe yok, kenar yok)
		float dz = abs(uv.y);
		float ax = abs(uv.x) / h.x;
		float along = 1.0 - smoothstep(0.45, 1.0, ax);
		along *= along;
		float a = 0.55 * exp(-pow(dz / 0.38, 2.0)) + 0.45 * exp(-pow(dz / 0.85, 2.0));
		a *= 1.0 - smoothstep(0.5, 1.0, dz / h.y);
		col = color.rgb * a * along * strength;
	} else if (pattern == 4) {
		// Yerde yumuşak ışık (düzlem yere yatırılır): köşesiz, kenara doğru tamamen sönen elips
		vec2 q = uv / h;
		float r = length(q);
		col = color.rgb * exp(-r * r * 3.0) * (1.0 - smoothstep(0.45, 1.0, r)) * strength * flick(seed);
	} else {
		// Yerde ışık lekesi (düzlem yere yatırılır): yumuşak elips
		vec2 q = uv / h;
		float d = dot(q, q);
		col = color.rgb * exp(-d * 4.0) * smoothstep(1.0, 0.55, max(abs(q.x), abs(q.y))) * strength * flick(seed);
	}
	ALBEDO = col * pulse_k();
}
