// Işık bariyerinin arabayı taradığı parlak yatay şerit: bariyer hizasında, arabanın o kesitteki
// üst hattı boyunca. Her zaman görünsün diye derinlik testi yok (eklemeli parıltı).
shader_type spatial;
render_mode unshaded, blend_add, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec4 hot : source_color = vec4(1.0, 0.42, 0.0, 1.0);
uniform float strength = 1.0;

void fragment() {
	// UV.y: -1 (alt) .. 1 (üst) şeridin kalınlığı boyunca; UV.x: 0..1 uçlarda söner
	float v = abs(UV.y);
	float core = exp(-pow(v * 7.0, 2.0));
	float halo = exp(-pow(v * 2.2, 2.0));
	float ends = smoothstep(0.0, 0.06, UV.x) * smoothstep(1.0, 0.94, UV.x);
	vec3 col = hot.rgb * halo * 0.9 + vec3(1.0, 0.93, 0.82) * core * 1.2;
	ALBEDO = col * ends * strength;
}
