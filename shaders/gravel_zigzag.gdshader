// Çakıl, "kesik zikzak yarıklar" tasarımı: yere yatık düzlemde yatay zikzak sıraları; zikzağın her
// kolu ayrı bir yarık (köşelerde boşluk). Yarığın içi dipten ışıklı (ortası açık), kenarı koyu duvar;
// parlaklık üstündeki ışık perdesiyle aynı nabızda (gravel_curtain ile aynı faz).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 light : source_color = vec4(0.18, 0.36, 1.0, 1.0);
uniform vec4 core : source_color = vec4(0.77, 0.83, 1.0, 1.0);
// Yanan yarığın rengi (daha açık, doygun mavi)
uniform vec4 lit_color : source_color = vec4(0.42, 0.58, 1.0, 1.0);
// Nokta düzeninde ara ton (3 ve 2 numaralı noktalar bu tondan geçer)
uniform vec4 mid_color : source_color = vec4(0.30, 0.56, 1.0, 1.0);
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
// Nokta düzeni (düz dünya, hava alanı): petek dizilimli yuvarlak noktalar (sütun aralığı arm, sıra
// aralığı row_gap, yarıçap radius; sıralar sırayla çeyrek sütun sağa / sola kayık). Her nokta yukarı
// hava üfler; parlaklığı tam gücünü gösterir. Işık adım adım yana yürür (baş ve arkasında iki sönük
// nokta). Aynı formül RoadGenerator.air_at'te (fizik): parlaklık ve itiş hiç ayrışmaz
uniform bool dots = false;
// Işığın yürüme yönü (+1 soldan sağa, -1 sağdan sola) ve alanın tohumu (şimdilik kullanılmıyor)
uniform float dir = 1.0;
uniform int seed = 0;
// Seviyeler arası farkın katı (AirDifficulty "uneven"; büyüdükçe sönük noktalar daha az iter)
uniform float uneven = 1.0;

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

// --- Nokta düzeni: RoadGenerator.air_at ile birebir aynı hesap (değiştirirsen ikisini birlikte) ---
// Işık adım adım yürür (yumuşak değil): her STEP_TIME saniyede baş bir sütun ilerler. Her sırada üç
// nokta yanar: baş (1, en parlak), arkasında 2 ve 3 (daha sönük); kalanlar taban. Dört net seviye.
const float STEP_TIME = 0.17;
const float BASE = 0.6;

// Noktanın ışığı (0 taban, 1/3, 2/3, 1 baş)
float dot_light(float col, float row, float nx) {
	float xc = col + 0.5 + (mod(row, 2.0) < 0.5 ? 0.25 : -0.25);
	float L = nx + 4.0;
	float u = mod(floor(t / STEP_TIME), L) - 1.0;
	float rank = dir > 0.0 ? floor(u - xc + 0.5) : floor(xc - (nx - u) + 0.5);
	return (rank >= 0.0 && rank <= 2.0) ? 1.0 - rank / 3.0 : 0.0;
}

// Noktanın gücü: taban + ışığı kadar ("uneven" büyüdükçe taban düşer, seviyeler arası fark artar)
float dot_power(float col, float row, float nx) {
	float base = 1.0 - (1.0 - BASE) * uneven;
	return base + (1.0 - base) * dot_light(col, row, nx);
}

void fragment() {
	if (dots) {
		vec2 p = lp.xy;
		float W = counts.x * arm;
		float H = counts.y * row_gap;
		float row = clamp(floor((p.y + H * 0.5) / row_gap), 0.0, counts.y - 1.0);
		float off = (mod(row, 2.0) < 0.5 ? 0.25 : -0.25) * arm;
		float col = clamp(floor((p.x + W * 0.5 - off) / arm), 0.0, counts.x - 1.0);
		vec2 c = vec2((col + 0.5) * arm - W * 0.5 + off, (row + 0.5) * row_gap - H * 0.5);
		// Kenar yumuşatma uzaklığın ekrandaki değişimine göre (yere eğik bakışta nokta dikeyde basık;
		// yöne göre ayrı yumuşar, çevresine bulanık yüzey taşmaz)
		float dist = length(p - c);
		// Uzaklığın ekrandaki değişimi elle (fwidth sıra/sütun geçişinde sıçrar, ince çizgi bırakıyordu)
		vec2 n = (p - c) / max(dist, 0.0001);
		float w = max(abs(dot(n, dFdx(p))) + abs(dot(n, dFdy(p))), 0.002);
		float inside = 1.0 - smoothstep(radius - w, radius + w, dist);
		// Uzak dolgu yalnız noktalar iki yönde de pikselden küçükken (çok uzakta): ara mesafede noktalar kalır
		float fw = min(length(dFdx(p)), length(dFdy(p)));
		// Parlaklık = güç: taban koyu mavi, baş beyaza yakın açık mavi, 2 ve 3 arada (net tonlar)
		float k = dot_light(col, row, counts.x);
		// Ara tonlar doygun orta maviden geçer (koyu mavi ile beyazın düz karışımı soluk mor-gri olurdu)
		vec3 lit = k < 0.5 ? mix(light.rgb, mid_color.rgb, k * 2.0) : mix(mid_color.rgb, lit_color.rgb, (k - 0.5) * 2.0);
		float far = smoothstep(radius * 0.6, radius * 1.6, fw);
		ALBEDO = lit;
		// Noktalar seçilemeyecek kadar küçükken (çok uzakta) dolu, ışıklı mavi alan (koyulaşmasın)
		ALPHA = mix(inside, 0.8 + 0.2 * k, far);
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
