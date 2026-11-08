class_name DebrisField
extends Node3D
## Alt katmanda kayaların yerine üst kattaki yolların kırık parçaları (RoadDebris): havada asılı,
## kendi eksenlerinde döner; aralarında bağımsız molozlar yüzer (zararsız, çarpınca savrulur).
## LowerLayer bunu kurar ve sürer: parça boyu üretimi (spawn_chunk), uzak dekor, ders parçası,
## dönüş ve temizlik (update). Parçaların kapladığı yer LowerLayer.rocks listesine girer (kaya
## kuralları, geçit hesabı ve otomatik pilot aynı listeyi kullanır).

## Araba bir parçaya (gövde ya da kanat) çarptı
signal hit

## Kırık parça miktarı (kaya yoğunluğuna göre; telefonda hafif kalsın diye az) ve gölgeleri
@export var debris_amount := 0.7
@export var debris_shadows := false
## Parçaların görünmeye başladığı uzaklık (m, arabadan): ötesi gizli (ekranda daha az parça). Arada
## birden belirmezler: kameradan FADE.y'de tamamen görünmez, FADE.x'te tamamen görünür (sisin
## içinden yavaşça çıkar; malzemenin uzaklık solması, saydamlık maliyeti yok)
@export var debris_view := 255.0
const FADE := Vector2(205.0, 265.0)
const REVEAL_TIME := 1.2
## Görünürlüğün açılma süresi sayacı (-1: açık)
var _reveal_t := -1.0

## Kırık yol parçası kalıpları (boyut başına): { mesh, hulls (çarpışma: bant bant dış bükey),
## aabb, feature }. Menüde kare kare hazırlanır (pool_step), oyun yeniden başlayınca da kalır;
## oyunda yalnız kopyalanır
static var _debris_pool: Array = [[], [], [], []]
static var _rubble_meshes: Array[Mesh] = []
static var _pool_queue: Array = []
static var _pool_planned := false
static var _debris_lit: StandardMaterial3D
static var _debris_flat: StandardMaterial3D
## Gölgelendiriciler bu oturumda ısıtıldı mı (derlenen gölgelendirici sahne yenilense de kalır)
static var _warmed := false


## Gölgelendiriciler ısıtıldı mı (açılış örtüsü bunu bekler)
static func is_warm() -> bool:
	return _warmed


## Dönen parçalar: { node, axis (dünya), spin (rad/sn), base (Basis), a (açı), s (ölçek) }
var _debris: Array = []
## Molozlar: { p, b (Basis), v, w (eksen), ws (rad/sn), k (kalıp), s (ölçek), hit }
var _rubble: Array = []
var _rubble_mm: Array[MultiMeshInstance3D] = []
const RUBBLE_CAP := 160
## Gölgelendirici ısıtma: alt katmanın malzemeleri oyun başında arabanın gövdesinin içinde, minicik
## birkaç kare çizilir (ilk inişte ve ilk hayalette derleme takılması olmasın)
var _warm: Node3D
var _warm_frames := 0
var _frame_count := 0
## Molozun arabaya değdiği kutu (yarı genişlik): x kanatlar, y gövde, z araba boyu
const RUBBLE_REACH := Vector3(3.6, 1.3, 2.6)
## Savrulan moloz: yana itilme hızı (m/s), arabanın hızından aldığı pay, hız sönümü (1/sn)
const RUBBLE_SIDE := Vector2(5.0, 10.0)
const RUBBLE_CARRY := 0.35
const RUBBLE_DRAG := 0.6
var _last_rubble_sfx := 0
## Üretilen parça boyunun portal sınırı (parçalar bunun önüne taşmaz)
var _chunk_stop := -INF

var layer: LowerLayer
var car: Car
var roads: RoadGenerator
var _rng: RandomNumberGenerator
## Bu düğümün kurduğu parçalar (araba geçince silinir)
var _nodes: Array[Node3D] = []
## Ölçüm (test): moloz süresi (µs, toplam)
var perf_rubble_us := 0


