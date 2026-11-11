class_name GiantField
extends Node3D
## Düz dünya denemesi: boşlukta duran devler (models/giants/giant.glb, tools/blender/giant.py).
## Yoldan ve arabadan tamamen bağımsız: doğduğu anda yeri (yan ve yükseklik) sabitlenir; yol kayınca,
## inip çıkınca, araba zıplayınca ya da sağa sola gidince oynamaz. Uzakta, seyrek (aynı anda en çok
## iki) ve hafif bize dönük; arabanın hızından bağımsız, ağır ağır yaklaşıp yanımızdan geçer.
## Aşağı (uçuşa) inerken arka plan gibi solarak kaybolur.

const GIANT_SCENE := preload("res://models/giants/giant.glb")
## Modelin boyu (m)
const MODEL_HEIGHT := 10.0
## Devin boyu (m) aralığı
const HEIGHT := Vector2(80.0, 120.0)
## Yana uzaklık (m) aralığı
const SIDE := Vector2(150.0, 210.0)
## Doğduğu yer: arabanın bu kadar önünde (m); bu kadar arkada kalınca kaldırılır
const AHEAD := 520.0
const BEHIND := 120.0
## Arabaya göre yaklaşma hızı (m/sn): arabanın hızından bağımsız, ağır
const PASS_SPEED := 9.0
## İki dev arasında geçen süre (sn) aralığı ve aynı anda en çok kaç dev
const GAP := Vector2(16.0, 30.0)
const MAX_ALIVE := 2
## Yola doğru dönüklük (derece)
const TURN := 14.0
## Tabanın, devin boyuna göre ana yol seviyesinin ne kadar altında olduğu (sisin içinden yükselir)
const SINK := 0.55
## İnişte solma: son yolun bu kadar altından uçuş yüksekliğinin tırmanma payının üstüne kadar
const DROP_START := 2.0

var car: Car
var _rng := RandomNumberGenerator.new()
var _giants: Array = []   # [{node, ahead (m), side, lateral, height}]
var _timer := 3.0
var _mats: Dictionary = {}


func setup(p_car: Car, color: Color, seed_value := -1) -> void:
	car = p_car
	if seed_value >= 0:
		_rng.seed = seed_value * 31 + 7
	else:
		_rng.randomize()
	# Gövde (Main) renk, oluk ve üçgenler (Accent) bir ton açık, göz yarıkları (Slot) koyu; düz renk,
	# sise erimez (uzakta net siluet); inişte birlikte solar
	for pair in [["Main", color], ["Accent", color.lightened(0.22)], ["Slot", color.darkened(0.55)]]:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = pair[1]
		m.disable_fog = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		_mats[pair[0]] = m


func _spawn() -> void:
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
	# Yan ve yükseklik doğduğu anda sabitlenir (sonra yola ve arabaya bağlı değil)
	var x := car.global_position.x + side * _rng.randf_range(SIDE.x, SIDE.y)
	var y := RoadGenerator.MAIN_LEVEL - h * SINK
	_giants.append({"node": g, "ahead": AHEAD, "x": x, "y": y})


func _process(delta: float) -> void:
	if car == null:
		return
	# İnişte solma (arka plan katmanlarıyla aynı ilerleme)
	var t := clampf(inverse_lerp(car.last_floor_y - DROP_START, car.flight_altitude + car.climb_height,
		car.global_position.y), 0.0, 1.0)
	var alpha := (1.0 - t) * (1.0 - t)
	for m: StandardMaterial3D in _mats.values():
		m.albedo_color.a = alpha
	visible = alpha > 0.01
	# Yeni dev: seyrek, yalnız yolda giderken
	_timer -= delta
	if _timer <= 0.0 and car.mode == Car.Mode.DRIVE:
		_timer = _rng.randf_range(GAP.x, GAP.y)
		if _giants.size() < MAX_ALIVE:
			_spawn()
	var cz := car.global_position.z
	for i in range(_giants.size() - 1, -1, -1):
		var d: Dictionary = _giants[i]
		d.ahead -= PASS_SPEED * delta
		if d.ahead < -BEHIND:
			(d.node as Node3D).queue_free()
			_giants.remove_at(i)
			continue
		(d.node as Node3D).global_position = Vector3(d.x, d.y, cz - d.ahead)
