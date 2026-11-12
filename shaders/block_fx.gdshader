// Direkli blok tasarımlarının ışık veren katı parçaları (floresan tüp, lazer, tabela, segment çubuk).
// Kutular birim kutu ölçeklenerek kurulur; boyut MODEL_MATRIX'ten okunur (desen metre cinsinden).
shader_type spatial;
render_mode unshaded;

// 0 floresan tüp, 1 lazer ışını, 2 led tabela, 3 segment çubuk, 4 düz ışık (lamba, ray),
// 5 sırayla yanan çubuk (seed = sıra: 0 en üst; yukarıdan aşağı yumuşak dalga)
uniform int pattern = 0;
uniform vec4 c_main : source_color = vec4(1.0, 0.79, 0.29, 1.0);
uniform vec4 c_hot : source_color = vec4(1.0, 0.96, 0.86, 1.0);
uniform vec4 c_low : source_color = vec4(1.0, 0.42, 0.0, 1.0);
uniform vec4 c_dark : source_color = vec4(0.1, 0.06, 0.14, 1.0);
uniform float t = 0.0;
uniform float seed = 0.0;
// Floresan titremesi (0 kapalı)
uniform float flicker = 0.0;
// Sırayla yanma dalgasının süresi (sn)
uniform float period = 1.4;
// Dalgada bir çubuktan sonrakine gecikme (turun kesri)
uniform float phase_step = 0.28;
// Sırayla yanan çubukta sönük halin parlaklığı: 0 koyulaşır (kısılan lamba), 1 ana renkte kalır
uniform float dim_keep = 0.0;
// Düz dünya denemesi: parıltı (kenara doğru açılan öz) yok, yalnız sönük ve yanan düz renk
uniform bool flat_mode = false;

varying vec3 lp;
varying vec3 hs;
varying vec3 ln;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Floresan gibi ara sıra kısa titreme: çoğu an tam parlak
float flick(float s) {
	float f = hash(vec2(floor(t * 14.0), s));
	float k = f > 0.965 ? 0.3 : (f > 0.94 ? 0.7 : 1.0);
	return mix(1.0, k, flicker);
}

// Yukarıdan aşağı yanma dalgası: i. çubuk bir öncekinden biraz sonra parlar; hiç tam sönmez
float cascade(float i) {
	float x = fract(t / period - i * phase_step);
	float w = 0.5 + 0.5 * cos(6.28318 * x);
	return 0.28 + 0.72 * pow(w, 1.4);
}

void vertex() {
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	hs = sc * 0.5;
	lp = VERTEX * sc;
	ln = NORMAL;
}

void fragment() {
	float ndv = abs(dot(NORMAL, VIEW));
	vec3 col = c_main.rgb;
	if (pattern == 0) {
		// Tüp: ortası beyaza yakın, kenarları renkli
		col = mix(c_main.rgb, c_hot.rgb, pow(ndv, 1.4)) * flick(seed);
	} else if (pattern == 1) {
		col = mix(c_main.rgb, c_hot.rgb, pow(ndv, 3.0)) * (0.85 + 0.15 * sin(t * 30.0 + seed * 7.0));
	} else if (pattern == 2) {
		// Led tabela: ön yüzde nokta vuruşlu, ortadan iki yana akan oklar
		col = c_dark.rgb;
		if (ln.z > 0.5) {
			float cs = 0.055;
			vec2 uv = lp.xy;
			vec2 cell = floor(uv / cs) + 0.5;
			vec2 f = abs(fract(uv / cs) - 0.5);
			float led = step(length(f), 0.33);
			vec2 cc = cell * cs;
			float a = abs(cc.x) + abs(cc.y) * 0.9;
			float on = step(0.5, fract(a / 0.3 - t * 1.3)) * step(0.08, abs(cc.x));
			float edge = min(hs.x - abs(uv.x), hs.y - abs(uv.y));
			vec3 lc = mix(c_low.rgb * 0.18, mix(c_main.rgb, c_hot.rgb, 0.25), on);
			col = mix(c_dark.rgb, lc, led * step(0.03, edge));
		}
	} else if (pattern == 3) {
		// Segment çubuk: ortadan dışa sırayla dolan bölmeler (yükleniyor çubuğu gibi)
		float sw = 0.2;
		float u = abs(lp.x);
		float seg = floor(u / sw);
		float fx = fract(u / sw);
		float gap = step(0.82, fx);
		float fill = fract(t * 0.6 + seed * 0.37) * (hs.x / sw + 3.0);
		float lit = step(seg, fill);
		float k = clamp(u / hs.x, 0.0, 1.0);
		vec3 lc = mix(c_hot.rgb, mix(c_main.rgb, c_low.rgb, k), smoothstep(0.0, 0.6, k));
		col = mix(c_low.rgb * 0.22, lc, lit);
		col = mix(col, c_dark.rgb, gap);
	} else if (pattern == 5) {
		float k = cascade(seed);
		// Kısılan lamba grileşmez, koyu turuncu-kızıla kayar; parlarken özü beyaza yakın
		vec3 dim = mix(c_main.rgb * vec3(0.55, 0.32, 0.18), c_main.rgb, dim_keep);
		col = flat_mode ? mix(c_main.rgb * 0.5, mix(c_main.rgb, c_hot.rgb, 0.6), k)
			: mix(dim, c_main.rgb, k) + c_hot.rgb * pow(ndv, 1.2) * k * k * 0.8;
	} else {
		col = c_main.rgb * flick(seed);
	}
	ALBEDO = col;
}
