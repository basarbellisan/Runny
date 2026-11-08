class_name LowerLayer
extends Node3D
## Alt katman: kayalar, kuyruklu kayalar ve yukarı fırlatan portallar (tünel).
## Aşağıda kristal yok: depo, aşağıdaki hayat süresidir. Sadece araba uçarken
## aktiftir; araba yola dönünce temizlenir.

signal crystal_collected
signal rock_hit
## Hayalet arabanın içinden geçti (çarpmaz: enerji emer)
signal ghost_passed
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
## Kayaların yerine üst kattaki yolların kırık parçaları (RoadDebris): havada asılı, kendi
## eksenlerinde döner; aralarında bağımsız molozlar yüzer (zararsız, çarpınca savrulur). false: eski kayalar
@export var use_debris := true
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
## Kuyruklu kayaların yerine hayalet: aynı yerden aynı hızla bize doğru uçar, çarpılmaz, içimizden
## geçer (enerji emer: ghost_passed). false: eski kuyruklu kaya
@export var comets_are_ghosts := true
## Test: hayalet tam arabanın hizasında ve yüksekliğinde gelir (içimizden geçer)
var ghost_aim := false
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
## Ders (kanatlar): rastgele kaya, kaya duvarı ve kuyruklu kaya yok; kayaları ders koyar (place_rock)
var scripted := false
## Alt katmanda geçen süre ve sıradaki kuyruklu kayanın zamanı
var _time := 0.0
var _next_comet := 0.0
var _comet_mat := StandardMaterial3D.new()
## Hayaletler: { node, v } (kaya değil: kaya kuralları ve otomatik pilotun kaçışı onları saymaz)
var ghosts: Array = []
const GHOST_SCENE := preload("res://models/ghosts/ghost.glb")
## Kameraya bu kadar (m) yaklaşınca tamamen söner, ikincisinden uzakta tam görünür
const GHOST_NEAR_FADE := Vector2(3.0, 9.0)
var _ghost_body: ShaderMaterial
var _ghost_face: ShaderMaterial
var _ghost_eye: ShaderMaterial
var _ghost_mats: Array[ShaderMaterial] = []
var _tail_mat := StandardMaterial3D.new()
var _rng := RandomNumberGenerator.new()

var _rock_mesh: Mesh
## Kırık yol parçası kalıpları (boyut başına): { mesh, hulls (çarpışma: bant bant dış bükey),
## aabb, feature }. Oyun başında kare kare hazırlanır (_pool_queue), sonra yalnız kopyalanır
var _debris_pool: Array = [[], [], [], []]
var _rubble_meshes: Array[Mesh] = []
var _pool_queue: Array = []
var _debris_lit := StandardMaterial3D.new()
var _debris_flat := StandardMaterial3D.new()
## Dönen parçalar: { node, axis (dünya), spin (rad/sn), base (Basis), a (açı), s (ölçek) }
var _debris: Array = []
## Molozlar: { p, b (Basis), v, w (eksen), ws (rad/sn), k (kalıp), s (ölçek), hit }
var _rubble: Array = []
var _rubble_mm: Array[MultiMeshInstance3D] = []
const RUBBLE_CAP := 160
## Molozun arabaya değdiği kutu (yarı genişlik): x kanatlar, y gövde, z araba boyu
const RUBBLE_REACH := Vector3(3.6, 1.3, 2.6)
## Savrulan molozun çarpmadan aldığı hızın payı (0 yapışır, 1 tam esnek sekme)
const RUBBLE_BOUNCE := 0.25
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
	for c in Palette.LOWER.rocks:
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
	_setup_ghost_materials()
	_setup_debris()


