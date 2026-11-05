// Çakıl, yarıktan yükselen ışık perdesi (MultiMesh, eklemeli): yarık boyunca uzanan dik düzlem;
// dipte kuvvetli, yukarı doğru erir, uçlarda yumuşakça biter; boyu nefes alır gibi uzar/kısalır.
// INSTANCE_CUSTOM.xy = yarığın (kol, sıra) hücresi (gravel_zigzag ile aynı faz).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec4 light : source_color = vec4(0.18, 0.36, 1.0, 1.0);
uniform vec4 core : source_color = vec4(0.77, 0.83, 1.0, 1.0);
uniform float max_height = 0.65;
uniform float strength = 0.38;
uniform float t = 0.0;

varying float y01;
varying float xl;
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
	xl = VERTEX.x;
	VERTEX.y = y01 * max_height * mix(0.35, 1.0, bv);
}

void fragment() {
	float ends = 1.0 - smoothstep(0.3, 0.5, abs(xl));
	float fade = pow(1.0 - y01, 3.2) + 0.7 * exp(-y01 * 16.0);
	vec3 col = mix(light.rgb, core.rgb, pow(1.0 - y01, 5.0) * 0.7);
	ALBEDO = col * fade * ends * strength * mix(0.55, 1.0, bv);
}
