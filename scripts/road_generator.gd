class_name RoadGenerator
extends Node3D
## Havada duran, birbirinden bağımsız duvar-yolları üretir.
## Her yeni yol, arabanın o anki hızı ve atlama fiziğine göre
## ulaşılabilir olacak şekilde yerleştirilir: gazsız ulaşılamaz, tam gazla ulaşılır.
##
## Yollar "kalıplar" hâlinde üretilir; kalıplar mesafe arttıkça açılır:
##  düz      – şimdiki gibi düz yollar
##  eğim     – hafif yokuş yukarı/aşağı tek yol
##  vadi     – yokuş aşağı, alçak yol, rampayla tekrar yukarı
##  merdiven – art arda alçalan basamaklar, sonra büyük rampa
##  rampa    – kısa rampa: kalkışta yukarı fırlatır, daha yüksek bir yola konulur
##  çıkmaz   – yanda alçak, geniş, davetkâr bir yol; devamı yok (uçuşa düşersin).
##             Ana yol her zaman yanında devam eder.
##  çatal    – yol ikiye ayrılır: alçak, geniş, kolay yol ya da rampayla çıkılan
##             dar, yüksek, zor yol (turuncu çizgili, puanı iki kat). İleride birleşir.

class Segment:
	var x: float
	var top: float       # yakın uçtaki (z_start) yükseklik
	var top_end: float   # uzak uçtaki (z_end) yükseklik
	var width: float
	var z_start: float   # yakın uç (büyük z)
	var z_end: float     # uzak uç (küçük z)
	var main: bool       # ana yol mu
	var dead_end := false
	## Çatalda yüksek (zor) yol: üstünde puan iki kat
	var bonus := false
	## Çatal kolu: 0 ortak yol, 1 alçak kol, 2 yüksek kol
	var route := 0
	## Hangi çatala ait (kol seçimi için)
	var fork_id := 0
	## Yol üstündeki engeller ve çakıl: { x0, x1, z0 (yakın), z1 (uzak), gravel }
	var obstacles: Array[Dictionary] = []
	## Yatık yol: z'ye göre yana yatma açısı (rad, artı = sağ kenar yukarı).
	## bank_z yakından uzağa sıralı; aradaki geçişler yumuşak (smoothstep).
	var bank_z := PackedFloat32Array()
	var bank_a := PackedFloat32Array()

	func bank_at(z: float) -> float:
		if bank_z.is_empty() or z >= bank_z[0]:
			return 0.0 if bank_z.is_empty() else bank_a[0]
		for i in range(1, bank_z.size()):
			if z >= bank_z[i]:
				var t := inverse_lerp(bank_z[i - 1], bank_z[i], z)
				return lerpf(bank_a[i - 1], bank_a[i], smoothstep(0.0, 1.0, t))
		return bank_a[bank_a.size() - 1]

	## Yüzeyin (x, z)'deki yüksekliği (yatık yolda kenarlar orta çizgiden farklı)
	func surface_y(px: float, z: float) -> float:
		return top_at(z) + (px - x) * tan(bank_at(z))

	## z_near..z_far arasında engel/çakıl yok mu
	func clear_between(z_near: float, z_far: float) -> bool:
		for o in obstacles:
			if o.z1 < z_near and o.z0 > z_far:
				return false
		return true
	var node: Node3D

	func contains(pos: Vector3, margin := 0.0) -> bool:
		return pos.z <= z_start and pos.z >= z_end \
			and absf(pos.x - x) <= width * 0.5 + margin

	## Eğim (tan): artı = ileri doğru yokuş yukarı
	func slope() -> float:
		return (top_end - top) / maxf(z_start - z_end, 0.01)

	func top_at(z: float) -> float:
		return lerpf(top, top_end, clampf((z_start - z) / maxf(z_start - z_end, 0.01), 0.0, 1.0))

	func max_top() -> float:
		return maxf(top, top_end)


## Ana seviye ve alçak seviye (yol üstü yüksekliği)
const MAIN_LEVEL := 0.0
const LOW_LEVEL := -9.0
## Duvarların dibi bu derinliğin altına inmez (bulut tabakası -42, uçuş -55)
const WALL_FLOOR := 36.0
## Yolların inebileceği en alçak seviye
const MIN_LEVEL := -18.0
## Bölge renkleri: her bölge_uzunluğu metrede bir yumuşakça değişir
const ZONES: Array[Color] = [
	Color("fbfaf7"), Color("b3c4a5"), Color("a5bccf"), Color("dcc8a6"), Color("9da7b1"),
]

@export var view_distance := 450.0
@export var cleanup_distance := 40.0
## Düz yollarda yükseklik bu bandın içinde kalır
@export var height_band := Vector2(-4.0, 4.0)
@export var min_width := Vector2(3.0, 5.0)    # (zor, kolay)
@export var max_width := Vector2(6.5, 10.0)   # (zor, kolay)
## Bu mesafeye (metre) gelince zorluk tavan yapar
@export var difficulty_distance := 3000.0
@export_range(0.0, 1.0) var side_road_chance := 0.3
## Boşluğun, gazsız ulaşılamayan en kısa ile tam gazla ulaşılan en uzun
## arasındaki yeri (0: az gaz yeter, 1: tam gaz şart)
@export var gap_difficulty := Vector2(0.1, 0.85)
## Kalıpların açıldığı mesafeler (m)
@export var slopes_from := 300.0
@export var ramps_from := 800.0
## Çıkmaz kalıbının seçilme ağırlığı (diğerleri ~0.5-1)
@export var dead_end_weight := 0.5
## Çatal kalıbının seçilme ağırlığı
@export var fork_weight := 0.6
## Yatık yollar (yana yatıp düzelen) bu mesafeden sonra gelir; ağırlık ve en fazla açı
@export var banks_from := 500.0
@export var bank_weight := 1.0
@export var max_bank_deg := 15.0
## Düz yollara engel (çarpınca patlar) ve çakıl (yavaşlatır) bu mesafeden sonra gelir
@export var obstacles_from := 350.0
## Düz bir yolun engelli olma olasılığı (zorlukla bu değere çıkar)
@export_range(0.0, 1.0) var obstacle_chance := 1.0
## Pist ışıkları: yolun sonundaki ışıklı bölgenin süresi (sn, o anki hızla)
@export var lights_time := 0.75
@export var max_slope_deg := 18.0
@export var zone_length := 1000.0

var car: Car
var segments: Array[Segment] = []
var _head: Segment
var _decor: Array[Node3D] = []
var _rng := RandomNumberGenerator.new()
var _unit_box := BoxMesh.new()
var _line_mat := ShaderMaterial.new()
var _ramp_line_mat := ShaderMaterial.new()
var _chevron_mat := StandardMaterial3D.new()
var _kerb_red := StandardMaterial3D.new()
var _kerb_white := StandardMaterial3D.new()
var _runway_mat := ShaderMaterial.new()
var _runway_halo_mat := ShaderMaterial.new()
var _block_mat := StandardMaterial3D.new()
var _block_top_mat := StandardMaterial3D.new()
var _gravel_mat := StandardMaterial3D.new()
var _stone_mat := StandardMaterial3D.new()
## Sıradaki ana yolların tarifi (kalıptan gelir)
var _plan: Array[Dictionary] = []
## Çıkmazdan sonra ana yol birkaç yol boyunca o taraftan uzaklaşır
var _avoid_side := 0.0
var _avoid_count := 0
## Hangi kalıpların üretildiği ve yükseklik/eğim aralığı (test/istatistik için)
var pattern_counts := {}
var stats := {"min_top": INF, "max_top": -INF, "max_slope_deg": 0.0, "dead_ends": 0, "ramps_up": 0}