## Hayalet malzemeleri (hepsi ortak): örtü yarı saydam, tepede (yüz) opak, etek ucunda %50;
## etek dalgalanır. Önce iç yüz, sonra dış yüz çizilir (next_pass)
func _setup_ghost_materials() -> void:
	var front := ShaderMaterial.new()
	front.shader = preload("res://shaders/ghost.gdshader")
	var back := ShaderMaterial.new()
	back.shader = preload("res://shaders/ghost_back.gdshader")
	for m: ShaderMaterial in [front, back]:
		m.set_shader_parameter("color", Color("f7f4ff"))
		m.set_shader_parameter("glow", 1.0)
		m.set_shader_parameter("alpha_by_height", 1.0)
		m.set_shader_parameter("alpha_bottom", 0.5)
		m.set_shader_parameter("alpha_top", 1.0)
		m.set_shader_parameter("wave_power", 4.0)
		m.set_shader_parameter("wave_amp", 0.22)
		m.set_shader_parameter("scallops", 8.0)
		m.set_shader_parameter("eyes", 0.0)
		m.set_shader_parameter("hem", 0)
		m.set_shader_parameter("trail", 0.0)
		m.set_shader_parameter("near_fade", GHOST_NEAR_FADE)
		_ghost_mats.append(m)
	back.next_pass = front
	_ghost_body = back
	_ghost_face = ShaderMaterial.new()
	_ghost_face.shader = preload("res://shaders/ghost_face.gdshader")
	_ghost_face.set_shader_parameter("near_fade", GHOST_NEAR_FADE)
	_ghost_eye = _ghost_face.duplicate()
	_ghost_eye.set_shader_parameter("color", Color(1, 1, 1, 1))


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
	while use_debris and not _pool_queue.is_empty():
		_build_next_debris()
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
	ghosts.clear()
	_debris.clear()
	_rubble.clear()
	for mm in _rubble_mm:
		mm.multimesh.visible_instance_count = 0
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
	if _time >= _next_comet and not scripted:
		_next_comet = _time + _rng.randf_range(comet_interval.x, comet_interval.y)
		if comets_are_ghosts:
			_spawn_ghost()
		else:
			_spawn_comet()
	for m in _ghost_mats:
		m.set_shader_parameter("t", _time)
	# Geride kalıp silinen hayaletler listeden çıkar
	ghosts = ghosts.filter(func(gh): return is_instance_valid(gh.node))
	for gh in ghosts:
		gh.node.position += gh.v * delta
		if ghost_aim:
			# Test: arabanın hizasını ve yüksekliğini izler (mutlaka içinden geçer)
			var cp := car.global_position
			gh.node.position.x = lerpf(gh.node.position.x, cp.x, 1.0 - exp(-8.0 * delta))
			gh.node.position.y = lerpf(gh.node.position.y, cp.y + 0.5, 1.0 - exp(-8.0 * delta))
	_debris = _debris.filter(func(d): return is_instance_valid(d.node))
	for d in _debris:
		d.a += d.spin * delta
		d.node.basis = (Basis(d.axis, d.a) * d.base).scaled(Vector3.ONE * d.s)
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
	if scripted:
		_spawn_decor(roads.path_x_at(z), (z + z_end) * 0.5)
		return z_end
	var dens := lerpf(rock_density.x, rock_density.y, clampf(_time / maxf(density_time, 0.1), 0.0, 1.0))
	var n := roundi(dens * (z - z_end) / 100.0 * _rng.randf_range(0.7, 1.3))
	if use_debris:
		_spawn_debris_chunk(z, z_end, n)
		_spawn_decor(roads.path_x_at(z), (z + z_end) * 0.5)
		return z_end
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
	if use_debris:
		# Uzakta süzülen büyük kırık yol parçaları (çarpışmasız, gölgesiz), çok yavaş döner
		for i in _rng.randi_range(0, 2):
			var side := -1.0 if _rng.randf() < 0.5 else 1.0
			var proto := _pick_proto(RoadDebris.Size.LARGE if _rng.randf() < 0.6 else RoadDebris.Size.LONG)
			var pos := Vector3(cx + side * _rng.randf_range(45.0, 115.0), fy + _rng.randf_range(-25.0, 15.0), z)
			var axis := _rand_axis()
			_spawn_debris(proto, pos, Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, 0)), axis,
				_rng.randf_range(0.03, 0.1) * _rand_sign(), false, false, _rng.randf_range(1.0, 2.0))
		return
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