func setup(p_layer: LowerLayer, rng: RandomNumberGenerator) -> void:
	layer = p_layer
	car = p_layer.car
	roads = p_layer.roads
	_rng = rng


func _ready() -> void:
	_setup_debris()
	_set_fade(1.0)  # önceki oyun açılma ortasında bittiyse


## Bir parça boyu (z..z_end) kırık yol; n: kaya sayısı karşılığı, stop_z: portal sınırı
func spawn_chunk(z: float, z_end: float, n: int, stop_z: float) -> void:
	_chunk_stop = stop_z
	_spawn_debris_chunk(z, z_end, roundi(n * debris_amount))


## Uzakta süzülen büyük kırık yol parçaları (çarpışmasız, gölgesiz), çok yavaş döner
func spawn_decor(cx: float, z: float) -> void:
	var fy := car.flight_altitude
	for i in (1 if _rng.randf() < 0.5 else 0):
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var proto := _pick_proto(RoadDebris.Size.LARGE if _rng.randf() < 0.6 else RoadDebris.Size.LONG)
		var pos := Vector3(cx + side * _rng.randf_range(45.0, 115.0), fy + _rng.randf_range(-25.0, 15.0), z)
		var axis := _rand_axis()
		_spawn_debris(proto, pos, Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, 0)), axis,
			_rng.randf_range(0.03, 0.1) * _rand_sign(), false, false, _rng.randf_range(1.0, 2.0))


## Ders için tek parça (tam istenen yerde): küçük, yatık (üstünden yükselerek geçilir), dik
## eksende yavaşça döner
func place_lesson_piece(pos: Vector3, r: float) -> Dictionary:
	var proto := _pick_proto(RoadDebris.Size.SMALL)
	var place := _plan_motion(proto, pos, Motion.FLAT)
	_place_debris(proto, place, false)
	return {"x": pos.x, "y": pos.y, "z": pos.z, "r": r}


## Dönüş, uzaktakileri gizleme ve geride kalanların temizliği (fizik adımında, LowerLayer'dan)
func update(delta: float, z: float) -> void:
	_debris = _debris.filter(func(d): return is_instance_valid(d.node))
	for d in _debris:
		d.a += d.spin * delta
		# Uzaktakiler gizli (sisin içinde, görünmeden hemen önce belirir): çizilmez, dönmez
		var shown: bool = z - d.node.position.z < debris_view
		if shown != d.node.visible:
			d.node.visible = shown
		if shown:
			d.node.basis = (Basis(d.axis, d.a) * d.base).scaled(Vector3.ONE * d.s)
	var limit := z + 30.0
	for i in range(_nodes.size() - 1, -1, -1):
		var n := _nodes[i]
		if not is_instance_valid(n) or n.position.z > limit:
			if is_instance_valid(n):
				n.queue_free()
			_nodes.remove_at(i)


## Hepsini sil (alt katman kapanınca)
func clear() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	_debris.clear()
	_rubble.clear()
	for mm in _rubble_mm:
		mm.multimesh.visible_instance_count = 0


## Kurulu parça ya da moloz kalmadı mı
func is_empty() -> bool:
	return _nodes.is_empty() and _rubble.is_empty()


## İnişte görünürlüğün açılması: uçuşa geçilince sınır kameradan dışarı doğru REVEAL_TIME'da
## FADE'e genişler (önce yakındaki parçalar, sonra uzaktakiler sisin içinden belirir)
func reveal() -> void:
	_reveal_t = 0.0
	_set_fade(0.0)


static func _set_fade(k: float) -> void:
	if _debris_lit == null:
		return
	var near := lerpf(0.0, FADE.x, k)
	var far := near + lerpf(25.0, FADE.y - FADE.x, k)
	for m: StandardMaterial3D in [_debris_lit, _debris_flat]:
		m.distance_fade_max_distance = near
		m.distance_fade_min_distance = far