func _ready() -> void:
	var dashed := preload("res://shaders/dashed_line.gdshader")
	_line_mat.shader = dashed
	_line_mat.set_shader_parameter("color", Palette.SNOW)
	_ramp_line_mat.shader = dashed
	_ramp_line_mat.set_shader_parameter("color", Palette.ACCENT)
	_chevron_mat.albedo_color = Palette.ACCENT
	_chevron_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_kerb_red.albedo_color = Color("e23c30")
	_kerb_red.roughness = 0.8
	_kerb_white.albedo_color = Palette.SNOW
	_kerb_white.roughness = 0.8
	_runway_mat.shader = preload("res://shaders/runway_dots.gdshader")
	_runway_halo_mat.shader = preload("res://shaders/runway_halo.gdshader")
	_block_mat.albedo_color = Palette.GRAPHITE
	_block_mat.roughness = 0.9
	_block_top_mat.albedo_color = Palette.ACCENT
	_block_top_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_gravel_mat.albedo_color = Color("8a7558")
	_gravel_mat.roughness = 1.0
	_stone_mat.albedo_color = Color("d6c7a8")
	_stone_mat.roughness = 1.0


func start(p_car: Car, seed_value := -1) -> void:
	car = p_car
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	# Başlangıç pisti: uzun ve geniş
	var z0 := car.global_position.z
	_head = _add_segment(0.0, MAIN_LEVEL, MAIN_LEVEL, 9.0, z0 + 15.0, z0 - 140.0, true)
	_fill(z0)


func update(car_pos: Vector3) -> void:
	_fill(car_pos.z)
	var limit := car_pos.z + cleanup_distance
	for i in range(segments.size() - 1, -1, -1):
		var s := segments[i]
		if s.z_end > limit:
			s.node.queue_free()
			segments.remove_at(i)
	for i in range(_decor.size() - 1, -1, -1):
		if _decor[i].position.z > limit + 60.0:
			_decor[i].queue_free()
			_decor.remove_at(i)


## Arabanın altındaki (üstüne konduğu) yol
func segment_under(pos: Vector3) -> Segment:
	for s in segments:
		# Araba gövdesi yokuşta eğilmez: düz kutu, eğimli yüzeye ön/arka köşesiyle
		# değer ve merkezi yüzeyin biraz üstünde kalır
		if s.contains(pos, 0.5) and absf(pos.y - s.surface_y(pos.x, pos.z)) < 0.6 + absf(s.slope()) * 2.2:
			return s
	return null


## Verilen z'nin önündeki (ileri, -z yönü) ana yollar, yakından uzağa
func main_segments_ahead(z: float) -> Array[Segment]:
	var out: Array[Segment] = []
	for s in segments:
		if s.main and s.z_end < z:
			out.append(s)
	return out


## Yolları en az verilen z'ye kadar üret
func generate_until(z: float) -> void:
	while _head.z_end > z:
		_head = _next_from(_head)


## Tam gazın hızı; hesapta %90 gaz alınır (roket bir an erken/geç basılsa da yetsin)
func _v_boost(v: float) -> float:
	return v + 0.9 * minf(v * car.boost_bonus, car.boost_max_extra)


## Arabanın dist_ahead metre ileride ulaşacağı tahmini hız
func estimate_speed(dist_ahead: float) -> float:
	return clampf(car.speed + car.acceleration * dist_ahead / maxf(car.speed, 1.0),
		car.start_speed, car.max_speed)


## Ana yolun verilen z'deki x konumu (boşluklarda iki yol arası)
func path_x_at(z: float) -> float:
	generate_until(z - 1.0)
	var prev: Segment = null
	for s in segments:
		if not s.main:
			continue
		if z <= s.z_start and z >= s.z_end:
			return s.x
		if z > s.z_start:
			if prev == null:
				return s.x
			return lerpf(prev.x, s.x, inverse_lerp(prev.z_end, s.z_start, z))
		prev = s
	return _head.x


## z civarında inilebilecek ana yolu bulur. Yolun başından en az margin_start,
## sonundan en az margin_end içeride kalan bir iniş noktası döndürür:
## { "seg": Segment, "z": float }
func find_landing(z: float, margin_start := 12.0, margin_end := 25.0) -> Dictionary:
	# Uygun yol bulunana kadar ileriye doğru yol üretmeye devam et
	var horizon := z - 250.0
	while horizon > z - 2000.0:
		generate_until(horizon)
		for s in segments:
			if not s.main:
				continue
			var near := s.z_start - margin_start
			var far := s.z_end + margin_end
			if near <= far or far > z:
				continue
			# Engelli yolda: inişten sonra ~45 m boş olan, istenen yere en yakın nokta
			var want := minf(z, near)
			for k in 40:
				var land := want + (k + 1) / 2 * 5.0 * (1.0 if k % 2 == 1 else -1.0)
				if land > near or land < far:
					continue
				if s.clear_between(land + 3.0, land - 45.0):
					return {"seg": s, "z": land}
		horizon -= 250.0
	return {}


## z_near..z_far arasında, x'in her yoldan en az margin uzakta olup olmadığı
func is_clear(x: float, z_near: float, z_far: float, margin: float) -> bool:
	for s in segments:
		if s.z_end > z_near or s.z_start < z_far:
			continue
		if absf(x - s.x) < s.width * 0.5 + margin:
			return false
	return true


## z_near..z_far arasındaki en yüksek yol üstü
func max_top_between(z_near: float, z_far: float) -> float:
	var top := -INF
	for s in segments:
		if s.z_end > z_near or s.z_start < z_far:
			continue
		top = maxf(top, s.max_top())
	return top


func _fill(car_z: float) -> void:
	generate_until(car_z - view_distance)


# --------------------------------------------------------------------------
# Kalıplar
# --------------------------------------------------------------------------

