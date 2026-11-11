shader_type spatial;
render_mode depth_prepass_alpha;
// Düz dünya denemesi: dev (models/giants/giant.glb). Sahnenin ışığını (güneş ve ortam ışığı) alır,
// yüzleri ışığa göre açık-koyu; uzatılmış bacaklar aşağıya doğru erir
// (modelin kendi yüksekliğinde fade_from'da görünmez, fade_to'da tam). Bloklar gibi sise de erir.

uniform vec4 color : source_color = vec4(1.0);
uniform float fade_from = 0.0;
uniform float fade_to = 6.0;

varying float ly;

void vertex() {
	ly = VERTEX.y;
}

void fragment() {
	ALBEDO = color.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	ALPHA = smoothstep(fade_from, fade_to, ly);
}
