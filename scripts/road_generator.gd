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
	## Yol üstü rampa: kalkışta yana bu hızla (m/s) fırlatır (eksi sol)
	## Hangi kalıptan üretildi ve üstüne hangi olaylar dizildi (analiz için)
	var pattern := ""
	var events_log: Array[String] = []
	var ramp := false
	var kick := 0.0
	## Yol ağının yan yolu (alçak/yüksek): sonunda ana yola dönüş rampası var
	var side_road := false
	## Ada zincirinde: sonundaki boşluk gazsız zıplamayla geçilir (roket gerekmez)
	var hop := false
	## Aynı yolun bir sonraki parçası (boşluksuz devam eder: daralma, kayma, tümsek)
	var next_flush: Segment

	## Bu yolun (bitişik parçalarıyla birlikte) en uzak ucu: boşluk burada başlar
	func road_end_z() -> float:
		var s := self
		while s.next_flush:
			s = s.next_flush
		return s.z_end
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


## Düz yolların ritmi: her ruh hâlinin süresi (sn, o anki hızla; min, max)
## (iniş ve pist ışıkları bölgesinin dışında kalan, olayların dizildiği kısım)
const MOOD_SECONDS := {"nefes": Vector2(0.6, 1.0), "orta": Vector2(1.0, 2.0), "yoğun": Vector2(1.8, 3.2)}

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
## Kalıpların açıldığı mesafeler (m). Başlangıç pistinden hemen sonra hepsi
## kolay hâlleriyle gelebilir (her oyun farklı başlar); ease_distance'a kadar
## açılar ve yükseklikler yavaşça tam değerine çıkar.
@export var slopes_from := 0.0
@export var ramps_from := 150.0
## Çıkmaz ve çatal (uçuşa düşme, iki kol) bu mesafeden sonra
@export var advanced_from := 400.0
@export var ease_distance := 1500.0
## Çıkmaz kalıbının seçilme ağırlığı (diğerleri ~0.5-1)
@export var dead_end_weight := 0.5
## Çatal kalıbının seçilme ağırlığı
@export var fork_weight := 0.6
## Yol ağı (yol üstü rampalar, alçak/yüksek yan yollar, dönüş rampaları) bu mesafeden
## sonra gelir; düz uzun bir yolun bu olasılıkla ağ olması, mesafeyle artar (az -> çok)
@export var network_from := 0.0
## Ada zinciri kalıbının ağırlığı (yolun ~%20'si)
@export var island_weight := 3.0
## Yol ağı kalıbının ağırlığı (başta, network_full_at'ta); diğer kalıplar ~0.5-1.1
@export var network_weight := Vector2(1.2, 2.4)
@export var network_full_at := 4000.0
## Yatık yollar (yana yatıp düzelen) bu mesafeden sonra gelir; ağırlık ve en fazla açı
@export var banks_from := 0.0
@export var bank_weight := 1.0
@export var max_bank_deg := 15.0
## Düz yollara engel (çarpınca patlar) ve çakıl (yavaşlatır) bu mesafeden sonra gelir
@export var obstacles_from := 0.0
## Düz bir yolun engelli olma olasılığı (zorlukla bu değere çıkar)
@export_range(0.0, 1.0) var obstacle_chance := 1.0
## Pist ışıkları: yolun sonundaki ışıklı bölgenin süresi (sn, o anki hızla)
@export var lights_time := 1.1
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
var _ramp_top_mat := StandardMaterial3D.new()
var _kerb_red := StandardMaterial3D.new()
var _kerb_white := StandardMaterial3D.new()
var _runway_mat := ShaderMaterial.new()
var _runway_halo_mat := ShaderMaterial.new()
## Pist ışıklarının akış saati: oyunun kare saatiyle ilerler
var _light_time := 0.0
var _block_mat := StandardMaterial3D.new()
var _block_top_mat := StandardMaterial3D.new()
var _gravel_mat := StandardMaterial3D.new()
var _stone_mat := StandardMaterial3D.new()
## Yol kristalleri: her yol için bir MultiMesh. Kristaller yolun düğümünden ayrı
## tutulur (havadaki yay yolun ucunu geçer): { node, mm, pts, alive, z_far }
var _crystal_sets: Array[Dictionary] = []
var _crystal_pending := {}
var _crystal_mesh: Mesh
var _crystal_mat := ShaderMaterial.new()
var _pickup_fx: Array[CPUParticles3D] = []
var _pickup_next := 0
## Kristal rengi (enerji göstergesi de bu renkte)
@export var crystal_color := Palette.ENERGY
## Kristal başına enerji ve toplama yarıçapı (araba yarı genişliğine eklenir)
@export var crystal_value := 3.0
## Bir yolun sonundaki boşluk için gereken enerjinin kaç katı kristal konur (baş, son)
@export var crystal_supply := Vector2(2.0, 1.2)
## Arz, deponun doluluğuyla değişir: dolu depoda bu katın ilki, boş depoda ikincisi.
## Dolu depoda yol üstündeki kristal gruplarının çoğu da hiç konmaz.
@export var crystal_need_range := Vector2(0.3, 1.6)
## Depo bu orandan azsa arz ayrıca bu katla artar (aşağıda kristal yok: depo, düşünce
## hayat süresi; azken toparlanma fırsatı)
@export var crystal_low_at := 0.3
@export var crystal_low_boost := 1.4
## Kristaller hep tek sıra, yol boyunca bu aralıkla (m)
@export var crystal_spacing := 6.0
## Ana yolda en uzun engelsiz düzlük (sn): daha uzunsa araya tek blok ya da yarım
## çakıl girer. İnişten bu kadar sn sonrasından pist bölgesine kadar geçerli.
@export var max_empty_time := 1.2
@export var fill_after_landing := 1.0
## Kristallerin kolay yerlerde (iniş, pist) olan payı (baş, son)
@export var crystal_easy_share := Vector2(0.6, 0.15)
## Arz ve kolay payın son değerine indiği mesafe (m)
@export var crystal_hard_at := 6000.0
## Sıradaki ana yolların tarifi (kalıptan gelir)
var _plan: Array[Dictionary] = []
var _recent: Array[String] = []
## Her kalıbın son gelişinden bu yana kaç kalıp geçti
var _since := {}
## Son kullanılan yol içi olaylar (aynısı hemen tekrar gelmesin)
var _recent_events: Array[String] = []
var _last_mood := ""
var _mood_run := 0
## Test/analiz: üretilen her yol burada da tutulur (--dump_roads ile dosyaya yazılır)
var keep_history := false
var history: Array[Segment] = []
var crystal_z_history: Array = []
var _current_kind := ""
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
	_ramp_top_mat.albedo_color = Palette.ACCENT.lerp(Palette.SNOW, 0.45)
	_ramp_top_mat.roughness = 0.9
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
	var gem := SphereMesh.new()
	gem.radial_segments = 4
	gem.rings = 1
	gem.radius = 0.34
	gem.height = 1.0
	_crystal_mesh = gem
	_crystal_mat.shader = preload("res://shaders/crystal.gdshader")
	for i in 4:
		_pickup_fx.append(_make_pickup_fx())
	set_crystal_color(crystal_color)


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
	for i in range(_crystal_sets.size() - 1, -1, -1):
		if _crystal_sets[i].z_far > limit:
			_crystal_sets[i].node.queue_free()
			_crystal_sets.remove_at(i)


func _process(delta: float) -> void:
	_light_time += delta
	_runway_mat.set_shader_parameter("t", _light_time)
	_runway_halo_mat.set_shader_parameter("t", _light_time)
	_crystal_mat.set_shader_parameter("t", _light_time)


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
		_flush_crystals()


## Tam gazın hızı; hesapta %90 gaz alınır (roket bir an erken/geç basılsa da yetsin)
func _v_boost(v: float) -> float:
	return v + 0.9 * minf(v * car.boost_bonus, car.boost_max_extra)


## Arabanın dist_ahead metre ileride ulaşacağı tahmini hız
func estimate_speed(dist_ahead: float) -> float:
	var t := dist_ahead / maxf(car.speed, 1.0)
	var v := car.speed
	if v < car.max_speed:
		v = minf(v + car.acceleration * t, car.max_speed)
	else:
		v += car.late_acceleration * t
	return clampf(v, car.start_speed, car.top_speed)


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
			# Bitişik parçaları olan yolda koşu payı yolun gerçek sonuna göre
			var near := s.z_start - margin_start
			var far := maxf(s.z_end, s.road_end_z() + margin_end)
			if near <= far or far > z:
				continue
			# Engelli yolda: inişten sonra ~45 m boş olan, istenen yere en yakın nokta
			var want := minf(z, near)
			for k in 40:
				var land := want + (k + 1) / 2 * 5.0 * (1.0 if k % 2 == 1 else -1.0)
				if land > near or land < far:
					continue
				if _chain_clear(s, land + 3.0, land - 45.0):
					return {"seg": s, "z": land}
		horizon -= 250.0
	return {}


## Yol ve bitişik parçalarında z_near..z_far arası engelsiz mi
func _chain_clear(s: Segment, z_near: float, z_far: float) -> bool:
	while s:
		if not s.clear_between(z_near, z_far):
			return false
		if s.z_end < z_far:
			return true
		s = s.next_flush
	return true


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
	# Test: başlangıç pistinden hemen sonra denenen el yapımı kalıp
	if not test_level.is_empty() and not _test_used:
		_test_used = true
		if vary_test:
			_custom_seen[LevelCheck.signature(test_level)] = true
		_plan.append({"custom": test_level, "vary": vary_test})
		return
	# Yükseklik sınırlı kalsın: alçaktayken inen, yüksekteyken çıkan kalıp yok
	var low := level < MAIN_LEVEL - 3.0
	var high := level > MAIN_LEVEL + 3.0
	# Başta kalıplar kolay hâlleriyle gelir (ease 0 → 1)
	var ease := clampf(travelled / maxf(ease_distance, 1.0), 0.0, 1.0)
	var options := [["düz", 0.9]]
	if travelled >= slopes_from:
		options.append(["eğim", 0.6])
		if not low:
			options.append(["vadi", 0.6])
	if travelled >= ramps_from:
		if not low:
			options.append(["merdiven", 0.5])
		if not high:
			options.append(["rampa", 0.5])
	if travelled >= advanced_from:
		if not low:
			options.append(["çıkmaz", dead_end_weight])
		if not low and not high:
			options.append(["çatal", fork_weight])
	if travelled >= banks_from:
		options.append(["yatık", bank_weight])
	if travelled >= ramps_from and not low:
		options.append(["ada", island_weight])
	if travelled >= network_from:
		var dens := clampf((travelled - network_from) / maxf(network_full_at - network_from, 1.0), 0.0, 1.0)
		options.append(["ağ", lerpf(network_weight.x, network_weight.y, dens)])
	var custom := _eligible_levels(travelled, car.speed)
	if not custom.is_empty() and not low:
		options.append(["özel", custom_weight])
	# Tekrar yok: son kalıp hiç gelmez, son birkaç kalıbın şansı düşer.
	# Aç kalma: uzun süredir gelmeyen kalıbın şansı artar (her kalıp düzenli görünsün).
	for o in options:
		o[1] *= minf(1.0 + 0.35 * float(_since.get(o[0], 6)), 4.0)
	var total := 0.0
	for o in options:
		if not _recent.is_empty() and _recent[-1] == o[0] and options.size() > 1:
			o[1] = 0.0
		elif o[0] in _recent:
			o[1] *= 0.4
		total += o[1]
	var pick := _rng.randf() * total
	var kind: String = options[0][0]
	for o in options:
		pick -= o[1]
		if pick <= 0.0 and o[1] > 0.0:
			kind = o[0]
			break
	pattern_counts[kind] = int(pattern_counts.get(kind, 0)) + 1
	_current_kind = kind
	for k in _since:
		_since[k] = int(_since[k]) + 1
	_since[kind] = 0
	_recent.append(kind)
	if _recent.size() > 3:
		_recent.pop_front()
	match kind:
		"ağ":
			_plan.append({"network": true})
		"düz":
			for i in _rng.randi_range(1, 2):
				_plan.append({})
		"eğim":
			var dir := -1.0 if _rng.randf() < 0.5 else 1.0
			if low: dir = 1.0
			elif high: dir = -1.0
			_plan.append({"angle": dir * _rng.randf_range(10.0, 15.0) * lerpf(0.6, 1.0, ease), "len": 0.6})
		"vadi":
			_plan.append({"dh": _rng.randf_range(-1.5, -0.5), "angle": -_rng.randf_range(12.0, 16.0) * lerpf(0.65, 1.0, ease), "len": 0.5})
			_plan.append({"dh": _rng.randf_range(-2.0, -0.5), "width": 1.1})
			_plan.append({"dh": _rng.randf_range(-0.6, 0.0), "rise_to": MAIN_LEVEL + _rng.randf_range(-1.0, 1.0), "len": 0.4})
		"merdiven":
			for i in _rng.randi_range(2, 3):
				_plan.append({"dh": -_rng.randf_range(2.5, 3.5)})
			_plan.append({"dh": _rng.randf_range(-0.6, 0.0), "rise_to": MAIN_LEVEL + _rng.randf_range(-1.0, 1.0), "len": 0.4})
		"rampa":
			_plan.append({"angle": _rng.randf_range(15.0, 18.0) * lerpf(0.7, 1.0, ease), "len": 0.35})
			_plan.append({"up": true})
		"çıkmaz":
			_plan.append({"dead_end": true, "len": 1.4})
			_plan.append({})
		"yatık":
			var dir := -1.0 if _rng.randf() < 0.5 else 1.0
			_plan.append({"bank": dir * _rng.randf_range(0.75, 1.0) * max_bank_deg * lerpf(0.55, 1.0, ease),
				"s_curve": _rng.randf() < 0.4})
		"ada":
			_plan.append({"islands": true})
		"özel":
			# El yapımı kalıp: yakında gelmemiş olanlardan biri
			var pick_from: Array[Dictionary] = custom.filter(func(l): return not str(l.name) in _custom_recent)
			if pick_from.is_empty():
				pick_from = custom
			var chosen: Dictionary = pick_from[_rng.randi() % pick_from.size()]
			_custom_recent.append(str(chosen.name))
			if _custom_recent.size() > maxi(custom_levels.size() - 1, 1):
				_custom_recent.pop_front()
			# Tasarımcının "oyuna girsin" dediği türevler de kalıbın yerine gelebilir
			var bases: Array[Dictionary] = [chosen]
			for vr in chosen.get("variants", []):
				if vr is Dictionary and vr.get("on", false) and vr.get("pieces") is Array:
					var b: Dictionary = chosen.duplicate()
					b.erase("variants")
					b["pieces"] = vr.pieces.duplicate(true)
					b["obstacles"] = vr.get("obstacles", []).duplicate(true)
					bases.append(b)
			chosen = bases[_rng.randi() % bases.size()]
			# Yarı yarıya aynalı gelir (sağ ↔ sol): fizik simetrik, test edilen kalıbın aynası da geçer
			if _rng.randf() < 0.5:
				chosen = mirror_level(chosen)
			# Kurulurken her seferinde yeni bir türev türetilir (aynısı iki kez gelmez)
			_plan.append({"custom": chosen, "vary": true})
		"çatal":
			# Önce geniş bir yol: iki kola da buradan atlanır
			_plan.append({"width": 1.6, "len": 0.8, "dh": _rng.randf_range(-1.0, 0.0)})
			_plan.append({"fork": true})