## Sıradaki kalıbı seçip tarifini plana ekler. Tarif anahtarları:
##  dh       – önceki yolun sonuna göre başlangıç yüksekliği farkı (yoksa serbest)
##  up       – ulaşılabilen en yüksek basamak (rampa sonrası)
##  rise     – yolun kendi eğimiyle yükselmesi (eksi: yokuş aşağı)
##  rise_to  – yolun sonu bu yüksekliğe çıksın (rampa)
##  len      – uzunluk çarpanı, width – genişlik çarpanı
##  dead_end – bu yolun yanına bir çıkmaz yol ekle
func _plan_pattern(travelled: float, level: float) -> void:
	# Yükseklik sınırlı kalsın: alçaktayken inen, yüksekteyken çıkan kalıp yok
	var low := level < MAIN_LEVEL - 3.0
	var high := level > MAIN_LEVEL + 3.0
	var flat := 1.0 if travelled < slopes_from else (0.9 if travelled < ramps_from else 1.1)
	var options := [["düz", flat]]
	if travelled > slopes_from:
		options.append(["eğim", 0.6])
		if not low:
			options.append(["vadi", 0.6])
	if travelled > ramps_from:
		if not low:
			options += [["merdiven", 0.5], ["çıkmaz", dead_end_weight]]
		if not low and not high:
			options.append(["çatal", fork_weight])
	if travelled > banks_from:
		options.append(["yatık", bank_weight])
		if not high:
			options.append(["rampa", 0.5])
	var total := 0.0
	for o in options:
		total += o[1]
	var pick := _rng.randf() * total
	var kind: String = options[0][0]
	for o in options:
		pick -= o[1]
		if pick <= 0.0:
			kind = o[0]
			break
	pattern_counts[kind] = int(pattern_counts.get(kind, 0)) + 1
	match kind:
		"düz":
			for i in _rng.randi_range(1, 3):
				_plan.append({})
		"eğim":
			var dir := -1.0 if _rng.randf() < 0.5 else 1.0
			if low: dir = 1.0
			elif high: dir = -1.0
			_plan.append({"angle": dir * _rng.randf_range(10.0, 15.0), "len": 0.6})
		"vadi":
			_plan.append({"dh": _rng.randf_range(-1.5, -0.5), "angle": -_rng.randf_range(12.0, 16.0), "len": 0.5})
			_plan.append({"dh": _rng.randf_range(-2.0, -0.5), "width": 1.1})
			_plan.append({"dh": _rng.randf_range(-0.6, 0.0), "rise_to": MAIN_LEVEL + _rng.randf_range(-1.0, 1.0), "len": 0.4})
		"merdiven":
			for i in _rng.randi_range(2, 3):
				_plan.append({"dh": -_rng.randf_range(2.5, 3.5)})
			_plan.append({"dh": _rng.randf_range(-0.6, 0.0), "rise_to": MAIN_LEVEL + _rng.randf_range(-1.0, 1.0), "len": 0.4})
		"rampa":
			_plan.append({"angle": _rng.randf_range(15.0, 18.0), "len": 0.35})
			_plan.append({"up": true})
		"çıkmaz":
			_plan.append({"dead_end": true, "len": 1.4})
			_plan.append({})
		"yatık":
			var dir := -1.0 if _rng.randf() < 0.5 else 1.0
			_plan.append({"bank": dir * _rng.randf_range(0.75, 1.0) * max_bank_deg,
				"s_curve": _rng.randf() < 0.4})
		"çatal":
			# Önce geniş bir yol: iki kola da buradan atlanır
			_plan.append({"width": 1.6, "len": 0.8, "dh": _rng.randf_range(-1.0, 0.0)})
			_plan.append({"fork": true})


