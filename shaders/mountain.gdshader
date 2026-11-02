// Dağ silüeti: dibe doğru sis rengine erir (köşe rengi alfası: 0 dipte, 1 yukarıda).
// alpha: katmanlar arası geçişte bütün dağ saydamlaşır (arkasındaki gök ne renkse ona erir).
// Derinlik yazar ve güneşten sonra çizilir: tam görünürken arkasında kalan güneşi örter.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_always;

uniform vec4 color : source_color = vec4(0.3, 0.15, 0.4, 1.0);
uniform vec4 fog : source_color = vec4(0.57, 0.34, 0.64, 1.0);
uniform float alpha = 1.0;

void fragment() {
	ALBEDO = mix(fog.rgb, color.rgb, COLOR.a);
	ALPHA = alpha;
}
