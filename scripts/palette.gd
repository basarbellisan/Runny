class_name Palette
extends RefCounted
## Oyunun renkleri. Minimal, İskandinav: kırık beyazlar, griler, kömür
## ve tek bir vurgu rengi (turuncu: araba, portal, kritik uyarılar).

const PAPER := Color("f2f0eb")      # üst katman gökyüzü ve sis
const SNOW := Color("fbfaf7")       # en açık duvar
const MIST := Color("e2dfd8")
const STONE := Color("c9c5bd")
const ASPHALT := Color("2a2c30")    # yol yüzeyi
const GRAPHITE := Color("1c1e22")   # alt katman gökyüzü
const SLATE := Color("7c8087")      # alt katman kayaları (koyu zeminde seçilsin)
const INK_DARK := Color("232529")   # açık zeminde yazı
const INK_LIGHT := Color("f2f0eb")  # koyu zeminde yazı
const ACCENT := Color("ff5a1f")

const WALLS: Array[Color] = [SNOW, MIST, STONE]
## Enerji kristalleri (yolda ve alt katmanda) ve enerji göstergesi
const ENERGY := Color("9fe02a")

## Üst katmanın paletleri: yol boyunca bölge bölge (zone_length metrede bir) yumuşakça geçer.
## Gökyüzü degradesi, renkli sis (yolların altı ve dekor aşağıda sise karışır), renkli ışık,
## yol üstü / yan yüzü, şerit çizgisi, dekor ve yazı rengi (ink: göstergelerin yazısı)
const SKIES := [
	# Pembe-mor alacakaranlık
	{"name": "dusk",
		"sky_top": Color("2a1c50"), "sky_horizon": Color("8a4c9c"),
		"ground_horizon": Color("9c5aa6"), "ground_bottom": Color("c675cc"),
		"fog": Color("9256a2"), "fog_density": 0.0045, "fog_height": -6.0, "fog_height_density": 0.09,
		"ambient": Color("8c64b4"), "ambient_energy": 0.8, "sun": Color("ffe0ea"), "sun_energy": 0.75,
		"road_top": Color("3a2c4e"), "road_side": Color("c25c8e"), "line": Color("f6d8ee"),
		"decor": Color("7a4590"), "cloud": Color(0.78, 0.52, 0.82, 0.22), "ink": INK_LIGHT},
]
## Alt katman (uçuş): hep mercan; koyu erik rengi kayalar (3. görseldeki gibi)
const LOWER := {
	"sky_top": Color("f7c7b2"), "sky_horizon": Color("f2937e"),
	"ground_horizon": Color("ef8270"), "ground_bottom": Color("e6625a"),
	"fog": Color("f08976"), "fog_density": 0.006, "fog_height": -160.0, "fog_height_density": 0.03,
	"ambient": Color("f2a08e"), "ambient_energy": 0.9, "sun": Color("fff0e6"), "sun_energy": 0.8,
	"cloud": Color(0.96, 0.62, 0.55, 0.5), "ink": INK_DARK,
	"rocks": [Color("3f2639"), Color("4b2f45"), Color("5b3a52")],
}


## Mesafeye göre üst katman paleti: her bölge zone_length metre, sonundaki %20'de sıradakine geçer
static func sky_at(distance: float, zone_length: float) -> Dictionary:
	var f := maxf(distance, 0.0) / maxf(zone_length, 1.0)
	var i := int(f)
	var a: Dictionary = SKIES[i % SKIES.size()]
	var b: Dictionary = SKIES[(i + 1) % SKIES.size()]
	var t := smoothstep(0.8, 1.0, f - i)
	if t <= 0.0 or a == b:
		return a
	return blend(a, b, t)


## İki paletin karışımı (renk ve sayılar)
static func blend(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for k in a:
		var va: Variant = a[k]
		var vb: Variant = b.get(k, va)
		if va is Color or va is float:
			out[k] = lerp(va, vb, t)
		else:
			out[k] = va if t < 0.5 else vb
	return out