func _next_from(prev: Segment) -> Segment:
	var dist_ahead := car.global_position.z - prev.z_end
	var travelled := -prev.z_end
	var difficulty := clampf(travelled / difficulty_distance, 0.0, 1.0)
	if _plan.is_empty():
		_plan_pattern(travelled, prev.top_end)
	var spec: Dictionary = _plan.pop_front()
	if spec.get("fork", false):
		var merge := _add_fork(prev)
		if merge:
			return merge
		spec = {}

	# Araba bu yolun sonuna vardığında ne hızda olacak (tahmini)
	var v := estimate_speed(dist_ahead)
	var v_boost := _v_boost(v)
	# Kalkış: yolun sonundaki küçük zıplama + eğimin verdiği dikey hız
	var slope := prev.slope()
	var vy := car.launch_velocity + v * slope
	var vy_b := car.launch_velocity + v_boost * slope
	var max_up := maxf(vy, 0.0) * maxf(vy, 0.0) / (2.0 * car.gravity) * 0.6

	var dh: float
	if spec.has("dh"):
		dh = spec.dh
	elif spec.has("up"):
		dh = max_up * _rng.randf_range(0.6, 0.9)
	else:
		# Düz yollar: ana seviyeye doğru geri dön
		var level := prev.top_end
		if level < MAIN_LEVEL + height_band.x:
			dh = _rng.randf_range(0.0, max_up)
		elif level > MAIN_LEVEL + height_band.y:
			dh = _rng.randf_range(-3.0, 0.0)
		else:
			dh = _rng.randf_range(-2.0, max_up)
	dh = minf(dh, max_up)
	# Aşağı doğru kalkıyorsak (yokuş aşağının sonu) yeni yol biraz alçakta olmalı
	if vy < 2.0:
		dh = minf(dh, -2.0)

	# Araba, arka ucu yoldan çıkınca havalanır; o anda ön ucu kenardan
	# bir araba boyu ileridedir. Boşluk, gazsız ulaşılamayacak (ön yüze
	# çakılır) ama tam gazla iniş yolun üstüne denk gelecek şekilde seçilir.
	var car_len := car.half_length * 2.0
	# Kısa, dik bir yolda gaz tam dolmayabilir (tepede araba havalanır,
	# gaz havada artmaz): eğimli yolun sonrasındaki boşluğu yarım gazla hesapla
	var sloped := absf(slope) > 0.1
	var v_reach := lerpf(v, v_boost, 0.5) if sloped else v_boost
	var vy_reach := car.launch_velocity + v_reach * slope
	var gaps := _gap_window(dh, v, v_reach, vy, vy_reach, car_len)
	if gaps.y < gaps.x:
		dh = minf(dh, -1.0)
		gaps = _gap_window(dh, v, v_reach, vy, vy_reach, car_len)
	# Eğimden sonra pencere dar kalırsa yeni yolu alçalt: uçuş uzar, pencere açılır
	while sloped and gaps.y - gaps.x < 4.0 and prev.top_end + dh > MIN_LEVEL + 1.0:
		dh -= 1.0
		gaps = _gap_window(dh, v, v_reach, vy, vy_reach, car_len)
	var hard := gap_difficulty.y if not sloped else lerpf(gap_difficulty.x, gap_difficulty.y, 0.5)
	# Eğimli yola erken inilsin ki üstünde hizalanıp gaz verecek yol kalsın
	var angled := spec.has("angle") or spec.has("rise_to")
	if angled:
		hard = gap_difficulty.x
	var gap := lerpf(gaps.x, maxf(gaps.y, gaps.x),
		_rng.randf_range(gap_difficulty.x, maxf(gap_difficulty.x, hard)))

	var width := _rng.randf_range(
		lerpf(min_width.y, min_width.x, difficulty),
		lerpf(max_width.y, max_width.x, difficulty)) * float(spec.get("width", 1.0))
	# Havada sağa sola ne kadar kayabiliriz
	var t := _flight_time(dh, vy_b)
	var reach := car.steer_speed * t * car.air_control
	var max_dx := prev.width * 0.5 + reach * 0.6
	var dx := _rng.randf_range(-max_dx, max_dx)
	var main_side := -1.0 if _rng.randf() < 0.5 else 1.0
	if spec.get("dead_end", false):
		# Çıkmaza yer aç: ana yol bir yana kayar, çıkmaz diğer yanda olur
		dx = main_side * _rng.randf_range(0.5, 0.8) * max_dx
	elif angled:
		dx = _rng.randf_range(-1.0, 1.0) * minf(max_dx, prev.width * 0.3)
	elif _avoid_count > 0:
		# Çıkmazın olduğu taraftan uzaklaş: çıkmazdan düşen araba ana yola çarpmasın
		dx = -_avoid_side * _rng.randf_range(0.0, max_dx)
		_avoid_count -= 1
	var length := _rng.randf_range(40.0, 100.0) * (v / car.start_speed) * float(spec.get("len", 1.0))
	# Düz, geniş yollar bazen engelli olur: sağ-sol oynanacak yer için uzar
	var banked: bool = spec.has("bank")
	var plain: bool = not (banked or spec.has("angle") or spec.has("rise_to") or spec.has("rise") or spec.get("dead_end", false))
	var with_obstacles: bool = plain and travelled > obstacles_from and width >= 5.5 \
		and _rng.randf() < obstacle_chance * clampf(0.5 + difficulty, 0.0, 1.0)
	if with_obstacles:
		length = maxf(length * 2.0, v * 8.0)

	# Tam roketle bile yolun üstüne inilsin, yolu aşıp gidilmesin
	var v_full := v + minf(v * car.boost_bonus, car.boost_max_extra)
	var vy_full := car.launch_velocity + v_full * slope
	var land_far := car_len + v_full * _flight_time(dh, vy_full) - gap
	length = maxf(length, land_far + v * 1.2)

	var top := maxf(prev.top_end + dh, MIN_LEVEL)
	var rise: float = spec.get("rise", 0.0)
	var max_tan := tan(deg_to_rad(max_slope_deg))
	if spec.has("angle"):
		# İstenen açıda eğim. Yol, inişten sonra hizalanıp gaz verecek kadar
		# uzun olmalı (~1.4 sn); yükseklik değişimi 11 m'yi geçerse açı yumuşar.
		var tn := minf(tan(deg_to_rad(absf(spec.angle))), max_tan)
		length = maxf(length, v * 1.4 + 8.0)
		rise = signf(spec.angle) * minf(length * tn, 10.0 if spec.angle > 0.0 else 9.0)
	if spec.has("rise_to"):
		rise = spec.rise_to - top
		length = maxf(length, v * 1.4 + 8.0)
	# Yokuş aşağı en dibe kadar inmesin: sonraki boşluk için alçalma payı kalsın
	rise = clampf(rise, MIN_LEVEL + (4.0 if rise < 0.0 else 0.0) - top, MAIN_LEVEL + 6.0 - top)
	# Eğim sınırı: gerekirse yolu uzat
	length = maxf(length, absf(rise) / max_tan)

	var z_start := prev.z_end - gap
	var seg: Segment
	if banked:
		# Yatık yol: düz başlar (iniş), bükülür, düzelir; sonu düz (pist ışıkları + roket)
		var flat_in := 10.0
		var flat_out := clampf(v * lights_time, 14.0, 48.0) + v * 0.8
		length = maxf(length, flat_in + flat_out + v * 3.0)
		rise = 0.0
		var a := deg_to_rad(spec.bank)
		var t0 := z_start - flat_in
		var t1 := z_start - length + flat_out
		var m := t0 - t1
		var pts: Array = [[z_start, 0.0], [t0, 0.0]]
		if spec.get("s_curve", false):
			pts += [[t0 - m * 0.25, a], [t0 - m * 0.4, a], [t0 - m * 0.6, -a], [t0 - m * 0.75, -a]]
		else:
			pts += [[t0 - m * 0.3, a], [t0 - m * 0.7, a]]
		pts += [[t1, 0.0], [z_start - length, 0.0]]
		seg = _add_banked_segment(prev.x + dx, top, width, z_start, z_start - length, pts)
	else:
		seg = _add_segment(prev.x + dx, top, top + rise, width, z_start, z_start - length, true)
	if with_obstacles and absf(rise) < 0.01:
		_add_obstacles(seg, v)

	if spec.get("dead_end", false):
		_add_dead_end(prev, seg, -main_side, v, vy_b)
	elif _rng.randf() < side_road_chance:
		_add_side_road(seg)
	_add_decor(seg)
	return seg


## (en kısa, en uzun) boşluk: gazsız ulaşılamaz, tam gazla iniş yolun en az 2.5 m içinde
func _gap_window(dh: float, v: float, v_boost: float, vy: float, vy_b: float, car_len: float) -> Vector2:
	var lo := car_len + v * _flight_time(dh, vy) + 1.5
	if dh > 0.0:
		# Yukarı basamak: tam gazla bile ön uç, araba yeterince yükselmeden yola varmasın
		lo = maxf(lo, car_len + v_boost * _rise_time(dh, vy_b) + 1.0)
	var hi := car_len + v_boost * _flight_time(dh, vy_b) - 2.5
	return Vector2(lo, hi)


## Kalkıştan (dikey hız vy), dh yüksekliğine inene kadar geçen süre
func _flight_time(dh: float, vy: float) -> float:
	var g := car.gravity
	return (vy + sqrt(maxf(vy * vy - 2.0 * g * dh, 0.0))) / g


## Kalkıştan dh yüksekliğine çıkana kadar geçen süre (dh > 0)
func _rise_time(dh: float, vy: float) -> float:
	var g := car.gravity
	return (vy - sqrt(maxf(vy * vy - 2.0 * g * dh, 0.0))) / g