func _next_from(prev: Segment) -> Segment:
	var dist_ahead := car.global_position.z - prev.z_end
	var travelled := -prev.z_end
	var difficulty := clampf(travelled / difficulty_distance, 0.0, 1.0)
	_act = action * lerpf(action_growth.x, action_growth.y, clampf(travelled / maxf(action_growth_at, 1.0), 0.0, 1.0))
	if _plan.is_empty():
		_plan_pattern(travelled, prev.top_end)
	var spec: Dictionary = _plan.pop_front()
	if spec.get("fork", false):
		var merge := _add_fork(prev)
		if merge:
			return merge
		spec = {}
	if spec.get("islands", false):
		return _build_islands(prev, travelled)
	if spec.has("custom"):
		return _build_custom(prev, spec.custom, travelled, spec.get("vary", false))

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
	var network: bool = spec.get("network", false)
	# Düz yollar ritimle gelir: kısa nefes, orta, yoğun. Uzunluk saniye cinsinden
	# sınırlı; uzun yol ancak içi doluysa çıkar (boş uzun yol yok).
	var mood := ""
	if network:
		width = maxf(width, 6.0)
		length = _clear_start(v, _land_far_estimate(v, dh, gap, slope)) \
			+ v * _rng.randf_range(3.5, 5.5) * clampf(_act * 0.5, 1.0, 1.3) + _clear_end(v)
	elif plain and travelled > obstacles_from:
		mood = _next_mood(difficulty)
		# Başka bir kalıbın içindeki düz yol (vadinin dibi, merdiven basamağı...) kısa kalsın:
		# kalıbın kendisi asıl olay
		if not spec.is_empty() and mood == "yoğun":
			mood = "orta"
		# Aksiyon arttıkça olaylı kısım da uzar: iniş/pist bölgelerine göre payı büyür
		var content := v * float(MOOD_SECONDS[mood].x + _rng.randf() * (MOOD_SECONDS[mood].y - MOOD_SECONDS[mood].x)) \
			* float(spec.get("len", 1.0)) * clampf(_act * 0.5, 1.0, 1.3)
		length = _clear_start(v, _land_far_estimate(v, dh, gap, slope)) + content + _clear_end(v)
		# Olaylı yol dar olmasın: dar yolda çoğu olay (kapı, zikzak, çakıl şeridi...) seçilemez
		if mood != "nefes":
			width = maxf(width, 6.0 if mood == "orta" else 6.6)

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
	var first: Segment = null
	if banked:
		# Yatık yol: düz başlar (iniş), bükülür, düzelir; sonu düz (pist ışıkları + roket)
		var flat_in := 10.0
		var flat_out := clampf(v * lights_time, 18.0, 70.0) + v * 0.8
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
		if _rng.randf() < 0.7:
			# Yatık bölümde yüksek kenarda kristaller: kayarken tutunmak gerek
			var hx := seg.x + signf(spec.bank) * width * 0.28
			_crystal_line(seg, hx, t0 - m * 0.3, hx, t0 - m * (0.4 if spec.get("s_curve", false) else 0.7), 4)
	elif mood != "" and absf(rise) < 0.01:
		# İçi değişen yol: bitişik parçalar (daralma, kayma, tümsek) ve engel dizilimleri
		first = _build_road(prev.x + dx, top, width, z_start, length, v, land_far, mood)
		seg = _last_of(first)
	else:
		seg = _add_segment(prev.x + dx, top, top + rise, width, z_start, z_start - length, true)
	if first == null:
		first = seg
	# Boşluğun üstünde, doğru gazla geçenin yayında kristaller
	if _rng.randf() < lerpf(0.4, 0.75, difficulty) * _act:
		_gap_crystals(prev, first.x, top - prev.top_end, gap, v)
	if network and absf(rise) < 0.01:
		_add_network(seg, v, land_far, travelled)
	elif absf(rise) > 0.01 and not banked and seg.width >= 4.6:
		# Eğimli yol da boş kalmasın: inişten sonra, pistten önce olaylar
		_fill_events(seg, v, z_start - _clear_start(v, land_far), seg.z_end + _clear_end(v), "orta")
	elif spec.get("dead_end", false):
		_add_dead_end(prev, seg, -main_side, v, vy_b)
		_fill_events(seg, v, z_start - _clear_start(v, land_far), seg.z_end + _clear_end(v), "orta")
	elif (mood == "" or seg == first) and _rng.randf() < side_road_chance:
		_add_side_road(seg)
	elif mood == "" and not banked and travelled > obstacles_from:
		# Kalıbın içindeki kısa düz yol (rampa yolu, basamak...) da boş kalmasın
		_fill_events(seg, v, z_start - _clear_start(v, land_far), seg.z_end + _clear_end(v), "orta", -1, true)
	if not banked and travelled > obstacles_from:
		_fill_gaps(first, v, land_far)
	_road_crystals(first, v, travelled)
	_add_decor(first)
	return seg


func _last_of(s: Segment) -> Segment:
	while s.next_flush:
		s = s.next_flush
	return s


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
		# Alçak (kolay) kol da boş kalmasın
		_fill_events(seg, v, p.zs - _v_boost(v) * 0.6 - 10.0, p.ze + _clear_end(v), "yoğun")
		_fill_gaps(seg, v)
	for p in plan_h:
		var seg := _add_segment(p.x, p.top, p.end, p.w, p.zs, p.ze, true, true)
		seg.route = 2
		seg.fork_id = fork_id
		# Zor kolun düz yollarında yarım çakıl (dar yolda: kenardan atabilir)
		if absf(p.end - p.top) < 0.3 and _rng.randf() < 0.6:
			var gl := v * _rng.randf_range(0.2, 0.3)
			var room: float = (p.zs - p.ze) - v * 1.0 - _clear_end(v)
			if room > gl:
				var gz: float = p.zs - v * 1.0 - _rng.randf_range(0.0, room - gl)
				var left := _rng.randf() < 0.5
				_add_gravel(seg, seg.x - seg.width * 0.5 if left else seg.x, seg.x if left else seg.x + seg.width * 0.5, gz, gl)
	var m_w := absf(x_l - x_h) + maxf(end_l.w, end_h.w)
	var v_full := v + minf(v * car.boost_bonus, car.boost_max_extra)
	var m_len := v * _rng.randf_range(2.0, 2.6)
	for e in [[end_h, g_h], [end_l, g_l]]:
		var far: float = car_len + v_full * _flight_time(m_top - e[0].end, car.launch_velocity) - e[1]
		m_len = maxf(m_len, far + v * 1.2)
	var merge := _add_segment((x_l + x_h) * 0.5, m_top, m_top, m_w,
		m_start, m_start - m_len, true)
	# Geniş birleşme yolu da engelli: en uzak inişten sonra, pistten önce
	var m_far := 0.0
	for e in [[end_h, g_h], [end_l, g_l]]:
		m_far = maxf(m_far, car_len + v_full * _flight_time(m_top - e[0].end, car.launch_velocity) - e[1])
	# Geniş birleşme yolunda büyük çakıl (yarı genişlik), sonra boşluklar dolar
	if _rng.randf() < 0.7:
		var gl := v * _rng.randf_range(0.3, 0.5)
		var room := (m_start - merge.z_end) - v * 0.3 - _clear_end(v) - v * 1.0
		if room > gl:
			var gz := m_start - v * 0.3 - _rng.randf_range(0.0, room - gl)
			var left := _rng.randf() < 0.5
			_add_gravel(merge, merge.x - merge.width * 0.5 if left else merge.x, merge.x if left else merge.x + merge.width * 0.5, gz, gl)
	_fill_events(merge, v, m_start - _clear_start(v, m_far), merge.z_end + _clear_end(v), "orta", -1, true)
	_fill_gaps(merge, v)
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
	# Ucunda tam genişlik blok: çıkmaza girilirse sonunda zamanında yandan atlamak gerek
	_add_block(s, s.x - w * 0.5, s.x + w * 0.5, s.z_end + 1.4, 1.2)
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

func _add_segment(x: float, top: float, top_end: float, width: float, z_start: float, z_end: float, is_main: bool,
		bonus := false, wall_depth := -1.0, lights := true) -> Segment:
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
	var depth := clampf(_rng.randf_range(6.0, 28.0) if wall_depth < 0.0 else wall_depth, 4.0, minf(top, top_end) + WALL_FLOOR)
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
	if is_main and lights:
		_add_runway_lights(body, s, slope_len)

	s.node = body
	segments.append(s)
	_remember(s)
	stats.min_top = minf(stats.min_top, minf(top, top_end))
	stats.max_top = maxf(stats.max_top, maxf(top, top_end))
	stats.max_slope_deg = maxf(stats.max_slope_deg, rad_to_deg(absf(body.rotation.x)))
	if rise > 1.0:
		stats.ramps_up += 1
	return s


## Pist ışıkları: yolun son ~1.1 saniyesinde iki kenarda kırmızı yuvarlak ışıklar.
## Bölgenin başında seyrek (~5 m), yolun ucuna doğru düzgünce sıklaşır (~1 m).
## Parlak bir bant dizi boyunca ~0.6 sn'de yolun ucuna akar ve döngüyle tekrarlar: "şimdi gaz".
func _add_runway_lights(body: Node3D, s: Segment, slope_len: float) -> void:
	var v := estimate_speed(car.global_position.z - s.z_end)
	var zone := clampf(v * lights_time, 18.0, minf(70.0, slope_len * 0.6))
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
	ball.radius = 0.16
	ball.height = 0.32
	ball.radial_segments = 10
	ball.rings = 5
	dots.mesh = ball
	var quad := QuadMesh.new()
	quad.size = Vector2(1.9, 1.9)
	halos.mesh = quad
	var half := slope_len * 0.5
	var cos_a := cos(body.rotation.x)
	var i := 0
	for j in dists.size():
		var dist: float = dists[j]
		var lz := -half + dist
		# Işığın dizideki sırası: 0 bölgenin başı, 1 yolun ucu. Mesafeye değil sıraya
		# göre: akan bant her an aynı sayıda ışığı yakar (uçta sıkışıp kalmaz)
		var along := 1.0 - float(j) / maxf(dists.size() - 1, 1)
		for sx in [-1.0, 1.0]:
			var pos := Vector3(sx * (s.width * 0.5 - 0.22), 0.18, lz)
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
## Yolun başında boş kalacak uzunluk. İnişte roketin hızı hâlâ üstümüzde
## olabilir: boş bölge gazlı hıza göre; tam roketle en uzak iniş noktasından
## sonra da kaçacak vakit kalsın.
func _clear_start(v: float, land_far: float) -> float:
	return maxf(_v_boost(v) * 0.6 + 10.0, land_far + _v_boost(v) * 0.55 + 6.0)


## Yolun sonunda boş kalacak uzunluk: pist ışıkları ve gaz öncesi hizalanma
func _clear_end(v: float) -> float:
	# Son engelden sonra ~0.45 sn tepki + pist ışıklarının ilk yarısında hizalanıp gaz
	return clampf(v * lights_time * 0.6, 14.0, 45.0) + v * 0.45


## Tam roketle bu boşluğu atlayan arabanın yeni yolun başından ne kadar ileride ineceği
func _land_far_estimate(v: float, dh: float, gap: float, slope: float) -> float:
	var v_full := v + minf(v * car.boost_bonus, car.boost_max_extra)
	return car.half_length * 2.0 + v_full * _flight_time(dh, car.launch_velocity + v_full * slope) - gap


## Yolda x0..x1 genişliğinde, z'den başlayıp depth boyunca çakıl
func _add_gravel(s: Segment, x0: float, x1: float, z: float, depth: float) -> void:
	s.obstacles.append({"x0": x0, "x1": x1, "z0": z, "z1": z - depth, "gravel": true})
	stats.gravel = int(stats.get("gravel", 0)) + 1
	var body := s.node
	# Eğimli yolda gövde döndürülmüş: yol boyunca uzunluk eğime göre
	var c := cos(body.rotation.x)
	depth /= c
	var center := Vector3((x0 + x1) * 0.5 - s.x, 0.0, (z - body.position.z) / c - depth * 0.5)
	_add_box(body, center + Vector3(0, 0.02, 0), Vector3(x1 - x0, 0.03, depth), _gravel_mat)
	# Kenarlarında koyu çizgi: "zemin değişiyor"
	for ez in [0.0, -depth]:
		_add_box(body, center + Vector3(0, 0.035, depth * 0.5 + ez), Vector3(x1 - x0, 0.02, 0.25), _block_mat)
	for k in int((x1 - x0) * depth * 0.45):
		var st := _add_box(body, center + Vector3(_rng.randf_range(-0.5, 0.5) * (x1 - x0 - 0.3), 0.05,
			_rng.randf_range(-0.5, 0.5) * (depth - 0.3)), Vector3.ONE * _rng.randf_range(0.08, 0.2), _stone_mat)
		st.rotation.y = _rng.randf() * TAU


# --------------------------------------------------------------------------
# Yol içi: ritim, bitişik parçalar ve engel dizilimleri
# --------------------------------------------------------------------------

