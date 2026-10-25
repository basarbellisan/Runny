shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Pist ışığının parlaması: kameraya dönük yuvarlak hale, yalnız ışık yanarken görünür.

uniform vec4 color : source_color = vec4(1.0, 0.16, 0.08, 1.0);
uniform float rate = 1.4;
uniform float band = 0.3;
// Oyunun kendi saati (RoadGenerator her karede yazar)
uniform float t = 0.0;

varying float along;

void vertex() {
	along = INSTANCE_CUSTOM.g;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

float lit(float a) {
	float head = fract(t * rate) * (1.0 + 2.0 * band) - band;
	return 1.0 - smoothstep(0.0, band, abs(a - head));
}

void fragment() {
	float p = lit(along);
	float r = length(UV - vec2(0.5)) * 2.0;
	float glow = clamp(1.0 - r, 0.0, 1.0);
	ALBEDO = mix(color.rgb, vec3(1.0, 0.45, 0.2), glow * glow * p);
	ALPHA = glow * p * 0.85;
}