## Çatal: önceki yolun sonundan iki kol ayrılır, ikisi de dümdüz gider ve
## ileride geniş bir yolda birleşir (her kolun sonundan dümdüz atlayınca
## birleşme yoluna inilir). Birleşme yolunu döndürür; yer yoksa null.
##  alçak kol: iki geniş yol, kolay boşluklar
##  yüksek kol: rampa, rampadan fırlayıp konulan dar yüksek yol, zor boşluklu
##              bir dar yol daha. Turuncu çizgili; üstünde puan iki kat.
func _add_fork(prev: Segment) -> Segment:
	var v := estimate_speed(car.global_position.z - prev.z_end)
	var reach := car.steer_speed * _flight_time(-2.0, car.launch_velocity) * car.air_control
	var off := minf(prev.width * 0.5 + reach * 0.6, 5.5)
	if off < 4.0 or prev.top_end < MIN_LEVEL + 8.0:
		return null
	var low_side := -1.0 if _rng.randf() < 0.5 else 1.0
	var x_l := prev.x + low_side * off
	var x_h := prev.x - low_side * off

	# Alçak kol
	var plan_l: Array[Dictionary] = []
	var top := prev.top_end
	var z := prev.z_end
	var slope := prev.slope()
	for i in 2:
		var r := _pick_gap(slope, -_rng.randf_range(2.0, 3.0) if i == 0 else -_rng.randf_range(0.5, 1.5),
			v, Vector2(0.05, 0.3))
		top += r.dh
		var zs: float = z - r.gap
		var ze := zs - maxf(v * _rng.randf_range(1.8, 2.4), r.min_len)
		plan_l.append({"x": x_l, "top": top, "end": top, "w": _rng.randf_range(7.0, 8.5), "zs": zs, "ze": ze})
		z = ze
		slope = 0.0

	# Yüksek kol: rampa
	var plan_h: Array[Dictionary] = []
	top = prev.top_end
	z = prev.z_end
	var r := _pick_gap(prev.slope(), _rng.randf_range(-1.0, 0.0), v, Vector2(0.2, 0.45))
	top += r.dh
	var ramp_len := maxf(v * 1.4 + 8.0, r.min_len)
	var rise := minf(ramp_len * tan(deg_to_rad(minf(16.0, max_slope_deg))), 9.0)
	var zs: float = z - r.gap
	plan_h.append({"x": x_h, "top": top, "end": top + rise, "w": _rng.randf_range(4.2, 5.0), "zs": zs, "ze": zs - ramp_len})
	z = zs - ramp_len
	top += rise
	slope = rise / ramp_len
	# Rampadan fırlayıp konulan yüksek dar yol, sonra zor boşluklu bir dar yol daha
	var vy := car.launch_velocity + v * slope
	var max_up := vy * vy / (2.0 * car.gravity) * 0.6
	for i in 2:
		var dh := max_up * _rng.randf_range(0.5, 0.8) if i == 0 else _rng.randf_range(-1.5, 0.3)
		r = _pick_gap(slope, dh, v, Vector2(0.15, 0.4) if i == 0 else Vector2(0.45, 0.8))
		top += r.dh
		zs = z - r.gap
		var ze := zs - maxf(v * _rng.randf_range(1.5, 1.9), r.min_len)
		plan_h.append({"x": x_h, "top": top, "end": top, "w": _rng.randf_range(3.3, 4.2), "zs": zs, "ze": ze})
		z = ze
		slope = 0.0

	# Birleşme: iki kolun da altında, ikisinin sonundan da dümdüz atlanınca inilen geniş yol
	var end_l: Dictionary = plan_l.back()
	var end_h: Dictionary = plan_h.back()
	var car_len := car.half_length * 2.0
	var v_boost := _v_boost(v)
	var m_top := minf(end_l.end, end_h.end) - _rng.randf_range(1.5, 3.0)
	var g_l := 0.0
	var g_h := 0.0
	for attempt in 6:
		var w_l := _gap_window(m_top - end_l.end, v, v_boost, car.launch_velocity, car.launch_velocity, car_len)
		var w_h := _gap_window(m_top - end_h.end, v, v_boost, car.launch_velocity, car.launch_velocity, car_len)
		g_l = lerpf(w_l.x, w_l.y, _rng.randf_range(0.1, 0.3))
		g_h = lerpf(w_h.x, w_h.y, _rng.randf_range(0.1, 0.3))
		if w_l.y - w_l.x > 2.0 and w_h.y - w_h.x > 2.0:
			break
		m_top -= 1.0
	m_top = maxf(m_top, MIN_LEVEL)
	var m_start := minf(end_l.ze - g_l, end_h.ze - g_h)
	# Erken biten kolun son yolu uzar: iki boşluk da kendi penceresinde kalır
	end_l.ze = m_start + g_l
	end_h.ze = m_start + g_h

	var fork_id := int(stats.get("forks", 0)) + 1
	for p in plan_l:
		var seg := _add_segment(p.x, p.top, p.end, p.w, p.zs, p.ze, true)
		seg.route = 1
		seg.fork_id = fork_id
	for p in plan_h:
		var seg := _add_segment(p.x, p.top, p.end, p.w, p.zs, p.ze, true, true)
		seg.route = 2
		seg.fork_id = fork_id
	var m_w := absf(x_l - x_h) + maxf(end_l.w, end_h.w)
	var v_full := v + minf(v * car.boost_bonus, car.boost_max_extra)
	var m_len := v * _rng.randf_range(2.0, 2.6)
	for e in [[end_h, g_h], [end_l, g_l]]:
		var far: float = car_len + v_full * _flight_time(m_top - e[0].end, car.launch_velocity) - e[1]
		m_len = maxf(m_len, far + v * 1.2)
	var merge := _add_segment((x_l + x_h) * 0.5, m_top, m_top, m_w,
		m_start, m_start - m_len, true)
	_add_decor(merge)
	stats.forks = fork_id
	return merge


## Bir boşluk seç: { gap, dh }. Eğimden sonra pencere yarım gazla hesaplanır
## ve dar kalırsa yeni yol alçaltılır (_next_from ile aynı kurallar).
func _pick_gap(slope: float, dh: float, v: float, frac: Vector2) -> Dictionary:
	var v_boost := _v_boost(v)
	var sloped := absf(slope) > 0.1
	var v_reach := lerpf(v, v_boost, 0.5) if sloped else v_boost
	var vy := car.launch_velocity + v * slope
	var vy_reach := car.launch_velocity + v_reach * slope
	var max_up := maxf(vy, 0.0) * maxf(vy, 0.0) / (2.0 * car.gravity) * 0.6
	dh = minf(dh, max_up)
	if vy < 2.0:
		dh = minf(dh, -2.0)
	var car_len := car.half_length * 2.0
	var w := _gap_window(dh, v, v_reach, vy, vy_reach, car_len)
	while w.y - w.x < 3.0 and dh > -8.0:
		dh -= 1.0
		w = _gap_window(dh, v, v_reach, vy, vy_reach, car_len)
	var gap := lerpf(w.x, w.y, _rng.randf_range(frac.x, frac.y))
	# Sonraki yolun en az bu kadar uzun olması gerek (tam roketle aşılmasın)
	var v_full := v + minf(v * car.boost_bonus, car.boost_max_extra)
	var land_far := car_len + v_full * _flight_time(dh, car.launch_velocity + v_full * slope) - gap
	return {"gap": gap, "dh": dh, "min_len": land_far + v * 1.2}


## Çıkmaz: ana yolun yanında, daha alçak, geniş ve davetkâr bir yol. Önceki
## yolun sonundan ulaşılabilir ama devamı yok; ana yoldan önce biter ki ondan
## düşen araba bir sonraki yolun ön yüzüne çakılmasın, uçuşa düşsün.
func _add_dead_end(prev: Segment, main_seg: Segment, side: float, v: float, vy_b: float) -> void:
	var w := _rng.randf_range(6.0, 8.0)
	var drop := _rng.randf_range(4.0, 7.0)
	# Alçağa uçuş daha uzun sürer: havada yana daha çok kayılabilir
	var reach := car.steer_speed * _flight_time(-drop, vy_b) * car.air_control
	var limit := prev.width * 0.5 + reach * 0.85
	var gap := main_seg.width * 0.5 + w * 0.5 + 2.0
	var options: Array[float] = []
	for i in 21:
		var x := prev.x + lerpf(-limit, limit, i / 20.0)
		if absf(x - main_seg.x) >= gap and signf(x - main_seg.x) == side:
			options.append(x)
	var main_len := main_seg.z_start - main_seg.z_end
	var length := minf(_rng.randf_range(60.0, 90.0) * (v / car.start_speed), main_len - 35.0)
	if options.is_empty() or length < 40.0:
		return
	var x: float = options[_rng.randi() % options.size()]
	var top := maxf(prev.top_end - drop, MIN_LEVEL)
	var s := _add_segment(x, top, top, w, main_seg.z_start, main_seg.z_start - length, false)
	s.dead_end = true
	stats.dead_ends += 1
	_avoid_side = signf(x - main_seg.x)
	_avoid_count = 3


