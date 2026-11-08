// Hayaletin yüzü ve gözleri: ışıktan etkilenmez (çizimdeki kömür siyahı ve beyaz kalır);
// kameraya yaklaşınca örtüyle birlikte söner (ghost.gdshaderinc near_fade)
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_back, shadows_disabled;

uniform vec4 color : source_color = vec4(0.122, 0.118, 0.11, 1.0);
uniform vec2 near_fade = vec2(0.0, 0.0);

void fragment() {
	ALBEDO = color.rgb;
	float a = color.a;
	if (near_fade.y > 0.0) {
		a *= smoothstep(near_fade.x, near_fade.y, length(VERTEX));
	}
	ALPHA = a;
}
