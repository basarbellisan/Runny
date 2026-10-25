shader_type spatial;
render_mode unshaded, shadows_disabled;
// Pist ışığı noktası (MultiMesh). INSTANCE_CUSTOM.g: yoldaki yeri (0 bölgenin başı,
// 1 yolun ucu). Parlak bir bant (ışıkların ~%20'si) dizi boyunca yolun ucuna akar,
// döngüyle tekrarlar. Sönükken küçük ve koyu kırmızı, yanarken iki kat büyük ve parlak
// kırmızı-turuncu (beyaz değil: yanındaki beyaz yol çizgisine karışmasın).

uniform vec4 color : source_color = vec4(1.0, 0.12, 0.06, 1.0);
uniform float rate = 1.4;
uniform float band = 0.3;
// Oyunun kendi saati (RoadGenerator her karede yazar)
uniform float t = 0.0;

varying float along;

float lit(float a) {
	float head = fract(t * rate) * (1.0 + 2.0 * band) - band;
	return 1.0 - smoothstep(0.0, band, abs(a - head));
}

void vertex() {
	along = INSTANCE_CUSTOM.g;
	VERTEX *= 1.0 + lit(along);
}



void fragment() {
	float p = lit(along);
	vec3 off = color.rgb * 0.45;
	vec3 on = vec3(1.0, 0.32, 0.12);
	ALBEDO = mix(off, on, p);
}