## Ders için: sıradaki tüneli bu z'ye planla (öndeki sıra oraya gelince kurulur)
func plan_portal_at(z: float) -> void:
	_next_portal = _plan_portal(z)


## Ders için tek kaya (tam istenen yerde)
func place_rock(pos: Vector3, r: float) -> Dictionary:
	if use_debris:
		# Derste: küçük bir kırık parça, yatık (üstünden yükselerek geçilir), dik eksende yavaşça döner
		var proto := _pick_proto(RoadDebris.Size.SMALL)
		var place := _plan_motion(proto, pos, 1)
		_place_debris(proto, place, false)
		return {"x": pos.x, "y": pos.y, "z": pos.z, "r": r}
	return _spawn_rock(pos, r)


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


## Hayalet (kuyruklu kayanın yerine): uzakta (~240 m) belirir, başı önde, ekseni yataydan 20°
## yukarı eğik bize doğru uçar; arabanın hizasına yakın bir çizgide gelir. Çarpılmaz: içinden
## geçilince bir kez enerji emer (ghost_passed). Etek dalgalanır.
func _spawn_ghost() -> void:
	var p := car.global_position
	var y := car.flight_altitude + (_rng.randf_range(-0.8, 1.2) if _rng.randf() < 0.75 else _rng.randf_range(6.0, 8.0))
	var area := Area3D.new()
	area.position = Vector3(p.x + _rng.randf_range(-5.0, 5.0), y, p.z - 240.0)
	if ghost_aim:
		area.position = Vector3(p.x, p.y, p.z - 240.0)
	add_child(area)
	var g: Node3D = GHOST_SCENE.instantiate()
	# Baş (+Y) bize (+Z) doğru, 20° yukarı
	g.rotation = Vector3(deg_to_rad(70), 0, 0)
	area.add_child(g)
	for mi in g.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for si in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(si)
			var name := src.resource_name if src else ""
			m.set_surface_override_material(si, _ghost_body if name == "Body" else (_ghost_face if name == "Face" else _ghost_eye))
	var shape := SphereShape3D.new()
	shape.radius = 1.9
	var col := CollisionShape3D.new()
	col.shape = shape
	area.add_child(col)
	var info := {"node": area, "v": Vector3(0.0 if ghost_aim else _rng.randf_range(-1.5, 1.5), 0.0, _rng.randf_range(comet_speed.x, comet_speed.y)), "hit": false}
	area.body_entered.connect(func(body):
		if body == car and not info.hit:
			info.hit = true
			ghost_passed.emit())
	_items.append(area)
	ghosts.append(info)


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


# --- Kırık yol parçaları (kayaların yerine) ---------------------------------------------------

## Parçanın havadaki hareketi: serbest takla (rastgele eksen), yatık dönüş (dik eksen: düz durur,
## yükselerek üstünden geçilir), uzun ekseninde yuvarlanma (uçuş yönünde uzanır), enine yuvarlanma
## (kopmuş köprü: koridoru keser, yanında geçit)
enum Motion { TUMBLE, FLAT, ROLL, WALL }