## Yol içi olaylar: [ağırlık, gereken en az yol genişliği, yolun şeklini değiştirir mi]
##  tek_blok    – rastgele bir yerde tek blok
##  iki_blok    – iki blok, ayrı yerlerde, düzensiz
##  kapı        – bir sıra blok, arada tek geçit (yeri rastgele)
##  zikzak      – sağ-sol sırayla 2-4 sıra blok
##  çakıl_şerit – yol boyunca çakıl, içinde tek temiz şerit
##  çakıl_tarla – yolun tamamı çakıl (geçmek zorundasın, yavaşlatır)
##  çakıl_yan   – yolun bir yanı çakıl
##  blok_çakıl  – bir yanda blok, öbür yanda çakıl, ortada şerit
##  daralma     – yol bir süre daralır (ortada ya da bir yanda)
##  yarık       – yolun bir yarısı bir süre yok
##  kayma       – yol yana kayar (basamak gibi), devamı kaymış yerden gider
##  genişleme   – yol bir süre genişler
##  tümsek      – küçük tümsek: tepede hafifçe havalanırsın
const EVENTS := {
	"tek_blok": [1.0, 4.6, false], "iki_blok": [0.8, 5.0, false], "kapı": [0.7, 6.4, false],
	"zikzak": [0.5, 5.5, false], "çakıl_şerit": [0.55, 6.0, false], "çakıl_tarla": [0.35, 6.5, false],
	"çakıl_yan": [0.55, 5.0, false], "blok_çakıl": [0.4, 7.0, false],
	"daralma": [0.6, 5.6, true], "yarık": [0.55, 5.6, true], "kayma": [0.75, 4.8, true],
	"genişleme": [0.3, 0.0, true], "tümsek": [1.1, 0.0, true],
}
## Aksiyon çarpanı: yoldaki olay sayısı ve sıklığı, yoğun yolların payı, kristal
## fırsatları bununla çarpılır (1 = eski yoğunluk). Olaylar arası tepki süresi
## yine de en az ~0.45 sn kalır.
@export var action := 2.0
## Aksiyon mesafeyle artar: çarpanın başta ve action_growth_at metrede aldığı kat
@export var action_growth := Vector2(1.0, 2.0)
@export var action_growth_at := 8000.0
## Şu anki (mesafeyle büyümüş) aksiyon çarpanı
var _act := 2.0
## Ruh hâline göre bir yoldaki olay sayısı (en az, en çok)
const MOOD_EVENTS := {"nefes": Vector2i(1, 1), "orta": Vector2i(2, 3), "yoğun": Vector2i(3, 6)}


## Sıradaki düz yolun ruh hâli. İki nefes üst üste gelmez, yoğun en fazla iki kez.
func _next_mood(difficulty: float) -> String:
	var options := [["nefes", 0.7 / maxf(_act, 0.1)], ["orta", 1.4], ["yoğun", (0.5 + 1.3 * difficulty) * _act]]
	var total := 0.0
	for o in options:
		if o[0] == _last_mood and (o[0] == "nefes" or _mood_run >= 2):
			o[1] = 0.0
		total += o[1]
	var pick := _rng.randf() * total
	var mood := "orta"
	for o in options:
		pick -= o[1]
		if pick <= 0.0 and o[1] > 0.0:
			mood = o[0]
			break
	_mood_run = _mood_run + 1 if mood == _last_mood else 1
	_last_mood = mood
	stats["ritim_" + mood] = int(stats.get("ritim_" + mood, 0)) + 1
	return mood


## Olay seç: genişliği yetenler arasından ağırlıkla; son olay hiç gelmez,
## son birkaç olayın şansı düşer. Uygun yoksa "".
func _pick_event(w: float, shapes_ok: bool, no_gravel := false) -> String:
	var total := 0.0
	var weights := {}
	for kind: String in EVENTS:
		var e: Array = EVENTS[kind]
		if w < e[1] or (e[2] and not shapes_ok) or (kind == "genişleme" and w > 7.5):
			continue
		if no_gravel and kind.contains("çakıl"):
			continue
		var wt: float = e[0]
		if not _recent_events.is_empty() and _recent_events[-1] == kind:
			wt = 0.0
		elif kind in _recent_events:
			wt *= 0.35
		weights[kind] = wt
		total += wt
	if total <= 0.0:
		return ""
	var pick := _rng.randf() * total
	for kind: String in weights:
		pick -= weights[kind]
		if pick <= 0.0 and weights[kind] > 0.0:
			_recent_events.append(kind)
			if _recent_events.size() > 5:
				_recent_events.pop_front()
			return kind
	return ""


## Olayın ölçüleri (uzunluk ve rastgele ayarları)
func _make_event(kind: String, w: float, v: float) -> Dictionary:
	var e := {"kind": kind, "len": 1.2}
	match kind:
		"iki_blok":
			# Biri bir yana, öbürü öbür yana düşebilir: arada karşıya geçecek vakit olsun
			e.sep = v * _rng.randf_range(0.75, 1.0)
			e.len = e.sep + 1.2
		"zikzak":
			e.n = _rng.randi_range(2, 4)
			e.sp = v * _rng.randf_range(0.65, 0.9)
			e.len = (e.n - 1) * e.sp + 1.2
		# Çakıllar saniye cinsinden: hızlanınca da aynı süre üstünde kalınır
		"çakıl_şerit":
			e.len = maxf(v * _rng.randf_range(0.4, 0.6), 12.0)
		"çakıl_tarla":
			e.len = maxf(v * _rng.randf_range(0.3, 0.45), 8.0)
		"çakıl_yan":
			e.len = maxf(v * _rng.randf_range(0.35, 0.55), 10.0)
		"blok_çakıl":
			e.len = maxf(v * _rng.randf_range(0.3, 0.4), 10.0)
		"daralma":
			e.len = v * _rng.randf_range(0.45, 0.8)
			e.w = clampf(w * _rng.randf_range(0.5, 0.65), 3.8, w - 1.4)
			e.dx = 0.0 if _rng.randf() < 0.4 else (-1.0 if _rng.randf() < 0.5 else 1.0) * (w - e.w) * 0.5 * _rng.randf_range(0.5, 1.0)
		"yarık":
			e.len = v * _rng.randf_range(0.4, 0.7)
			e.w = maxf(w * 0.5, 3.8)
			e.dx = (-1.0 if _rng.randf() < 0.5 else 1.0) * (w - e.w) * 0.5
		"kayma":
			e.len = 0.0
			e.dx = (-1.0 if _rng.randf() < 0.5 else 1.0) * _rng.randf_range(1.6, minf(3.0, w - 3.6))
		"genişleme":
			e.len = v * _rng.randf_range(0.6, 1.0)
			e.w = w + _rng.randf_range(2.0, 4.0)
			e.dx = _rng.randf_range(-1.5, 1.5)
		"tümsek":
			# Rampa boyu hızla uzar (eğim aynı kalır); tepeden uçuş + iniş sonrası pay
			e.half = maxf(7.0, v * 0.15)
			e.h = e.half * _rng.randf_range(0.09, 0.15)
			var vy: float = v * e.h / e.half * car.bump_launch + 1.0
			# Tepeden uçuş (yerden kalkıp aynı yüksekliğe iniş) tamamen ayrılır
			e.len = e.half * 2.0 + v * (2.0 * vy / car.gravity) * 1.1
	return e


## z_from'dan z_to'ya (ileriye) dizilecek olaylar; ruh hâline göre sayı ve aralık
func _plan_events(z_from: float, z_to: float, w: float, v: float, mood: String, shapes_ok: bool,
		n_max := -1, no_gravel := false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if n_max < 0:
		n_max = _rng.randi_range(roundi(MOOD_EVENTS[mood].x * _act), roundi(MOOD_EVENTS[mood].y * _act))
	var z := z_from - v * _rng.randf_range(0.0, 0.4)
	var tries := 0
	# Sayı dolsa da yolun kalanı ~1 sn'den uzunsa olay eklemeye devam (uzun boş düzlük olmasın)
	while (out.size() < n_max or z - z_to > v * 1.0) and tries < n_max + 12:
		tries += 1
		# Boş kalan yeri dolduran fazladan olaylar çakılsız (çakıl kenardan atabilir)
		var kind := _pick_event(w, shapes_ok, no_gravel or out.size() >= n_max)
		if kind == "":
			break
		var e := _make_event(kind, w, v)
		if z - e.len < z_to:
			continue
		e.z = z
		out.append(e)
		stats["olay_" + kind] = int(stats.get("olay_" + kind, 0)) + 1
		# Sonraki olaya tepki süresi: yoğunda kısa; çakıldan ve tümsekten sonra toparlanma payı
		var gap := v * (_rng.randf_range(0.55, 0.75) if mood == "yoğun" else _rng.randf_range(0.7, 1.1))
		gap = maxf(gap / maxf(_act, 0.1), v * 0.45)
		if kind.contains("çakıl"):
			# Çakıldan sonra araba ~0.8 sn sendeler: toparlanma payı
			gap = maxf(gap, v * 1.15)
		elif kind == "tümsek":
			# İnişten sonra toparlanma (sarsıntı): bir sonraki olaya biraz vakit
			gap = maxf(gap, v * 0.75)
		elif kind == "kayma":
			gap = maxf(gap, v * 0.7)
		elif kind in ["daralma", "yarık", "genişleme"]:
			# Dar/geniş bölümden çıkınca bir sonraki sıranın geçidine kaymaya vakit
			gap = maxf(gap, v * 0.8)
		z -= e.len + gap
	return out


## İçi değişen düz yol: inişte ve pist ışıklarında boş, arada olaylar. Şekil olayları
## yolu bitişik parçalara böler (aynı yükseklik, boşluksuz). İlk parçayı döndürür.
func _build_road(x: float, top: float, w: float, z_start: float, length: float, v: float,
		land_far: float, mood: String) -> Segment:
	var z_end := z_start - length
	var z0 := z_start - _clear_start(v, land_far)
	var z_last := z_end + _clear_end(v)
	var events: Array[Dictionary] = []
	if z0 - z_last > 4.0:
		events = _plan_events(z0, z_last, w, v, mood, true)
	# Bölümler: { za, zb, x, w, ta, tb }
	var secs: Array[Dictionary] = []
	var cur_x := x
	var sec_start := z_start
	for e in events:
		if not EVENTS[e.kind][2]:
			continue
		secs.append({"za": sec_start, "zb": e.z, "x": cur_x, "w": w, "ta": top, "tb": top})
		match e.kind:
			"daralma", "yarık", "genişleme":
				secs.append({"za": e.z, "zb": e.z - e.len, "x": cur_x + e.dx, "w": e.w, "ta": top, "tb": top})
				sec_start = e.z - e.len
			"kayma":
				# Yol çok uzağa sürüklenmesin
				var dx: float = e.dx
				if absf(cur_x + dx - x) > 4.0:
					dx = -dx
				cur_x += dx
				sec_start = e.z
			"tümsek":
				secs.append({"za": e.z, "zb": e.z - e.half, "x": cur_x, "w": w, "ta": top, "tb": top + e.h})
				secs.append({"za": e.z - e.half, "zb": e.z - e.half * 2.0, "x": cur_x, "w": w, "ta": top + e.h, "tb": top})
				sec_start = e.z - e.half * 2.0
	secs.append({"za": sec_start, "zb": z_end, "x": cur_x, "w": w, "ta": top, "tb": top})
	var depth := _rng.randf_range(6.0, 28.0)
	var built: Array[Segment] = []
	for i in secs.size():
		var c: Dictionary = secs[i]
		if c.za - c.zb < 0.5:
			continue
		var sg := _add_segment(c.x, c.ta, c.tb, c.w, c.za, c.zb, true, false,
			depth + minf(c.ta, c.tb) - top, i == secs.size() - 1)
		if not built.is_empty():
			built[-1].next_flush = sg
		built.append(sg)
	# Şekil olaylarında kristal: dar parçanın ortası, kaymadan sonraki yeni hat, tümsek tepesi
	for e in events:
		if not EVENTS[e.kind][2] or _rng.randf() > 0.6 * _act:
			continue
		for sg in built:
			if e.z - 1.0 <= sg.z_start and e.z - 1.0 >= sg.z_end:
				match e.kind:
					"daralma", "yarık":
						_crystal_line(sg, sg.x, sg.z_start - 3.0, sg.x, sg.z_end + 3.0, 3)
					"kayma":
						var gx := sg.x + _rng.randf_range(-0.25, 0.25) * sg.width
						_crystal_line(sg, gx, e.z - 4.0, gx, e.z - 4.0 - minf(18.0, sg.z_start - sg.z_end - 6.0), 3)
					"tümsek":
						# Tepeden uçarken geçilen yay
						var vy: float = v * e.h / e.half * car.bump_launch + 1.0
						_arc_crystals(sg, Vector3(sg.x, top + e.h, e.z - e.half), 0.0, vy, v,
							2.0 * vy / car.gravity, 3)
				break
	# Engel olayları, üstüne düştükleri (tam genişlikteki) parçaya
	for e in events:
		if EVENTS[e.kind][2]:
			continue
		for sg in built:
			if e.z <= sg.z_start and e.z - e.len >= sg.z_end:
				_place_event(sg, e, v)
				break
	for e in events:
		built[0].events_log.append(e.kind)
	for sg in built:
		_validate_rows(sg, v)
	return built[0]


## Uzun boş düzlük kalmasın: ana yolun (bitişik parçalarıyla) inişten fill_after_landing
## sn sonrasından pist bölgesine kadar, max_empty_time'dan uzun engelsiz aralıklarına
## tek blok ya da yarım çakıl girer (yeri, yanı ve sayısı her seferinde değişir).
## Yokuş, tümsek ve yatık parçalar kendisi manevra sayılır. Yol ağındaki dönüş
## inişleri de dolar: inen araba havada yön verip yerini seçer.
func _fill_gaps(first: Segment, v: float, land_far := 0.0) -> void:
	var chain: Array[Segment] = [first]
	while chain[-1].next_flush:
		chain.append(chain[-1].next_flush)
	# Tam gazla en uzak inişten sonra da biraz pay (havada yön verip yer seçilir)
	var z_from := first.z_start - maxf(v * fill_after_landing, land_far + v * 0.25)
	var z_to := chain[-1].z_end + _clear_end(v)
	if z_from - z_to < v * max_empty_time:
		return
	# Meşgul aralıklar (yakın z, uzak z)
	var busy: Array[Vector2] = []
	for i in chain.size():
		var sg := chain[i]
		if absf(sg.top_end - sg.top) > 0.3 or (sg.bank_a.size() > 0 and not sg.ramp):
			# Yokuş/tümsek parçası kendisi manevra; tümsekten fırlayınca iniş yeri de boş
			busy.append(Vector2(sg.z_start, sg.z_end - (v * 1.4 if i > 0 or sg.next_flush else 0.0)))
		if i > 0 and (absf(sg.x - chain[i - 1].x) > 0.5 or absf(sg.width - chain[i - 1].width) > 0.5):
			busy.append(Vector2(sg.z_start + v * 0.3, sg.z_start - v * 0.3))
		for o in sg.obstacles:
			if o.get("ramp", false):
				# Rampaya yaklaşma payı
				busy.append(Vector2(o.z0 + v * 0.5, o.z1))
			elif o.gravel:
				# Çakıldan sonra sendeleme payı
				busy.append(Vector2(o.z0, o.z1 - v * 1.0))
			else:
				busy.append(Vector2(o.z0, o.z1))
	# Ana yolun üstündeki rampa parçaları (yol ağı, adalar)
	for r in segments:
		if r.ramp and r.z_start <= first.z_start and r.z_end >= z_to - 1.0:
			for sg in chain:
				if absf(r.x - sg.x) < sg.width * 0.5 and r.z_start <= sg.z_start and r.z_end >= sg.z_end - 1.0:
					busy.append(Vector2(r.z_start + v * 0.5, r.z_end))
	busy.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x > b.x)
	var hw: float = car.model.half_width if car.model else 1.1
	var lane := maxf(3.4, hw * 2.0 + 1.3)
	# İniş bölgesi de sayılır ama oraya yalnız çakıl girer (inen arabayı öldürmez)
	var land_edge := z_from
	var cur := first.z_start - v * 0.3
	busy.append(Vector2(z_to, z_to))
	for b in busy:
		var gap := cur - maxf(minf(b.x, cur), z_to)
		if gap > v * max_empty_time:
			var n := int(ceil(gap / (v * max_empty_time))) - 1
			var step := gap / (n + 1)
			for k in n:
				var z := cur - step * (k + 1) + _rng.randf_range(-0.15, 0.15) * step
				var host: Segment = null
				for sg in chain:
					if z <= sg.z_start - 1.0 and z - 1.2 >= sg.z_end:
						host = sg
				if host == null:
					continue
				var after := z - (cur - gap)
				if z > land_edge:
					# İniş bölgesinde: kısa çakıl, ardından toparlanma payı
					var gl2 := minf(v * 0.22, 14.0)
					if after - gl2 >= v * 1.0 and host.width >= 5.5:
						if _rng.randf() < 0.5:
							_add_gravel(host, host.x - host.width * 0.5, host.x + host.width * 0.5, z, gl2)
						else:
							var left2 := _rng.randf() < 0.5
							_add_gravel(host, host.x - host.width * 0.5 if left2 else host.x,
								host.x if left2 else host.x + host.width * 0.5, z, gl2)
						stats["dolgu"] = int(stats.get("dolgu", 0)) + 1
					continue
				if host.width >= lane + 1.4 and (_rng.randf() < 0.75 or after < v * 1.1):
					_single_block(host, z, lane)
				elif after >= v * 1.1 and host.width >= 3.0:
					var gl := minf(v * 0.2, 12.0)
					var left := _rng.randf() < 0.5
					_add_gravel(host, host.x - host.width * 0.5 if left else host.x,
						host.x if left else host.x + host.width * 0.5, z, gl)
				stats["dolgu"] = int(stats.get("dolgu", 0)) + 1
		cur = minf(cur, b.y)
		if cur <= z_to:
			break
	for sg in chain:
		_validate_rows(sg, v)


