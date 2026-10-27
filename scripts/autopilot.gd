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
## Test: çıkmaz yollara bilerek gir (çakılmadan uçuşa düşülmeli)
var seek_dead_ends := false
## Test: yan yolları kullan (alçak yola düş, eğik rampaya gir, dönüş rampasıyla dön)
var seek_side := false
## Test: kristal topla (kapalıyken hiç kristal almaz: enerji bitip düşmeli)
var collect_crystals := true
## Yan yoldan ana yola dönüş sayısı
var side_trips := 0
var _on_side := false
var _drive_time := 0.0
var _diving := false
var _dive_dir := 1.0
## Çatalda kol seçimi: çatallar sırayla alçak/yüksek kola gidilir


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
		return Vector2(_fly_steer(), 0.0) if not _should_climb() else Vector2(0.0, 1.0)
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

	if seek_dead_ends and current != null and current.dead_end:
		return Vector2.ZERO  # çıkmazda dümdüz git, sonunda düş
	if seek_side and car.mode == Car.Mode.DRIVE and current != null:
		var side_input := _side_input(current, pos)
		if not is_nan(side_input):
			return Vector2(side_input, 0.0)
	var target: RoadGenerator.Segment = null
	if seek_dead_ends:
		for s in roads.segments:
			if s.dead_end and s.z_start < pos.z and s.z_start > pos.z - 120.0:
				target = s
				break
	var kicked: RoadGenerator.Segment = car._last_segment
	if current == null and kicked != null and kicked.ramp and kicked.kick != 0.0:
		# Eğik rampadan atıldık: rampanın attığı yöndeki yola in (geri dönmeye çalışma)
		var reach := pos.z - maxf(car.forward_speed, 1.0) * 1.2
		for s in roads.segments:
			if not s.ramp and signf(s.x - kicked.x) == signf(kicked.kick) \
					and absf(s.x - kicked.x) > 1.0 and s.z_start > reach and s.z_end < pos.z:
				target = s
				break
	if target == null and current == null:
		# Havadayken tam altımızda bir yol varsa (ör. portaldan sonra yan yol) ona in
		for s in roads.segments:
			if s.contains(pos, -0.8) and s.top_at(pos.z) < pos.y + 0.5:
				target = s
				break
	for s in ([] if target else roads.main_segments_ahead(pos.z + 2.0)):
		if s == current:
			continue
		if s.route != 0:
			# Çatal: bir kol seç, öbür kolun yollarını yok say
			if s.route != 1 + s.fork_id % 2:
				continue
		# Havadayken üstünden geçtiğimiz yol da hedef (ada zinciri: başını geçtik ama yana kayıyoruz)
		if s.z_start < pos.z or s.contains(pos) or (current == null and s.z_end < pos.z - 4.0):
			target = s
			break
	if target == null:
		# Önümüzdeki yol henüz üretilmemiş (uzun yol): bulunduğumuz yolda kal
		if current == null:
			return Vector2.ZERO
		target = current
	var aim := target.x
	if current != null:
		# Tekerler yoldan taşmasın: kenardan tekerlerin dış ucu + pay kadar içeride kal
		var lim := maxf(current.width * 0.5 - car.model.half_width - 0.5, 0.0)
		aim = clampf(aim, current.x - lim, current.x + lim)
		var dodge := _dodge(current, pos)
		if not is_nan(dodge):
			return Vector2(_steer_to(dodge, pos), 0.0)
		# Çakıl arabayı savurur: kenara yakınsa ortaya doğru tut
		if car.on_gravel and absf(pos.x - current.x) > current.width * 0.5 - car.model.half_width - 1.2:
			return Vector2(_steer_to(current.x, pos), 0.0)
		# Roket: yolun sonuna ~0.6 sn kala (pist ışıklarında) hizalıysak gaza bas
		var time_to_edge := (pos.z - current.road_end_z()) / maxf(car.forward_speed, 1.0)
		# Enerji için: önümüzdeki, yolun üstündeki en yakın kristale doğru (pistte değilsek)
		var to_joint := (pos.z - current.z_end) / maxf(car.forward_speed, 1.0)
		# Ada zincirinde sonraki ada yandaysa kristal kovalama: önce oraya kay
		var island_shift := current.hop and absf(target.x - current.x) > 2.0
		if collect_crystals and not island_shift and time_to_edge > 0.9 and (current.next_flush == null or to_joint > 0.9):
			var cx := _crystal_aim(current, pos, lim)
			if not is_nan(cx):
				aim = cx
		if current.next_flush == target and to_joint < 1.2:
			# Bitişik parça (daralma, kayma): ona geçmeden hizalan, onun sınırında da kal
			var lim2 := maxf(target.width * 0.5 - car.model.half_width - 0.5, 0.0)
			aim = clampf(target.x, maxf(current.x - lim, target.x - lim2), minf(current.x + lim, target.x + lim2))
		var aligned := absf(aim - pos.x) < 1.0 and absf(car.velocity.x) < 3.0
		# Ada zincirinde küçük boşluklar gazsız geçilir (gaz kısa adayı aştırır)
		if use_boost and not current.hop and time_to_edge < 0.6 and (aligned or time_to_edge < 0.42):
			return Vector2(0.0, 1.0)
	var steer := _steer_to(aim, pos) if current != null else _toward(aim - pos.x, 0.25)
	if current == null and car._kick_hold > 0.0:
		# Eğik rampadan atıldık: hız hedefe götürüyorsa dokunma, yetmiyorsa o yana bas
		var t_land := maxf(car._time_to_fall_to(target.top_at(pos.z)), 0.05)
		var land_x := pos.x + car.velocity.x * t_land
		if absf(land_x - aim) < target.width * 0.3:
			return Vector2.ZERO
		return Vector2(signf(aim - land_x), 0.0)
	if not car.is_on_floor() and car.velocity.y < 0.0:
		# İnerken: önce gövdeyi düzle (direksiyon yatırır), sonra az az hizalan
		# (Eğik rampadan kalkınca gövde biraz yatık olur; o kadarı temiz inişe engel değil)
		if absf(car.roll) > 0.22:
			return Vector2(clampf(car.roll * 3.0, -1.0, 1.0), 0.0)
		# Hedef ada yandaysa (ada zinciri) tam bas, yoksa az az hizalan
		var from_island: bool = car._last_segment != null and (car._last_segment.hop or car._last_segment.pattern == "ada")
		var far_side := from_island and target != null and absf(aim - pos.x) > target.width * 0.5 - 0.8
		steer = clampf(steer, -1.0, 1.0) if far_side else clampf(steer, -0.3, 0.3)
	return Vector2(steer, 0.0)


