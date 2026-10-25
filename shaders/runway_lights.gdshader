shader_type spatial;
render_mode unshaded, cull_back;
// Pist ışıkları: yolun sonuna doğru akan kırmızı darbeler (uçak pisti gibi).
// Işıklar MultiMesh: her ışığın dünya z'si INSTANCE_CUSTOM.r'de; darbe ileri (-z) ilerler.

uniform vec4 color : source_color = vec4(1.0, 0.23, 0.18, 1.0);
uniform float spacing = 10.0;
uniform float speed = 2.2;

varying float light_z;

void vertex() {
	light_z = INSTANCE_CUSTOM.r;
}

void fragment() {
	float ph = fract(light_z / spacing + TIME * speed);
	float pulse = smoothstep(0.0, 0.08, ph) * (1.0 - smoothstep(0.18, 0.4, ph));
	ALBEDO = mix(color.rgb * 0.55, vec3(1.0, 0.9, 0.86), pulse * 0.75);
}