## Boş bir yol aralığını (ağın parçaları arası, yan yollar) engel olaylarıyla doldurur
func _fill_events(s: Segment, v: float, z_from: float, z_to: float, mood: String, n_max := -1,
		no_gravel := false) -> void:
	for e in _plan_events(z_from, z_to, s.width, v, mood, false, n_max, no_gravel):
		_place_event(s, e, v)
		s.events_log.append(e.kind)
	_validate_rows(s, v)


## Blok sıralarını baştan sona dolaşır: bir önceki sıranın geçidinden bu sıranın
## geçidine o hızla (tepki süresiyle) yetişilemiyorsa bu sıranın blokları kaldırılır.
## Böylece arka arkaya gelen olaylar hiçbir zaman imkânsız bir dizilim kurmaz.
func _validate_rows(s: Segment, v: float) -> void:
	var hw: float = car.model.half_width if car.model else 1.1
	var lo := s.x - s.width * 0.5 + hw + 0.3
	var hi := s.x + s.width * 0.5 - hw - 0.3
	if hi < lo:
		return
	var blocks: Array[Dictionary] = []
	for o in s.obstacles:
		if not o.gravel and not o.get("ramp", false):
			blocks.append(o)
	blocks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.z0 > b.z0)
	var gravel_ends: Array[float] = []
	for o in s.obstacles:
		if o.gravel:
			gravel_ends.append(o.z1)
	var reach: Array[Vector2] = [Vector2(lo, hi)]
	var last_z := s.z_start
	var i := 0
	while i < blocks.size():
		var row: Array[Dictionary] = [blocks[i]]
		var j := i + 1
		while j < blocks.size() and blocks[i].z0 - blocks[j].z0 < 1.5:
			row.append(blocks[j])
			j += 1
		i = j
		# Çakıldan çıkınca araba bir süre sendeler: hemen arkasına blok sırası gelmesin
		var shaken := false
		for gz in gravel_ends:
			if gz > row[0].z0 and gz - row[0].z0 < v * 0.9:
				shaken = true
		# Önceki sıradan bu yana yana ne kadar gidilebilir
		var dt: float = (last_z - row[0].z0) / maxf(v, 1.0)
		var grow := car.steer_speed * maxf(dt - 0.3, 0.0) * 0.65
		var grown: Array[Vector2] = []
		for iv in reach:
			grown.append(Vector2(maxf(iv.x - grow, lo), minf(iv.y + grow, hi)))
		var free: Array[Vector2] = [Vector2(lo, hi)]
		for o in row:
			var b0: float = o.x0 - hw - 0.45
			var b1: float = o.x1 + hw + 0.45
			var nf: Array[Vector2] = []
			for iv in free:
				if b1 <= iv.x or b0 >= iv.y:
					nf.append(iv)
					continue
				if b0 > iv.x:
					nf.append(Vector2(iv.x, b0))
				if b1 < iv.y:
					nf.append(Vector2(b1, iv.y))
			free = nf
		# Tuzak olmasın: önceki sıranın her geçidinden bu sıranın bir geçidine yetişilebilmeli
		var next: Array[Vector2] = []
		var trap := false
		for a in grown:
			var hit := false
			for b in free:
				var x0 := maxf(a.x, b.x)
				var x1 := minf(a.y, b.y)
				if x1 >= x0:
					next.append(Vector2(x0, x1))
					hit = true
			if not hit:
				trap = true
		if next.is_empty() or shaken or trap:
			for o in row:
				if o.has("node") and is_instance_valid(o.node):
					o.node.queue_free()
				s.obstacles.erase(o)
				stats.removed_rows = int(stats.get("removed_rows", 0)) + 1
			reach = grown
			continue
		reach = next
		last_z = float(row[0].z1)


func _place_event(s: Segment, e: Dictionary, v: float) -> void:
	var w := s.width
	var x0 := s.x - w * 0.5
	var x1 := s.x + w * 0.5
	var hw: float = car.model.half_width if car.model else 1.1
	var lane := maxf(3.4, hw * 2.0 + 1.3)
	var z: float = e.z
	var gems := _rng.randf() < 0.65 * _act
	match e.kind:
		"tek_blok":
			var b := _single_block(s, z, lane)
			if gems:
				_near_miss_crystals(s, b, z, hw)
		"iki_blok":
			var b := _single_block(s, z, lane)
			_single_block(s, z - e.sep, lane)
			if gems:
				_near_miss_crystals(s, b, z, hw)
		"kapı":
			var g := _rng.randf_range(lane, lane + 0.8)
			var gx := _rng.randf_range(x0 + g * 0.5, x1 - g * 0.5)
			if gx - g * 0.5 - x0 > 0.6:
				_add_block(s, x0, gx - g * 0.5, z, 1.2)
			if x1 - gx - g * 0.5 > 0.6:
				_add_block(s, gx + g * 0.5, x1, z, 1.2)
			if gems:
				_crystal_line(s, gx, z + 7.0, gx, z - 5.0, 3)
		"zikzak":
			var side := -1.0 if _rng.randf() < 0.5 else 1.0
			var bw := minf(w - lane, 4.5)
			for i in e.n:
				if side < 0.0:
					_add_block(s, x0, x0 + bw, z - i * e.sp, 1.2)
				else:
					_add_block(s, x1 - bw, x1, z - i * e.sp, 1.2)
				side = -side
		"çakıl_şerit":
			var l := _rng.randf_range(3.0, 3.6)
			var lc := _rng.randf_range(x0 + l * 0.5, x1 - l * 0.5)
			if lc - l * 0.5 - x0 > 0.5:
				_add_gravel(s, x0, lc - l * 0.5, z, e.len)
			if x1 - lc - l * 0.5 > 0.5:
				_add_gravel(s, lc + l * 0.5, x1, z, e.len)
			if gems:
				_crystal_line(s, lc, z - 2.0, lc, z - e.len + 2.0, maxi(int(e.len / 6.0), 2))
		"çakıl_tarla":
			_add_gravel(s, x0, x1, z, e.len)
			if gems:
				var gx := _rng.randf_range(x0 + 1.5, x1 - 1.5)
				_crystal_line(s, gx, z - 2.0, gx, z - e.len + 2.0, 3)
		"çakıl_yan":
			var bw := w * _rng.randf_range(0.5, 0.6)
			if _rng.randf() < 0.5:
				_add_gravel(s, x0, x0 + bw, z, e.len)
			else:
				_add_gravel(s, x1 - bw, x1, z, e.len)
		"blok_çakıl":
			var bw := _rng.randf_range(1.8, 2.6)
			var gw := w - bw - lane
			if _rng.randf() < 0.5:
				_add_block(s, x0, x0 + bw, z - e.len * 0.5, 1.2)
				_add_gravel(s, x1 - gw, x1, z, e.len)
			else:
				_add_block(s, x1 - bw, x1, z - e.len * 0.5, 1.2)
				_add_gravel(s, x0, x0 + gw, z, e.len)


## Bloğun hemen yanından (kıl payı) geçen kristal çizgisi: geçidin blok tarafında
func _near_miss_crystals(s: Segment, b: Vector2, z: float, hw: float) -> void:
	var left_room := b.x - (s.x - s.width * 0.5)
	var right_room := (s.x + s.width * 0.5) - b.y
	var gx := b.x - hw - 0.3 if left_room > right_room else b.y + hw + 0.3
	_crystal_line(s, gx, z + 9.0, gx, z - 3.0, 3)


## Rastgele yerde tek blok; bir yanında araba geçecek kadar yer kalır. (x0, x1) döndürür.
func _single_block(s: Segment, z: float, lane: float) -> Vector2:
	var w := s.width
	var x0 := s.x - w * 0.5
	var bw := _rng.randf_range(1.4, clampf(w - lane - 0.2, 1.4, 3.2))
	var lo := x0
	var hi := x0 + w - bw
	if _rng.randf() < 0.5:
		lo = minf(x0 + lane, hi)  # solda geçit
	else:
		hi = maxf(x0 + w - bw - lane, lo)  # sağda geçit
	var bx := _rng.randf_range(lo, hi)
	_add_block(s, bx, bx + bw, z, 1.2)
	return Vector2(bx, bx + bw)


## Yolda x0..x1 genişliğinde, z'den başlayan depth derinliğinde blok (çarpınca patlar)
func _add_block(s: Segment, x0: float, x1: float, z: float, depth: float) -> void:
	s.obstacles.append({"x0": x0, "x1": x1, "z0": z, "z1": z - depth, "gravel": false})
	stats.blocks = int(stats.get("blocks", 0)) + 1
	var body := s.node
	var c := cos(body.rotation.x)
	var center := Vector3((x0 + x1) * 0.5 - s.x, 0.0, (z - body.position.z) / c - depth * 0.5)
	var size := Vector3(x1 - x0 - 0.1, 0.9, depth)
	var block := StaticBody3D.new()
	block.position = center + Vector3(0, 0.45, 0)
	body.add_child(block)
	s.obstacles[-1].node = block
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	block.add_child(col)
	_add_box(block, Vector3.ZERO, size, _block_mat)
	_add_box(block, Vector3(0, 0.46, 0), Vector3(size.x, 0.04, size.z), _block_top_mat)


# --------------------------------------------------------------------------
# Kristaller (enerji): roket ve kanatlar harcar, yalnız bunlardan dolar
# --------------------------------------------------------------------------

func set_crystal_color(c: Color) -> void:
	crystal_color = c
	_crystal_mat.set_shader_parameter("color", c)
	_crystal_mat.set_shader_parameter("light", c.lerp(Color.WHITE, 0.65))
	for fx in _pickup_fx:
		((fx.mesh as BoxMesh).material as StandardMaterial3D).albedo_color = c.lerp(Color.WHITE, 0.4)


## Bir kristal bırak (dünya konumu, merkezi). Yol üretimi bitince toplu kurulur.
func _crystal(host: Segment, p: Vector3) -> void:
	var key := host.get_instance_id()
	if not _crystal_pending.has(key):
		_crystal_pending[key] = {"host": host, "pts": PackedVector3Array()}
	_crystal_pending[key].pts.append(p)


## Yol yüzeyinin üstünde (x, z) noktasında kristal
func _crystal_on(host: Segment, x: float, z: float, lift := 1.0) -> void:
	_crystal(host, Vector3(x, host.surface_y(x, z) + lift, z))


## za'dan zb'ye yol boyunca tek sıra, en çok n kristal: düz (hep xb hizasında,
## çapraz değil), crystal_spacing aralıkla. gated: depo doluysa grup çoğu zaman konmaz.
func _crystal_line(host: Segment, _xa: float, za: float, xb: float, zb: float, n: int, gated := true) -> void:
	if gated and not _want_crystals():
		return
	var fit := int(absf(za - zb) / crystal_spacing) + 1
	var dir := -1.0 if zb < za else 1.0
	for i in mini(n, fit):
		_crystal_on(host, xb, za + dir * crystal_spacing * i)


