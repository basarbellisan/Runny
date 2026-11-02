// Ortak perde: ekranın altından yükselen sınırın altında kalan kısım silinir.
// Ekrandaki yükseklik kamera uzayındaki yönden hesaplanır (gökyüzü ve dağlar aynı sonucu verir)
uniform float cover = 0.0;
uniform float soft = 0.22;
uniform float tan_half_fov = 0.6;

// v: kamera uzayında yön (z eksi ileri); 0 ekranın altı, 1 üstü
float wipe_h(vec3 v) {
	return (v.y / max(-v.z, 0.0001)) / tan_half_fov * 0.5 + 0.5;
}

float wipe_low(vec3 v) {
	float w = mix(-soft, 1.0 + soft, cover);
	return 1.0 - smoothstep(w - soft, w + soft, wipe_h(v));
}
