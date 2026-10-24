class_name RoadGenerator
extends Node3D
## Havada duran, birbirinden bağımsız duvar-yolları üretir.
## Her yeni yol, arabanın o anki hızı ve atlama fiziğine göre
## ulaşılabilir olacak şekilde yerleştirilir.

class Segment:
	var x: float
	var top: float
	var width: float
	var z_start: float  # yakın uç (büyük z)
	var z_end: float    # uzak uç (küçük z)
	var main: bool      # ana yol mu, yan yol mu
	var node: Node3D

	func contains(pos: Vector3, margin := 0.0) -> bool:
		return pos.z <= z_start and pos.z >= z_end \
			and absf(pos.x - x) <= width * 0.5 + margin


@export var view_distance := 450.0
@export var cleanup_distance := 40.0
## Yolların yüksekliği bu bandın içinde kalır (başlangıca göre)
@export var height_band := Vector2(-8.0, 4.0)
@export var min_width := Vector2(3.0, 5.0)    # (zor, kolay)
@export var max_width := Vector2(6.5, 10.0)   # (zor, kolay)
## Bu mesafeye (metre) gelince zorluk tavan yapar
@export var difficulty_distance := 3000.0
@export_range(0.0, 1.0) var side_road_chance := 0.3
## Boşluğun, gazsız ulaşılamayan en kısa ile tam gazla ulaşılan en uzun
## arasındaki yeri (0: az gaz yeter, 1: tam gaz şart)
@export var gap_difficulty := Vector2(0.1, 0.85)

var car: Car
var segments: Array[Segment] = []
var _head: Segment
var _decor: Array[Node3D] = []
var _rng := RandomNumberGenerator.new()
var _unit_box := BoxMesh.new()
var _wall_mats: Array[StandardMaterial3D] = []
var _asphalt_mat := StandardMaterial3D.new()
var _line_mat := ShaderMaterial.new()


func _ready() -> void:
	for c in Palette.WALLS:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 1.0
		_wall_mats.append(m)
	_asphalt_mat.albedo_color = Palette.ASPHALT
	_asphalt_mat.roughness = 1.0
	_line_mat.shader = preload("res://shaders/dashed_line.gdshader")
	_line_mat.set_shader_parameter("color", Palette.SNOW)


func start(p_car: Car, seed_value := -1) -> void:
	car = p_car
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	# Başlangıç pisti: uzun ve geniş
	_head = _add_segment(0.0, 0.0, 9.0, car.global_position.z + 15.0, car.global_position.z - 140.0, true)
	_fill(car.global_position.z)


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
		if s.contains(pos, 0.5) and absf(pos.y - s.top) < 0.6:
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
		top = maxf(top, s.top)
	return top


func _fill(car_z: float) -> void:
	generate_until(car_z - view_distance)


func _next_from(prev: Segment) -> Segment:
	var dist_ahead := car.global_position.z - prev.z_end
	var travelled := -prev.z_end
	var difficulty := clampf(travelled / difficulty_distance, 0.0, 1.0)
	# Araba bu yolun sonuna vardığında ne hızda olacak (tahmini)
	var v := estimate_speed(dist_ahead)

	# Yükseklik farkı: yukarı çıkış atlama gücüyle sınırlı
	var max_up := car.launch_velocity * car.launch_velocity / (2.0 * car.gravity) * 0.6
	var dh: float
	if prev.top < height_band.x:
		dh = _rng.randf_range(0.0, max_up)
	elif prev.top > height_band.y:
		dh = _rng.randf_range(-4.0, 0.0)
	else:
		dh = _rng.randf_range(-3.0, max_up)

	# Araba, arka ucu yoldan çıkınca havalanır; o anda ön ucu kenardan
	# bir araba boyu ileridedir. Boşluk, gazsız ulaşılamayacak (ön yüze
	# çakılır) ama tam gazla iniş yolun üstüne denk gelecek şekilde seçilir.
	var car_len := car.half_length * 2.0
	var v_boost := v + minf(v * car.boost_bonus, car.boost_max_extra)
	var t := _flight_time(dh)
	var min_gap := _min_gap(dh, v, v_boost, car_len)
	var max_gap := car_len + v_boost * t - 2.5
	if max_gap < min_gap:
		dh = minf(dh, 0.0)
		t = _flight_time(dh)
		min_gap = _min_gap(dh, v, v_boost, car_len)
		max_gap = car_len + v_boost * t - 2.5
	var gap := lerpf(min_gap, maxf(max_gap, min_gap), _rng.randf_range(gap_difficulty.x, maxf(gap_difficulty.x, gap_difficulty.y)))

	var width := _rng.randf_range(
		lerpf(min_width.y, min_width.x, difficulty),
		lerpf(max_width.y, max_width.x, difficulty))
	# Havada sağa sola ne kadar kayabiliriz
	var reach := car.steer_speed * t * car.air_control
	var max_dx := prev.width * 0.5 + reach * 0.6
	var dx := _rng.randf_range(-max_dx, max_dx)
	var length := _rng.randf_range(40.0, 100.0) * (v / car.start_speed)

	var z_start := prev.z_end - gap
	var seg := _add_segment(prev.x + dx, prev.top + dh, width, z_start, z_start - length, true)

	if _rng.randf() < side_road_chance:
		_add_side_road(seg)
	_add_decor(seg)
	return seg


