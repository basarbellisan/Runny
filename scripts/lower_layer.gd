class_name LowerLayer
extends Node3D
## Alt katman: kayalar, enerji kristalleri ve yukarı fırlatan portallar.
## Sadece araba uçarken aktiftir; araba yola dönünce temizlenir.

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

## Kristal toplama mesafesi (yarı genişlik): x kanatlar, y gövde, z araba boyu
const CRYSTAL_REACH := Vector3(3.2, 1.8, 2.6)

@export var fill_distance := 350.0
@export var corridor_half_width := 14.0
## Portallar arası süre (saniye, o anki hızla)
@export var portal_interval := Vector2(7.0, 10.0)
@export var first_portal_time := Vector2(5.0, 7.0)
## Kaya sırası başına kaya sayısı (en az, en çok)
@export var rocks_per_row := Vector2(1, 3)
## Kaya sıraları arası süre (saniye, o anki hızla)
@export var row_interval := Vector2(0.7, 1.0)
## Kayanın yukarıda (yükselerek kaçılan yükseklikte) süzülme şansı
@export_range(0.0, 1.0) var high_rock_chance := 0.25
## Kristal dizisinin yukarıda çıkma şansı
@export_range(0.0, 1.0) var high_crystal_chance := 0.35
## Portaldan yukarıdaki yola iniş süresi (yaklaşık)
@export var launch_time := 3.0

var car: Car
var roads: RoadGenerator
var active := false
var rocks: Array = []      # { x, z, r, node }
var portals: Array = []    # Portal
var _items: Array[Node3D] = []
var _spinners: Array = []  # dönen kristaller
var _crystals: Array = []
var _next_row_z := 0.0
var _next_portal: Portal
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
	_crystal_mat.albedo_color = Palette.SNOW
	_crystal_mat.emission_enabled = true
	_crystal_mat.emission = Palette.SNOW
	_crystal_mat.emission_energy_multiplier = 1.2
	_portal_mat.albedo_color = Palette.ACCENT
	_portal_mat.emission_enabled = true
	_portal_mat.emission = Palette.ACCENT
	_portal_mat.emission_energy_multiplier = 2.0
	_portal_fill_mat.albedo_color = Color(Palette.ACCENT, 0.22)
	_portal_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_portal_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_portal_fill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


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
	while _next_row_z > z - fill_distance:
		# Portalın önünde kayasız bir yaklaşma payı: hizalanmaya vakit kalsın
		if _next_portal and _next_row_z <= _next_portal.z + 55.0:
			_spawn_portal(_next_portal)
			_next_row_z = _next_portal.z - 25.0
			var interval := car.speed * _rng.randf_range(portal_interval.x, portal_interval.y)
			_next_portal = _plan_portal(_next_portal.z - interval)
			continue
		_spawn_row(_next_row_z)
		# Sıralar arası süre hızdan bağımsız kalsın
		_next_row_z -= maxf(26.0, car.speed * _rng.randf_range(row_interval.x, maxf(row_interval.x, row_interval.y)))

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


## Araba önündeki ilk portal
func next_portal(z: float) -> Portal:
	for p in portals:
		if p.z < z:
			return p
	return _next_portal


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


func _spawn_row(z: float) -> void:
	var cx := roads.path_x_at(z)
	var fy := car.flight_altitude
	var row: Array[Dictionary] = []
	for i in _rng.randi_range(int(rocks_per_row.x), maxi(int(rocks_per_row.x), int(rocks_per_row.y))):
		var r := _rng.randf_range(2.0, 3.8)
		var pos := Vector3(
			cx + _rng.randf_range(-corridor_half_width, corridor_half_width),
			fy + (_rng.randf_range(4.5, 8.0) if _rng.randf() < high_rock_chance else _rng.randf_range(-1.0, 1.0)),
			z + _rng.randf_range(-2.0, 2.0))
		row.append(_spawn_rock(pos, r))

	if _rng.randf() < 0.6:
		for attempt in 5:
			var x := cx + _rng.randf_range(-10.0, 10.0)
			if row.all(func(rk): return absf(rk.x - x) > rk.r + 2.0):
				# Bazı kristal dizileri yukarıda: yükselmenin ödülü
				var y := fy + (6.5 if _rng.randf() < high_crystal_chance else 0.0)
				for k in 3:
					_spawn_crystal(Vector3(x, y, z - 9.0 - k * 4.0))
				break

	# Uzakta süzülen kayalar (dekor)
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
	var info := {"x": pos.x, "z": pos.z, "r": r, "node": area}
	rocks.append(info)
	return info


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

	# Yukarı doğru ışık sütunu: portalın yerini uzaktan belli eder
	var beam := MeshInstance3D.new()
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.6
	beam_mesh.bottom_radius = 1.6
	beam_mesh.height = 30.0
	beam_mesh.radial_segments = 8
	beam.mesh = beam_mesh
	beam.material_override = _portal_fill_mat
	beam.position.y = 20.0
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(beam)

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