## Uçuş yayında tek sıra kristal, yol boyunca crystal_spacing aralıkla, yayın ortasında.
## p0 kalkış noktası; vx yana, vy yukarı hız; speed ileri hız; t_all uçuş süresi.
func _arc_crystals(host: Segment, p0: Vector3, vx: float, vy: float, speed: float, t_all: float,
		n_max := 4) -> void:
	if t_all < 0.3 or not _want_crystals():
		return
	var dt := crystal_spacing / maxf(speed, 1.0)
	var n := clampi(int(t_all * 0.5 / dt) + 1, 1, n_max)
	var t0 := t_all * 0.5 - dt * (n - 1) * 0.5
	for i in n:
		var t := t0 + dt * i
		_crystal(host, p0 + Vector3(vx * t, vy * t - 0.5 * car.gravity * t * t + 0.8, -speed * t))


## Deponun boşluğu (0 dolu, 1 boş): kristal arzı buna göre
func _crystal_need() -> float:
	if car == null:
		return 1.0
	return 1.0 - clampf(car.energy / maxf(car.max_energy, 1.0), 0.0, 1.0)


## Bu kristal grubu konsun mu: depo %45'in üstündeyse giderek seyrekleşir, doluyken ~%20'si kalır
func _want_crystals() -> bool:
	var full := smoothstep(0.45, 0.95, 1.0 - _crystal_need())
	return _rng.randf() >= full * 0.8


func _pending_count(host: Segment) -> int:
	var key := host.get_instance_id()
	return _crystal_pending[key].pts.size() if _crystal_pending.has(key) else 0


func _flush_crystals() -> void:
	for key in _crystal_pending:
		# Bir yolda hep tek sıra: yakından uzağa, öncekine aralıktan yakın olan atlanır
		var raw: Array = Array(_crystal_pending[key].pts)
		raw.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.z > b.z)
		var pts := PackedVector3Array()
		for q: Vector3 in raw:
			if pts.is_empty() or pts[-1].z - q.z >= crystal_spacing * 0.75:
				pts.append(q)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _crystal_mesh
		mm.instance_count = pts.size()
		var z_far := INF
		var alive: Array[bool] = []
		for i in pts.size():
			mm.set_instance_transform(i, Transform3D(Basis(), pts[i]))
			mm.set_instance_custom_data(i, Color(_rng.randf(), 0, 0, 0))
			z_far = minf(z_far, pts[i].z)
			alive.append(true)
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = _crystal_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_crystal_sets.append({"node": mi, "mm": mm, "pts": pts, "alive": alive, "z_far": z_far,
			"z_near": pts[0].z})
		stats.crystals = int(stats.get("crystals", 0)) + pts.size()
		if keep_history:
			for q in pts:
				crystal_z_history.append([q.x, q.z])
	_crystal_pending.clear()


## Arabanın değdiği kristalleri topla; toplananların sayısını döndürür
func collect_crystals(pos: Vector3, half_width: float, half_length: float) -> int:
	var got := 0
	for cs in _crystal_sets:
		if cs.z_far > pos.z + 4.0 or cs.z_near < pos.z - 80.0:
			continue
		var pts: PackedVector3Array = cs.pts
		for i in pts.size():
			if not cs.alive[i]:
				continue
			var p := pts[i]
			if absf(p.z - pos.z) < half_length + 0.5 and absf(p.x - pos.x) < half_width + 0.55 \
					and p.y - pos.y > -0.9 and p.y - pos.y < 2.3:
				cs.alive[i] = false
				cs.mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), p))
				var fx := _pickup_fx[_pickup_next]
				_pickup_next = (_pickup_next + 1) % _pickup_fx.size()
				fx.global_position = p
				fx.restart()
				got += 1
	return got