## Portal için: bu bölgede (z_near..z_far, x ± half_w) kırık parça var mı
func zone_blocked(x: float, z_near: float, z_far: float, half_w: float) -> bool:
	for o in layer.rocks:
		if o.has("rad") and o.z - o.rad < z_near and o.z + o.rad > z_far and absf(o.x - x) < o.rad + half_w:
			return true
	return false


## Portalın yaklaşma yolunu aç: bölgeye taşan parçaları kaldır (yalnız boş yer bulunamazsa)
func clear_zone(x: float, z_near: float, z_far: float, half_w: float) -> void:
	for o in layer.rocks:
		if o.has("rad") and o.z - o.rad < z_near and o.z + o.rad > z_far and absf(o.x - x) < o.rad + half_w:
			if is_instance_valid(o.node):
				o.node.queue_free()


func rubble_count() -> int:
	return _rubble.size()


## Parçanın havadaki hareketi: serbest takla (rastgele eksen), yatık dönüş (dik eksen: düz durur,
## yükselerek üstünden geçilir), uzun ekseninde yuvarlanma (uçuş yönünde uzanır), enine yuvarlanma
## (kopmuş köprü: koridoru keser, yanında geçit)
enum Motion { TUMBLE, FLAT, ROLL, WALL }


func _setup_debris() -> void:
	for i in 8:
		# Moloz kalıbı başına bir çoklu örnek (tek çizim): konumları her kare güncellenir
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = RUBBLE_CAP
		mm.visible_instance_count = 0
		mm.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Molozlar görüntü karesinde kendisi akar (fizik adımı aradeğerlemesi gerekmez)
		mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(mmi)
		_rubble_mm.append(mmi)


## Kalıp hazırlığının bir adımı (menüde ve oyunda kare başına bir kez çağrılır); bitince true
static func pool_step() -> bool:
	if not _pool_planned:
		_plan_pool()
	if _pool_queue.is_empty():
		return true
	_build_next_debris()
	return _pool_queue.is_empty()


static func _plan_pool() -> void:
	_pool_planned = true
	_debris_lit = StandardMaterial3D.new()
	_debris_flat = StandardMaterial3D.new()
	for m: StandardMaterial3D in [_debris_lit, _debris_flat]:
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 1.0
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		# Uzakta görünmez, yaklaştıkça belirir (en küçük > en büyük: uzaklaştıkça solar)
		m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
		m.distance_fade_min_distance = FADE.y
		m.distance_fade_max_distance = FADE.x
	_debris_flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
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


func _process(delta: float) -> void:
	if layer == null or not layer.use_debris:
		return
	# Kalıplar normalde menüde hazırlanır; eksikse oyunun ilk karesinde (yüklenirken) tamamlanır,
	# gölgelendiriciler de o anda ısıtılır (uçuşta ve ilk hayalette takılma olmasın)
	# Sahne yerine oturduktan sonra (birkaç kare: kamera, yollar, gökyüzü hazır); oyun açılış
	# örtüsünün (game.gd) altında: derleme takılması görünmez
	_frame_count += 1
	if not _warmed and _frame_count > 3 and car != null:
		while not pool_step():
			pass
		_warmed = true
		_prewarm()
	for k in _rubble_mm.size():
		if _rubble_mm[k].multimesh.mesh == null and k < _rubble_meshes.size():
			_rubble_mm[k].multimesh.mesh = _rubble_meshes[k]
	if _warm_frames > 0:
		_warm_frames -= 1
		if _warm_frames == 0 and is_instance_valid(_warm):
			_warm.queue_free()
	if _reveal_t >= 0.0:
		_reveal_t += delta
		var k := clampf(_reveal_t / REVEAL_TIME, 0.0, 1.0)
		_set_fade(k * k * (3.0 - 2.0 * k))
		if k >= 1.0:
			_reveal_t = -1.0
	if not _rubble.is_empty():
		var _t0 := Time.get_ticks_usec()
		_update_rubble(delta)
		perf_rubble_us += Time.get_ticks_usec() - _t0