## Yan yol testi: yan yoldaysak ortada kal (sonundaki rampa ana yola atar); ana yolda
## önümüzde yana atan rampa varsa ona gir; yanımızda alçak yol varsa kenardan ona düş.
## Karışmayacaksa NAN.
func _side_input(current: RoadGenerator.Segment, pos: Vector3) -> float:
	if current.ramp:
		return 0.0
	if not current.main:
		if current.side_road:
			_on_side = true
			var dodge := _dodge(current, pos)
			return _toward((current.x if is_nan(dodge) else dodge) - pos.x, 0.3)
		return NAN
	if _on_side:
		side_trips += 1
		_on_side = false
	# Önce engelden kaç (normal sürüş halleder)
	if not is_nan(_dodge(current, pos)):
		return NAN
	var forward := maxf(car.forward_speed, 1.0)
	for s in roads.segments:
		if s.ramp and s.kick != 0.0 and s.z_start < pos.z - 2.0 and s.z_start > pos.z - forward * 2.0 \
				and s.z_start <= current.z_start and s.z_end >= current.z_end \
				and absf(s.x - current.x) < current.width * 0.5:
			return _toward(s.x - pos.x, 0.2)
	for s in roads.segments:
		if s.side_road and s.top < current.top - 1.0 \
				and s.z_start > pos.z - 5.0 and s.z_end < pos.z - forward * 1.5 \
				and absf(s.x - current.x) < (s.width + current.width) * 0.5 + 2.0:
			return signf(s.x - pos.x)
	return NAN


## Önümüzdeki ~1 sn içindeki, bu yolun üstündeki (yerden alınabilir) en yakın kristalin x'i
func _crystal_aim(current: RoadGenerator.Segment, pos: Vector3, lim: float) -> float:
	var forward := maxf(car.forward_speed, 1.0)
	var best := NAN
	var best_z := -INF
	for p in roads.crystals_ahead(pos, forward * 1.0):
		if p.y - pos.y > 2.0 or absf(p.x - current.x) > lim + 0.3:
			continue
		# Bir saniyede yana ancak bu kadar gidilir
		if absf(p.x - pos.x) > car.steer_speed * (pos.z - p.z) / forward * 0.8 + 0.6:
			continue
		if p.z > best_z:
			best_z = p.z
			best = p.x
	return best