## Önümüzdeki (henüz toplanmamış) kristaller: test sürücüsü için
func crystals_ahead(pos: Vector3, dist: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for cs in _crystal_sets:
		if cs.z_far > pos.z or cs.z_near < pos.z - dist:
			continue
		var pts: PackedVector3Array = cs.pts
		for i in pts.size():
			if cs.alive[i] and pts[i].z < pos.z - 1.0 and pts[i].z > pos.z - dist:
				out.append(pts[i])
	return out


func _make_pickup_fx() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 10
	p.lifetime = 0.35
	p.explosiveness = 1.0
	p.local_coords = false
	p.spread = 180.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 7.0
	p.gravity = Vector3.ZERO
	p.damping_min = 6.0
	p.damping_max = 9.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.16
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("ffb36b")
	mesh.material = mat
	p.mesh = mesh
	add_child(p)
	return p


## Bir ana yolun (bitişik parçalarıyla) kristalleri: önce zor yerlere konmuş olanlar
## sayılır, hedefe kadar kolay çizgilerle (iniş ve pist) tamamlanır. Hedef: yolun
## sonundaki boşluk için gereken enerjinin arz katı; mesafeyle azalır.
func _road_crystals(first: Segment, v: float, travelled: float) -> void:
	var k := clampf(travelled / maxf(crystal_hard_at, 1.0), 0.0, 1.0)
	# Bir boşluk için tipik roket: pist ışıklarında basılır, yerde ~0.65 sn yanar
	var need := car.boost_energy_rate * 0.65
	var tank := lerpf(crystal_need_range.x, crystal_need_range.y, _crystal_need())
	if 1.0 - _crystal_need() < crystal_low_at:
		tank *= crystal_low_boost
	var target := ceili(need * lerpf(crystal_supply.x, crystal_supply.y, k) * tank / maxf(crystal_value, 1.0))
	var chain: Array[Segment] = [first]
	while chain[-1].next_flush:
		chain.append(chain[-1].next_flush)
	var have := 0
	for sg in chain:
		have += _pending_count(sg)
	var easy := maxi(roundi(target * lerpf(crystal_easy_share.x, crystal_easy_share.y, k)), target - have)
	if easy <= 0:
		return
	var last := chain[-1]
	# İniş bölgesi: engel yok, tek sıra kristal (ortada ya da bir yanda: seçim);
	# bazen bir yanda çakıl
	var n_land := ceili(easy * 0.55)
	var land_z := first.z_start - v * _rng.randf_range(0.3, 0.5)
	var span := minf(crystal_spacing * maxf(n_land - 1, 1), (first.z_start - first.z_end) * 0.5)
	if land_z - span > first.z_end + 2.0:
		var lx := first.x + _rng.randf_range(-0.3, 0.3) * first.width
		_crystal_line(first, lx, land_z, lx, land_z - span, n_land, false)
		var free := land_z - span - (first.z_start - _clear_start(v, 0.0))
		# (Yatık yolda yok: düz kutu yatık yüzeye oturmaz, kenarda havada kalır)
		if _rng.randf() < 0.18 * _act and first.width >= 5.0 and first.obstacles.is_empty() \
				and first.bank_a.is_empty() and land_z - span - first.z_end > 30.0:
			# Yanda kısa çakıl: inen arabayı öldürmez, yavaşlatır
			var bw := first.width * _rng.randf_range(0.35, 0.45)
			var gz := land_z - _rng.randf_range(0.0, span * 0.5)
			if _rng.randf() < 0.5:
				_add_gravel(first, first.x - first.width * 0.5, first.x - first.width * 0.5 + bw, gz, 10.0)
			else:
				_add_gravel(first, first.x + first.width * 0.5 - bw, first.x + first.width * 0.5, gz, 10.0)
	# Pist çizgisi: bir yandan başlayıp ortaya iner (hizalanırken toplanır)
	var n_run := easy - n_land
	if n_run > 0:
		var zone := clampf(v * lights_time, 18.0, 70.0)
		var za := maxf(last.z_end + zone, last.z_end + 4.0 + crystal_spacing * (n_run - 1))
		za = minf(za, last.z_start - 2.0)
		var cx := last.x + _rng.randf_range(-0.12, 0.12) * last.width
		_crystal_line(last, cx, za, cx, last.z_end + 4.0, n_run, false)


## Boşluğun üstünde, orta karar gazla atlayanın uçuş yayında kristaller
func _gap_crystals(prev: Segment, next_x: float, dh: float, gap: float, v: float) -> void:
	var slope := prev.slope()
	var v_mid := lerpf(v, _v_boost(v), 0.55)
	var vy := car.launch_velocity + v_mid * slope
	var t_all := _flight_time(dh, vy)
	if t_all < 0.3:
		return
	_arc_crystals(prev, Vector3(prev.x, prev.top_end, prev.z_end - car.half_length),
		(next_x - prev.x) * v_mid / maxf(gap, 1.0), vy, v_mid, t_all, _rng.randi_range(3, 4))
	stats.gap_arcs = int(stats.get("gap_arcs", 0)) + 1


## Rampadan kalkışın yayında kristaller (yana atan rampada yana da kayar)
func _ramp_crystals(r: Segment, v: float) -> void:
	var vy := car.launch_velocity + v * r.slope()
	var t_all := _flight_time(-(r.top_end - r.top) - 0.5, vy)
	_arc_crystals(r, Vector3(r.x, r.top_end, r.z_end - car.half_length), r.kick, vy, v, t_all, 4)


# --------------------------------------------------------------------------
# Ada zincirleri: kısa adalar, aralarında gazsız sıçramalar, yan yana yollar
# --------------------------------------------------------------------------

## Ada zinciri türleri:
##  ada       – her adımda 1-3 yan yana kısa ada; üstlerinde blok, çakıl, kristal
##  ada_rampa – rampa (up) / rampa (down) adalar, uçlarında zıplatan kamalar, bloklar
##  ada_çoklu – her adımda 2-3 ada, farklı yüksekliklerde (alçak / orta / yüksek)
##  ada_eğik  – sağda solda uzak adalar; her birinin sonunda karşıya atan eğik rampa
## Adalar arası boşluk gazsız zıplamayla geçilir (gaz verirsen kısa adayı aşabilirsin).
## Zincire girişte ve çıkışta roketli normal boşluk vardır.
const ISLAND_KINDS := {"ada": 1.0, "ada_rampa": 1.0, "ada_çoklu": 0.9, "ada_eğik": 0.8}
var _last_island := ""


## Gazsız zıplamanın yatay erişimi (araba boyu dahil) ve uçuş süresi: vy kalkıştaki dikey hız
func _hop(v: float, vy: float, dh: float) -> Vector2:
	var t := _flight_time(dh, vy)
	return Vector2(car.half_length * 2.0 + v * t, t)


func _build_islands(prev: Segment, travelled: float) -> Segment:
	var total := 0.0
	var weights := {}
	for k: String in ISLAND_KINDS:
		weights[k] = 0.0 if k == _last_island else float(ISLAND_KINDS[k])
		total += weights[k]
	var pick := _rng.randf() * total
	var kind := "ada"
	for k: String in weights:
		pick -= weights[k]
		if pick <= 0.0 and weights[k] > 0.0:
			kind = k
			break
	_last_island = kind
	stats[kind] = int(stats.get(kind, 0)) + 1
	var hw: float = car.model.half_width if car.model else 1.1
	var lv := car.launch_velocity
	var g := car.gravity
	# Havada yana erişim (güvenli pay ile)
	var v0 := estimate_speed(car.global_position.z - prev.z_end)
	var reach_t := _flight_time(-1.0, lv)
	var side_reach := car.steer_speed * reach_t * car.air_control * 0.7
	# Yan yana adalar arası (merkezden merkeze): adalar ayrı dursun (aralarında boşluk)
	var d := _rng.randf_range(5.0, 5.8)
	# Adadan adaya yana erişim: adada kalkıştan önce kayma (~0.35 sn) + havada
	var lane_reach := side_reach + car.steer_speed * 0.35
	# Giriş: roketli normal boşluk; ilk ada tam roketle inişi taşıyacak kadar uzun
	var entry := _pick_gap(prev.slope(), _rng.randf_range(-1.5, 0.0), v0, gap_difficulty)
	var top := maxf(prev.top_end + float(entry.dh), MIN_LEVEL + 6.0)
	var z := prev.z_end - float(entry.gap)
	var cx := prev.x + _rng.randf_range(-1.5, 1.5)
	var steps := _rng.randi_range(5, 7) if kind == "ada_eğik" else _rng.randi_range(6, 9)
	var main_x := cx
	var prev_lanes: Array = [cx]
	var last_main: Segment = null
	var eg_side := -1.0 if _rng.randf() < 0.5 else 1.0
	# Önceki zıplamanın en uzak inişi: bu adanın en az bu kadar uzun olması gerekir
	var min_next_L := 0.0
	# Bu adaya en uzak iniş (adanın başından): engeller bunun ötesinde başlar
	var land_far_cur: float = float(entry.min_len) - v0 * 1.2
	var depth := _rng.randf_range(10.0, 24.0)
	for k in steps:
		var v := estimate_speed(car.global_position.z - z)
		var last := k == steps - 1
		# --- Bu adımın şeridleri: [x, genişlik, yükseklik farkı]
		var lanes: Array = []
		match kind:
			"ada_eğik":
				eg_side = -eg_side
				var w := _rng.randf_range(4.8, 5.8)
				lanes.append([cx + eg_side * _rng.randf_range(3.0, 4.2) if k > 0 else cx, w, 0.0])
			"ada_çoklu":
				var sets := [[-d, 0.0, d], [-d, d], [0.0, d], [-d, 0.0]]
				var xs: Array = sets[_rng.randi() % sets.size()]
				var hs := [-1.2, -0.6, 0.0]
				hs.shuffle()
				for i in xs.size():
					lanes.append([cx + float(xs[i]), _rng.randf_range(3.4, 4.2), hs[i % 3] if xs.size() > 1 else 0.0])
			_:
				var sets := [[0.0], [-d, d], [0.0, d], [-d, 0.0], [-d, 0.0, d]]
				var wts := [1.0, 1.0, 0.8, 0.8, 0.5]
				var tw := 0.0
				for x in wts:
					tw += x
				var p := _rng.randf() * tw
				var xs: Array = sets[0]
				for i in sets.size():
					p -= wts[i]
					if p <= 0.0:
						xs = sets[i]
						break
				for x in xs:
					lanes.append([cx + float(x), _rng.randf_range(3.6, 4.2) if xs.size() > 1 else _rng.randf_range(4.6, 6.2),
						_rng.randf_range(-0.8, 0.0) if xs.size() > 1 else 0.0])
		if k == 0 or last:
			# Giriş ve çıkış adası tek ve geniş: roketli boşluğa iniş/kalkış
			lanes = [[cx, _rng.randf_range(5.5, 7.0), 0.0]] if kind != "ada_eğik" else [[lanes[0][0], 5.5, 0.0]]
		# Erişim: önceki adımın her adasından bu adımın en az bir adasına yetişilmeli
		if kind != "ada_eğik":
			for px in prev_lanes:
				var ok := false
				for ln in lanes:
					if absf(float(ln[0]) - float(px)) <= lane_reach + 0.5:
						ok = true
				if not ok:
					var has_mid := false
					for ln in lanes:
						if absf(float(ln[0]) - cx) < 1.0:
							has_mid = true
					if not has_mid:
						# Erişim için gereken orta ada: onunla çakışan adalar çıkar (orta ada kalmalı)
						lanes = lanes.filter(func(ln: Array) -> bool:
							return absf(float(ln[0]) - cx) >= (float(ln[1]) + 4.0) * 0.5 + 0.8)
						lanes.append([cx, 4.0, 0.0])
		# Adalar üst üste binmesin: soldan sağa, aralarında en az 0.8 m boşluk
		lanes.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		var kept: Array = []
		for ln in lanes:
			if kept.is_empty() or float(ln[0]) - float(kept[-1][0]) >= (float(ln[1]) + float(kept[-1][1])) * 0.5 + 0.8:
				kept.append(ln)
		lanes = kept
		# --- Ada boyu: kısa (0.7-1.4 sn); ilk ada roket inişini taşır
		var L := maxf(v * _rng.randf_range(0.7, 1.4), min_next_L)
		# Blok adası: arada bir biraz uzun (en çok 2 sn), inişten sonra engel sığsın;
		# tek adaysa geniş (blok yanından geçilsin)
		var block_isle := kind != "ada_eğik" and k > 0 and not last and _rng.randf() < 0.4
		if block_isle:
			L = maxf(L, v * _rng.randf_range(1.6, 2.0))
			if lanes.size() == 1:
				lanes[0][1] = maxf(float(lanes[0][1]), _rng.randf_range(5.2, 6.2))
			else:
				# Yan yana adalar da blok sığacak kadar geniş; aralarını biraz aç
				for ln in lanes:
					ln[0] = cx + (float(ln[0]) - cx) * 6.0 / d
					ln[1] = _rng.randf_range(4.9, 5.2)
		if k == 0:
			L = maxf(L, float(entry.min_len))
		if last:
			L = maxf(L, clampf(v * lights_time, 18.0, 70.0) + v * 1.2)
		# --- Uç türü: düz zıplama, kama (zıplatan rampa), eğik rampa; rampa up/down ada
		var end := "hop"
		var rise := 0.0
		if not last:
			match kind:
				"ada_rampa":
					var r := _rng.randf()
					if r < 0.35:
						end = "kama"
					elif r < 0.65:
						rise = _rng.randf_range(0.8, 1.6)   # rampa (up)
					else:
						rise = -_rng.randf_range(1.0, 2.0)  # rampa (down)
				"ada_eğik":
					end = "eğik"
				_:
					if _rng.randf() < 0.4:
						end = "kama"
		# Kalkışta dikey hız
		var slope := rise / maxf(L, 1.0)
		# Kama ve eğik rampa hıza göre: kalkıştaki dikey hız hep ~10-13 m/s (tepe ~2-3 m)
		var r_len := 6.0 if end == "kama" else 7.0
		var r_rise := 0.0
		if end == "kama":
			r_rise = clampf(r_len * (_rng.randf_range(10.0, 12.5) - lv) / maxf(v, 1.0), 0.4, 2.0)
		elif end == "eğik":
			r_rise = clampf(r_len * (_rng.randf_range(10.5, 12.0) - lv) / maxf(v, 1.0), 0.5, 2.0)
		var vy := lv + v * slope
		if end != "hop":
			vy = lv + v * r_rise / r_len
		# Sonraki adımın yüksekliği (bu adanın kalkış noktasına göre): zıplamanın
		# tepesinin epey altında kalmalı ki ön yüzüne çarpılmasın
		var apex := vy * vy / (2.0 * g)
		var end_top := top + rise + r_rise
		var dh_take := 0.0
		# Bu adımın en alçak adası (şerit yükseklik farkı; sonraki adımda en yüksek fark 0)
		var low_off := 0.0
		for ln in lanes:
			low_off = minf(low_off, float(ln[2]))
		if not last:
			dh_take = _rng.randf_range(-1.8, maxf(apex * 0.4 + low_off, -1.8))
			if end_top + dh_take < MIN_LEVEL + 4.0:
				dh_take = absf(dh_take) * 0.5
			if end_top + dh_take > MAIN_LEVEL + 5.0:
				dh_take = -absf(dh_take) - 0.5
		# --- Adaları kur
		var built: Array[Segment] = []
		var best := INF
		var main_i := 0
		for i in lanes.size():
			var ln: Array = lanes[i]
			var x: float = ln[0]
			var w: float = ln[1]
			var t0: float = top + float(ln[2])
			var sg := _add_segment(x, t0, t0 + rise, w, z, z - L, true, false, depth + t0 - top, last)
			sg.hop = not last
			sg.events_log.append(kind)
			built.append(sg)
			if absf(x - main_x) < best:
				best = absf(x - main_x)
				main_i = i
		# Yalnız bir ada "ana yol" (test sürücüsü ve portal bunu izler); öbürleri yan ada
		for i in built.size():
			built[i].main = i == main_i
			built[i].side_road = i != main_i
		var main_seg := built[main_i]
		main_x = main_seg.x
		# Uçlar: kama ya da eğik rampa adanın son kısmına
		var flight := Vector2.ZERO
		var kick := 0.0
		var next_x := cx
		if end == "eğik" and not last:
			var nx := cx + (-eg_side) * _rng.randf_range(3.0, 4.2)
			flight = _hop(v, vy, dh_take)
			kick = (nx - main_seg.x) / maxf(flight.y, 0.2)
			_add_ramp(main_seg, main_seg.x, main_seg.width, z - L + r_len, r_len, r_rise, 7.0, kick)
			next_x = nx
		elif end == "kama":
			for sg in built:
				_add_ramp(sg, sg.x, sg.width * _rng.randf_range(0.55, 1.0), z - L + r_len, r_len, r_rise, 0.0, 0.0)
		# Engeller ve kristaller: inişten sonra, kalkıştan önce
		var land_in := land_far_cur + v * 0.45 if k > 0 else _clear_start(v, land_far_cur)
		for sg in built:
			var za := sg.z_start - land_in
			var zb := sg.z_end + (r_len if end != "hop" else 0.0) + v * 0.4
			if za - zb > v * (0.3 if block_isle else 0.45) and sg.width >= 3.6 and (block_isle or _rng.randf() < 0.5):
				var bz := _rng.randf_range(zb + 1.5, za)
				var lane_w := maxf(3.4, hw * 2.0 + 1.3)
				if sg.width >= lane_w + 1.4 and (_rng.randf() < 0.7 or za - zb < 11.0):
					_single_block(sg, bz, lane_w)
					# Yer varsa ikinci blok (arada tepki payı)
					var bz2 := bz - v * _rng.randf_range(0.5, 0.7)
					if bz2 > zb + 1.5:
						_single_block(sg, bz2, lane_w)
				elif za - zb >= 11.0:
					bz = _rng.randf_range(zb + 10.5, za)
					var gw := sg.width * 0.5
					var left := _rng.randf() < 0.5
					_add_gravel(sg, sg.x - sg.width * 0.5 if left else sg.x + sg.width * 0.5 - gw,
						sg.x - sg.width * 0.5 + gw if left else sg.x + sg.width * 0.5, bz, 10.0)
				_validate_rows(sg, v)
			# Çakıl yaması (adanın tamamı ya da yarısı): inişte de olabilir (öldürmez,
			# yavaşlatır), kalkıştan en az ~0.7 sn önce biter ki yavaşlayan araba yetişsin
			if not last and sg.obstacles.is_empty() and _rng.randf() < 0.5:
				var gl := clampf(v * _rng.randf_range(0.18, 0.28), 8.0, 18.0)
				var g_end := sg.z_end + (r_len if end != "hop" else 0.0) + v * 0.7
				var room := sg.z_start - 2.0 - g_end - gl
				if room > 0.0:
					var gz := sg.z_start - 2.0 - _rng.randf_range(0.0, room)
					if _rng.randf() < 0.5:
						_add_gravel(sg, sg.x - sg.width * 0.5, sg.x + sg.width * 0.5, gz, gl)
					else:
						var left := _rng.randf() < 0.5
						_add_gravel(sg, sg.x - sg.width * 0.5 if left else sg.x, sg.x if left else sg.x + sg.width * 0.5, gz, gl)
			if last:
				_fill_gaps(sg, v)
			# Yan adalar kristalli (zor seçim ödüllü), ana adada bazen
			if (sg != main_seg or _rng.randf() < 0.3) and za - zb > 8.0:
				var gx := sg.x + _rng.randf_range(-0.2, 0.2) * sg.width
				_crystal_line(sg, gx, za, gx, maxf(zb, za - 24.0), 3)
		if end == "eğik" and not last:
			# Eğik rampanın uçuş yayında kristaller
			_arc_crystals(main_seg, Vector3(main_seg.x, main_seg.top_end + r_rise, z - L), kick, vy, v, flight.y, 3)
		last_main = main_seg
		prev_lanes = []
		for sg in built:
			prev_lanes.append(sg.x)
		if end == "eğik" and not last:
			prev_lanes = [next_x]
		if last:
			break
		# --- Boşluk: en yüksek adaya gazsız yetişilsin (şerit farkı +0.5 m payı),
		# en alçağa inen kısa adayı aşmasın
		var hop := _hop(v, vy, minf(dh_take - low_off + 0.2, apex * 0.6))
		var gap := car.half_length + v * hop.y * _rng.randf_range(0.3, 0.45)
		if end == "eğik":
			gap = car.half_length + v * flight.y * 0.4
		# Bir sonraki ada en uzak inişi taşısın (en alçak şeride, biraz hızlı gelinse de)
		var far := _hop(v * 1.15, vy, dh_take - low_off - 1.2)
		min_next_L = far.x - gap + v * 0.35
		land_far_cur = far.x - gap
		top = end_top + dh_take
		z = z - L - gap
		if end == "eğik":
			cx = next_x
	# Çıkış adası roketli boşluğa açılır: kolay kristal çizgileri
	_road_crystals(last_main, v0, travelled)
	_add_decor(last_main)
	return last_main


# --------------------------------------------------------------------------
# Yol ağı: yol üstü rampalar, alçak/yüksek yan yollar ve dönüş rampaları
# --------------------------------------------------------------------------

## Uzun düz bir ana yolun üstüne/yanına ağ kurar. Başı (iniş) ve sonu (pist ışıkları
## + hizalanma) boş kalır. Arada sırayla 1-4 parça dizilir (aynısı üst üste gelmez),
## parçaların arasındaki ana yol blok ve çakılla dolar. Her rampanın fırlattığı yer
## hıza göre hesaplanır ve iniş yeri boştur. Rampalar gaz istemez (üstlerinde gaz çalışmaz).
##  rampa  – düz rampa (tam ya da yarım genişlik, boyu/yüksekliği değişir); yarımsa
##           arkasına çakıl gelebilir: üstünden uç ya da çakıldan geç
##  slalom – sırayla sağda solda küçük yarım rampalar
##  alt    – yanda alçak yol: kenardan düşülür, sonundaki eğik rampa ana yola atar
##  üst    – ana yolda yana fırlatan eğik rampa yandaki yüksek yola atar;
##           onun sonundaki rampa ana yola geri atar
func _add_network(s: Segment, v: float, land_far: float, travelled: float) -> void:
	var dens := clampf((travelled - network_from) / maxf(network_full_at - network_from, 1.0), 0.0, 1.0)
	var z0 := s.z_start - _clear_start(v, land_far)
	var z_last := s.z_end + _clear_end(v)
	# Ana yolda boş kalması gereken aralıklar (rampaya yaklaşma, uçuş, iniş): (yakın z, uzak z)
	var busy: Array[Vector2] = []
	var cursor := z0
	var last := ""
	var low_side := 0.0
	# Alçak yol ilk parçaysa ana yolun inişinin yanından erken başlayabilir
	if _rng.randf() < 0.5:
		low_side = -1.0 if _rng.randf() < 0.5 else 1.0
		var end := _net_low(s, low_side, v, s.z_start - 12.0, z_last, busy)
		if not is_nan(end):
			last = "alt"
			stats["ağ_alt"] = int(stats.get("ağ_alt", 0)) + 1
	for attempt in 10:
		if cursor - v * 1.5 < z_last:
			break
		# Yan yollar (alt/üst) ağın asıl seçimi: ağırlıkları yüksek
		var options := [["rampa", 0.8], ["slalom", 0.4 + 0.4 * dens], ["alt", 1.5], ["üst", 1.4]]
		var total := 0.0
		for o in options:
			if o[0] == last:
				o[1] = 0.0
			total += o[1]
		var pick := _rng.randf() * total
		var kind: String = options[0][0]
		for o in options:
			pick -= o[1]
			if pick <= 0.0 and o[1] > 0.0:
				kind = o[0]
				break
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		if kind == "üst" and low_side != 0.0:
			side = -low_side  # alçak yolun öbür yanında
		# Parçalar arasında biraz (engelli) düz yol
		var at := cursor - (v * _rng.randf_range(0.3, 1.2) if last != "" else 0.0)
		var end := NAN
		match kind:
			"rampa":
				end = _net_ramp(s, v, at, z_last, busy)
			"slalom":
				end = _net_slalom(s, v, at, z_last, busy)
			"alt":
				end = _net_low(s, side, v, at, z_last, busy)
				if not is_nan(end):
					low_side = side
			"üst":
				end = _net_high(s, side, v, at, z_last, busy)
		if is_nan(end):
			# Sığmadı ya da bir iniş yerine denk geldi: biraz ileriden dene
			cursor -= v * 0.6
			continue
		stats["ağ_" + kind] = int(stats.get("ağ_" + kind, 0)) + 1
		last = kind
		# Alçak yolun yanındaki ana yol da kullanılabilir (dönüş inişi meşgul işaretli)
		cursor = minf(cursor - v * _rng.randf_range(1.0, 1.6), end) if kind == "alt" else end
	# Boş kalan ana yol aralıkları blok ve çakılla dolar
	busy.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x > b.x)
	var z := z0
	var stops := busy.duplicate()
	stops.append(Vector2(z_last, z_last))
	for b: Vector2 in stops:
		if z - b.x > v * 0.5:
			_fill_events(s, v, z, b.x, "yoğun" if _rng.randf() < dens else "orta")
		z = minf(z, b.y)


## Ana yolun [near, far] aralığı başka bir parçanın meşgul aralığıyla çakışmıyor mu
func _busy_free(busy: Array[Vector2], near: float, far: float) -> bool:
	for b in busy:
		if near > b.y and far < b.x:
			return false
	return true


