class_name LowerLayer
extends Node3D
## Alt katman: kayalar, kuyruklu kayalar ve yukarı fırlatan portallar (tünel).
## Aşağıda kristal yok: depo, aşağıdaki hayat süresidir. Sadece araba uçarken
## aktiftir; araba yola dönünce temizlenir.

signal crystal_collected
signal rock_hit
signal portal_entered(portal: Portal)

## Portal planı: portal nerede, araba yukarıda nereye inecek
class Portal:
	var x: float
	var z: float
	var land: Vector3      # inilecek yol noktası (x, yol üstü, z)
	var clear_y: float     # bu yüksekliğe çıkana kadar yana kayma
	var node: Node3D
	var path: PackedVector3Array  # tünelin orta çizgisi (araba içinden geçer)

## Kristal toplama mesafesi (yarı genişlik): x kanatlar, y gövde, z araba boyu
const CRYSTAL_REACH := Vector3(3.2, 1.8, 2.6)

@export var fill_distance := 350.0
@export var corridor_half_width := 14.0
## Portallar arası süre (saniye, o anki hızla)
## İlk portal şansa kalır (az enerjiyle düşen ancak yakın bir portal denk gelirse kurtulur)
@export var portal_interval := Vector2(6.0, 10.0)
@export var first_portal_time := Vector2(2.0, 9.0)
## Kaya alanı: 100 m'deki kaya sayısı (yeni düşünce, uzun kalınca)
@export var rock_density := Vector2(7.0, 13.0)
## Yoğunluğun tavana çıktığı süre (alt katmanda kalınan sn)
@export var density_time := 20.0
## Kayanın yukarıda (yükselerek çarpılan yükseklikte) süzülme şansı; ortada
## (hem alçaktan hem yükselerek çarpılan, yalnız direksiyonla geçilen) olma şansı
@export_range(0.0, 1.0) var high_rock_chance := 0.25
@export_range(0.0, 1.0) var mid_rock_chance := 0.15
## Kuyruklu kaya: kaç sn'de bir (en az, en çok) ve bize doğru hızı (m/s)
@export var comet_interval := Vector2(3.0, 6.0)
@export var comet_speed := Vector2(30.0, 45.0)
## Kaya sırasının yanında kristal dizisi olma şansı (aşağıda kristal yok: 0)
@export_range(0.0, 1.0) var crystal_row_chance := 0.0
## Kristal dizisinin yukarıda çıkma şansı
@export_range(0.0, 1.0) var high_crystal_chance := 0.35
## Portaldan yukarıdaki yola iniş süresi (yaklaşık)
@export var launch_time := 3.0

var car: Car
var roads: RoadGenerator
var active := false
var rocks: Array = []      # { x, y, z, r, node, v (Vector3: hareketli kaya) }
var portals: Array = []    # Portal
var _items: Array[Node3D] = []
var _spinners: Array = []  # dönen kristaller
var _crystals: Array = []
var _next_row_z := 0.0
var _next_portal: Portal
## Alt katmanda geçen süre ve sıradaki kuyruklu kayanın zamanı
var _time := 0.0
var _next_comet := 0.0
var _comet_mat := StandardMaterial3D.new()
var _tail_mat := StandardMaterial3D.new()
var _rng := RandomNumberGenerator.new()

var _rock_mesh: Mesh
var _crystal_mesh: Mesh
var _rock_mats: Array[StandardMaterial3D] = []
var _crystal_mat := StandardMaterial3D.new()
var _portal_mat := StandardMaterial3D.new()
var _portal_fill_mat := StandardMaterial3D.new()


