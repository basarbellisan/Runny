// Çakıl, delikten yükselen ışık sütunu (MultiMesh, eklemeli): dipte kuvvetli, yukarı doğru erir;
// boyu nefes alır gibi uzar/kısalır. INSTANCE_CUSTOM.xy = deliğin ızgara hücresi (gravel_holes ile
// aynı faz). Örnek silindir: yarıçap 0.5, boy 1, kapaksız; örnek dönüşümü yalnız yatay ölçek.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled, shadows_disabled;

// Uzakta sisle aynı mesafede söner (eklemeli parıltı sise karışamaz; game.gd _apply_fog)
global uniform float far_fog_begin;
global uniform float far_fog_end;

float far_fade(vec3 view_pos) {
	return 1.0 - smoothstep(far_fog_begin, far_fog_end, length(view_pos));
}

uniform vec4 light : source_color = vec4(0.18, 0.36, 1.0, 1.0);
uniform vec4 core : source_color = vec4(0.77, 0.83, 1.0, 1.0);
uniform float max_height = 1.6;
uniform float strength = 0.8;
uniform float t = 0.0;

varying float y01;
varying float bv;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float breath(vec2 ci) {
	return 0.5 + 0.5 * sin(t * 2.2 - ci.y * 0.55 + hash(ci) * 2.0);
}

void vertex() {
	bv = breath(INSTANCE_CUSTOM.xy);
	y01 = VERTEX.y + 0.5;
	VERTEX.y = y01 * max_height * mix(0.35, 1.0, bv);
}

void fragment() {
	// Hava/ışık: kenarlara doğru saydamlaşır (hacim hissi), yukarı doğru erir, dipte en güçlü
	float ndv = abs(dot(NORMAL, VIEW));
	float soft = pow(ndv, 2.6);
	float fade = pow(1.0 - y01, 2.2) + 0.6 * exp(-y01 * 14.0);
	vec3 col = mix(light.rgb, core.rgb, pow(1.0 - y01, 5.0) * 0.7);
	ALBEDO = col * fade * soft * strength * mix(0.55, 1.0, bv);
	ALBEDO *= far_fade(VERTEX);
}