## Rampadan kalkıp dh (iniş yeri - rampa ucu) yüksekliğine inene kadar gidilen yol
func _ramp_flight(v: float, slope: float, dh: float) -> Vector2:
	var t := _flight_time(dh, car.launch_velocity + v * slope)
	return Vector2(car.half_length * 2.0 + v * t, t)


## Ana yolda tek düz rampa; sonraki boş z'yi döndürür (sığmazsa NAN)
func _net_ramp(s: Segment, v: float, z: float, z_last: float, busy: Array[Vector2]) -> float:
	var r_len := _rng.randf_range(6.0, 10.0)
	var r_rise := r_len * _rng.randf_range(0.14, 0.24)
	var fl := _ramp_flight(v, r_rise / r_len, -r_rise)
	var end := z - r_len - fl.x - v * 0.6
	if end < z_last or not _busy_free(busy, z + v * 0.45, end):
		return NAN
	var full := _rng.randf() < 0.4
	var rw := s.width if full else s.width * _rng.randf_range(0.45, 0.6)
	var sd := -1.0 if _rng.randf() < 0.5 else 1.0
	var rx := s.x if full else s.x + sd * (s.width - rw) * 0.5
	_add_ramp(s, rx, rw, z, r_len, r_rise, 0.0, 0.0)
	busy.append(Vector2(z + v * 0.45, end))
	s.events_log.append("ağ_rampa")
	if not full and _rng.randf() < 0.6:
		# Rampanın arkasında, uçuşun altında tam genişlik çakıl
		var g0 := z - r_len - fl.x * 0.15
		var depth := fl.x * _rng.randf_range(0.45, 0.65)
		_add_gravel(s, s.x - s.width * 0.5, s.x + s.width * 0.5, g0, depth)
	return end


## Sırayla sağda solda küçük yarım rampalar
func _net_slalom(s: Segment, v: float, z: float, z_last: float, busy: Array[Vector2]) -> float:
	var r_len := 5.0
	var r_rise := 0.8
	var fl := _ramp_flight(v, r_rise / r_len, -r_rise)
	var step := r_len + fl.x + v * _rng.randf_range(0.7, 0.9)
	var n := _rng.randi_range(3, 4)
	while n > 1 and z - step * n < z_last:
		n -= 1
	if n < 2 or not _busy_free(busy, z + v * 0.45, z - step * n):
		return NAN
	s.events_log.append("ağ_slalom")
	var rw := s.width * 0.5
	var sd := -1.0 if _rng.randf() < 0.5 else 1.0
	busy.append(Vector2(z + v * 0.45, z - step * n))
	for i in n:
		_add_ramp(s, s.x + sd * rw * 0.5, rw, z - step * i, r_len, r_rise, 0.0, 0.0)
		sd = -sd
	return z - step * n


## Alçak yan yol: ana yolun kenarından düşülerek girilir; sonunda ana yola atan eğik rampa.
## z0'dan başlar; ana yoldaki dönüş inişinin bittiği z'yi döndürür (sığmazsa NAN).
func _net_low(s: Segment, side: float, v: float, z0: float, z_last: float, busy: Array[Vector2]) -> float:
	var drop := _rng.randf_range(3.0, 5.5)
	var w := _rng.randf_range(4.5, 6.5)
	var x := s.x + side * (s.width * 0.5 + _rng.randf_range(0.6, 1.2) + w * 0.5)
	var top := s.top - drop
	var k_len := _rng.randf_range(6.0, 8.0)
	var k_rise := maxf(k_len * _rng.randf_range(0.32, 0.4), 0.0)
	var fl := _ramp_flight(v, k_rise / k_len, drop - k_rise)
	var lz0 := z0 + 6.0
	var lz_end := maxf(lz0 - v * _rng.randf_range(1.8, 3.2), z_last + fl.x)
	if lz0 - lz_end < v * 1.8 or not _busy_free(busy, lz_end, lz_end - fl.x - v * 0.6):
		return NAN
	for sg in segments:
		# Aynı yanda başka bir yan yol varsa üst üste binmesin
		if sg.side_road and signf(sg.x - s.x) == side and sg.z_end < lz0 + 5.0 and sg.z_start > lz_end - 5.0:
			return NAN
	var low := _add_segment(x, top, top, w, lz0, lz_end, false)
	low.side_road = true
	# Dönüş rampası yolun tamamını kaplar: yolun sonuna gelen herkes ana yola atılır
	_add_ramp(low, x, w, lz_end + k_len, k_len, k_rise, _rng.randf_range(5.0, 9.0), -side * absf(x - s.x) / fl.y)
	# Alçak yolda da engel olabilir (girişte ve rampanın önünde boş)
	# (Kenardan düşüp inince toparlanacak kadar sonra başlar)
	if lz0 - lz_end > v * 2.9 and _rng.randf() < 0.6:
		_fill_events(low, v, lz0 - v * 1.9, lz_end + k_len + v * 0.9, "orta")
	stats.side_roads = int(stats.get("side_roads", 0)) + 1
	s.events_log.append("ağ_alt")
	# Alçak yol kristal dolu: yol seçiminin karşılığı
	_crystal_line(low, x, lz0 - v * 0.9, x + _rng.randf_range(-1.0, 1.0), lz_end + k_len + 6.0, _rng.randi_range(5, 8))
	var end := lz_end - fl.x - v * 0.6
	busy.append(Vector2(lz_end, end))
	return end


## Yüksek yan yol: ana yolun yan yarısındaki eğik rampa yukarı ve yana atar; yüksek
## yolun sonundaki rampa ana yola geri atar
func _net_high(s: Segment, side: float, v: float, z0: float, z_last: float, busy: Array[Vector2]) -> float:
	var h := _rng.randf_range(1.8, 3.4)
	var rw := s.width * _rng.randf_range(0.42, 0.55)
	var rx := s.x + side * (s.width - rw) * 0.5
	var r_len := _rng.randf_range(7.0, 9.5)
	var r_rise := r_len * _rng.randf_range(0.18, 0.24)
	var fl1 := _ramp_flight(v, r_rise / r_len, h - r_rise)
	var w := _rng.randf_range(4.5, 5.5)
	var hx := s.x + side * (s.width * 0.5 + 0.8 + w * 0.5)
	var k_len := 6.0
	var k_rise := 0.8
	var fl2 := _ramp_flight(v, k_rise / k_len, -(h + k_rise))
	var r_end := z0 - r_len
	var hz0 := r_end - fl1.x * 0.45
	var hz_end := maxf(r_end - fl1.x - v * _rng.randf_range(1.4, 2.8), z_last + fl2.x)
	if hz_end > r_end - fl1.x - v * 1.0 or not _busy_free(busy, z0 + v * 0.45, r_end - v * 1.1) \
			or not _busy_free(busy, hz_end, hz_end - fl2.x - v * 0.6):
		return NAN
	for sg in segments:
		if sg.side_road and signf(sg.x - s.x) == side and sg.z_end < hz0 + 5.0 and sg.z_start > hz_end - 5.0:
			return NAN
	_add_ramp(s, rx, rw, z0, r_len, r_rise, _rng.randf_range(5.0, 9.0), side * absf(hx - rx) / fl1.y)
	# Rampaya girmeyen de rampanın yanından geçince hemen bloğa çarpmasın
	busy.append(Vector2(z0 + v * 0.45, r_end - v * 1.1))
	var high := _add_segment(hx, s.top + h, s.top + h, w, hz0, hz_end, false)
	high.side_road = true
	_add_ramp(high, hx, w, hz_end + k_len, k_len, k_rise, 7.0, -side * absf(hx - s.x) / fl2.y)
	var land := r_end - fl1.x - v * 1.0
	if land - (hz_end + k_len + v * 0.9) > v * 1.2 and _rng.randf() < 0.5:
		_fill_events(high, v, land, hz_end + k_len + v * 0.9, "orta", 2)
	stats.side_roads = int(stats.get("side_roads", 0)) + 1
	s.events_log.append("ağ_üst")
	_crystal_line(high, hx, land - 4.0, hx, hz_end + k_len + 6.0, _rng.randi_range(4, 6))
	var end := hz_end - fl2.x - v * 0.6
	busy.append(Vector2(hz_end, end))
	return end


## Bir yolun üstüne rampa: yakın ucu yolla aynı hizada, uzak ucu rise kadar yüksek.
## kick != 0 ise rampa o yana eğik (fırlattığı yönün tersi tarafı yüksek) ve kalkışta
## arabayı o yana atar. Üstünde turuncu oklar fırlatma yönünü gösterir.
func _add_ramp(host: Segment, x: float, width: float, z_start: float, length: float, rise: float,
		tilt_deg: float, kick: float) -> Segment:
	var s := Segment.new()
	s.x = x
	s.width = width
	s.z_start = z_start
	s.z_end = z_start - length
	s.top = host.top_at(z_start)
	s.top_end = s.top + rise
	s.main = false
	s.ramp = true
	s.kick = kick
	var a := -signf(kick) * deg_to_rad(tilt_deg) if kick != 0.0 else 0.0
	s.bank_z = PackedFloat32Array([s.z_start, s.z_end])
	s.bank_a = PackedFloat32Array([0.0, a])
	var body := StaticBody3D.new()
	body.position = Vector3(x, s.top, (s.z_start + s.z_end) * 0.5)
	# Araba rampanın yan duvarlarını yol duvarı saymasın (yarım girişte tekerler üstüne çıkar)
	body.set_meta("ramp", s)
	add_child(body)
	var cz := body.position.z
	var rows := 6
	var at := func(d: float, i: float, lift: float) -> Vector3:
		var z := z_start - length * i / rows
		var b := s.bank_at(z)
		# Ağzı yolun birkaç cm altından başlar: araba hep üstüne çıkar, altına girip
		# yüzeye alttan çarpmaz
		var lead := 0.08 if i == 0 else 0.0
		return Vector3(d * cos(b), rise * i / rows + d * sin(b) + lift - lead, z - cz)
	var hw := width * 0.5
	var top_st := SurfaceTool.new()
	top_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var side_st := SurfaceTool.new()
	side_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var unused := PackedVector3Array()
	for i in rows:
		var l0: Vector3 = at.call(-hw, i, 0.0)
		var r0: Vector3 = at.call(hw, i, 0.0)
		var l1: Vector3 = at.call(-hw, i + 1, 0.0)
		var r1: Vector3 = at.call(hw, i + 1, 0.0)
		_quad(top_st, faces, l0, r0, r1, l1, Vector3.UP)
		_quad(side_st, faces, l0, l1, Vector3(l1.x, -0.6, l1.z), Vector3(l0.x, -0.6, l0.z), Vector3.LEFT)
		_quad(side_st, faces, r0, r1, Vector3(r1.x, -0.6, r1.z), Vector3(r0.x, -0.6, r0.z), Vector3.RIGHT)
	var bl: Vector3 = at.call(-hw, rows, 0.0)
	var br: Vector3 = at.call(hw, rows, 0.0)
	_quad(side_st, faces, bl, br, Vector3(br.x, -0.6, br.z), Vector3(bl.x, -0.6, bl.z), Vector3.FORWARD)
	# Oklar: fırlatma yönüne bakan turuncu ^ işaretleri
	var arrows := SurfaceTool.new()
	arrows.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lat := clampf(kick / maxf(estimate_speed(car.global_position.z - z_start), 1.0) * 2.5, -0.9, 0.9)
	var dir := Vector2(lat, 1.0).normalized()
	var arm := minf(width * 0.32, 1.6)
	for k in 3:
		var tc := (k + 0.7) / 3.4 * rows
		var dc := lat * hw * 0.3
		for sgn in [-1.0, 1.0]:
			var back := dir.rotated(sgn * deg_to_rad(130.0))
			var p0 := Vector2(dc, tc * length / rows)
			var p1 := p0 + back * arm
			var nrm := Vector2(-back.y, back.x) * 0.16
			var q := [p0 - nrm, p0 + nrm, p1 + nrm, p1 - nrm]
			var pts: Array = []
			for v2 in q:
				pts.append(at.call(v2.x, v2.y / length * rows, 0.03))
			_quad(arrows, unused, pts[0], pts[1], pts[2], pts[3], Vector3.UP)
	for pair in [[top_st, _ramp_top_mat], [side_st, _wall_material(host)], [arrows, _chevron_mat]]:
		var mi := MeshInstance3D.new()
		mi.mesh = pair[0].commit()
		mi.material_override = pair[1]
		body.add_child(mi)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	s.node = body
	# Rampa, üstünde durduğu yoldan önce aransın (segment_under ilk eşleşeni döndürür)
	segments.insert(maxi(segments.find(host), 0), s)
	_remember(s)
	# Ana yoldaki rampa: test sürücüsü ve portal inişi için engel gibi işaretli
	if host.main:
		host.obstacles.append({"x0": x - hw, "x1": x + hw, "z0": s.z_start, "z1": s.z_end, "gravel": false, "ramp": true})
	stats.ramps = int(stats.get("ramps", 0)) + 1
	# Rampanın uçuşunda kristal yayı (yana atanda yana da kayar)
	if _rng.randf() < 0.55 * _act:
		_ramp_crystals(s, estimate_speed(car.global_position.z - z_start))
	return s


func _remember(s: Segment) -> void:
	s.pattern = _current_kind
	if keep_history:
		history.append(s)


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
	_remember(s)
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


# --------------------------------------------------------------------------
# El yapımı kalıplar (Bölüm Tasarımcısı: editor/, levels/*.json)
# --------------------------------------------------------------------------
# Tasarım dosyası metre cinsindendir: z girişten ileri doğru (0'dan), x sağa,
# h yükseklik (0 = ana seviye). Parçalar ("pieces") yollar, engeller ("obstacles")
# yolların üstündedir. Oyun tasarımı olduğu gibi kurar; yalnız girişini önceki yola
# göre yerleştirir (boşluk oyunun atlama fiziğiyle, gazsız geçilemez/roketle geçilir)
# ve kristalleri kendi algoritmasıyla dizer.

