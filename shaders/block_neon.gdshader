// Blok tasarımları (Tron havası): bloğun bütün gövdesi bu malzemeyle çizilir.
// Birim kutu ölçeklenerek kurulur (RoadGenerator._add_box); boyut MODEL_MATRIX'ten okunur,
// desenler metre cinsinden (blok genişliğinden bağımsız). Her yüz kendi düzleminde çizilir.
shader_type spatial;
render_mode unshaded;

// 0 ışık kafesi, 1 enerji duvarı, 2 ok (iki yana), 3 devre, 4 led matris, 5 neon tuğla
uniform int pattern = 0;
uniform vec4 c_main : source_color = vec4(1.0, 0.69, 0.0, 1.0);
uniform vec4 c_hot : source_color = vec4(1.0, 0.95, 0.7, 1.0);
uniform vec4 c_low : source_color = vec4(1.0, 0.42, 0.0, 1.0);
uniform vec4 c_dark : source_color = vec4(0.1, 0.06, 0.14, 1.0);
uniform float t = 0.0;

varying vec3 lp;
varying vec3 hs;
varying vec3 ln;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	hs = sc * 0.5;
	lp = VERTEX * sc;
	ln = NORMAL;
}

void fragment() {
	// Yüz düzlemi: u yatay, v dikey (ön/arka ve yanlar), tepede v = derinlik
	vec2 uv;
	vec2 half_uv;
	bool top = ln.y > 0.5;
	bool bottom = ln.y < -0.5;
	bool side = abs(ln.x) > 0.5;
	if (top || bottom) {
		uv = lp.xz;
		half_uv = hs.xz;
	} else if (side) {
		uv = lp.zy;
		half_uv = hs.zy;
	} else {
		uv = lp.xy;
		half_uv = hs.xy;
	}
	// Yüzün kenarına uzaklık (metre)
	float e = min(half_uv.x - abs(uv.x), half_uv.y - abs(uv.y));
	// Dikey yüzlerde 0 (dip) .. 1 (tepe)
	float k = (uv.y + half_uv.y) / (2.0 * half_uv.y);
	vec3 col = c_dark.rgb;

	if (pattern == 0) {
		// Işık kafesi: koyu gövde, parlayan kenar tüpleri, ince ızgara, yukarı süzülen tarama bandı
		vec2 g = abs(fract(uv / 0.3) - 0.5);
		float grid = step(0.46, max(g.x, g.y));
		col = mix(col, c_main.rgb, grid * 0.35);
		if (!top && !bottom) {
			float y = uv.y + half_uv.y;
			float band = fract(t * 0.45) * (2.0 * half_uv.y + 0.8) - 0.4;
			col += c_main.rgb * exp(-pow((y - band) * 7.0, 2.0)) * 0.55;
		}
		col = mix(col, c_main.rgb, smoothstep(0.075, 0.055, e));
		col = mix(col, c_hot.rgb, smoothstep(0.03, 0.015, e));
	} else if (pattern == 1) {
		// Enerji duvarı: dipte koyu turuncudan tepede açık sarıya ışık; yukarı akan tarama çizgileri
		if (top) {
			col = c_hot.rgb;
		} else {
			col = mix(c_low.rgb * 0.75, c_main.rgb, smoothstep(0.0, 0.75, k));
			col = mix(col, c_hot.rgb, smoothstep(0.8, 1.0, k));
			float s = step(0.72, fract((uv.y - t * 0.5) / 0.1));
			col *= 1.0 - 0.45 * s * (1.0 - k * 0.6);
		}
		col = mix(col, c_hot.rgb, smoothstep(0.035, 0.015, e));
	} else if (pattern == 2) {
		// İki yana oklar: ön yüzde ortadan dışa akan > > (sağda) ve < < (solda): "yanından geç"
		if (!top && !bottom && !side) {
			float f = abs(uv.x) + abs(uv.y) * 0.85;
			float s = step(0.5, fract(f / 0.42 - t * 1.4));
			col = mix(c_dark.rgb, c_main.rgb, s);
			// Ortada ince koyu ayraç
			col = mix(col, c_dark.rgb, step(abs(uv.x), 0.06));
		} else if (top) {
			col = c_main.rgb * 0.8;
		}
		col = mix(col, c_hot.rgb, smoothstep(0.05, 0.03, e));
	} else if (pattern == 3) {
		// Devre: koyu gövdede yatay iz yolları; izlerde akan ışık atımları, uçlarında lehim noktaları
		float row_h = 0.13;
		float row = floor(uv.y / row_h);
		float fy = abs(fract(uv.y / row_h) - 0.5);
		float seg_len = 0.36;
		float cell = floor(uv.x / seg_len);
		float fx = fract(uv.x / seg_len);
		float on = step(0.3, hash(vec2(row, cell + (top ? 37.0 : 0.0) + (side ? 71.0 : 0.0))));
		float trace = on * step(fy, 0.07) * step(0.08, fx) * step(fx, 0.92);
		float via = on * step(length(vec2((min(fx, 1.0 - fx) - 0.08) * seg_len, (fract(uv.y / row_h) - 0.5) * row_h)), 0.028);
		float dir = hash(vec2(row, 3.0)) < 0.5 ? -1.0 : 1.0;
		float pulse = step(fract(uv.x * 0.9 * dir + t * (0.8 + hash(vec2(row, 9.0))) + hash(vec2(row, 5.0))), 0.12);
		col = mix(col, c_main.rgb * 0.8, max(trace, via));
		col = mix(col, c_hot.rgb, trace * pulse);
		col = mix(col, c_main.rgb, smoothstep(0.05, 0.03, e));
	} else if (pattern == 4) {
		// Led matris: kare ledler, üzerinden çapraz bir parlaklık dalgası geçer
		float cs = 0.11;
		vec2 cell = floor(uv / cs);
		vec2 f = abs(fract(uv / cs) - 0.5);
		float led = step(max(f.x, f.y), 0.36);
		float w = pow(0.5 + 0.5 * sin(cell.x * 0.55 - cell.y * 0.45 + t * 5.0), 3.0);
		vec3 lc = mix(c_low.rgb * 0.55, c_main.rgb, w);
		lc = mix(lc, c_hot.rgb, smoothstep(0.85, 1.0, w));
		col = mix(c_dark.rgb, lc, led);
		col = mix(col, c_main.rgb, smoothstep(0.035, 0.02, e));
	} else {
		// Neon tuğla: içten yanan turuncu-sarı gövde, önde üç koyu yarık, üstten geçen parıltı
		col = mix(c_low.rgb, c_main.rgb, k);
		if (top) {
			col = c_main.rgb;
		}
		if (!top && !bottom && !side) {
			float slit = 0.0;
			for (int i = 0; i < 3; i++) {
				float yy = -half_uv.y + (float(i) + 1.0) * (2.0 * half_uv.y / 4.0);
				slit = max(slit, step(abs(uv.y - yy), 0.025) * step(abs(uv.x), half_uv.x - 0.12));
			}
			col = mix(col, c_dark.rgb, slit * 0.85);
		}
		float sweep = exp(-pow((uv.x + uv.y * 0.6) - (fract(t * 0.35) * (2.0 * half_uv.x + 3.0) - half_uv.x - 1.5), 2.0) * 6.0);
		col = mix(col, c_hot.rgb, sweep * 0.5);
		col = mix(col, c_hot.rgb, smoothstep(0.035, 0.015, e));
	}
	ALBEDO = col;
}
