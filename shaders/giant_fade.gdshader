shader_type spatial;
render_mode unshaded, shadows_disabled, depth_prepass_alpha;
// Düz dünya denemesi: dev (models/giants/giant.glb). Düz renk; uzatılmış bacaklar aşağıya doğru erir
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
	ALPHA = smoothstep(fade_from, fade_to, ly);
}
