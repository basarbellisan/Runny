// Işık bariyerinde kesilme: arabanın bariyer düzlemini (dünya z = cut_z) geçen kısmı görünmez olur;
// kesik yüzeyde ince, kızgın bir kenar parlar. Arabanın kendi malzemesiyle aynı hesap (BaseMaterial3D).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness = 0.6;
uniform float metallic = 0.0;
uniform float specular = 0.5;
uniform float cut_z = -1e9;
uniform vec4 cut_hot : source_color = vec4(1.0, 0.5, 0.1, 1.0);

varying vec3 cut_wp;

void vertex() {
	cut_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float d = cut_wp.z - cut_z;
	if (d < 0.0) {
		discard;
	}
	float e = 1.0 - smoothstep(0.0, 0.07, d);
	ALBEDO = mix(albedo.rgb, cut_hot.rgb, e);
	EMISSION = cut_hot.rgb * e * 2.5;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = specular;
}