func _add_side_road(main_seg: Segment) -> void:
	var side := -1.0 if _rng.randf() < 0.5 else 1.0
	var w := _rng.randf_range(2.5, 5.0)
	var x := main_seg.x + side * (main_seg.width * 0.5 + w * 0.5 + _rng.randf_range(2.5, 6.0))
	var length := main_seg.z_start - main_seg.z_end
	var z_start := main_seg.z_start - _rng.randf_range(0.0, length * 0.2)
	var z_end := z_start - length * _rng.randf_range(0.5, 0.9)
	var top := main_seg.top_at(z_start) + _rng.randf_range(-2.0, 0.3)
	_add_segment(x, top, top, w, z_start, z_end, false)


# --------------------------------------------------------------------------
# Yol yapımı ve renkler
# --------------------------------------------------------------------------

func _add_segment(x: float, top: float, top_end: float, width: float, z_start: float, z_end: float, is_main: bool, bonus := false) -> Segment:
	var s := Segment.new()
	s.bonus = bonus
	s.x = x
	s.top = top
	s.top_end = top_end
	s.width = width
	s.z_start = z_start
	s.z_end = z_end
	s.main = is_main

	var length := z_start - z_end
	var rise := top_end - top
	var slope_len := sqrt(length * length + rise * rise)
	# Duvarın dibi uçuş katmanına (bulutların altı) inmesin
	var depth := clampf(_rng.randf_range(6.0, 28.0), 4.0, minf(top, top_end) + WALL_FLOOR)
	var body := StaticBody3D.new()
	body.position = Vector3(x, (top + top_end) * 0.5, (z_start + z_end) * 0.5)
	# Eğimli yol: kutu x ekseninde döner (uzak uç yukarı = yokuş yukarı)
	body.rotation.x = atan2(rise, length)
	add_child(body)

	var shape := BoxShape3D.new()
	shape.size = Vector3(width, depth, slope_len)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = -depth * 0.5
	body.add_child(col)

	_add_box(body, Vector3(0, -depth * 0.5, 0), Vector3(width, depth, slope_len), _wall_material(s))
	# Asfalt ve kenar çizgileri; yokuş yukarı rampaların çizgileri turuncu
	_add_box(body, Vector3(0, -0.04, 0), Vector3(width - 0.3, 0.1, slope_len - 0.3), _asphalt_material(s))
	var line_x := width * 0.5 - 0.45
	var line_mat := _ramp_line_mat if rise > 1.0 or bonus else _line_mat
	for sx in [-1.0, 1.0]:
		_add_box(body, Vector3(sx * line_x, 0.015, 0), Vector3(0.18, 0.02, slope_len - 0.6), line_mat)
	if rise > 1.0:
		_add_chevrons(body, width, slope_len)
	if is_main:
		_add_runway_lights(body, s, slope_len)

	s.node = body
	segments.append(s)
	stats.min_top = minf(stats.min_top, minf(top, top_end))
	stats.max_top = maxf(stats.max_top, maxf(top, top_end))
	stats.max_slope_deg = maxf(stats.max_slope_deg, rad_to_deg(absf(body.rotation.x)))
	if rise > 1.0:
		stats.ramps_up += 1
	return s


