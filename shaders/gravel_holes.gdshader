// Çakıl, "delikten yükselen ışık" tasarımı: yere yatık düzlemde düzenli ızgarada yuvarlak delikler.
// Deliğin içinde dipte parlak ışık (ortada açık), kenarında koyu duvar. Parlaklık, üstündeki ışık
// sütunuyla aynı nabızda (gravel_beam ile aynı hash/faz). Birim düzlem ölçeklenerek kurulur.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 light : source_color = vec4(0.18, 0.36, 1.0, 1.0);
uniform vec4 core : source_color = vec4(0.77, 0.83, 1.0, 1.0);
uniform vec4 wall : source_color = vec4(0.05, 0.04, 0.10, 1.0);
uniform vec2 spacing = vec2(1.25, 1.25);
// 1: çapraz dizilim (her ikinci sıra yarım aralık kayık)
uniform float stagger = 0.0;
uniform vec2 counts = vec2(4.0, 20.0);
uniform float radius = 0.28;
uniform float t = 0.0;

varying vec3 lp;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Sütunun nefesi (0..1): yol boyunca ilerleyen yumuşak dalga, her delik biraz kendi fazında
float breath(vec2 ci) {
	return 0.5 + 0.5 * sin(t * 2.2 - ci.y * 0.55 + hash(ci) * 2.0);
}

void vertex() {
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	lp = VERTEX * sc;
}

void fragment() {
	// Düzlem: genişlik (counts.x + stagger/2) aralık, boy counts.y aralık; sıra = y yönünde
	float qy = (lp.y + counts.y * spacing.y * 0.5) / spacing.y;
	float row = floor(qy);
	float xo = stagger * 0.5 * mod(row, 2.0);
	float qx = (lp.x + (counts.x + 0.5 * stagger) * spacing.x * 0.5) / spacing.x - xo;
	vec2 ci = vec2(floor(qx), row);
	float in_grid = step(0.0, ci.x) * step(ci.x, counts.x - 1.0) * step(0.0, ci.y) * step(ci.y, counts.y - 1.0);
	vec2 f = (vec2(fract(qx), fract(qy)) - 0.5) * spacing;
	float r = length(f) / radius;
	float inside = 1.0 - smoothstep(0.93, 1.0, r);
	float b = breath(ci);
	// Ortada dipteki ışık (açık), dışa doğru mavi, kenarda gölgede kalan duvar
	vec3 glow = mix(core.rgb, light.rgb, smoothstep(0.0, 0.55, r)) * mix(0.55, 1.0, b);
	vec3 col = mix(glow, wall.rgb, smoothstep(0.62, 0.95, r));
	ALBEDO = col;
	ALPHA = inside * in_grid;
}
