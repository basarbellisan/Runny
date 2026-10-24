class_name CarModel
extends Node3D
## Arabanın görünümü: gövde ve dört teker, koddan kurulur.
## variant 1 – Kutu: köşeli İskandinav station wagon, tampon ve çamurluklar
## variant 2 – Gezgin: alçak dar gövde, iri tekerler tamamen dışarıda
## variant 3 – Konsept: uzun alçak gövde, büyük ince tekerler, beyaz jantlar
##
## Tekerler (wheels) fizik için de kullanılır: her birinin yerdeki
## temas noktası (contact), yarıçapı ve süspansiyon/dönüş düğümleri var.

@export_range(1, 3) var variant := 1:
	set(v):
		variant = v
		if is_node_ready():
			_build()

## Her teker: { contact: Vector3 (yerel, y=0), radius, front, mount, steer, spin }
var wheels: Array[Dictionary] = []
## Gövde ve tekerlerin yandan en dış noktası (duvar kontrolü için)
var half_width := 1.0
var paint_material: StandardMaterial3D
var dark_material: StandardMaterial3D
var tire_material: StandardMaterial3D

var _glass := StandardMaterial3D.new()
var _hub := StandardMaterial3D.new()
var _light := StandardMaterial3D.new()


func _init() -> void:
	paint_material = StandardMaterial3D.new()
	paint_material.albedo_color = Palette.ACCENT
	paint_material.roughness = 0.55
	dark_material = StandardMaterial3D.new()
	dark_material.albedo_color = Color("2a2c30")
	dark_material.roughness = 0.9
	tire_material = StandardMaterial3D.new()
	tire_material.albedo_color = Color("1c1d20")
	tire_material.roughness = 1.0
	_glass.albedo_color = Color("232529")
	_glass.roughness = 0.25
	_hub.albedo_color = Palette.SNOW
	_hub.roughness = 0.6
	_light.albedo_color = Color.WHITE
	_light.emission_enabled = true
	_light.emission = Color.WHITE


func _ready() -> void:
	_build()


func _build() -> void:
	for c in get_children():
		c.free()
	wheels.clear()
	half_width = 0.0
	match variant:
		1:
			_build_box()
		2:
			_build_rover()
		_:
			_build_concept()


func _build_box() -> void:
	var r := 0.44
	_box(Vector3(1.72, 0.52, 3.7), Vector3(0, 0.62, 0), paint_material)
	_box(Vector3(1.5, 0.5, 2.0), Vector3(0, 1.12, 0.45), _glass)           # kabin
	_box(Vector3(1.56, 0.06, 2.04), Vector3(0, 1.4, 0.45), paint_material)  # tavan
	_box(Vector3(1.8, 0.18, 0.16), Vector3(0, 0.46, -1.9), dark_material)   # ön tampon
	_box(Vector3(1.8, 0.18, 0.16), Vector3(0, 0.46, 1.9), dark_material)    # arka tampon
	for z in [-1.22, 1.22]:
		for x in [-0.9, 0.9]:
			_box(Vector3(0.24, 0.12, 1.1), Vector3(x, 0.92, z), dark_material)  # çamurluk
	_lights(Vector3(0.5, 0.68, -1.86), Vector3(0.38, 0.14, 0.04))
	_wheels(0.94, 1.22, r, 0.34, false)


func _build_rover() -> void:
	var r := 0.56
	_box(Vector3(1.24, 0.46, 3.1), Vector3(0, 0.74, 0), paint_material)
	_box(Vector3(1.1, 0.44, 1.3), Vector3(0, 1.18, -0.15), _glass)
	_box(Vector3(1.16, 0.06, 1.34), Vector3(0, 1.43, -0.15), paint_material)
	# Taşıyıcı kol ve koruma çerçevesi
	_box(Vector3(2.1, 0.12, 0.14), Vector3(0, 0.62, -1.25), dark_material)
	_box(Vector3(2.1, 0.12, 0.14), Vector3(0, 0.62, 1.25), dark_material)
	_box(Vector3(1.3, 0.1, 0.1), Vector3(0, 1.5, 0.75), dark_material)
	for x in [-0.6, 0.6]:
		_box(Vector3(0.1, 0.7, 0.1), Vector3(x, 1.15, 0.75), dark_material)
	_lights(Vector3(0.36, 0.82, -1.56), Vector3(0.3, 0.14, 0.04))
	_wheels(1.06, 1.25, r, 0.42, true)


func _build_concept() -> void:
	var r := 0.52
	_box(Vector3(1.58, 0.36, 3.9), Vector3(0, 0.6, 0), paint_material)
	_box(Vector3(1.2, 0.3, 1.7), Vector3(0, 0.93, 0.25), _glass)
	_box(Vector3(1.6, 0.05, 0.5), Vector3(0, 0.82, 1.75), dark_material)    # arka kanatçık
	_box(Vector3(1.4, 0.06, 0.04), Vector3(0, 0.62, -1.96), _light)          # ön ışık şeridi
	_wheels(0.96, 1.3, r, 0.24, true)


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _lights(pos: Vector3, size: Vector3) -> void:
	for sx in [-1.0, 1.0]:
		_box(size, Vector3(pos.x * sx, pos.y, pos.z), _light)


## Dört teker: mount (süspansiyonla iner/kalkar) > steer (ön tekerde döner) > spin
func _wheels(track: float, base: float, radius: float, width: float, hubs: bool) -> void:
	var tire := CylinderMesh.new()
	tire.top_radius = radius
	tire.bottom_radius = radius
	tire.height = width
	tire.radial_segments = 10
	tire.rings = 0
	var hub := CylinderMesh.new()
	hub.top_radius = radius * 0.5
	hub.bottom_radius = radius * 0.5
	hub.height = width + 0.02
	hub.radial_segments = 6
	hub.rings = 0
	half_width = maxf(half_width, track + width * 0.5)
	for z in [-base, base]:
		for x in [-track, track]:
			var mount := Node3D.new()
			mount.position = Vector3(x, radius, z)
			add_child(mount)
			var steer := Node3D.new()
			mount.add_child(steer)
			var spin := Node3D.new()
			steer.add_child(spin)
			var mi := MeshInstance3D.new()
			mi.mesh = tire
			mi.material_override = tire_material
			mi.rotation.z = PI * 0.5
			spin.add_child(mi)
			var h := MeshInstance3D.new()
			h.mesh = hub
			h.material_override = _hub if hubs else dark_material
			h.rotation.z = PI * 0.5
			spin.add_child(h)
			wheels.append({"contact": Vector3(x, 0, z), "radius": radius, "front": z < 0,
				"mount": mount, "steer": steer, "spin": spin})