func _setup_debris() -> void:
	for m: StandardMaterial3D in [_debris_lit, _debris_flat]:
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 1.0
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_debris_flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if not use_debris:
		return
	# Kalıplar: biçimler orta ve büyük parçalara dağılır (tek rampa, eğimli, yokuş); şerit düzenleri
	# sırayla, eşit dağılır. Boyutlar dönüşümlü sıraya girer (erken lazım olursa her boyuttan biri hazır)
	var F := RoadDebris.Feature
	var feats := [
		[F.NONE, F.NONE, F.NONE, F.NONE, F.NONE, F.NONE, F.NONE, F.NONE],
		[F.RAMP_ALONE, F.NONE, F.BANK, F.NONE, F.RAMP_ALONE, F.NONE, F.BANK, F.NONE],
		[F.NONE, F.CLIMB, F.NONE, F.BANK, F.CLIMB, F.NONE],
		[F.NONE, F.NONE, F.NONE, F.NONE, F.NONE],
	]
	var style := 0
	for i in 8:
		for size in 4:
			if i < feats[size].size():
				_pool_queue.append({"size": size, "seed": i + 1, "feature": feats[size][i],
					"style": style % RoadGenerator.LINE_STYLES.size()})
				style += 1
		_pool_queue.append({"rubble": i + 1})
		# Moloz kalıbı başına bir çoklu örnek (tek çizim): konumları her kare güncellenir
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = RUBBLE_CAP
		mm.visible_instance_count = 0
		mm.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_rubble_mm.append(mmi)


func _process(delta: float) -> void:
	if not use_debris:
		return
	# Kalıplar kare başına bir tane hazırlanır (takılma olmasın); uçuşa geçilince kalanı hemen
	if not active and not _pool_queue.is_empty():
		_build_next_debris()
	if not _rubble.is_empty():
		_update_rubble(delta)


func _build_next_debris() -> void:
	var job: Dictionary = _pool_queue.pop_front()
	if job.has("rubble"):
		var holder := Node3D.new()
		holder.add_child(RoadDebris.build_rubble(job.rubble))
		var baked := _bake_debris(holder, false)
		holder.free()
		_rubble_mm[_rubble_meshes.size()].multimesh.mesh = baked.mesh
		_rubble_meshes.append(baked.mesh)
		return
	var node := RoadDebris.build(job.size, job.seed, job.style, job.feature)
	var proto := _bake_debris(node, true)
	node.free()
	proto.feature = job.feature
	proto.size = job.size
	_debris_pool[job.size].append(proto)


## Parçanın tüm yüzeyleri tek örgüde (renkler köşe renginde): gölgeli ve gölgesiz (şerit çizgisi)
## iki yüzey, az çizim. Çarpışma: her yarı boyuna ~6 m'lik bantlara bölünür, her bant dış bükey
## (bükülmüş ya da yokuşlu parçada boşluğu doldurmasın); biraz içeri çekilir (sıyırınca affeder)
func _bake_debris(root: Node3D, with_hulls: bool) -> Dictionary:
	var lit_v := PackedVector3Array()
	var lit_n := PackedVector3Array()
	var lit_c := PackedColorArray()
	var flat_v := PackedVector3Array()
	var flat_n := PackedVector3Array()
	var flat_c := PackedColorArray()
	var hulls: Array = []
	var box := AABB()
	var first := true
	for child in root.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var xf := mi.transform
		var local_box := mi.mesh.get_aabb()
		box = xf * local_box if first else box.merge(xf * local_box)
		first = false
		var bands := maxi(1, ceili(local_box.size.z / 6.0))
		var band_len := maxf(local_box.size.z / bands, 0.01)
		var band_pts: Array = []
		for b in bands:
			band_pts.append({})
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var mat := mi.mesh.surface_get_material(si) as StandardMaterial3D
			var flat := mat != null and mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
			var col: Color = mat.albedo_color if mat else Color.WHITE
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms := PackedVector3Array()
			if arr[Mesh.ARRAY_NORMAL] != null:
				norms = arr[Mesh.ARRAY_NORMAL]
			var idx := PackedInt32Array()
			if arr[Mesh.ARRAY_INDEX] != null:
				idx = arr[Mesh.ARRAY_INDEX]
			var count := idx.size() if idx.size() > 0 else verts.size()
			var ov := PackedVector3Array()
			var on := PackedVector3Array()
			ov.resize(count)
			on.resize(count)
			for k in count:
				var vi: int = idx[k] if idx.size() > 0 else k
				ov[k] = xf * verts[vi]
				on[k] = (xf.basis * norms[vi]).normalized() if norms.size() > 0 else Vector3.UP
			var oc := PackedColorArray()
			oc.resize(count)
			oc.fill(col)
			if flat:
				flat_v.append_array(ov)
				flat_n.append_array(on)
				flat_c.append_array(oc)
			else:
				lit_v.append_array(ov)
				lit_n.append_array(on)
				lit_c.append_array(oc)
			if with_hulls:
				for v in verts:
					var f := (v.z - local_box.position.z) / band_len
					var w := xf * v
					var key := Vector3i(roundi(w.x * 10.0), roundi(w.y * 10.0), roundi(w.z * 10.0))
					# Komşu bantlar ~0.6 m üst üste biner (arada boşluk kalmasın)
					for b in range(maxi(0, floori(f - 0.1)), mini(bands, floori(f + 0.1) + 1)):
						band_pts[b][key] = w
		for d: Dictionary in band_pts:
			if d.size() < 4:
				continue
			var pts := PackedVector3Array(d.values())
			var c := Vector3.ZERO
			for p in pts:
				c += p
			c /= pts.size()
			for i in pts.size():
				pts[i] = c + (pts[i] - c) * 0.92
			hulls.append(pts)
	var mesh := ArrayMesh.new()
	for g in [[lit_v, lit_n, lit_c, _debris_lit], [flat_v, flat_n, flat_c, _debris_flat]]:
		if (g[0] as PackedVector3Array).is_empty():
			continue
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = g[0]
		a[Mesh.ARRAY_NORMAL] = g[1]
		a[Mesh.ARRAY_COLOR] = g[2]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		mesh.surface_set_material(mesh.get_surface_count() - 1, g[3])
	return {"mesh": mesh, "hulls": hulls, "aabb": box}


