class_name Progress
extends RefCounted
## Oyuncunun birikimi: para, açılan arabalar ve her arabanın parça seviyeleri. Ayrı dosyada saklanır
## (user://progress.cfg); oyun kayıtlarından (save.cfg: seçili araba, rekor) bağımsız.
##
## Para oyun sonunda kazanılır: önce gidilen km, sonra depoda kalan kristal paraya dönüşür.
## Garajda harcanır: parça geliştirme (tekerlek, depo, kanat; her biri 5 seviye) ve kilitli arabalar.
## Geliştirmeler kalıcıdır, geri alınmaz.
##
## Deneme için: --coins=N (komut satırı) ya da ?coins=N (web) parayı o değere ayarlar.

const PATH := "user://progress.cfg"
## Başta açık temel arabalar (ağır, orta, hafif)
const BASIC := [2, 8, 7]
## Kilitli özel arabaların fiyatı
const CAR_PRICE := {6: 3000, 10: 6000, 9: 10000, 12: 15000}
## Parçalar: tekerlek (tutuş), depo (kristal kapasitesi), kanat (uçuş)
const PARTS := ["grip", "tank", "flight"]
const MAX_LEVEL := 5
## Parçanın bir sonraki seviyesinin fiyatı (seviye 0 -> 1: ilk değer)
const LEVEL_PRICE := [200, 400, 800, 1600, 3200]
## Oyun sonu: km başına ve depoda kalan kristal (enerji) başına para
const COIN_PER_KM := 100.0
const COIN_PER_CRYSTAL := 1.0

static var coins := 0
static var _owned := {}
static var _levels := {}
static var _loaded := false


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	coins = int(cfg.get_value("wallet", "coins", 0))
	for v in cfg.get_value("cars", "owned", []):
		_owned[int(v)] = true
	var lv: Dictionary = cfg.get_value("cars", "levels", {})
	for k in lv:
		_levels[int(k)] = (lv[k] as Dictionary).duplicate()
	var forced := _forced_coins()
	if forced >= 0:
		coins = forced


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("wallet", "coins", coins)
	cfg.set_value("cars", "owned", _owned.keys())
	cfg.set_value("cars", "levels", _levels)
	cfg.save(PATH)


static func get_coins() -> int:
	_ensure()
	return coins


static func owns(v: int) -> bool:
	_ensure()
	return v in BASIC or _owned.has(v)


static func car_price(v: int) -> int:
	return int(CAR_PRICE.get(v, 0))


## Parçanın seviyesi (0-5)
static func level(v: int, part: String) -> int:
	_ensure()
	return int((_levels.get(v, {}) as Dictionary).get(part, 0))


## Bir sonraki seviyenin fiyatı; en üst seviyedeyse -1
static func upgrade_price(v: int, part: String) -> int:
	var l := level(v, part)
	return -1 if l >= MAX_LEVEL else LEVEL_PRICE[l]


static func buy_upgrade(v: int, part: String) -> bool:
	var p := upgrade_price(v, part)
	if p < 0 or coins < p or not owns(v):
		return false
	coins -= p
	var d: Dictionary = _levels.get(v, {})
	d[part] = level(v, part) + 1
	_levels[v] = d
	save()
	return true


static func unlock(v: int) -> bool:
	_ensure()
	var p := car_price(v)
	if owns(v) or coins < p:
		return false
	coins -= p
	_owned[v] = true
	save()
	return true


## Oyun sonu kazancı: [km parası, kristal parası]
static func reward(meters: float, crystals: float) -> Array:
	var a := int(floor(maxf(meters, 0.0) / 1000.0 * COIN_PER_KM))
	var b := int(floor(maxf(crystals, 0.0) * COIN_PER_CRYSTAL))
	return [a, b]


## Parayı ekler ve hemen kaydeder (oyun sonu ekranı sayarken kapatılsa da kaybolmaz)
static func add(n: int) -> void:
	_ensure()
	coins += n
	save()


static func _forced_coins() -> int:
	var v := ""
	if OS.has_feature("web"):
		var r: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('coins') || ''")
		v = "" if r == null else str(r)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--coins="):
			v = a.get_slice("=", 1)
	return int(v) if v.is_valid_int() else -1
