// Dağ silüeti: opak (arkasındaki güneşi örter), dibe doğru sis rengine erir.
// Köşe rengi alfası: 0 dipte, 1 yukarıda (Backdrop._ridge)
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

uniform vec4 color : source_color = vec4(0.3, 0.15, 0.4, 1.0);
uniform vec4 fog : source_color = vec4(0.57, 0.34, 0.64, 1.0);

void fragment() {
	ALBEDO = mix(fog.rgb, color.rgb, COLOR.a);
}
