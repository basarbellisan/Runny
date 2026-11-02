// Gökyüzü: üst katman ve alt katman degradeleri; aralarında ekranın altından yükselen yumuşak bir
// perde (cover 0: yalnız üst, 1: yalnız alt). Katmanlar arası geçişte üst gökyüzü alttan silinir.
shader_type sky;

uniform vec4 up_top : source_color;
uniform vec4 up_hor : source_color;
uniform vec4 up_bot : source_color;
uniform vec4 lo_top : source_color;
uniform vec4 lo_hor : source_color;
uniform vec4 lo_bot : source_color;
uniform float sky_curve = 0.3;
uniform float ground_curve = 0.3;
#include "res://shaders/backdrop_wipe.gdshaderinc"
// Kameranın dünya yönelimi (gökyüzü yönünü kamera uzayına çevirmek için)
uniform mat3 cam_basis = mat3(1.0);

vec3 grad(vec3 top, vec3 hor, vec3 bot, vec3 dir) {
	float v = acos(clamp(dir.y, -1.0, 1.0));
	if (dir.y >= 0.0) {
		float c = 1.0 - v / (PI * 0.5);
		return mix(hor, top, clamp(1.0 - pow(1.0 - c, 1.0 / sky_curve), 0.0, 1.0));
	}
	float c = (v - PI * 0.5) / (PI * 0.5);
	return mix(hor, bot, clamp(1.0 - pow(1.0 - c, 1.0 / ground_curve), 0.0, 1.0));
}

void sky() {
	vec3 u = grad(up_top.rgb, up_hor.rgb, up_bot.rgb, EYEDIR);
	vec3 l = grad(lo_top.rgb, lo_hor.rgb, lo_bot.rgb, EYEDIR);
	COLOR = mix(u, l, wipe_low(transpose(cam_basis) * EYEDIR));
}
