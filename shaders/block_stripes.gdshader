// Blok ön yüzündeki ışıklı çapraz uyarı şeritleri (dünya konumuna göre, yüz boyutundan bağımsız)
shader_type spatial;
render_mode unshaded;

uniform vec4 color : source_color = vec4(1.0, 0.353, 0.122, 1.0);
uniform vec4 dark : source_color = vec4(0.11, 0.118, 0.133, 1.0);
uniform float width = 0.32;
uniform float t = 0.0;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float s = fract((wp.x + wp.y) / (width * 2.0) - t * 0.6);
	float on = step(0.5, s);
	ALBEDO = mix(dark.rgb, color.rgb, on);
}
