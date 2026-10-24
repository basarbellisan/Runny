shader_type spatial;
render_mode unshaded;
// Yol kenarındaki kesik çizgi: dünya z'sine göre kesildiği için çizgiler
// yolla birlikte durur, araba hızlandıkça daha hızlı akar (hız referansı).

uniform vec4 color : source_color = vec4(1.0);
// Bir çizgi + bir boşluk uzunluğu (metre)
uniform float period = 6.0;
// Periyodun ne kadarı çizgi
uniform float duty = 0.5;

varying float world_z;

void vertex() {
	world_z = (MODEL_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	if (fract(world_z / period) > duty) {
		discard;
	}
	ALBEDO = color.rgb;
}
