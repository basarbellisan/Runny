shader_type spatial;
render_mode unshaded, shadows_disabled;
// Yol kristali (MultiMesh): kendi ekseninde döner, hafifçe süzülür. Yüzleri
// yöne göre açık-koyu turuncu: parlayan bir taş gibi okunur.

uniform vec4 color : source_color = vec4(1.0, 0.42, 0.1, 1.0);
uniform vec4 light : source_color = vec4(1.0, 0.86, 0.62, 1.0);
// Oyunun kendi saati (RoadGenerator her karede yazar)
uniform float t = 0.0;

varying vec3 n_local;

void vertex() {
	float phase = INSTANCE_CUSTOM.r * 6.2831;
	float a = t * 2.4 + phase;
	float c = cos(a);
	float s = sin(a);
	VERTEX = vec3(c * VERTEX.x + s * VERTEX.z, VERTEX.y, -s * VERTEX.x + c * VERTEX.z);
	NORMAL = vec3(c * NORMAL.x + s * NORMAL.z, NORMAL.y, -s * NORMAL.x + c * NORMAL.z);
	n_local = NORMAL;
	VERTEX.y += sin(t * 3.0 + phase) * 0.12;
}

void fragment() {
	float f = clamp(dot(normalize(n_local), normalize(vec3(0.45, 0.8, 0.4))), 0.0, 1.0);
	ALBEDO = mix(color.rgb, light.rgb, f * f * 0.85);
}
