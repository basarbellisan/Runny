// Arabanın küp (voksel) ikizi. Her küpün rengi arabanın o noktadaki rengi, arabayla aynı ışıkla
// çizilir. Hareket burada hesaplanır (işlemciye yük yok, her karede akıcı): küp kesme düzlemine
// varana kadar arabayla birlikte gizli gider (orada gerçek araba görünür), vardığı an (tr) tam
// yerinde belirir; ayrılma itkisiyle (INSTANCE_CUSTOM.xyz, gövdeye göre) açılır, sürüklenmeyle yavaşlar, hafifçe
// düşer, döner, küçülüp kaybolur. Bariyer hizasında (cut_z) kızgın parlar.
// Aynı hesap car.gd _shard_at içinde (kameranın takibi için).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, skip_vertex_transform;

// Kesilme anındaki gövde dönüşümü: küp verisi arabaya göre (yerel) ve önceden hazır
uniform mat4 body = mat4(1.0);
uniform float t = 0.0;
uniform vec3 v0 = vec3(0.0, 0.0, -30.0);
uniform float cut_z = -1e9;
uniform float life = 3.2;
uniform float drag = 1.2;
uniform float grav = 2.0;
// Ayrıldıktan sonra arabanın biçiminde birlikte gittiği süre (sn), sonra dağılır
uniform float hold = 0.0;
uniform vec4 cut_hot : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform float roughness = 0.6;

varying vec3 wpos;

vec3 hash3(float s) {
	return fract(sin(vec3(s * 127.1, s * 311.7, s * 74.7)) * 43758.5453);
}

mat3 rot(vec3 a, float ang) {
	float c = cos(ang);
	float s = sin(ang);
	float ic = 1.0 - c;
	return mat3(
		vec3(c + a.x * a.x * ic, a.y * a.x * ic + a.z * s, a.z * a.x * ic - a.y * s),
		vec3(a.x * a.y * ic - a.z * s, c + a.y * a.y * ic, a.z * a.y * ic + a.x * s),
		vec3(a.x * a.z * ic + a.y * s, a.y * a.z * ic - a.x * s, c + a.z * a.z * ic));
}

void vertex() {
	mat4 W = body * MODEL_MATRIX;
	vec3 p0 = W[3].xyz;
	mat3 B = mat3(W[0].xyz, W[1].xyz, W[2].xyz);
	// Ayrılma hızı: arabanın hızı + (gövdeye göre) itki; ileri hızın bir kesri korunur
	vec3 kw = mat3(body) * INSTANCE_CUSTOM.xyz;
	vec3 vr = v0 + kw;
	vr.z = (v0.z + kw.z) * INSTANCE_CUSTOM.w;
	float tr = v0.z < -0.01 ? max((cut_z - p0.z) / v0.z, 0.0) : 0.0;
	float age = t - tr;
	vec3 c = p0 + v0 * t;
	float sc = 0.0;
	mat3 R = mat3(1.0);
	if (age >= 0.0) {
		sc = clamp(1.0 - pow(age / life, 2.0), 0.0, 1.0);
		float a2 = age - hold;
		if (a2 > 0.0) {
			float e = exp(-drag * a2);
			c = p0 + v0 * (tr + hold) + vr * (1.0 - e) / drag;
			c.y += grav / drag * ((1.0 - e) / drag - a2);
			vec3 h = hash3(INSTANCE_CUSTOM.w * 911.0 + INSTANCE_CUSTOM.x * 37.0 + 1.0);
			vec3 ax = normalize(h * 2.0 - 1.0 + vec3(0.001));
			R = rot(ax, (4.0 + 8.0 * h.x) * a2);
		}
	}
	vec3 w = c + R * (B * VERTEX) * sc;
	wpos = w;
	VERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(R * normalize(B * NORMAL), 0.0)).xyz);
}

void fragment() {
	float d = abs(wpos.z - cut_z);
	float band = 1.0 - smoothstep(0.0, 0.09, d);
	float core = 1.0 - smoothstep(0.0, 0.03, d);
	ALBEDO = mix(COLOR.rgb, cut_hot.rgb, band);
	EMISSION = cut_hot.rgb * band * 3.0 + vec3(1.0, 0.92, 0.8) * core * 1.8;
	ROUGHNESS = roughness;
}