static func _build_next_debris() -> void:
	var job: Dictionary = _pool_queue.pop_front()
	if job.has("rubble"):
		var holder := Node3D.new()
		holder.add_child(RoadDebris.build_rubble(job.rubble))
		var baked := _bake_debris(holder, false)
		holder.free()
		_rubble_meshes.append(baked.mesh)
		return
	var node := RoadDebris.build(job.size, job.seed, job.style, job.feature)
	var proto := _bake_debris(node, true, job.feature != RoadDebris.Feature.NONE)
	node.free()
	proto.feature = job.feature
	proto.size = job.size
	_debris_pool[job.size].append(proto)


## Parçanın tüm yüzeyleri tek örgüde (renkler köşe renginde): gölgeli ve gölgesiz (şerit çizgisi)
## iki yüzey, az çizim. Çarpışma görünen biçimin aynısı: düz parça tek dış bükey, biçimli parça
## boyuna bantlar (yokuşta, eğimde boşluğu doldurmasın)
static func _bake_debris(root: Node3D, with_hulls: bool, banded := false) -> Dictionary:
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
		# Düz parça tek dış bükey (kesikler dış bükeyliği bozmaz: görünen biçimin aynısı); biçimli
		# parça boyuna 3 m'lik bantlar (kıvrımı izler)
		var bands := maxi(1, ceili(local_box.size.z / 3.0)) if banded else 1
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
			# Şekil bir kez kurulur, tüm kopyalar paylaşır (her parçada yeniden hesaplanmasın)
			var sh := ConvexPolygonShape3D.new()
			sh.points = pts
			hulls.append(sh)
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
	while (_debris_pool[size] as Array).is_empty() and not pool_step():
		pass
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
		layer.rocks.append({"x": b.x, "y": b.y, "z": b.z, "r": b.rad / 0.85, "rad": b.rad, "h": b.h, "node": node})
	# Etrafında kendi molozları
	for i in [0, 1, 1, 2][proto.size] + _rng.randi_range(0, 1):
		var b: Dictionary = place.blobs[_rng.randi() % place.blobs.size()]
		_add_rubble(Vector3(b.x, b.y, b.z) + _rand_axis() * _rng.randf_range(b.rad * 0.7, b.rad + 4.0))
	return true


func _debris_fits(blobs: Array, merge: bool) -> bool:
	var span: float = car.wing_half_span * 2.0 + 0.6
	var fy := car.flight_altitude
	# Portalın önündeki yaklaşma payına taşmasın (büyük parça da)
	for b: Dictionary in blobs:
		if b.z - b.rad < _chunk_stop + 5.0:
			return false
	# Yalnız yakındakiler (boyuna): tüm listeyi her yuvar için dolaşmasın
	var z_lo := INF
	var z_hi := -INF
	for b: Dictionary in blobs:
		z_lo = minf(z_lo, b.z - b.rad)
		z_hi = maxf(z_hi, b.z + b.rad)
	var near: Array = []
	for o in layer.rocks:
		if not o.has("v") and o.z > z_lo - 40.0 and o.z < z_hi + 40.0:
			near.append(o)
	var near_all := near + blobs
	for b: Dictionary in blobs:
		for o in near:
			if o.has("v"):
				continue
			var orad: float = o.get("rad", 0.85 * o.r)
			var oh: float = o.get("h", 0.85 * o.r)
			# Boyuna pay geniş: arka arkaya iki parça arasında keskin zikzak gerekmesin
			if absf(o.z - b.z) > b.rad + orad + 12.0 or absf(o.y - b.y) > b.h + oh + 2.0:
				continue
			var gap: float = absf(o.x - b.x) - b.rad - orad
			if gap < (0.3 if merge else span):
				return false
		if absf(b.y - fy) < b.h + 1.5:
			var cx := roads.path_x_at(b.z)
			var blocks: Array[Vector2] = []
			for o in near_all:
				var orad: float = o.get("rad", 0.85 * o.get("r", 0.0))
				var oh: float = o.get("h", orad)
				if absf(o.z - b.z) < b.rad + orad + 3.0 and absf(o.y - fy) < oh + 1.5:
					blocks.append(Vector2(o.x - orad - 1.0, o.x + orad + 1.0))
			blocks.sort_custom(func(a: Vector2, c: Vector2) -> bool: return a.x < c.x)
			var cur := cx - layer.corridor_half_width - 4.0
			var ok := false
			for bl in blocks:
				if bl.x - cur >= span:
					ok = true
					break
				cur = maxf(cur, bl.y)
			if not ok and cx + layer.corridor_half_width + 4.0 - cur >= span:
				ok = true
			if not ok:
				return false
	return true