func _pick_proto(size: int) -> Dictionary:
	while (_debris_pool[size] as Array).is_empty() and not _pool_queue.is_empty():
		_build_next_debris()
	var list: Array = _debris_pool[size]
	return list[_rng.randi() % list.size()]


func _rand_axis() -> Vector3:
	var v := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
	return v.normalized() if v.length_squared() > 0.01 else Vector3.UP


func _rand_sign() -> float:
	return 1.0 if _rng.randf() < 0.5 else -1.0


## Parçanın duruşu, dönüşü ve kapladığı yer. Kapladığı yer dönüşün süpürdüğü hacimdir (yuvarlar:
## x, y, z, rad yatay yarıçap, h dikey yarı yükseklik): parça dönerken de geçitler açık kalsın
func _plan_motion(proto: Dictionary, pos: Vector3, mode: int) -> Dictionary:
	var box: AABB = proto.aabb
	var r_all := 0.0
	var r_xz := 0.0
	var r_xy := 0.0
	var y_max := 0.0
	for i in 8:
		var c := box.get_endpoint(i)
		r_all = maxf(r_all, c.length())
		r_xz = maxf(r_xz, Vector2(c.x, c.z).length())
		r_xy = maxf(r_xy, Vector2(c.x, c.y).length())
		y_max = maxf(y_max, absf(c.y))
	var base: Basis
	var axis: Vector3
	var spin: float
	var blobs: Array = []
	match mode:
		Motion.TUMBLE:
			base = Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU))
			axis = _rand_axis()
			spin = _rng.randf_range(0.25, 0.7) * _rand_sign()
			blobs.append({"x": pos.x, "y": pos.y, "z": pos.z, "rad": r_all, "h": r_all})
		Motion.FLAT:
			base = Basis.from_euler(Vector3(_rng.randf_range(-0.18, 0.18), _rng.randf() * TAU, _rng.randf_range(-0.18, 0.18)))
			axis = Vector3(_rng.randf_range(-0.15, 0.15), 1.0, _rng.randf_range(-0.15, 0.15)).normalized()
			spin = _rng.randf_range(0.2, 0.55) * _rand_sign()
			blobs.append({"x": pos.x, "y": pos.y, "z": pos.z, "rad": r_xz, "h": y_max + r_xz * 0.36})
		_:
			# Uzun ekseni (parçanın z'si) uçuş yönünde ya da enine; o eksen etrafında yuvarlanır
			var yaw := _rng.randf_range(-0.15, 0.15) if mode == Motion.ROLL else PI * 0.5 + _rng.randf_range(-0.2, 0.2)
			var yb := Basis(Vector3.UP, yaw)
			base = yb * Basis(Vector3.BACK, _rng.randf() * TAU)
			axis = yb * Vector3.BACK
			spin = _rng.randf_range(0.12, 0.35) * _rand_sign()
			var z0 := box.position.z + r_xy * 0.5
			var z1 := box.end.z - r_xy * 0.5
			var n := maxi(1, ceili((z1 - z0) / maxf(r_xy, 1.0)))
			for i in n + 1:
				var p := pos + axis * lerpf(z0, z1, float(i) / n)
				blobs.append({"x": p.x, "y": p.y, "z": p.z, "rad": r_xy, "h": r_xy})
	return {"pos": pos, "base": base, "axis": axis, "spin": spin, "blobs": blobs}


