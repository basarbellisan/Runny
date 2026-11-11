class_name GiantField
extends Node3D
## Düz dünya denemesi: uzakta duran devasa devler (models/giants/giant.glb, tools/blender/giant.py),
## eski dev blokların yerine. Bloklar gibi dünyada sabit dururlar: doğdukları yerde kalırlar, yola,
## arabanın yüksekliğine ya da zıplamaya bağlı değiller; ekrandaki hareketleri yalnız bakış açısından
## (uzaktaki dağ gibi, çok uzakta oldukları için ağır ağır). Seyrek (yol boyunca 450-750 m'de bir) ve
## hafif bize dönük. Çok uzaktan sisin yerine yavaşça belirirler; aşağı (uçuşa) inerken solarlar.

const GIANT_SCENE := preload("res://models/giants/giant.glb")
## Modelin boyu (m)
const MODEL_HEIGHT := 10.0
## Devin boyu (m): devasa
const HEIGHT := Vector2(170.0, 260.0)
## Yolun ortasından (doğduğu andaki araba hizasından) yana uzaklık (m)
const SIDE := Vector2(220.0, 340.0)
## Arabanın bu kadar önünde doğar (m); bu kadar arkada kalınca kaldırılır
const AHEAD := 620.0
const BEHIND := 300.0
## İki dev arası yol boyu (m)
const GAP := Vector2(450.0, 750.0)
## Yola doğru dönüklük (derece)
const TURN := 14.0
## Tabanın, devin boyuna göre ana yol seviyesinin ne kadar altında olduğu (sisin içinden yükselir)
const SINK := 0.5
## Uzaktan beliriş: bu uzaklıkta görünmez, şu uzaklıkta tam (m; kamera 900 m'ye kadar çizer)
const FADE := Vector2(880.0, 640.0)
## İnişte solma: son yolun bu kadar altından uçuş yüksekliğinin tırmanma payının üstüne kadar
const DROP_START := 2.0

var car: Car
var _rng := RandomNumberGenerator.new()
var _giants: Array[Node3D] = []
var _next_z := INF
var _mats: Dictionary = {}


func setup(p_car: Car, color: Color, seed_value := -1) -> void:
	car = p_car
	if seed_value >= 0:
		_rng.seed = seed_value * 31 + 7
	else:
		_rng.randomize()
	_next_z = car.global_position.z - 250.0
	# Gövde (Main) renk, oluk ve üçgenler (Accent) bir ton açık, göz yarıkları (Slot) koyu; düz renk.
	# Sis yerine uzaklıkla belirir (sise erirse bu uzaklıkta hiç görünmez); inişte birlikte solar
	for pair in [["Main", color], ["Accent", color.lightened(0.22)], ["Slot", color.darkened(0.55)]]:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = pair[1]
		m.disable_fog = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
		m.distance_fade_min_distance = FADE.x
		m.distance_fade_max_distance = FADE.y
		_mats[pair[0]] = m


func _spawn(z: float) -> void:
	var g: Node3D = GIANT_SCENE.instantiate()
	for mi in g.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			var nm := src.resource_name if src else "Main"
			(mi as MeshInstance3D).set_surface_override_material(i, _mats.get(nm, _mats.Main))
	var side := -1.0 if _rng.randf() < 0.5 else 1.0
	var h := _rng.randf_range(HEIGHT.x, HEIGHT.y)
	g.scale = Vector3.ONE * h / MODEL_HEIGHT
	g.rotation.y = -side * deg_to_rad(TURN)
	add_child(g)
	# Dünyada sabit: bir kez yerleşir, sonra hiç oynamaz
	g.global_position = Vector3(car.global_position.x + side * _rng.randf_range(SIDE.x, SIDE.y),
		RoadGenerator.MAIN_LEVEL - h * SINK, z)
	_giants.append(g)


func _process(_delta: float) -> void:
	if car == null:
		return
	var cz := car.global_position.z
	# Yol boyunca seyrek: sıradaki yer arabanın AHEAD önüne girince doğar
	while cz - AHEAD < _next_z:
		_spawn(_next_z)
		_next_z -= _rng.randf_range(GAP.x, GAP.y)
	for i in range(_giants.size() - 1, -1, -1):
		if _giants[i].global_position.z > cz + BEHIND:
			_giants[i].queue_free()
			_giants.remove_at(i)
	# İnişte solma (arka plan katmanlarıyla aynı ilerleme)
	var t := clampf(inverse_lerp(car.last_floor_y - DROP_START, car.flight_altitude + car.climb_height,
		car.global_position.y), 0.0, 1.0)
	var alpha := (1.0 - t) * (1.0 - t)
	for m: StandardMaterial3D in _mats.values():
		m.albedo_color.a = alpha
	visible = alpha > 0.01