func _spawn_debris(proto: Dictionary, pos: Vector3, base: Basis, axis: Vector3, spin: float,
		collide: bool, shadow: bool, scale_by: float) -> Node3D:
	var node: Node3D = Area3D.new() if collide else Node3D.new()
	node.position = pos
	node.basis = base.scaled(Vector3.ONE * scale_by)
	node.visible = car.global_position.z - pos.z < debris_view
	add_child(node)
	var mi := MeshInstance3D.new()
	mi.mesh = proto.mesh
	if not shadow or not debris_shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	if collide:
		var area := node as Area3D
		area.monitorable = false
		# Gövde (araba cismi) ve kanat/gövde çarpma kutuları (Car.HIT_LAYER)
		area.collision_mask = 1 | Car.HIT_LAYER
		area.area_entered.connect(func(other: Area3D):
			if other.has_meta("car_hit"):
				hit.emit())
		for sh: Shape3D in proto.hulls:
			var col := CollisionShape3D.new()
			col.shape = sh
			node.add_child(col)
		(node as Area3D).body_entered.connect(func(body):
			if body == car:
				hit.emit())
	_nodes.append(node)
	_debris.append({"node": node, "axis": axis, "spin": spin, "base": base, "a": 0.0, "s": scale_by})
	return node


## Bir parça boyu (z..z_end) kırık yol: kopmuş köprü, yığın ya da dağınık alan; aralarda moloz
func _spawn_debris_chunk(z: float, z_end: float, n: int) -> void:
	var S := RoadDebris.Size
	var cx := roads.path_x_at(z)
	var fy := car.flight_altitude
	var style := _rng.randf()
	# Uçuşun ilk ~150 m'sinde kopmuş köprü yok (araba daha inerken önüne duvar çıkmasın)
	if layer.active and z > layer.flight_start_z - 150.0 and style < 0.25:
		style = 0.25 + _rng.randf() * 0.75
	var weight := 0.0
	if style < 0.25:
		# Kopmuş köprü: koridoru enine kesen uzun (ya da büyük) parça, uzun ekseninde yuvarlanır;
		# yanında kanat açıklığından geniş bir geçit (bazen iki yanında birer parça)
		var wz := _rng.randf_range(z_end + 4.0, z - 4.0)
		var gap_x := cx + _rng.randf_range(-9.0, 9.0)
		var gap_w := _rng.randf_range(10.0, 13.0)
		var sides := [-1.0, 1.0] if _rng.randf() < 0.6 else [_rand_sign()]
		for side: float in sides:
			var proto := _pick_proto(S.LONG if _rng.randf() < 0.55 else S.LARGE)
			var hl: float = (proto.aabb as AABB).size.z * 0.5
			var pos := Vector3(gap_x + side * (gap_w * 0.5 + hl), fy + _rng.randf_range(-1.0, 1.0), wz + _rng.randf_range(-2.0, 2.0))
			_place_debris(proto, _plan_motion(proto, pos, Motion.WALL))
		weight = n * 0.5
	elif style < 0.4 and (not layer.active or z < layer.flight_start_z - 220.0):
		# Yığın: birbirine yakın birkaç küçük-orta parça, bol moloz
		var c := Vector3(cx + _rng.randf_range(-10.0, 10.0), fy + _rng.randf_range(-1.0, 3.0), _rng.randf_range(z_end + 6.0, z - 6.0))
		for i in _rng.randi_range(2, 3):
			var proto := _pick_proto(S.SMALL if _rng.randf() < 0.5 else S.MEDIUM)
			var pos := c + Vector3(_rng.randf_range(-8.0, 8.0), _rng.randf_range(-3.0, 5.0), _rng.randf_range(-7.0, 7.0))
			_place_debris(proto, _plan_motion(proto, pos, Motion.TUMBLE), true, true)
		for i in _rng.randi_range(4, 6):
			_add_rubble(c + Vector3(_rng.randf_range(-10.0, 10.0), _rng.randf_range(-5.0, 7.0), _rng.randf_range(-9.0, 9.0)))
		weight = n * 0.5
	var tries := 0
	# Yerleştirme denemeleri süreyle sınırlı (telefonda karede takılma olmasın; sığmayan atlanır)
	var t_start := Time.get_ticks_usec()
	while weight < n and tries < n * 4 and Time.get_ticks_usec() - t_start < 900:
		tries += 1
		var roll := _rng.randf()
		# Çoğu büyük ve uzun (yukarıdaki yolların oranında); az sayıda küçük-orta
		var size: int = S.SMALL if roll < 0.15 else (S.MEDIUM if roll < 0.4 else (S.LARGE if roll < 0.7 else S.LONG))
		var proto := _pick_proto(size)
		var mode: int = Motion.ROLL
		if size == S.SMALL or size == S.MEDIUM:
			mode = Motion.TUMBLE if _rng.randf() < 0.55 else Motion.FLAT
		elif size == S.LARGE:
			mode = Motion.ROLL if _rng.randf() < 0.6 else Motion.FLAT
		var h := _rng.randf()
		var y := fy + _rng.randf_range(-1.5, 1.5)
		var pz := _rng.randf_range(z_end, z)
		# Uçuşun başında araba yukarıdan iner: ilk ~220 m'de uçuş yüksekliğinin üstünde parça yok,
		# alçaktakiler de takla atmaz (iniş yoluna uzanmasın)
		var descent := layer.active and pz > layer.flight_start_z - 220.0
		if descent:
			y = fy + _rng.randf_range(-3.0, -1.0)
			if mode == Motion.TUMBLE:
				mode = Motion.FLAT
		elif h < layer.high_rock_chance:
			y = fy + _rng.randf_range(6.0, 10.0)
		elif h < layer.high_rock_chance + layer.mid_rock_chance:
			y = fy + _rng.randf_range(2.5, 4.5)
		var pos := Vector3(cx + _rng.randf_range(-layer.corridor_half_width - 3.0, layer.corridor_half_width + 3.0), y, pz)
		if _place_debris(proto, _plan_motion(proto, pos, mode)):
			weight += [1.0, 1.5, 2.5, 3.0][size]
	# Koridorda dağınık molozlar
	for i in _rng.randi_range(0, 3):
		_add_rubble(Vector3(cx + _rng.randf_range(-layer.corridor_half_width - 6.0, layer.corridor_half_width + 6.0),
			fy + _rng.randf_range(-4.0, 9.0), _rng.randf_range(z_end, z)))


