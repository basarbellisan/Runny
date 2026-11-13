shader_type spatial;
// Düz dünya: fırlatma tünelinin yerine yolu izleyen saydam beyaz şerit.
// UV.x şeridin enine (0..1), UV.y boyuna (0 giriş, 1 son). Enine ince çizgiler eşit aralıklı;
// sona doğru solar, uzaktan (kırık parçalar gibi) yavaşça belirir.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform vec4 color : source_color = vec4(0.984, 0.98, 0.969, 1.0);
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 0.95);
uniform float alpha = 0.3;
// Şeridin boyu (m), çizgi aralığı ve kalınlığı (m)
uniform float length_m = 60.0;
uniform float gap = 4.0;
uniform float line_w = 0.22;
// Sona doğru solma: UV.y bu aralıkta
uniform vec2 fade = vec2(0.75, 1.05);
// Uzaktan belirme: [tam görünür, görünmez] (m)
uniform vec2 appear = vec2(205.0, 265.0);

void fragment() {
	float s = UV.y * length_m;
	float mark = step(fract(s / gap) * gap, line_w);
	vec3 c = mix(color.rgb, line_color.rgb, mark);
	float a = mix(alpha, line_color.a, mark);
	a *= 1.0 - smoothstep(fade.x, fade.y, UV.y);
	a *= 1.0 - smoothstep(appear.x, appear.y, length(VERTEX));
	ALBEDO = c;
	ALPHA = a;
}
