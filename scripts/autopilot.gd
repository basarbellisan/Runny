class_name Autopilot
extends RefCounted
## Test için otomatik sürücü.
## Yolun sonuna yaklaşınca hizalanıp gaza basar. use_boost = false ise hiç
## gaz vermez (her boşluğun gaz gerektirdiğini test etmek için).
## dive_interval > 0 ise, yolda bu kadar saniye gittikten sonra bilerek
## yoldan düşer; uçarken kayalardan kaçıp portala yönelir.

var car: Car
var roads: RoadGenerator
var lower: LowerLayer
var dive_interval := 0.0
var use_boost := true
var _drive_time := 0.0
var _diving := false
var _dive_dir := 1.0


func _init(p_car: Car, p_roads: RoadGenerator, p_lower: LowerLayer, p_dive_interval := 0.0, p_use_boost := true) -> void:
	car = p_car
	roads = p_roads
	lower = p_lower
	dive_interval = p_dive_interval
	use_boost = p_use_boost


## x: direksiyon, y: gaz (Car._read_input ile aynı biçim)
func input() -> Vector2:
	if car.mode == Car.Mode.FLYING or car.mode == Car.Mode.FALLING:
		_drive_time = 0.0
		_diving = false
		return Vector2(_fly_steer(), 0.0)
	return _drive_input()


func _drive_input() -> Vector2:
	var pos := car.global_position
	var current: RoadGenerator.Segment = roads.segment_under(pos) if car.is_on_floor() else null

	if dive_interval > 0.0 and car.mode == Car.Mode.DRIVE:
		if current != null:
			_drive_time += car.get_physics_process_delta_time()
			if _drive_time > dive_interval and not _diving:
				_diving = true
				_dive_dir = signf(pos.x - current.x) if pos.x != current.x else 1.0
		if _diving:
			return Vector2(_dive_dir, 0.0)

	var target: RoadGenerator.Segment = null
	for s in roads.main_segments_ahead(pos.z + 2.0):
		if s == current:
			continue
		if s.z_start < pos.z or s.contains(pos):
			target = s
			break
	if target == null:
		return Vector2.ZERO
	var aim := target.x
	if current != null:
		var lim := current.width * 0.5 - 1.2
		aim = clampf(aim, current.x - lim, current.x + lim)
		# Yolun sonuna ~1.2 sn kala hizalıysak gaza bas
		var time_to_edge := (pos.z - current.z_end) / maxf(car.forward_speed, 1.0)
		if use_boost and time_to_edge < 1.2 and absf(aim - pos.x) < 1.5:
			return Vector2(0.0, 1.0)
	return Vector2(_toward(aim - pos.x, 0.25), 0.0)


func _fly_steer() -> float:
	var pos := car.global_position
	var goal := pos.x
	var portal := lower.next_portal(pos.z)
	if portal != null:
		goal = portal.x
	var forward := maxf(-car.velocity.z, 1.0)
	var best := pos.x
	var best_cost := INF
	for i in range(-30, 31):
		var cand := pos.x + i
		var cost := absf(cand - goal) * 0.1 + absf(cand - pos.x) * 0.02
		for r in lower.rocks:
			var d: float = pos.z - r.z
			if d < 0.0 or d > 60.0:
				continue
			# Kayanın hizasına geldiğimizde nerede olabiliriz
			var reach := car.steer_speed * maxf(d / forward - 0.15, 0.0)
			var x_at := pos.x + clampf(cand - pos.x, -reach, reach)
			if absf(x_at - r.x) < r.r + 2.2:
				cost += 1000.0
		if cost < best_cost:
			best_cost = cost
			best = cand
	return _toward(best - pos.x, 0.4)


func _toward(err: float, dead_zone: float) -> float:
	return 0.0 if absf(err) < dead_zone else signf(err)
