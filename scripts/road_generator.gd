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

class Segment:
	var x: float
	var top: float       # yakın uçtaki (z_start) yükseklik
	var top_end: float   # uzak uçtaki (z_end) yükseklik
	var width: float
	var z_start: float   # yakın uç (büyük z)
	var z_end: float     # uzak uç (küçük z)
	var main: bool       # ana yol mu
	var dead_end := false
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
		if s.contains(pos, 0.5) and absf(pos.y - s.top_at(pos.z)) < 0.6 + absf(s.slope()) * 2.2:
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
			return {"seg": s, "z": minf(z, near)}
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
	var flat := 1.0 if travelled < slopes_from else (0.6 if travelled < ramps_from else 0.4)
	var options := [["düz", flat]]
	if travelled > slopes_from:
		options.append(["eğim", 0.6])
		if not low:
			options.append(["vadi", 0.6])
	if travelled > ramps_from:
		if not low:
			options += [["merdiven", 0.5], ["çıkmaz", dead_end_weight]]
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


func _next_from(prev: Segment) -> Segment:
	var dist_ahead := car.global_position.z - prev.z_end
	var travelled := -prev.z_end
	var difficulty := clampf(travelled / difficulty_distance, 0.0, 1.0)
	if _plan.is_empty():
		_plan_pattern(travelled, prev.top_end)
	var spec: Dictionary = _plan.pop_front()

	# Araba bu yolun sonuna vardığında ne hızda olacak (tahmini)
	var v := estimate_speed(dist_ahead)
	var v_boost := v + minf(v * car.boost_bonus, car.boost_max_extra)
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
	var seg := _add_segment(prev.x + dx, top, top + rise, width, z_start, z_start - length, true)

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

func _add_segment(x: float, top: float, top_end: float, width: float, z_start: float, z_end: float, is_main: bool) -> Segment:
	var s := Segment.new()
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
	var line_mat := _ramp_line_mat if rise > 1.0 else _line_mat
	for sx in [-1.0, 1.0]:
		_add_box(body, Vector3(sx * line_x, 0.015, 0), Vector3(0.18, 0.02, slope_len - 0.6), line_mat)
	if rise > 1.0:
		_add_chevrons(body, width, slope_len)

	s.node = body
	segments.append(s)
	stats.min_top = minf(stats.min_top, minf(top, top_end))
	stats.max_top = maxf(stats.max_top, maxf(top, top_end))
	stats.max_slope_deg = maxf(stats.max_slope_deg, rad_to_deg(absf(body.rotation.x)))
	if rise > 1.0:
		stats.ramps_up += 1
	return s


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