## Pist ışıkları: yolun son ~0.75 saniyesinde iki kenarda kırmızı yuvarlak ışıklar.
## Bölgenin başında seyrek (~5 m), yolun ucuna doğru düzgünce sıklaşır (~1 m).
## Bir darbe dizi boyunca hızla yolun ucuna koşar ve döngüyle tekrarlar: "şimdi gaz".
func _add_runway_lights(body: Node3D, s: Segment, slope_len: float) -> void:
	var v := estimate_speed(car.global_position.z - s.z_end)
	var zone := clampf(v * lights_time, 14.0, minf(48.0, slope_len * 0.6))
	# Yolun ucundan geriye doğru: aralık uçta 1 m, bölgenin başında 5 m
	var dists: Array[float] = []
	var d := 0.6
	while d < zone:
		dists.append(d)
		d += lerpf(1.0, 5.0, d / zone)
	var dots := MultiMesh.new()
	var halos := MultiMesh.new()
	for mm in [dots, halos]:
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.instance_count = dists.size() * 2
	var ball := SphereMesh.new()
	ball.radius = 0.24
	ball.height = 0.48
	ball.radial_segments = 10
	ball.rings = 5
	dots.mesh = ball
	var quad := QuadMesh.new()
	quad.size = Vector2(2.2, 2.2)
	halos.mesh = quad
	var half := slope_len * 0.5
	var cos_a := cos(body.rotation.x)
	var i := 0
	for dist in dists:
		var lz := -half + dist
		# 0: ışıklı bölgenin başı, 1: yolun ucu (darbe bu yöne koşar)
		var along := 1.0 - dist / zone
		for sx in [-1.0, 1.0]:
			var pos := Vector3(sx * (s.width * 0.5 - 0.25), 0.26, lz)
			for mm in [dots, halos]:
				mm.set_instance_transform(i, Transform3D(Basis(), pos))
				mm.set_instance_custom_data(i, Color(body.position.z + lz * cos_a, along, 0, 0))
			i += 1
	for pair in [[dots, _runway_mat], [halos, _runway_halo_mat]]:
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = pair[0]
		mi.material_override = pair[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(mi)


## Düz bir yola engeller ve çakıl şeritleri: sırayla sağda solda, aralarından
## sağ-sol yapılarak geçilir. Yolun başı (iniş) ve sonu (pist ışıkları + hizalanma)
## her zaman boş kalır. Engel: alçak beton blok, ön yüzüne çarpan patlar.
## Çakıl: üstünde hız düşer, direksiyon kayar.
func _add_obstacles(s: Segment, v: float) -> void:
	var w := s.width
	var hw: float = car.model.half_width if car.model else 1.1
	var lane := maxf(3.4, hw * 2.0 + 1.3)
	# İnişte roketin hızı hâlâ üstümüzde olabilir: boş bölge gazlı hıza göre
	var clear_start := _v_boost(v) * 0.9 + 15.0
	var clear_end := clampf(v * lights_time, 14.0, 48.0) + v * 1.0
	var z := s.z_start - clear_start
	var z_last := s.z_end + clear_end
	var side := -1.0 if _rng.randf() < 0.5 else 1.0
	var body := s.node
	while z > z_last:
		var gravel := _rng.randf() < 0.35
		var depth := _rng.randf_range(10.0, 20.0) if gravel else 1.2
		# Çakıldan sonra sendeleme geçsin, hız toparlansın: ışıklara biraz daha erken biter
		var end_margin := v * 0.7 if gravel else 0.0
		if z - depth - end_margin < z_last:
			if gravel:
				gravel = false
				depth = 1.2
				if z - depth < z_last:
					break
			else:
				break
		var x0: float
		var x1: float
		if not gravel and w >= lane * 2.0 + 1.6 and _rng.randf() < 0.3:
			# Ortada blok, iki yanda geçit
			var bw := w - lane * 2.0
			x0 = s.x - bw * 0.5
			x1 = s.x + bw * 0.5
		else:
			# Bir yanda blok/çakıl, öbür yanda geçit
			# Bloklar arası sağ-sol kayması bu hızda yetişilebilir kalsın (≤ ~4.5 m)
			var bw := minf(w - lane, 4.5) if not gravel else minf(w * _rng.randf_range(0.5, 0.6), 4.5)
			if side < 0.0:
				x0 = s.x - w * 0.5
				x1 = x0 + bw
			else:
				x1 = s.x + w * 0.5
				x0 = x1 - bw
			side = -side
		s.obstacles.append({"x0": x0, "x1": x1, "z0": z, "z1": z - depth, "gravel": gravel})
		stats["gravel" if gravel else "blocks"] = int(stats.get("gravel" if gravel else "blocks", 0)) + 1
		var center := Vector3((x0 + x1) * 0.5 - s.x, 0.0, z - depth * 0.5 - body.position.z)
		if gravel:
			_add_box(body, center + Vector3(0, 0.02, 0), Vector3(x1 - x0, 0.03, depth), _gravel_mat)
			# Kenarlarında koyu çizgi: "zemin değişiyor"
			for ez in [0.0, -depth]:
				_add_box(body, center + Vector3(0, 0.035, depth * 0.5 + ez), Vector3(x1 - x0, 0.02, 0.25), _block_mat)
			for k in int((x1 - x0) * depth * 0.45):
				var st := _add_box(body, center + Vector3(_rng.randf_range(-0.5, 0.5) * (x1 - x0 - 0.3), 0.05,
					_rng.randf_range(-0.5, 0.5) * (depth - 0.3)), Vector3.ONE * _rng.randf_range(0.08, 0.2), _stone_mat)
				st.rotation.y = _rng.randf() * TAU
		else:
			var size := Vector3(x1 - x0 - 0.1, 0.9, depth)
			var block := StaticBody3D.new()
			block.position = center + Vector3(0, 0.45, 0)
			body.add_child(block)
			var col := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = size
			col.shape = shape
			block.add_child(col)
			_add_box(block, Vector3.ZERO, size, _block_mat)
			_add_box(block, Vector3(0, 0.46, 0), Vector3(size.x, 0.04, size.z), _block_top_mat)
		z -= depth + v * _rng.randf_range(0.65, 0.95)


## Bu noktada çakıl var mı
func gravel_at(pos: Vector3) -> bool:
	var s := segment_under(pos)
	if s == null:
		return false
	for o in s.obstacles:
		if o.gravel and pos.z <= o.z0 and pos.z >= o.z1 and pos.x >= o.x0 and pos.x <= o.x1:
			return true
	return false


## Yatık yol: yüzey boyunca yana yatar (bükülür) ve düzelir. Kutu değil, ızgara
## hâlinde kurulmuş tek parça bir yüzey; çarpışma da aynı yüzeyden. Orta çizgi
## düz kalır (yol orta çizgisi etrafında döner), kenarlar iner/kalkar.
func _add_banked_segment(x: float, top: float, width: float, z_start: float, z_end: float, pts: Array) -> Segment:
	var s := Segment.new()
	s.x = x
	s.top = top
	s.top_end = top
	s.width = width
	s.z_start = z_start
	s.z_end = z_end
	s.main = true
	for p in pts:
		s.bank_z.append(p[0])
		s.bank_a.append(p[1])
	var length := z_start - z_end
	var depth := clampf(_rng.randf_range(6.0, 28.0), 4.0, top + WALL_FLOOR)
	var body := StaticBody3D.new()
	body.position = Vector3(x, top, (z_start + z_end) * 0.5)
	add_child(body)
	var cz := body.position.z
	var rows := maxi(int(length / 2.0), 2)
	# Yüzey üstünde, orta çizgiden d uzaklıktaki nokta (yerel)
	var at := func(d: float, i: int, lift: float) -> Vector3:
		var z := z_start - length * i / rows
		var a := s.bank_at(z)
		return Vector3(d * cos(a), d * sin(a) + lift, z - cz)
	var hw := width * 0.5
	var wall := SurfaceTool.new()
	wall.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	for i in rows:
		var l0: Vector3 = at.call(-hw, i, 0.0)
		var r0: Vector3 = at.call(hw, i, 0.0)
		var l1: Vector3 = at.call(-hw, i + 1, 0.0)
		var r1: Vector3 = at.call(hw, i + 1, 0.0)
		_quad(wall, faces, l0, r0, r1, l1, Vector3.UP)
		var lb0 := Vector3(l0.x, -depth, l0.z)
		var lb1 := Vector3(l1.x, -depth, l1.z)
		var rb0 := Vector3(r0.x, -depth, r0.z)
		var rb1 := Vector3(r1.x, -depth, r1.z)
		_quad(wall, faces, l0, l1, lb1, lb0, Vector3.LEFT)
		_quad(wall, faces, r0, r1, rb1, rb0, Vector3.RIGHT)
	# Ön (yakın) ve arka (uzak) yüzler
	var f_l: Vector3 = at.call(-hw, 0, 0.0)
	var f_r: Vector3 = at.call(hw, 0, 0.0)
	_quad(wall, faces, f_l, f_r, Vector3(f_r.x, -depth, f_r.z), Vector3(f_l.x, -depth, f_l.z), Vector3.BACK)
	var b_l: Vector3 = at.call(-hw, rows, 0.0)
	var b_r: Vector3 = at.call(hw, rows, 0.0)
	_quad(wall, faces, b_l, b_r, Vector3(b_r.x, -depth, b_r.z), Vector3(b_l.x, -depth, b_l.z), Vector3.FORWARD)
	var wall_mi := MeshInstance3D.new()
	wall_mi.mesh = wall.commit()
	wall_mi.material_override = _wall_material(s)
	body.add_child(wall_mi)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)

	# Asfalt ve kenar çizgileri yüzeyi izler
	var unused := PackedVector3Array()
	var asphalt := SurfaceTool.new()
	asphalt.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lines := SurfaceTool.new()
	lines.begin(Mesh.PRIMITIVE_TRIANGLES)
	var line_x := hw - 0.45
	for i in rows:
		_quad(asphalt, unused, at.call(-hw + 0.15, i, 0.02), at.call(hw - 0.15, i, 0.02),
			at.call(hw - 0.15, i + 1, 0.02), at.call(-hw + 0.15, i + 1, 0.02), Vector3.UP)
		for sx in [-1.0, 1.0]:
			var c: float = sx * line_x
			_quad(lines, unused, at.call(c - 0.09, i, 0.04), at.call(c + 0.09, i, 0.04),
				at.call(c + 0.09, i + 1, 0.04), at.call(c - 0.09, i + 1, 0.04), Vector3.UP)
	# Alçak kenarda kırmızı-beyaz bordür: yol nereye yatıyorsa o kenarda, yatık
	# bölüm boyunca (S bükülmede öbür kenara geçer)
	var kerbs: Array[SurfaceTool] = [SurfaceTool.new(), SurfaceTool.new()]
	for k in kerbs:
		k.begin(Mesh.PRIMITIVE_TRIANGLES)
	var kerb_len := 1.6
	var kerb_rows := int(length / kerb_len)
	var any_kerb := [false, false]
	for j in kerb_rows:
		var z0 := z_start - j * kerb_len
		var z1 := z0 - kerb_len
		var a := s.bank_at((z0 + z1) * 0.5)
		if absf(a) < deg_to_rad(1.5):
			continue
		# a > 0: sağ kenar yukarı, sol kenar aşağı
		var side := -1.0 if a > 0.0 else 1.0
		var c := j % 2
		var p := func(d: float, z: float) -> Vector3:
			var b := s.bank_at(z)
			return Vector3(d * cos(b), d * sin(b) + 0.05, z - cz)
		var outer: float = side * (hw - 0.05)
		var inner: float = side * (hw - 0.8)
		_quad(kerbs[c], unused, p.call(outer, z0), p.call(inner, z0), p.call(inner, z1), p.call(outer, z1), Vector3.UP)
		any_kerb[c] = true
	for c in 2:
		if any_kerb[c]:
			var kmi := MeshInstance3D.new()
			kmi.mesh = kerbs[c].commit()
			kmi.material_override = _kerb_red if c == 0 else _kerb_white
			body.add_child(kmi)
	var asphalt_mi := MeshInstance3D.new()
	asphalt_mi.mesh = asphalt.commit()
	asphalt_mi.material_override = _asphalt_material(s)
	body.add_child(asphalt_mi)
	var lines_mi := MeshInstance3D.new()
	lines_mi.mesh = lines.commit()
	lines_mi.material_override = _line_mat
	lines_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(lines_mi)
	_add_runway_lights(body, s, length)

	s.node = body
	segments.append(s)
	stats.min_top = minf(stats.min_top, top)
	stats.max_top = maxf(stats.max_top, top)
	stats.banked = int(stats.get("banked", 0)) + 1
	stats.max_bank_deg = maxf(float(stats.get("max_bank_deg", 0.0)), rad_to_deg(absf(s.bank_a[2])))
	return s