## Gazsız ulaşılamayan en kısa boşluk. Yukarı basamakta tam gazla bile
## ön uç, araba yeterince yükselmeden yolun hizasına varmamalı.
func _min_gap(dh: float, v: float, v_boost: float, car_len: float) -> float:
	var gap := car_len + v * _flight_time(dh) + 1.5
	if dh > 0.0:
		gap = maxf(gap, car_len + v_boost * _rise_time(dh) + 1.0)
	return gap


## Kenardan kalkıştan, dh yüksekliğine inene kadar geçen süre
func _flight_time(dh: float) -> float:
	var vy := car.launch_velocity
	var g := car.gravity
	return (vy + sqrt(maxf(vy * vy - 2.0 * g * dh, 0.0))) / g


## Kenardan kalkıştan, dh yüksekliğine çıkana kadar geçen süre (dh > 0)
func _rise_time(dh: float) -> float:
	var vy := car.launch_velocity
	var g := car.gravity
	return (vy - sqrt(maxf(vy * vy - 2.0 * g * dh, 0.0))) / g


func _add_side_road(main_seg: Segment) -> void:
	var side := -1.0 if _rng.randf() < 0.5 else 1.0
	var w := _rng.randf_range(2.5, 5.0)
	var x := main_seg.x + side * (main_seg.width * 0.5 + w * 0.5 + _rng.randf_range(2.5, 6.0))
	var length := main_seg.z_start - main_seg.z_end
	var z_start := main_seg.z_start - _rng.randf_range(0.0, length * 0.2)
	var z_end := z_start - length * _rng.randf_range(0.5, 0.9)
	var top := main_seg.top + _rng.randf_range(-2.0, 0.3)
	_add_segment(x, top, w, z_start, z_end, false)


func _add_segment(x: float, top: float, width: float, z_start: float, z_end: float, is_main: bool) -> Segment:
	var s := Segment.new()
	s.x = x
	s.top = top
	s.width = width
	s.z_start = z_start
	s.z_end = z_end
	s.main = is_main

	var length := z_start - z_end
	var depth := _rng.randf_range(6.0, 28.0)
	var body := StaticBody3D.new()
	body.position = Vector3(x, top, (z_start + z_end) * 0.5)
	add_child(body)

	var shape := BoxShape3D.new()
	shape.size = Vector3(width, depth, length)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = -depth * 0.5
	body.add_child(col)

	_add_box(body, Vector3(0, -depth * 0.5, 0), Vector3(width, depth, length),
		_wall_mats[_rng.randi() % _wall_mats.size()])
	# Asfalt ve kenar çizgileri (yolun kenarını görmeyi kolaylaştırır)
	_add_box(body, Vector3(0, -0.04, 0), Vector3(width - 0.3, 0.1, length - 0.3), _asphalt_mat)
	var line_x := width * 0.5 - 0.45
	for sx in [-1.0, 1.0]:
		_add_box(body, Vector3(sx * line_x, 0.015, 0), Vector3(0.18, 0.02, length - 0.6), _line_mat)

	s.node = body
	segments.append(s)
	return s


func _add_box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _unit_box
	mi.material_override = mat
	mi.position = pos
	mi.scale = size
	parent.add_child(mi)
	return mi


## Uzakta süzülen ince, uzun monolitler (dekor)
func _add_decor(seg: Segment) -> void:
	for i in _rng.randi_range(0, 2):
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var size := Vector3(_rng.randf_range(3, 8), _rng.randf_range(20, 60), _rng.randf_range(3, 10))
		var pos := Vector3(
			seg.x + side * _rng.randf_range(35.0, 120.0),
			seg.top + _rng.randf_range(-30.0, 10.0),
			_rng.randf_range(seg.z_end, seg.z_start))
		var block := _add_box(self, pos, size, _wall_mats[_rng.randi() % _wall_mats.size()])
		block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_decor.append(block)
