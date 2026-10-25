shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Pist ışığının parlaması: kameraya dönük yuvarlak hale, darbe geçerken büyür.

uniform vec4 color : source_color = vec4(1.0, 0.18, 0.1, 1.0);
uniform float rate = 2.6;

varying float along;

void vertex() {
	along = INSTANCE_CUSTOM.g;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

float chase(float a) {
	float head = fract(TIME * rate) * 1.3;
	float d = head - a;
	return d >= 0.0 ? exp(-d * 10.0) : 0.0;
}

void fragment() {
	float p = chase(along);
	float r = length(UV - vec2(0.5)) * 2.0;
	float glow = clamp(1.0 - r / (0.55 + 0.45 * p), 0.0, 1.0);
	ALBEDO = mix(color.rgb, vec3(1.0, 0.55, 0.45), p * 0.6);
	ALPHA = glow * glow * (0.35 + 0.6 * p);
}
