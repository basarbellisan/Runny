// Güneş diski ya da hale (radial: UV ortasından dışa sönen); alttan yükselen perdeyle silinir
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
#include "res://shaders/backdrop_wipe.gdshaderinc"

uniform vec4 color : source_color = vec4(1.0, 0.56, 0.5, 1.0);
uniform bool radial = false;

void fragment() {
	float a = color.a;
	if (radial) {
		float d = length(UV - vec2(0.5)) * 2.0;
		a *= clamp(1.0 - d, 0.0, 1.0) * mix(1.0, 0.55, smoothstep(0.0, 0.65, d));
	}
	ALBEDO = color.rgb;
	ALPHA = a * (1.0 - wipe_low(VERTEX));
}