func _ready() -> void:
	var rock := SphereMesh.new()
	rock.radial_segments = 6
	rock.rings = 3
	_rock_mesh = _flat_shaded(rock)
	var crystal := SphereMesh.new()
	crystal.radial_segments = 4
	crystal.rings = 1
	_crystal_mesh = _flat_shaded(crystal)
	for c in [Palette.SLATE.darkened(0.12), Palette.SLATE, Palette.SLATE.lightened(0.12)]:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 1.0
		_rock_mats.append(m)
	_crystal_mat.albedo_color = Palette.ENERGY
	_crystal_mat.emission_enabled = true
	_crystal_mat.emission = Palette.ENERGY
	_crystal_mat.emission_energy_multiplier = 1.2
	_portal_mat.albedo_color = Palette.ACCENT
	_portal_mat.emission_enabled = true
	_portal_mat.emission = Palette.ACCENT
	_portal_mat.emission_energy_multiplier = 2.0
	_portal_fill_mat.albedo_color = Color(Palette.ACCENT, 0.22)
	_portal_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_portal_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_portal_fill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_comet_mat.albedo_color = Color("ffb067")
	_comet_mat.emission_enabled = true
	_comet_mat.emission = Color("ff7a2e")
	_comet_mat.emission_energy_multiplier = 1.6
	_tail_mat.vertex_color_use_as_albedo = true
	_tail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


func setup(p_car: Car, p_roads: RoadGenerator, seed_value := -1) -> void:
	car = p_car
	roads = p_roads
	if seed_value >= 0:
		_rng.seed = seed_value + 1000
	else:
		_rng.randomize()


func activate() -> void:
	if active:
		return
	active = true
	_time = 0.0
	_next_comet = _rng.randf_range(2.0, 4.0)
	var z := car.global_position.z
	_next_row_z = z - 70.0
	_next_portal = _plan_portal(z - car.speed * _rng.randf_range(first_portal_time.x, first_portal_time.y))


func deactivate() -> void:
	active = false
	for n in _items:
		if is_instance_valid(n):
			n.queue_free()
	_items.clear()
	_spinners.clear()
	_crystals.clear()
	rocks.clear()
	portals.clear()
	_next_portal = null


func update(delta: float) -> void:
	if not active:
		return
	var z := car.global_position.z
	_time += delta
	while _next_row_z > z - fill_distance:
		# Portalın önünde kısa bir kayasız yaklaşma payı (tünelin ağzına hizalanmak için)
		if _next_portal and _next_row_z <= _next_portal.z + 35.0:
			_spawn_portal(_next_portal)
			_next_row_z = _next_portal.z - 45.0
			var interval := car.speed * _rng.randf_range(portal_interval.x, portal_interval.y)
			_next_portal = _plan_portal(_next_portal.z - interval)
			continue
		var stop := _next_portal.z + 35.0 if _next_portal else -INF
		_next_row_z = _spawn_chunk(_next_row_z, stop)
	# Kuyruklu kayalar: uzaktan parlayarak bize doğru gelir
	if _time >= _next_comet:
		_next_comet = _time + _rng.randf_range(comet_interval.x, comet_interval.y)
		_spawn_comet()
	for r in rocks:
		if r.has("v") and is_instance_valid(r.node):
			r.node.position += r.v * delta
			r.x = r.node.position.x
			r.y = r.node.position.y
			r.z = r.node.position.z

	var limit := z + 30.0
	for i in range(_items.size() - 1, -1, -1):
		var n := _items[i]
		if not is_instance_valid(n) or n.position.z > limit:
			if is_instance_valid(n):
				n.queue_free()
			_items.remove_at(i)
	rocks = rocks.filter(func(r): return r.z < limit and is_instance_valid(r.node))
	portals = portals.filter(func(p): return p.z < limit)
	_spinners = _spinners.filter(func(n): return is_instance_valid(n))
	_collect_crystals()
	for n in _spinners:
		n.rotate_y(2.0 * delta)


## Kristal toplama: fizik çakışmasını beklemeden, kanat genişliğine göre doğrudan
## kontrol edilir. Böylece kristal kanada değdiği anda toplanır, ses gecikmez.
func _collect_crystals() -> void:
	if car.mode != Car.Mode.FLYING:
		return
	var pos := car.global_position + Vector3(0, 0.6, 0)
	for i in range(_crystals.size() - 1, -1, -1):
		if not is_instance_valid(_crystals[i]):
			_crystals.remove_at(i)
			continue
		var cr: Node3D = _crystals[i]
		var d := cr.global_position - pos
		if absf(d.x) < CRYSTAL_REACH.x and absf(d.y) < CRYSTAL_REACH.y and absf(d.z) < CRYSTAL_REACH.z:
			_crystals.remove_at(i)
			cr.queue_free()
			crystal_collected.emit()


