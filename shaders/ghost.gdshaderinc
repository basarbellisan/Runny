// Hayalet örtüsünün ortak kodu (ghost.gdshader dış yüz, ghost_back.gdshader iç yüz)

uniform vec4 color : source_color = vec4(0.96, 0.93, 1.0, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float alpha_center = 0.45;
uniform float alpha_edge = 0.92;
uniform float glow = 0.25;
uniform float t = 0.0;
uniform float phase = 0.0;
// Etek dalgası: genlik (m), dilim sayısı (etek ucundaki yuvarlak dilimler), hız
uniform float wave_amp = 0.25;
uniform float scallops = 5.0;
uniform float wave_speed = 2.2;
// Boyunca ilerleyen kıvrım (kuyruk, şerit): genlik, sıklık
uniform float ripple_amp = 0.0;
uniform float ripple_freq = 6.0;
// Geriye savrulma (bize doğru gelirken etek arkada kalır)
uniform float trail = 0.35;
// Etek ucunun biçimi: 0 düz, 1 yuvarlak dilimli, 2 yırtık şeritler
uniform int hem = 1;
uniform float hem_depth = 0.12;
// Gözler (önde): açı aralığı (turun kesri), yükseklik, boyut; 0 yok
uniform float eyes = 1.0;
uniform vec2 eye_pos = vec2(0.055, 0.74);
uniform vec2 eye_size = vec2(0.03, 0.07);
uniform vec4 eye_color : source_color = vec4(0.16, 0.08, 0.22, 1.0);
uniform float eye_glow = 0.0;
// Ağız (oval), 0 yok
uniform float mouth = 0.0;
// Kukuleta: önde koyu yüz oyuğu
uniform float hood = 0.0;
uniform vec4 hood_color : source_color = vec4(0.16, 0.08, 0.22, 1.0);
// Hologram: dolgu yok denecek kadar az, kenar ve tarama çizgileri parlar
uniform float holo = 0.0;
// Yüzün (gözlerin) baktığı açı (turun kesri; 0 ön): öne yatırılmış hayalette yukarıya bakan taraf
uniform float face_angle = 0.0;

varying float v_h;
varying float v_da;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void vertex() {
	float a = UV.x * 6.28318;
	float h = UV.y;
	float k = pow(1.0 - h, 2.0);
	float tt = t * wave_speed + phase;
	vec2 rad = length(VERTEX.xz) > 0.001 ? normalize(VERTEX.xz) : vec2(0.0);
	// Etek: yukarı-aşağı ve içe-dışa dalga (dilimler dolaşır)
	VERTEX.y += wave_amp * k * sin(a * scallops + tt);
	VERTEX.xz += rad * wave_amp * 0.6 * k * sin(a * scallops * 0.5 - tt * 0.7);
	// Boyunca kıvrım
	VERTEX.x += ripple_amp * k * sin(h * ripple_freq - tt * 1.4 + a * 2.0);
	VERTEX.z += ripple_amp * 0.5 * k * cos(h * ripple_freq * 0.8 - tt * 1.1);
	// Geriye savrulma
	VERTEX.z -= trail * k * (1.0 + 0.25 * sin(tt * 0.6));
	v_h = h;
	v_da = fract(UV.x - face_angle) - 0.5;  // ön UV.x = 0.5 (ağın dikişi arkada)
}

float ellipse(vec2 p, vec2 c, vec2 s) {
	vec2 q = (p - c) / s;
	return dot(q, q);
}

void fragment() {
	float h = v_h;
	float da = v_da;
	// Etek ucu
	if (hem == 1) {
		float sc = 0.5 + 0.5 * cos(da * 6.28318 * scallops);
		if (h < hem_depth * (1.0 - sc)) {
			discard;
		}
	} else if (hem == 2) {
		float strip = floor((da + 0.5) * 22.0);
		float len = hem_depth * (0.3 + 1.7 * hash(strip + 3.0));
		if (h < len) {
			discard;
		}
	}
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	float a = mix(alpha_center, alpha_edge, fres);
	// Etek ucuna doğru incelir (kumaşın ucu saydamlaşır)
	a *= smoothstep(0.0, 0.18, h + 0.04);
	vec3 col = color.rgb;
	vec3 em = color.rgb * glow + rim_color.rgb * fres * 0.35;
	float front = FRONT_FACING ? 1.0 : 0.0;
	// Kukuleta: önde koyu oyuk
	if (hood > 0.0 && front > 0.5) {
		float f = ellipse(vec2(da, h), vec2(0.0, 0.7), vec2(0.13, 0.17));
		float m = 1.0 - smoothstep(0.75, 1.0, f);
		col = mix(col, hood_color.rgb, m);
		em = mix(em, vec3(0.0), m);
		a = mix(a, 0.97, m);
	}
	// Gözler
	if (eyes > 0.0 && front > 0.5) {
		float e = min(ellipse(vec2(da, h), vec2(-eye_pos.x, eye_pos.y), eye_size),
			ellipse(vec2(da, h), vec2(eye_pos.x, eye_pos.y), eye_size));
		float m = 1.0 - smoothstep(0.7, 1.0, e);
		col = mix(col, eye_color.rgb, m);
		em = mix(em, eye_color.rgb * eye_glow, m);
		a = mix(a, 1.0, m);
	}
	if (mouth > 0.0 && front > 0.5) {
		float e = ellipse(vec2(da, h), vec2(0.0, eye_pos.y - 0.15), vec2(0.035, 0.045));
		float m = 1.0 - smoothstep(0.7, 1.0, e);
		col = mix(col, eye_color.rgb, m);
		a = mix(a, 1.0, m);
	}
	if (holo > 0.0) {
		float scan = step(0.6, fract(h * 26.0 - t * 1.5));
		a = clamp(fres * 1.1 + scan * 0.12 + 0.05, 0.0, 1.0) * smoothstep(0.0, 0.15, h + 0.04);
		em = color.rgb * (0.15 + fres * 1.1 + scan * 0.45);
		col = color.rgb * 0.3;
	}
#ifdef BACK_FACE
	// İç yüz: örtünün içi, biraz daha koyu ve saydam
	col *= 0.82;
	em *= 0.6;
	a *= 0.7;
#endif
	// Ortamın (mercan) ışığı kumaşı fazla boyamasın: rengin çoğu kendinden ışık
	ALBEDO = col * 0.35;
	EMISSION = em;
	ALPHA = clamp(a, 0.0, 1.0);
}