## Kapladığı yer boşsa parçayı koy: başka parçalarla üst üste binmez; aralarında kalan boşluk ya
## kanat açıklığından geniştir ya da hiç yoktur (merge: yığında dar aralık olabilir, geçit sayılmaz).
## Aynı hizada uçuş yüksekliğinde koridorda en az bir geçit kalmalı
func _place_debris(proto: Dictionary, place: Dictionary, check := true, merge := false) -> bool:
	if check and not _debris_fits(place.blobs, merge):
		return false
	var node := _spawn_debris(proto, place.pos, place.base, place.axis, place.spin, true, true, 1.0)
	for b: Dictionary in place.blobs:
		rocks.append({"x": b.x, "y": b.y, "z": b.z, "r": b.rad / 0.85, "rad": b.rad, "h": b.h, "node": node})
	# Etrafında kendi molozları
	for i in [2, 4, 6, 8][proto.size] + _rng.randi_range(0, 3):
		var b: Dictionary = place.blobs[_rng.randi() % place.blobs.size()]
		_add_rubble(Vector3(b.x, b.y, b.z) + _rand_axis() * _rng.randf_range(b.rad * 0.7, b.rad + 4.0))
	return true


func _debris_fits(blobs: Array, merge: bool) -> bool:
	var span: float = car.wing_half_span * 2.0 + 0.6
	var fy := car.flight_altitude
	for b: Dictionary in blobs:
		for o in rocks:
			if o.has("v"):
				continue
			var orad: float = o.get("rad", 0.85 * o.r)
			var oh: float = o.get("h", 0.85 * o.r)
			if absf(o.z - b.z) > b.rad + orad + 3.0 or absf(o.y - b.y) > b.h + oh + 2.0:
				continue
			var gap: float = absf(o.x - b.x) - b.rad - orad
			if gap < (0.3 if merge else span):
				return false
		if absf(b.y - fy) < b.h + 1.5:
			var cx := roads.path_x_at(b.z)
			var blocks: Array[Vector2] = []
			for o in rocks + blobs:
				if o.has("v"):
					continue
				var orad: float = o.get("rad", 0.85 * o.get("r", 0.0))
				var oh: float = o.get("h", orad)
				if absf(o.z - b.z) < b.rad + orad + 3.0 and absf(o.y - fy) < oh + 1.5:
					blocks.append(Vector2(o.x - orad - 1.0, o.x + orad + 1.0))
			blocks.sort_custom(func(a: Vector2, c: Vector2) -> bool: return a.x < c.x)
			var cur := cx - corridor_half_width - 4.0
			var ok := false
			for bl in blocks:
				if bl.x - cur >= span:
					ok = true
					break
				cur = maxf(cur, bl.y)
			if not ok and cx + corridor_half_width + 4.0 - cur >= span:
				ok = true
			if not ok:
				return false
	return true


