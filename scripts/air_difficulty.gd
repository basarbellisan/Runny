class_name AirDifficulty
extends RefCounted
## Hava engelinin oyun ilerledikçe zorlaşması. Hava öbür engeller gibi "var / yok" değil: sürekli
## bir kuvvet, her hücrede ayrı güçte esiyor. Bu yüzden zorluk kademesiz artırılabilir.
##
## Seviye (level) 0 ile 1 arası: gidilen mesafe START_M'ye kadar 0, FULL_M'de 1 (arası yumuşak geçiş).
## Her ayar [başlangıç, en zor] değerleri arasında seviyeye göre kayar. Başlangıç değerleri bugünkü
## ayarlı hava (1 = değişmez). Şimdilik en zor değerler de buna yakın: zorlaşma az hissedilir;
## ileride karar verilince yalnız bu tablo değişir.
##
## Denemek için seviyeyi elle ver: ?hava=0.7 (web) ya da --hava=0.7 (komut satırı); 0 kolay, 1 en zor.

## Zorlaşmanın başladığı ve tamamlandığı mesafe (m). Oyunun genel zorlaşması (RoadGenerator.hard_from)
## 18 km'de başlıyor; hava ondan önce, yavaşça ağırlaşır
const START_M := 2000.0
const FULL_M := 18000.0

## Ayarlar: [başlangıç, en zor] (hepsi bugünkü değerin katı)
const KNOBS := {
	# Güç: kaldırma, burun kaldırma, yatırma, yana itme ve savurma kuvvetleri
	"power": [1.0, 1.15],
	# Fark: yanan ve sönük noktaların güç farkı (sönükler daha az iter; araba daha çok yatar ve savrulur)
	"uneven": [1.0, 1.25],
	# Tutuş: hava üstünde direksiyonun ne kadar dinlediği (küçüldükçe kaygan)
	"grip": [1.0, 0.9],
	# Yalpalama: havadan çıktıktan sonraki sağa sola sallanma
	"wobble": [1.0, 1.2],
}

static var level := 0.0
## Elle verilen seviye (deneme için); yoksa -1
static var forced: float = _read_forced()


## Her karede oyun çağırır: gidilen mesafeye göre seviye
static func update(distance: float) -> void:
	level = forced if forced >= 0.0 else smoothstep(START_M, FULL_M, distance)


## Ayarın şu anki değeri (bugünkü değerin katı)
static func k(knob: String) -> float:
	var v: Array = KNOBS[knob]
	return lerpf(float(v[0]), float(v[1]), level)


static func _read_forced() -> float:
	var v := ""
	if OS.has_feature("web"):
		var r: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('hava') || ''")
		v = "" if r == null else str(r)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hava="):
			v = a.get_slice("=", 1)
	return clampf(float(v), 0.0, 1.0) if v.is_valid_float() else -1.0