## Bağımsız moloz: yerinde çok yavaş süzülür ve döner; arabaya zarar vermez
func _add_rubble(p: Vector3) -> void:
	if _rubble_meshes.is_empty():
		return
	_rubble.append({"p": p, "b": Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)),
		"v": _rand_axis() * _rng.randf_range(0.0, 0.4), "w": _rand_axis(), "ws": _rng.randf_range(0.3, 1.5) * _rand_sign(), "a": 0.0,
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
		r.a += r.ws * delta
		if r.hit:
			# Savrulan moloz: hızı ve dönüşü yavaşça söner (yumuşak süzülme)
			r.v = (r.v as Vector3) * exp(-RUBBLE_DRAG * delta)
			r.ws = lerpf(r.ws, signf(r.ws) * 1.2, 1.0 - exp(-0.7 * delta))
		if r.p.z > cp.z + 30.0 or r.p.z < cp.z - 900.0:
			continue
		if cp.z - r.p.z > debris_view:
			keep.append(r)  # uzakta: çizilmez
			continue
		if flying and not r.hit:
			var d: Vector3 = r.p - cp
			var reach: Vector3 = RUBBLE_REACH + Vector3.ONE * 0.4 * float(r.s)
			if absf(d.x) < reach.x and absf(d.y) < reach.y and absf(d.z) < reach.z:
				_kick_rubble(r, d)
		keep.append(r)
		var k: int = r.k
		if counts[k] < RUBBLE_CAP:
			_rubble_mm[k].multimesh.set_instance_transform(counts[k], Transform3D((Basis(r.w, r.a) * r.b).scaled(Vector3.ONE * r.s), r.p))
			counts[k] += 1
	_rubble = keep
	for k in _rubble_mm.size():
		_rubble_mm[k].multimesh.visible_instance_count = counts[k]