func _spawn_debris(proto: Dictionary, pos: Vector3, base: Basis, axis: Vector3, spin: float,
		collide: bool, shadow: bool, scale_by: float) -> Node3D:
	var node: Node3D = Area3D.new() if collide else Node3D.new()
	node.position = pos
	node.basis = base.scaled(Vector3.ONE * scale_by)
	add_child(node)
	var mi := MeshInstance3D.new()
	mi.mesh = proto.mesh
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	if collide:
		for pts: PackedVector3Array in proto.hulls:
			var sh := ConvexPolygonShape3D.new()
			sh.points = pts
			var col := CollisionShape3D.new()
			col.shape = sh
			node.add_child(col)
		(node as Area3D).body_entered.connect(func(body):
			if body == car:
				rock_hit.emit())
	_items.append(node)
	_debris.append({"node": node, "axis": axis, "spin": spin, "base": base, "a": 0.0, "s": scale_by})
	return node


## Bir parça boyu (z..z_end) kırık yol: kopmuş köprü, yığın ya da dağınık alan; aralarda moloz
func _spawn_debris_chunk(z: float, z_end: float, n: int) -> void:
	var S := RoadDebris.Size
	var cx := roads.path_x_at(z)
	var fy := car.flight_altitude
	var style := _rng.randf()
	var weight := 0.0
	if style < 0.25:
		# Kopmuş köprü: koridoru enine kesen uzun (ya da büyük) parça, uzun ekseninde yuvarlanır;
		# yanında kanat açıklığından geniş bir geçit (bazen iki yanında birer parça)
		var wz := _rng.randf_range(z_end + 4.0, z - 4.0)
		var gap_x := cx + _rng.randf_range(-9.0, 9.0)
		var gap_w := _rng.randf_range(9.0, 12.0)
		var sides := [-1.0, 1.0] if _rng.randf() < 0.6 else [_rand_sign()]
		for side: float in sides:
			var proto := _pick_proto(S.LONG if _rng.randf() < 0.55 else S.LARGE)
			var hl: float = (proto.aabb as AABB).size.z * 0.5
			var pos := Vector3(gap_x + side * (gap_w * 0.5 + hl), fy + _rng.randf_range(-1.0, 1.0), wz + _rng.randf_range(-2.0, 2.0))
			_place_debris(proto, _plan_motion(proto, pos, Motion.WALL))
		weight = n * 0.5
	elif style < 0.4:
		# Yığın: birbirine yakın birkaç küçük-orta parça, bol moloz
		var c := Vector3(cx + _rng.randf_range(-10.0, 10.0), fy + _rng.randf_range(-1.0, 3.0), _rng.randf_range(z_end + 6.0, z - 6.0))
		for i in _rng.randi_range(3, 5):
			var proto := _pick_proto(S.SMALL if _rng.randf() < 0.6 else S.MEDIUM)
			var pos := c + Vector3(_rng.randf_range(-8.0, 8.0), _rng.randf_range(-3.0, 5.0), _rng.randf_range(-7.0, 7.0))
			_place_debris(proto, _plan_motion(proto, pos, Motion.TUMBLE), true, true)
		for i in _rng.randi_range(10, 18):
			_add_rubble(c + Vector3(_rng.randf_range(-10.0, 10.0), _rng.randf_range(-5.0, 7.0), _rng.randf_range(-9.0, 9.0)))
		weight = n * 0.5
	var tries := 0
	while weight < n and tries < n * 6:
		tries += 1
		var roll := _rng.randf()
		var size: int = S.SMALL if roll < 0.45 else (S.MEDIUM if roll < 0.77 else (S.LARGE if roll < 0.92 else S.LONG))
		var proto := _pick_proto(size)
		var mode: int = Motion.ROLL
		if size == S.SMALL or size == S.MEDIUM:
			mode = Motion.TUMBLE if _rng.randf() < 0.55 else Motion.FLAT
		elif size == S.LARGE:
			mode = Motion.ROLL if _rng.randf() < 0.6 else Motion.FLAT
		var h := _rng.randf()
		var y := fy + _rng.randf_range(-1.5, 1.5)
		if h < high_rock_chance:
			y = fy + _rng.randf_range(6.0, 10.0)
		elif h < high_rock_chance + mid_rock_chance:
			y = fy + _rng.randf_range(2.5, 4.5)
		var pos := Vector3(cx + _rng.randf_range(-corridor_half_width - 3.0, corridor_half_width + 3.0), y, _rng.randf_range(z_end, z))
		if _place_debris(proto, _plan_motion(proto, pos, mode)):
			weight += [1.0, 1.5, 2.5, 3.0][size]
	# Koridorda dağınık molozlar
	for i in _rng.randi_range(6, 14):
		_add_rubble(Vector3(cx + _rng.randf_range(-corridor_half_width - 6.0, corridor_half_width + 6.0),
			fy + _rng.randf_range(-4.0, 9.0), _rng.randf_range(z_end, z)))


