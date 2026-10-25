shader_type spatial;
render_mode unshaded, shadows_disabled;
// Pist ışığı noktası (MultiMesh). INSTANCE_CUSTOM.g: yoldaki yeri (0 baş, 1 yolun ucu),
// .b: uçtaki enine sıra. Bir darbe ışık dizisi boyunca hızla yolun ucuna koşar, döngü.

uniform vec4 color : source_color = vec4(1.0, 0.14, 0.08, 1.0);
uniform float rate = 2.6;

varying float along;

void vertex() {
	along = INSTANCE_CUSTOM.g;
}

float chase(float a) {
	float head = fract(TIME * rate) * 1.3;
	float d = head - a;
	return d >= 0.0 ? exp(-d * 10.0) : 0.0;
}

void fragment() {
	float p = chase(along);
	ALBEDO = mix(color.rgb * 0.85, vec3(1.0, 0.92, 0.88), p * 0.85);
}