func _kick_rubble(r: Dictionary, d: Vector3) -> void:
	r.hit = true
	# Kenara itilir: değdiği yanın dışına (kanat ucundaki daha çok yana, ortadaki az yana, biraz
	# yukarı-aşağı), arabanın hızının bir kısmını alıp kısa süre onunla gider, sonra geride kalır
	var sx := signf(d.x) if absf(d.x) > 0.05 else _rand_sign()
	var side := Vector3(sx * (0.5 + absf(d.x) / RUBBLE_REACH.x), clampf(d.y / RUBBLE_REACH.y, -1.0, 1.0) * 0.6 + 0.25, 0.0).normalized()
	r.v = (r.v as Vector3) + side * _rng.randf_range(RUBBLE_SIDE.x, RUBBLE_SIDE.y) + car.velocity * RUBBLE_CARRY
	# Dönüşü hızlanır (sonra yavaşça söner)
	r.b = Basis(r.w, r.a) * r.b
	r.a = 0.0
	r.w = _rand_axis()
	r.ws = _rng.randf_range(8.0, 15.0) * _rand_sign()
	var now := Time.get_ticks_msec()
	if layer.debug_log:
		print("KICK v=%v" % r.v)
	if now - _last_rubble_sfx > 70:
		_last_rubble_sfx = now
		Audio.play("debris", _rng.randf_range(-9.0, -5.0), _rng.randf_range(0.85, 1.2))


func _prewarm() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# Arabanın gövdesinin içinde, minicik: çizilir (derlenir) ama gövde örter, görünmez
	_warm = Node3D.new()
	car.get_node("Body").add_child(_warm)
	_warm.position = Vector3(0, 0.55, 0)
	_warm.scale = Vector3.ONE * 0.02
	# Parça (gölgeli + gölgesiz yüzey: tek rampada ikisi de var), moloz (çoklu örnek)
	var ramp: Dictionary = {}
	for proto: Dictionary in _debris_pool[RoadDebris.Size.MEDIUM]:
		if proto.feature == RoadDebris.Feature.RAMP_ALONE:
			ramp = proto
	if not ramp.is_empty():
		var mi := MeshInstance3D.new()
		mi.mesh = ramp.mesh
		_warm.add_child(mi)
	if not _rubble_meshes.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _rubble_meshes[0]
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D())
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		_warm.add_child(mmi)
	# Alt katmanın kendi malzemeleri: hayalet, portal, kaya
	layer.add_warm_meshes(_warm)
	for gi in _warm.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_warm_frames = 4