## Bağımsız moloz: yerinde çok yavaş süzülür ve döner; arabaya zarar vermez
func _add_rubble(p: Vector3) -> void:
	if _rubble_meshes.is_empty():
		return
	_rubble.append({"p": p, "b": Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)),
		"v": _rand_axis() * _rng.randf_range(0.0, 0.4), "w": _rand_axis(), "ws": _rng.randf_range(0.3, 1.5) * _rand_sign(),
		"k": _rng.randi() % _rubble_meshes.size(), "s": _rng.randf_range(0.8, 2.0), "hit": false})


## Molozlar (görüntü karesinde: yumuşak akar): süzülür, döner; araba değince çarpma açısına göre
## yerçekimsiz savrulur (ağır cisimden sekme: hızın çarpma yönündeki payı kadar itilir, hızla döner)
func _update_rubble(delta: float) -> void:
	var cp := car.get_global_transform_interpolated().origin + Vector3(0, 0.6, 0)
	var flying := car.mode == Car.Mode.FLYING
	var counts: Array[int] = []
	counts.resize(_rubble_mm.size())
	counts.fill(0)
	var keep: Array = []
	for r: Dictionary in _rubble:
		r.p += r.v * delta
		r.b = (Basis(r.w, r.ws * delta) * r.b).orthonormalized()
		if r.p.z > cp.z + 30.0 or r.p.z < cp.z - 900.0:
			continue
		if flying and not r.hit:
			var d: Vector3 = r.p - cp
			var reach: Vector3 = RUBBLE_REACH + Vector3.ONE * 0.4 * float(r.s)
			if absf(d.x) < reach.x and absf(d.y) < reach.y and absf(d.z) < reach.z:
				_kick_rubble(r, d)
		keep.append(r)
		var k: int = r.k
		if counts[k] < RUBBLE_CAP:
			_rubble_mm[k].multimesh.set_instance_transform(counts[k], Transform3D(r.b.scaled(Vector3.ONE * r.s), r.p))
			counts[k] += 1
	_rubble = keep
	for k in _rubble_mm.size():
		_rubble_mm[k].multimesh.visible_instance_count = counts[k]


func _kick_rubble(r: Dictionary, d: Vector3) -> void:
	r.hit = true
	# Çarpma yönü: arabanın kutusuna göre (burundaki moloz ileri, kanat ucundaki yana-ileri)
	var n := Vector3(d.x / RUBBLE_REACH.x, d.y / RUBBLE_REACH.y, -maxf(absf(d.z) / RUBBLE_REACH.z, 0.35)).normalized()
	var push := (1.0 + RUBBLE_BOUNCE) * maxf((car.velocity - (r.v as Vector3)).dot(n), 0.0)
	r.v = (r.v as Vector3) + n * push + _rand_axis() * 1.5
	r.w = _rand_axis()
	r.ws = _rng.randf_range(3.0, 9.0) * _rand_sign()