## Dörtgen (a, b, c, d sırayla çevre) iki üçgen: normal "out" yönüne bakacak
## sırayla eklenir (Godot'da ön yüz saat yönünde). faces'e çarpışma için de yazılır.
func _quad(st: SurfaceTool, faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3) -> void:
	for tri in [[a, b, c], [a, c, d]]:
		var p0: Vector3 = tri[0]
		var p1: Vector3 = tri[1]
		var p2: Vector3 = tri[2]
		var n := (p1 - p0).cross(p2 - p0)
		if n.dot(out) > 0.0:
			var tmp := p1
			p1 = p2
			p2 = tmp
		else:
			n = -n
		n = n.normalized()
		for p in [p0, p1, p2]:
			st.set_normal(n)
			st.add_vertex(p)
			faces.append(p)


## Rampanın üstüne ileri bakan turuncu oklar (^): "burası seni fırlatır"
func _add_chevrons(body: Node3D, width: float, slope_len: float) -> void:
	var arm := minf(width * 0.42, 2.8)
	var half := deg_to_rad(52.0)
	var count := clampi(int(slope_len / 8.0), 3, 8)
	for i in count:
		var apex_z := -slope_len * 0.5 + slope_len * (i + 0.6) / (count + 0.4)
		for sx in [-1.0, 1.0]:
			var d := Vector3(sx * sin(half), 0, cos(half))
			var mi := _add_box(body, Vector3(0, 0.02, apex_z) + d * arm * 0.5,
				Vector3(0.6, 0.02, arm), _chevron_mat)
			mi.rotation.y = atan2(d.x, d.z)


## Bölge rengi (mesafeye göre yumuşak geçiş); alçak yollar daha koyu
func _wall_material(s: Segment) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = _zone_color(-(s.z_start + s.z_end) * 0.5)
	var avg := (s.top + s.top_end) * 0.5
	var low := clampf((MAIN_LEVEL - avg - 2.0) / 7.0, 0.0, 1.0)
	m.albedo_color = m.albedo_color.darkened(0.28 * low + _rng.randf_range(0.0, 0.05))
	# Rampalar uzaktan seçilsin: yokuş yukarı duvarlar turuncuya çalar,
	# yokuş aşağılar biraz koyulaşır (kama biçimi gökyüzünden ayrılsın)
	var rise := s.top_end - s.top
	if rise > 1.0:
		m.albedo_color = m.albedo_color.lerp(Palette.ACCENT, 0.5)
	elif rise < -1.0:
		m.albedo_color = m.albedo_color.darkened(0.18)
	m.roughness = 1.0
	return m


## Yol yüzeyi kömür rengi; bölge renginden hafif bir ton alır
func _asphalt_material(s: Segment) -> StandardMaterial3D:
	var zone := _zone_color(-(s.z_start + s.z_end) * 0.5)
	var m := StandardMaterial3D.new()
	m.albedo_color = Palette.ASPHALT.lerp(zone.darkened(0.55), 0.35)
	m.roughness = 1.0
	return m


func _zone_color(distance: float) -> Color:
	var f := maxf(distance, 0.0) / zone_length
	var i := int(f)
	var blend := smoothstep(0.8, 1.0, f - i)
	return ZONES[i % ZONES.size()].lerp(ZONES[(i + 1) % ZONES.size()], blend)


func _add_box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _unit_box
	mi.material_override = mat
	mi.position = pos
	mi.scale = size
	parent.add_child(mi)
	return mi


## Uzakta süzülen ince, uzun monolitler (dekor), bölge renginde
func _add_decor(seg: Segment) -> void:
	for i in _rng.randi_range(0, 2):
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var size := Vector3(_rng.randf_range(3, 8), _rng.randf_range(20, 60), _rng.randf_range(3, 10))
		var pos := Vector3(
			seg.x + side * _rng.randf_range(35.0, 120.0),
			seg.top + _rng.randf_range(-30.0, 10.0),
			_rng.randf_range(seg.z_end, seg.z_start))
		var m := StandardMaterial3D.new()
		m.albedo_color = _zone_color(-pos.z).darkened(_rng.randf_range(0.0, 0.08))
		m.roughness = 1.0
		var block := _add_box(self, pos, size, m)
		block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_decor.append(block)
