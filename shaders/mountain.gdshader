// Dağ silüeti: dibe doğru sis rengine erir (köşe rengi alfası: 0 dipte, 1 yukarıda).
// Katmanlar arası geçişte alttan yükselen perdeyle silinir (backdrop_wipe).
// Derinlik yazar ve güneşten sonra çizilir: görünürken arkasında kalan güneşi örter.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_always;
#include "res://shaders/backdrop_wipe.gdshaderinc"

uniform vec4 color : source_color = vec4(0.3, 0.15, 0.4, 1.0);
uniform vec4 fog : source_color = vec4(0.57, 0.34, 0.64, 1.0);

void fragment() {
	ALBEDO = mix(fog.rgb, color.rgb, COLOR.a);
	ALPHA = 1.0 - wipe_low(VERTEX);
}
