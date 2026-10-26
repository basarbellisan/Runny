class_name CarFx
extends Node3D
## Arabanın efektleri: inişte tekerlerden toz, sert inişte ve yolun
## kenarına sürtünürken alt gövdeden kıvılcım. (Roket alevi yok: gaz arka ışık izini büyütür.) Parçacıklar dünyada kalır
## (araba hızla uzaklaşırken arkada iz bırakır).

var _dust: Array[CPUParticles3D] = []
var _dust_next := 0
var _sparks: CPUParticles3D
var _scrape: CPUParticles3D
var _gravel: CPUParticles3D


func _ready() -> void:
	top_level = true
	for i in 6:
		_dust.append(_make_dust())
	_sparks = _make_sparks(40, true)
	_scrape = _make_sparks(14, false)
	_gravel = _make_dust()
	_gravel.one_shot = false
	_gravel.explosiveness = 0.0
	_gravel.lifetime = 0.5
	_gravel.amount = 20


## Bir noktadan toz bulutu (amount 0..1)
func dust(pos: Vector3, amount := 1.0) -> void:
	var p := _dust[_dust_next]
	_dust_next = (_dust_next + 1) % _dust.size()
	p.global_position = pos
	p.initial_velocity_max = 2.0 + 4.0 * amount
	p.restart()


## Sert iniş: alt gövdeden geriye ve yanlara saçılan kıvılcımlar
func sparks(pos: Vector3, amount := 1.0) -> void:
	_sparks.global_position = pos
	_sparks.restart()


## Gövde yolun kenarına sürtünüyor: sürekli kıvılcım (pos null ise durur)
func scrape(on: bool, pos := Vector3.ZERO) -> void:
	if on:
		_scrape.global_position = pos
	_scrape.emitting = on


## Çakılda giderken tekerlerden sürekli toz
func gravel(on: bool, pos := Vector3.ZERO) -> void:
	if on:
		_gravel.global_position = pos
	_gravel.emitting = on


func _make_dust() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 14
	p.lifetime = 0.7
	p.explosiveness = 0.95
	p.local_coords = false
	p.direction = Vector3(0, 1, 0.6)
	p.spread = 70.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -2.0, 0)
	p.damping_min = 3.0
	p.damping_max = 5.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.4
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.6
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 0.0))
	p.scale_amount_curve = curve
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("d9d5cd")
	mat.roughness = 1.0
	mesh.material = mat
	p.mesh = mesh
	add_child(p)
	return p


func _make_sparks(count: int, burst: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = burst
	p.emitting = false
	p.amount = count
	p.lifetime = 0.45 if burst else 0.3
	p.explosiveness = 0.9 if burst else 0.0
	p.local_coords = false
	p.direction = Vector3(0, 0.5, 1)
	p.spread = 60.0 if burst else 35.0
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 14.0
	p.gravity = Vector3(0, -22.0, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.7, 0.05, 1.2) if burst else Vector3(0.1, 0.05, 0.8)
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.05, 0.4, 0.05)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("ffb36b")
	mesh.material = mat
	p.mesh = mesh
	# Kıvılcımlar hareket yönüne bakar (çizgi gibi)
	p.particle_flag_align_y = true
	add_child(p)
	return p
