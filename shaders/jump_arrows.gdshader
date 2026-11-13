shader_type spatial;
render_mode unshaded, shadows_disabled, fog_disabled, depth_prepass_alpha;
// Düz dünya denemesi: yol sonundaki zıplama okları (MultiMesh). Pist ışıkları gibi yanıp söner:
// parlak bir bant oklar boyunca yolun ucuna akar. INSTANCE_CUSTOM.g: okun dizideki yeri
// (0 bölgenin başı, 1 yolun ucu).

uniform vec4 color : source_color = vec4(1.0, 0.12, 0.06, 1.0);
uniform vec4 lit_color : source_color = vec4(1.0, 0.42, 0.32, 1.0);
uniform float rate = 1.4;
uniform float band = 0.3;
// Sönük okun parlaklığı (rengin bu kadarı)
uniform float dim = 0.5;
// Oyunun kendi saati (RoadGenerator her karede yazar)
uniform float t = 0.0;
// Sis yerine kendi uzaklık solması (uzaktan da yanıp sönmesi görünsün): fade_far.y'de görünmez
uniform vec2 fade_far = vec2(330.0, 430.0);

varying float along;

float lit(float a) {
	float head = fract(t * rate) * (1.0 + 2.0 * band) - band;
	return 1.0 - smoothstep(0.0, band, abs(a - head));
}

void vertex() {
	along = INSTANCE_CUSTOM.g;
	// Yanan ok bir an büyür (patlar)
	VERTEX.xz *= 1.0 + 0.22 * lit(along);
}

void fragment() {
	ALBEDO = mix(color.rgb * dim, lit_color.rgb, lit(along));
	ALPHA = 1.0 - smoothstep(fade_far.x, fade_far.y, -VERTEX.z);
}