## Önümüzdeki engel/çakıl varsa geçilecek x (yoksa NAN): engelin yanındaki boş
## geçitlerden bize en yakın olanı. Çakıla girmemek tercih edilir ama şart değil.
func _dodge(seg: RoadGenerator.Segment, pos: Vector3) -> float:
	var hw := car.model.half_width
	var look := maxf(car.forward_speed, 1.0) * 1.4
	# Önümüzdeki ilk engel sırası (aynı hizadaki bloklar ve çakıllar birlikte: kapı gibi)
	var row: Array[Dictionary] = []
	var on := seg
	var row_seg := seg
	while on and on.z_start > pos.z - look:
		var near_z := -INF
		for o in on.obstacles:
			if o.z1 < pos.z + car.half_length and o.z0 > pos.z - look:
				near_z = maxf(near_z, o.z0)
		if near_z > -INF:
			for o in on.obstacles:
				if o.z1 < pos.z + car.half_length and o.z0 > near_z - 10.0:
					row.append(o)
			row_seg = on
			break
		on = on.next_flush
	if row.is_empty():
		return NAN
	var lo := row_seg.x - row_seg.width * 0.5 + hw + 0.3
	var hi := row_seg.x + row_seg.width * 0.5 - hw - 0.3
	if row_seg != seg:
		# Engel ileriki bir parçadaysa aradaki (belki dar) parçalarda da yolda kalmalı:
		# önce oralardan geç, sonra kaç
		var mid := seg
		while mid and mid != row_seg:
			var mlo := mid.x - mid.width * 0.5 + hw + 0.3
			var mhi := mid.x + mid.width * 0.5 - hw - 0.3
			if maxf(lo, mlo) > minf(hi, mhi):
				return NAN
			lo = maxf(lo, mlo)
			hi = minf(hi, mhi)
			mid = mid.next_flush
	# Önce bloktan da çakıldan da kaç; olmuyorsa yalnız bloktan
	for avoid_gravel in [true, false]:
		var free: Array[Vector2] = [Vector2(lo, hi)]
		for o in row:
			if o.gravel and not avoid_gravel:
				continue
			var b0: float = o.x0 - hw - 0.45
			var b1: float = o.x1 + hw + 0.45
			var next_free: Array[Vector2] = []
			for iv in free:
				if b1 <= iv.x or b0 >= iv.y:
					next_free.append(iv)
					continue
				if b0 > iv.x:
					next_free.append(Vector2(iv.x, b0))
				if b1 < iv.y:
					next_free.append(Vector2(b1, iv.y))
			free = next_free
		var best := NAN
		for iv in free:
			var x := clampf(pos.x, iv.x, iv.y)
			if is_nan(best) or absf(x - pos.x) < absf(best - pos.x):
				best = x
		if not is_nan(best):
			return best
	return (lo + hi) * 0.5


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
		# Portala yaklaşırken hedef ağır basar (kayadan kaçıp portalı kaçırmasın)
		var near_portal := portal != null and (pos.z - portal.z) < forward * 2.5
		var cost := absf(cand - goal) * (0.6 if near_portal else 0.1) + absf(cand - pos.x) * 0.02
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


## Hemen önümüzde alçak bir kaya varsa (ve yukarısı boşsa) yüksel
func _should_climb() -> bool:
	if not use_boost or car.mode != Car.Mode.FLYING:
		return false
	var pos := car.global_position
	var forward := maxf(-car.velocity.z, 1.0)
	# Portala yaklaşırken alçakta kal
	var portal := lower.next_portal(pos.z)
	if portal != null and pos.z - portal.z < forward * 2.5:
		return false
	var low_ahead := false
	for r in lower.rocks:
		var d: float = pos.z - r.z
		if d < 0.0 or d > forward * 0.9:
			continue
		var ry: float = r.node.position.y
		if absf(r.x - pos.x) < r.r + 2.0:
			if ry > car.flight_altitude + 3.0:
				return false
			low_ahead = true
	return low_ahead


## Yerde: hedefe yaklaştıkça yavaşlayan direksiyon (aşıp yoldan çıkmasın)
func _steer_to(x: float, pos: Vector3) -> float:
	var want_vx := clampf((x - pos.x) * 9.0, -car.steer_speed, car.steer_speed)
	# Yatık yolda araba alçak yana kayar: o kaymayı da karşıla
	var slide := car.get_floor_normal().x * car.bank_slide if car.is_on_floor() else 0.0
	return clampf((want_vx - slide) / car.steer_speed + (want_vx - car.velocity.x) * 0.15, -1.0, 1.0)


func _toward(err: float, dead_zone: float) -> float:
	return 0.0 if absf(err) < dead_zone else signf(err)
