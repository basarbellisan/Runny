// Çakıl, "kesik zikzak yarıklar" tasarımı: yere yatık düzlemde yatay zikzak sıraları; zikzağın her
// kolu ayrı bir yarık (köşelerde boşluk). Yarığın içi dipten ışıklı (ortası açık), kenarı koyu duvar;
// parlaklık üstündeki ışık perdesiyle aynı nabızda (gravel_curtain ile aynı faz).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 light : source_color = vec4(0.18, 0.36, 1.0, 1.0);
uniform vec4 core : source_color = vec4(0.77, 0.83, 1.0, 1.0);
// Yanan yarığın rengi (daha açık, doygun mavi)
uniform vec4 lit_color : source_color = vec4(0.42, 0.58, 1.0, 1.0);
// (kullanılmıyor) eski kenar rengi
uniform vec4 wall : source_color = vec4(0.09, 0.14, 0.45, 1.0);
// Yarıkların alana oranı (uzakta desen bu oranla ortalama bir ışıltıya döner)
uniform float coverage = 0.45;
// Kolun yatay boyu (yarım periyot), zikzak genliği, sıra aralığı
uniform float arm = 0.8;
uniform float amp = 0.32;
uniform float row_gap = 1.2;
uniform vec2 counts = vec2(8.0, 10.0);  // kol sayısı, sıra sayısı
uniform float radius = 0.135;
uniform float t0 = 0.2;
uniform float t1 = 0.8;
// Çaprazlama: tek sıralar bu kadar kol yana kayık (0 hizalı, 0.5 tuğla, 1 ters yönde)
uniform float shift = 0.0;
uniform float t = 0.0;
// Ok düzeni (düz dünya denemesi): zikzak yerine yan yana sütunlarda oklar; sol yarı sola (<), sağ
// yarı sağa (>) bakar. Sütun genişliği arm, sıra aralığı row_gap; okun yarı boyu amp. Nabız aynı
// (ortadan iki yana açılan dalga, sütun sütun)
uniform bool arrows = false;

varying vec3 lp;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Ortadan sola ve sağa açılan dalga: faz, yarığın alanın ortasına uzaklığına (kol sayısı) göre
float breath_side(float d) {
	float w = 0.5 + 0.5 * sin(t * 3.2 - d * 1.15);
	return w * w;
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

// Ok düzeni: en yakın okun kolu uzaklığı ve sütun no'su
vec2 arrow_dist(vec2 p) {
	float W = counts.x * arm;
	float H = counts.y * row_gap;
	float col = clamp(floor((p.x + W * 0.5) / arm), 0.0, counts.x - 1.0);
	float row = clamp(floor((p.y + H * 0.5) / row_gap), 0.0, counts.y - 1.0);
	float cx = (col + 0.5) * arm - W * 0.5;
	float cy = (row + 0.5) * row_gap - H * 0.5;
	// Yön: sütun ortanın solundaysa sola
	float dir = (col + 0.5 < counts.x * 0.5) ? -1.0 : 1.0;
	float half_w = arm * 0.32;
	vec2 tip = vec2(cx + dir * half_w, cy);
	vec2 a = vec2(cx - dir * half_w, cy + amp);
	vec2 b = vec2(cx - dir * half_w, cy - amp);
	// Kollar uçta birleşir, dış uçları biraz kısa (t0)
	float d = min(seg_dist(p, mix(a, tip, t0), tip), seg_dist(p, mix(b, tip, t0), tip));
	return vec2(d, col);
}

void fragment() {
	if (arrows) {
		vec2 ad = arrow_dist(lp.xy);
		float r = ad.x / radius;
		float fw = max(length(dFdx(lp.xy)), length(dFdy(lp.xy)));
		float aa = clamp(fw / radius, 0.02, 1.0);
		float inside = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, r);
		float b = breath_side(abs(ad.y + 0.5 - counts.x * 0.5));
		vec3 lit = mix(light.rgb, lit_color.rgb, b);
		float far = smoothstep(radius * 0.35, radius * 1.2, fw);
		ALBEDO = lit;
		// Desen pikselden küçükken (uzakta; yere yatık bakışta 30 m'de bile) ortalama kapsama değil, dolu
		// ve nabızlı parlak mavi alan (yoksa siyah yolla karışıp koyu laciverde dönüyordu)
		ALPHA = mix(inside, 0.8 + 0.2 * b, far);
	} else {
	float W = (counts.x + shift) * arm;
	float H = counts.y * row_gap;
	float row = floor((lp.y + H * 0.5) / row_gap);
	float yc = (row + 0.5) * row_gap - H * 0.5;
	float xo = shift * arm * mod(max(row, 0.0), 2.0);
	float xa = lp.x + W * 0.5 - xo;
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
	// Kenar yumuşatma: bir pikselin metre karşılığı kadar (uzakta yarıklar titremesin)
	float fw = max(length(dFdx(lp.xy)), length(dFdy(lp.xy)));
	float aa = clamp(fw / radius, 0.02, 1.0);
	float inside = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, r);
	float b = breath_side(abs(bi + 0.5 + xo / arm - (counts.x + shift) * 0.5));
	// Gölge ve gri yok: yarık düz, doygun mavi; yanınca daha açık maviye çıkar (koyulaşmaz).
	// Ortada hafif açık bir şerit (ışığın kaynağı), kenarda koyu halka yok.
	vec3 lit = mix(light.rgb, lit_color.rgb, b);
	vec3 col = mix(lit, mix(lit, lit_color.rgb, 0.5), (1.0 - smoothstep(0.0, 0.45, r)) * 0.6);
	// Uzakta (yarık birkaç pikselden küçük): desen yerine ortalama mavi ışıltı; nabız korunur
	float far = smoothstep(radius * 0.35, radius * 1.2, fw);
	vec3 avg = lit;
	ALBEDO = mix(col, avg, far);
	ALPHA = mix(inside, coverage, far);
}
}