## Önümüzdeki (dist metre içindeki) kristallerin konumları: test sürücüsü için
func crystals_ahead(z: float, dist: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for cr in _crystals:
		if is_instance_valid(cr) and cr.global_position.z < z and cr.global_position.z > z - dist:
			out.append(cr.global_position)
	return out


## Araba önündeki ilk portal
func next_portal(z: float) -> Portal:
	for p in portals:
		if p.z < z:
			return p
	return _next_portal


## Tünelin orta çizgisi (dünya konumu): halkadan 8 m düz, sonra 26 m yarıçapla 55°
## yukarı kıvrılır, 14 m o açıyla devam eder
func _tube_path(ring: Vector3) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var straight := 8.0
	var radius := 26.0
	var turn := deg_to_rad(55.0)
	var z := 0.0
	while z <= straight:
		pts.append(ring + Vector3(0, 0, -z))
		z += 4.0
	var c := ring + Vector3(0, radius, -straight)
	var a := deg_to_rad(7.0)
	while a <= turn + 0.001:
		pts.append(c + Vector3(0, -radius * cos(a), -radius * sin(a)))
		a += deg_to_rad(7.0)
	var dir := Vector3(0, sin(turn), -cos(turn))
	var last := pts[pts.size() - 1]
	for d in [7.0, 14.0]:
		pts.append(last + dir * d)
	return pts


## Y ekseni dir'e bakan dönüş (boru parçaları için)
func _basis_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var zz := x.cross(y).normalized()
	x = y.cross(zz).normalized()
	return Basis(x, y, zz)


## Portalı, arabanın launch_time saniye sonra yukarıdaki bir yola ineceği yere koyar.
## Portal yolların hizasından yana kaydırılır ki araba yükselirken yollara girmesin.
func _plan_portal(z_desired: float) -> Portal:
	var v := roads.estimate_speed(car.global_position.z - z_desired)
	# İnişten sonra hizalanıp gaza basmaya yetecek kadar yol kalsın. Önce bol
	# pay (1.8 sn) ara; istenen yerden çok ileride kalıyorsa payı azalt ki
	# portal enerjinin yetmeyeceği kadar uzağa itilmesin.
	# (Roket gaz yolun son ~0.6 sn'sinde basılır: pay normal hızla hesaplanır)
	var z_land := z_desired - v * launch_time
	var landing := {}
	for run_up in [1.8, 1.3, 0.9]:
		landing = roads.find_landing(z_land, 12.0, v * run_up + 10.0)
		if not landing.is_empty() and landing.z > z_land - v * 2.0:
			break
	if landing.is_empty():
		return null
	var seg: RoadGenerator.Segment = landing.seg
	var p := Portal.new()
	p.land = Vector3(seg.x, seg.top_at(landing.z), landing.z)
	p.z = landing.z + v * launch_time
	# Yükselirken yolların bulunduğu yükseklik bandından geçtiği bölge
	var rise_far := p.z - v * 1.8 - 5.0
	p.clear_y = maxf(roads.max_top_between(p.z + 5.0, rise_far), seg.max_top()) + 2.0
	p.x = seg.x + corridor_half_width + 10.0
	for offset in [0.0, 8.0, -8.0, 11.0, -11.0, 14.0, -14.0, 18.0, -18.0, 22.0, -22.0, 27.0, -27.0]:
		if roads.is_clear(seg.x + offset, p.z + 5.0, rise_far, 3.0):
			p.x = seg.x + offset
			break
	return p


## Bir kaya parçası (~30-45 m) üretir, bir sonraki parçanın z'sini döndürür.
## Kayalar sıra sıra değil: dağınık alan, gevşek duvar ya da yığın; boyları ve
## yükseklikleri karışık. Her yerde kanat açıklığı kadar en az bir geçit kalır.
func _spawn_chunk(z: float, stop_z: float) -> float:
	var length := _rng.randf_range(30.0, 45.0)
	var z_end := maxf(z - length, stop_z)
	if z - z_end < 8.0:
		return z_end
	var dens := lerpf(rock_density.x, rock_density.y, clampf(_time / maxf(density_time, 0.1), 0.0, 1.0))
	var n := roundi(dens * (z - z_end) / 100.0 * _rng.randf_range(0.7, 1.3))
	var cx := roads.path_x_at(z)
	var fy := car.flight_altitude
	var style := _rng.randf()
	var tries := 0
	var placed := 0
	if style < 0.25:
		# Gevşek duvar: koridoru eğri büğrü kesen kayalar, düzensiz bir geçit
		var wz := _rng.randf_range(z_end + 4.0, z - 4.0)
		var gap_x := cx + _rng.randf_range(-10.0, 10.0)
		var gap_w := _rng.randf_range(8.0, 11.0)
		var x := cx - corridor_half_width - 2.0
		while x < cx + corridor_half_width + 2.0:
			var r := _rng.randf_range(2.0, 3.2)
			if absf(x - gap_x) > gap_w * 0.5 + r * 0.85:
				_try_rock(Vector3(x, fy + _rng.randf_range(-1.2, 1.2), wz + _rng.randf_range(-3.5, 3.5)), r, true)
			x += r * _rng.randf_range(1.5, 2.3)
		placed = n / 2
	elif style < 0.4:
		# Yığın: birbirine yaslanmış birkaç kaya, farklı yükseklikler
		var c := Vector3(cx + _rng.randf_range(-10.0, 10.0), fy, _rng.randf_range(z_end + 5.0, z - 5.0))
		for i in _rng.randi_range(3, 5):
			var r := _rng.randf_range(1.8, 3.4)
			_try_rock(c + Vector3(_rng.randf_range(-4.0, 4.0), _rng.randf_range(-1.0, 6.0), _rng.randf_range(-4.0, 4.0)), r, true)
		placed = n / 2
	while placed < n and tries < n * 6:
		tries += 1
		var r := _rng.randf_range(1.6, 3.0) if _rng.randf() > 0.1 else _rng.randf_range(3.5, 5.0)
		var h := _rng.randf()
		var y := fy + _rng.randf_range(-1.5, 1.5)
		if h < high_rock_chance:
			y = fy + _rng.randf_range(5.5, 9.0)
		elif h < high_rock_chance + mid_rock_chance:
			y = fy + _rng.randf_range(2.5, 4.5)
		var pos := Vector3(cx + _rng.randf_range(-corridor_half_width - 3.0, corridor_half_width + 3.0), y,
			_rng.randf_range(z_end, z))
		if _try_rock(pos, r, false):
			placed += 1
	_spawn_decor(cx, (z + z_end) * 0.5)
	return z_end


## Kayayı yerleştir: yakınındaki kayalarla arası ya kanat açıklığından geniş olmalı
## ya da birbirine yaslanmalı (tek büyük kaya gibi). Yanına aynı hizada geçit
## kalmıyorsa konmaz. merge: yaslanmaya izin (duvar, yığın)
func _try_rock(pos: Vector3, r: float, merge: bool) -> bool:
	var span: float = car.wing_half_span * 2.0 + 0.6
	var near: Array = []
	for o in rocks:
		if o.has("v"):
			continue
		var reach: float = 0.85 * (r + o.r)
		if absf(o.z - pos.z) > reach + 3.0 or absf(o.y - pos.y) > reach + 1.0:
			continue
		var dx := absf(o.x - pos.x)
		if dx < reach * (0.75 if merge else 0.55):
			continue  # yaslanmış: aynı kaya kütlesi
		if dx - reach < span:
			return false
		near.append(o)
	# Aynı hizada (z) uçuş yüksekliğinde koridorda en az bir geçit kalmalı
	var fy := car.flight_altitude
	if absf(pos.y - fy) < 0.85 * r + 1.5:
		var cx := roads.path_x_at(pos.z)
		var blocks: Array[Vector2] = [Vector2(pos.x - 0.85 * r - 1.0, pos.x + 0.85 * r + 1.0)]
		for o in rocks:
			if not o.has("v") and absf(o.z - pos.z) < 0.85 * (r + o.r) + 3.0 and absf(o.y - fy) < 0.85 * o.r + 1.5:
				blocks.append(Vector2(o.x - 0.85 * o.r - 1.0, o.x + 0.85 * o.r + 1.0))
		blocks.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var cur := cx - corridor_half_width - 4.0
		var ok := false
		for b in blocks:
			if b.x - cur >= span:
				ok = true
				break
			cur = maxf(cur, b.y)
		if not ok and cx + corridor_half_width + 4.0 - cur >= span:
			ok = true
		if not ok:
			return false
	_spawn_rock(pos, r)
	return true


## Uzakta süzülen kayalar (dekor)
func _spawn_decor(cx: float, z: float) -> void:
	var fy := car.flight_altitude
	for i in _rng.randi_range(0, 2):
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var deco := MeshInstance3D.new()
		deco.mesh = _rock_mesh
		deco.material_override = _rock_mats[_rng.randi() % _rock_mats.size()]
		deco.position = Vector3(cx + side * _rng.randf_range(40.0, 110.0),
			fy + _rng.randf_range(-25.0, 15.0), z)
		var s := _rng.randf_range(6.0, 20.0)
		deco.scale = Vector3(s, s * _rng.randf_range(0.5, 1.0), s)
		deco.rotation = Vector3(_rng.randf() * TAU, _rng.randf() * TAU, 0)
		deco.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(deco)
		_items.append(deco)


func _spawn_rock(pos: Vector3, r: float) -> Dictionary:
	var area := Area3D.new()
	area.position = pos
	add_child(area)
	var mesh := MeshInstance3D.new()
	mesh.mesh = _rock_mesh
	mesh.material_override = _rock_mats[_rng.randi() % _rock_mats.size()]
	mesh.scale = Vector3(r, r, r) * Vector3(
		_rng.randf_range(1.6, 2.4), _rng.randf_range(1.4, 2.0), _rng.randf_range(1.6, 2.4))
	mesh.rotation = Vector3(_rng.randf() * TAU, _rng.randf() * TAU, 0)
	area.add_child(mesh)
	var shape := SphereShape3D.new()
	shape.radius = r * 0.85
	var col := CollisionShape3D.new()
	col.shape = shape
	area.add_child(col)
	area.body_entered.connect(func(body):
		if body == car:
			rock_hit.emit())
	_items.append(area)
	var info := {"x": pos.x, "y": pos.y, "z": pos.z, "r": r, "node": area}
	rocks.append(info)
	return info


## Kuyruklu kaya: uzakta (~240 m) belirir, parlayan bir kuyrukla bize doğru gelir.
## Arabanın şu anki hizasına yakın bir çizgide gelir: kaçmak için direksiyon ya da yükselme.
func _spawn_comet() -> void:
	var p := car.global_position
	var r := _rng.randf_range(1.8, 2.6)
	var y := car.flight_altitude + (_rng.randf_range(-0.8, 1.2) if _rng.randf() < 0.75 else _rng.randf_range(6.0, 8.0))
	var pos := Vector3(p.x + _rng.randf_range(-5.0, 5.0), y, p.z - 240.0)
	var info := _spawn_rock(pos, r)
	var core: MeshInstance3D = info.node.get_child(0)
	core.material_override = _comet_mat
	core.scale = Vector3.ONE * r * 1.6
	info.v = Vector3(_rng.randf_range(-1.5, 1.5), 0.0, _rng.randf_range(comet_speed.x, comet_speed.y))
	# Kuyruk: arkasında (gelişinin tersine) uzayan, ucu sönen ışık
	var tail := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := 26.0
	var seg := 10
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var w := r * 1.3
		for q in [[Vector3(cos(a0) * w, sin(a0) * w, 0.0), Color(1.0, 0.62, 0.3, 0.75)],
				[Vector3(cos(a1) * w, sin(a1) * w, 0.0), Color(1.0, 0.62, 0.3, 0.75)],
				[Vector3(0, 0, -length), Color(1.0, 0.35, 0.15, 0.0)]]:
			im.surface_set_color(q[1])
			im.surface_add_vertex(q[0])
	im.surface_end()
	tail.mesh = im
	tail.material_override = _tail_mat
	tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	info.node.add_child(tail)
	var sparks := CPUParticles3D.new()
	sparks.amount = 24
	sparks.lifetime = 0.6
	sparks.local_coords = false
	sparks.direction = Vector3(0, 0, -1)
	sparks.spread = 18.0
	sparks.initial_velocity_min = 4.0
	sparks.initial_velocity_max = 10.0
	sparks.gravity = Vector3.ZERO
	sparks.scale_amount_min = 0.25
	sparks.scale_amount_max = 0.5
	var sm := BoxMesh.new()
	sm.size = Vector3.ONE * 0.5
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color("ffc27a")
	sm.material = smat
	sparks.mesh = sm
	info.node.add_child(sparks)


func _spawn_crystal(pos: Vector3) -> void:
	var area := Area3D.new()
	area.position = pos
	add_child(area)
	var mesh := MeshInstance3D.new()
	mesh.mesh = _crystal_mesh
	mesh.material_override = _crystal_mat
	mesh.scale = Vector3(0.9, 1.5, 0.9)
	area.add_child(mesh)
	var shape := SphereShape3D.new()
	shape.radius = 1.6
	var col := CollisionShape3D.new()
	col.shape = shape
	area.add_child(col)
	_items.append(area)
	_spinners.append(area)
	_crystals.append(area)


func _spawn_portal(p: Portal) -> void:
	var root := Area3D.new()
	root.position = Vector3(p.x, car.flight_altitude, p.z)
	add_child(root)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 4.2
	torus.outer_radius = 5.0
	torus.rings = 16
	torus.ring_segments = 6
	ring.mesh = _flat_shaded(torus)
	ring.material_override = _portal_mat
	ring.rotation.x = PI * 0.5
	root.add_child(ring)

	var fill := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 4.2
	disc.bottom_radius = 4.2
	disc.height = 0.05
	disc.radial_segments = 16
	fill.mesh = disc
	fill.material_override = _portal_fill_mat
	fill.rotation.x = PI * 0.5
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fill)

	# Tünel: halkadan sonra kısa düz, sonra yukarı kıvrılan saydam boru (araba içinden
	# geçip yukarı-ileri fırlar). Yukarı kalkan ucu portalın yerini uzaktan belli eder.
	p.path = _tube_path(root.position)
	for i in p.path.size() - 1:
		var a := p.path[i]
		var b := p.path[i + 1]
		var basis := _basis_y((b - a).normalized())
		var cyl := CylinderMesh.new()
		cyl.top_radius = 4.6
		cyl.bottom_radius = 4.6
		cyl.height = a.distance_to(b) + 0.05
		cyl.radial_segments = 18
		cyl.cap_top = false
		cyl.cap_bottom = false
		var tube := MeshInstance3D.new()
		tube.mesh = cyl
		tube.material_override = _portal_fill_mat
		tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tube.transform = Transform3D(basis, (a + b) * 0.5 - root.position)
		root.add_child(tube)
		if i % 2 == 0 and i > 0:
			var rib := MeshInstance3D.new()
			var t := TorusMesh.new()
			t.inner_radius = 4.4
			t.outer_radius = 4.75
			t.rings = 18
			t.ring_segments = 6
			rib.mesh = t
			rib.material_override = _portal_mat
			rib.transform = Transform3D(basis, a - root.position)
			root.add_child(rib)

	var shape := CylinderShape3D.new()
	shape.radius = 4.8
	shape.height = 3.0
	var col := CollisionShape3D.new()
	col.shape = shape
	col.rotation.x = PI * 0.5
	root.add_child(col)
	root.body_entered.connect(func(body):
		if body == car:
			portal_entered.emit(p))

	p.node = root
	portals.append(p)
	_items.append(root)


## Pürüzsüz gölgelemeyi kaldırıp her yüzü düz gösterir (low poly görünüm)
static func _flat_shaded(mesh: Mesh) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	for i in range(0, idx.size(), 3):
		var a := verts[idx[i]]
		var b := verts[idx[i + 1]]
		var c := verts[idx[i + 2]]
		var n := (c - a).cross(b - a)
		if n.length_squared() < 1e-10:
			continue
		n = n.normalized()
		# Yönü orijinal normallere göre dışa doğru düzelt
		if n.dot(normals[idx[i]] + normals[idx[i + 1]] + normals[idx[i + 2]]) < 0.0:
			n = -n
		for v in [a, b, c]:
			out_v.append(v)
			out_n.append(n)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = out_v
	out[Mesh.ARRAY_NORMAL] = out_n
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return result