## Sonsuz koşuya karışan el yapımı kalıplar (her biri "at" metreden sonra açılır)
var custom_levels: Array[Dictionary] = []
## Test: başlangıç pistinden hemen sonra bu kalıp gelir (editörde "Oyna", testler)
var test_level: Dictionary = {}
## Kurulan el yapımı kalıpların kaydı (test sonucu için): dünya konumları
var custom_log: Array[Dictionary] = []
## El yapımı kalıbın seçilme ağırlığı (diğer kalıplar ~0.5-3)
@export var custom_weight := 1.2
## Kalıp, tasarlandığı hızın en çok bu katına kadar gelir (daha hızlıda boşluklar bozulur)
@export var custom_speed_margin := 1.25
var _test_used := false
var _custom_recent: Array[String] = []
## Test: denenen kalıp da türetilerek gelsin (--vary)
var vary_test := false
## Bu oyunda gelmiş kalıp/türev imzaları: aynısı iki kez gelmez
var _custom_seen := {}

const LEVEL_DIR := "res://levels"


## levels/ klasöründeki tasarımları yükler
func load_levels() -> void:
	custom_levels.clear()
	for f in DirAccess.get_files_at(LEVEL_DIR):
		if not f.ends_with(".json"):
			continue
		var level := parse_level(FileAccess.get_file_as_string(LEVEL_DIR + "/" + f))
		if not level.is_empty():
			custom_levels.append(level)


## JSON metninden tasarım; bozuksa boş sözlük
static func parse_level(text: String) -> Dictionary:
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary or not data.has("pieces") or not data.pieces is Array or data.pieces.is_empty():
		return {}
	var level: Dictionary = data
	if not level.has("obstacles"):
		level.obstacles = []
	if not level.has("name"):
		level.name = "isimsiz"
	return level


## Başlangıçtan d metre sonra arabanın hızı (oyunun hızlanmasıyla)
func speed_at_distance(d: float) -> float:
	var v0 := car.start_speed
	var v := sqrt(v0 * v0 + 2.0 * car.acceleration * maxf(d, 0.0))
	if v > car.max_speed:
		var d_max := (car.max_speed * car.max_speed - v0 * v0) / (2.0 * car.acceleration)
		v = sqrt(car.max_speed * car.max_speed + 2.0 * car.late_acceleration * (d - d_max))
	return minf(v, car.top_speed)


## Şu anki mesafe ve hızda gelebilecek el yapımı kalıplar
func _eligible_levels(travelled: float, v: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for level in custom_levels:
		var at := float(level.get("at", 0.0))
		if travelled >= at and v <= speed_at_distance(at) * custom_speed_margin:
			out.append(level)
	return out


## Tasarımı önceki yolun ardına kurar; çıkış yolunu (sonraki kalıbın başlayacağı) döndürür
func _build_custom(prev: Segment, level: Dictionary, travelled: float, vary := false) -> Segment:
	var v := estimate_speed(car.global_position.z - prev.z_end)
	if vary:
		level = _fresh_variant(level, v)
	var v_boost := _v_boost(v)
	var slope := prev.slope()
	var vy := car.launch_velocity + v * slope
	var vy_b := car.launch_velocity + v_boost * slope
	var max_up := maxf(vy, 0.0) * maxf(vy, 0.0) / (2.0 * car.gravity) * 0.6
	var pieces: Array = level.pieces.duplicate()
	pieces.sort_custom(func(a, b): return float(a.z0) < float(b.z0))
	var entry: Dictionary = pieces[0]
	for p in pieces:
		if not p.get("side", false):
			entry = p
			break
	# Giriş: önceki yoldan normal bir boşlukla (gazsız ulaşılamaz, roketle ulaşılır)
	var dh := minf(_rng.randf_range(-2.0, 0.5), max_up)
	if vy < 2.0:
		dh = minf(dh, -2.0)
	var car_len := car.half_length * 2.0
	var gaps := _gap_window(dh, v, v_boost, vy, vy_b, car_len)
	if gaps.y < gaps.x:
		dh = minf(dh, -1.0)
		gaps = _gap_window(dh, v, v_boost, vy, vy_b, car_len)
	var gap := lerpf(gaps.x, maxf(gaps.y, gaps.x), 0.35)
	var oy := prev.top_end + dh - float(entry.get("h0", 0.0))
	# Tasarımın en alçak yeri bulutlara inmesin
	var lowest := INF
	for p in pieces:
		lowest = minf(lowest, minf(float(p.get("h0", 0.0)), float(p.get("h1", p.get("h0", 0.0)))))
	if lowest + oy < MIN_LEVEL:
		oy = MIN_LEVEL - lowest
	var ox := prev.x + _rng.randf_range(-1.0, 1.0) * minf(prev.width * 0.25, 2.0) - float(entry.get("x", 0.0))
	var zb := prev.z_end - gap + float(entry.get("z0", 0.0))
	_current_kind = "özel"
	var lname: String = str(level.get("name", "özel"))

	var obstacles: Array = level.obstacles
	var built: Array[Dictionary] = []  # { p, first, last }
	var heads: Array[Segment] = []
	for p in pieces:
		var x := ox + float(p.get("x", 0.0))
		var w := clampf(float(p.get("w", 8.0)), 2.5, 16.0)
		var plen := maxf(float(p.get("len", 40.0)), 4.0)
		var h0 := float(p.get("h0", 0.0))
		var h1 := float(p.get("h1", h0))
		var zs := zb - float(p.get("z0", 0.0))
		var ze := zs - plen
		var is_main: bool = not p.get("side", false)
		# Ucunda bitişik devamı olan parçada pist ışıkları yok
		var flush_next := _custom_successor(p, pieces) != null
		var bank := float(p.get("bank", 0.0))
		var first: Segment
		var last: Segment
		var bumps: Array = []
		for o in obstacles:
			if o.get("kind", "") == "bump" and _custom_on(o, p):
				bumps.append(o)
		if absf(bank) > 0.5 and absf(h1 - h0) < 0.01:
			var a := deg_to_rad(clampf(bank, -max_bank_deg, max_bank_deg))
			var flat_in := minf(10.0, plen * 0.2)
			var flat_out := minf(clampf(v * lights_time, 18.0, 70.0), plen * 0.3)
			var t0 := zs - flat_in
			var t1 := ze + flat_out
			var m := t0 - t1
			var pts: Array = [[zs, 0.0], [t0, 0.0], [t0 - m * 0.3, a], [t0 - m * 0.7, a], [t1, 0.0], [ze, 0.0]]
			first = _add_banked_segment(x, oy + h0, w, zs, ze, pts)
			first.main = is_main
			last = first
		elif not bumps.is_empty() and absf(h1 - h0) < 0.01:
			# Tümsek: yol parçalara bölünür (çık, in), bitişik devam eder
			bumps.sort_custom(func(a, b): return float(a.z0) < float(b.z0))
			var secs: Array = []
			var cur := zs
			for o in bumps:
				var bz := zb - float(o.z0)
				var half := maxf(float(o.get("len", 12.0)), 4.0) * 0.5
				var bh := clampf(float(o.get("rise", 1.0)), 0.3, 3.0)
				if bz > cur or bz - half * 2.0 < ze:
					continue
				secs.append([cur, bz, 0.0, 0.0])
				secs.append([bz, bz - half, 0.0, bh])
				secs.append([bz - half, bz - half * 2.0, bh, 0.0])
				cur = bz - half * 2.0
			secs.append([cur, ze, 0.0, 0.0])
			var depth := _rng.randf_range(6.0, 28.0)
			for i in secs.size():
				var c: Array = secs[i]
				if c[0] - c[1] < 0.5:
					continue
				var sg := _add_segment(x, oy + h0 + c[2], oy + h0 + c[3], w, c[0], c[1], is_main, false,
					depth + minf(c[2], c[3]), i == secs.size() - 1 and not flush_next)
				if last:
					last.next_flush = sg
				else:
					first = sg
				last = sg
		else:
			first = _add_segment(x, oy + h0, oy + h1, w, zs, ze, is_main, false, -1.0, not flush_next)
			last = first
		var sg := first
		while sg:
			sg.side_road = not is_main
			sg = sg.next_flush
		built.append({"p": p, "first": first, "last": last})
		if is_main:
			heads.append(last)
	# Bitişik parçalar (boşluksuz devam) birbirine bağlanır
	for b in built:
		var nxt: Variant = _custom_successor(b.p, pieces)
		if nxt != null:
			for c in built:
				if c.p == nxt:
					b.last.next_flush = c.first
	# Engeller: üstünde durduğu parçaya
	for o in obstacles:
		var kind: String = o.get("kind", "")
		if kind == "bump":
			continue
		var host: Dictionary = {}
		for b in built:
			if _custom_on(o, b.p):
				host = b
				if not b.p.get("side", false):
					break
		if host.is_empty():
			continue
		var wz := zb - float(o.get("z0", 0.0))
		var sg: Segment = host.first
		while sg.next_flush and wz < sg.z_end:
			sg = sg.next_flush
		var ow := clampf(float(o.get("w", 3.0)), 0.8, sg.width)
		var cx := clampf(ox + float(o.get("x", 0.0)), sg.x - sg.width * 0.5 + ow * 0.5, sg.x + sg.width * 0.5 - ow * 0.5)
		var olen := maxf(float(o.get("len", 6.0)), 0.6)
		match kind:
			"gravel":
				_add_gravel(sg, cx - ow * 0.5, cx + ow * 0.5, wz, olen)
			"block":
				_add_block(sg, cx - ow * 0.5, cx + ow * 0.5, wz, clampf(olen, 0.6, 4.0))
			"ramp", "kick":
				var rise := clampf(float(o.get("rise", 1.6)), 0.3, 4.0)
				var kick := 0.0
				var tilt := 0.0
				if kind == "kick":
					# Hedef yana uzaklığı (m) uçuş süresinde alacak yana hız
					var fl := _ramp_flight(v, rise / olen, -rise)
					kick = signf(float(o.get("dir", 1.0))) * float(o.get("dx", 8.0)) / maxf(fl.y, 0.3)
					tilt = 7.0
				_add_ramp(sg, cx, ow, wz, olen, rise, tilt, kick)
			"deadend":
				var end_seg: Segment = host.last
				end_seg.dead_end = true
				_add_block(end_seg, end_seg.x - end_seg.width * 0.5, end_seg.x + end_seg.width * 0.5, end_seg.z_end + 1.4, 1.2)
	# Kristaller: oyunun algoritmasıyla (iniş sırası, pist çizgisi, boşluk yayları)
	if level.get("crystals", true):
		var mains: Array[Dictionary] = []
		for b in built:
			if not b.p.get("side", false):
				mains.append(b)
		var prev_last: Segment = prev
		for b in mains:
			var dz: float = prev_last.z_end - b.first.z_start
			if dz > 4.0 and _rng.randf() < 0.6:
				_gap_crystals(prev_last, b.first.x, b.first.top - prev_last.top_end, dz, v)
			_road_crystals(b.first, v, travelled + float(b.p.get("z0", 0.0)))
			prev_last = b.last
		for b in built:
			if b.p.get("side", false):
				var s: Segment = b.first
				var cxs := s.x
				_crystal_line(s, cxs, s.z_start - 6.0, cxs, s.z_end + 6.0, mini(int((s.z_start - s.z_end) / crystal_spacing), 6))
	for b in built:
		_add_decor(b.first)
	# Çıkış: en uzaktaki ana yol (sonraki kalıp buradan devam eder)
	var head: Segment = heads[0] if not heads.is_empty() else built[-1].last
	for h in heads:
		if h.z_end < head.z_end:
			head = h
	custom_log.append({"name": lname, "zb": zb, "ox": ox, "oy": oy, "entry_z": prev.z_end, "exit_z": head.z_end,
		"travelled": travelled, "mirrored": level.get("mirrored", false), "tags": level.get("tags", [])})
	pattern_counts["özel:" + lname] = int(pattern_counts.get("özel:" + lname, 0)) + 1
	return head


## Engel bu parçanın üstünde mi (tasarım koordinatlarında)
func _custom_on(o: Dictionary, p: Dictionary) -> bool:
	var z0 := float(p.get("z0", 0.0))
	var oz := float(o.get("z0", 0.0))
	return oz >= z0 - 0.5 and oz <= z0 + float(p.get("len", 0.0)) + 0.5 \
		and absf(float(o.get("x", 0.0)) - float(p.get("x", 0.0))) <= float(p.get("w", 8.0)) * 0.5 + 0.5


## Bu parçanın ucunda boşluksuz devam eden parça (aynı yükseklikte, yan yana örtüşen)
func _custom_successor(p: Dictionary, pieces: Array) -> Variant:
	var end := float(p.get("z0", 0.0)) + float(p.get("len", 0.0))
	var h_end := float(p.get("h1", p.get("h0", 0.0)))
	for q in pieces:
		if q == p:
			continue
		if absf(float(q.get("z0", 0.0)) - end) < 0.6 and absf(float(q.get("h0", 0.0)) - h_end) < 0.3 \
				and absf(float(q.get("x", 0.0)) - float(p.get("x", 0.0))) < (float(q.get("w", 8.0)) + float(p.get("w", 8.0))) * 0.5 - 1.0:
			return q
	return null


## Dünya konumunu, kurulmuş son tasarımın koordinatlarına çevirir (test raporu için)
func to_design(pos: Vector3, index := 0) -> Vector2:
	if custom_log.is_empty():
		return Vector2.ZERO
	var c: Dictionary = custom_log[clampi(index, 0, custom_log.size() - 1)]
	var x := pos.x - float(c.ox)
	return Vector2(-x if c.get("mirrored", false) else x, float(c.zb) - pos.z)


## Kalıbın bu oyunda daha önce gelmemiş hali: ilk kez geliyorsa olduğu gibi, yoksa o andaki
## hızda kontrolden geçen yeni bir türev (bulunamazsa olduğu gibi)
func _fresh_variant(level: Dictionary, v: float) -> Dictionary:
	var sig := LevelCheck.signature(level)
	if not _custom_seen.has(sig):
		_custom_seen[sig] = true
		return level
	var res := LevelCheck.vary(level, _rng, _custom_seen, v)
	if res.is_empty():
		return level
	_custom_seen[res.sig] = true
	var lv: Dictionary = res.level
	lv["tags"] = res.tags
	return lv


## Kalıbın sağ ↔ sol aynası (yollar, yatıklık, engeller, eğik rampanın yönü)
static func mirror_level(level: Dictionary) -> Dictionary:
	var m := level.duplicate(true)
	m["mirrored"] = not level.get("mirrored", false)
	for p in m.pieces:
		p["x"] = -float(p.get("x", 0.0))
		if p.has("bank"):
			p["bank"] = -float(p.bank)
	for o in m.obstacles:
		o["x"] = -float(o.get("x", 0.0))
		if o.has("dir"):
			o["dir"] = -float(o.dir)
	return m
