shader_type spatial;
render_mode unshaded, shadows_disabled;
// Düz dünya denemesi (FlatStyle): yolun gövdesi tek renk yüzlerle. Yan duvarlar bir renk, alt yüz
// ve ön/arka uçlar başka renk; ışık, gölge, degrade yok (sis yine uygulanır).

uniform vec4 side : source_color = vec4(1.0);
uniform vec4 under : source_color = vec4(0.07, 0.07, 0.08, 1.0);
uniform vec4 ends : source_color = vec4(0.07, 0.07, 0.08, 1.0);
uniform vec4 rim : source_color = vec4(1.0);

varying vec3 n_local;

void vertex() {
	n_local = NORMAL;
}

void fragment() {
	vec3 n = normalize(n_local);
	vec3 c = ends.rgb;
	if (abs(n.x) > 0.5) {
		c = side.rgb;
	} else if (n.y < -0.5) {
		c = under.rgb;
	} else if (n.y > 0.5) {
		c = rim.rgb;
	}
	ALBEDO = c;
}
