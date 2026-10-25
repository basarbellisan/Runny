class_name CarModel
extends Node3D
## Arabanın görünümü: gövde ve dört teker, koddan kurulur.
## variant 1 – Kutu: köşeli İskandinav station wagon, tampon ve çamurluklar
## variant 2 – Gezgin: alçak dar gövde, iri tekerler tamamen dışarıda
## variant 3 – Konsept: uzun alçak gövde, büyük ince tekerler, beyaz jantlar
## variant 4 – Roadster: sivri uzun burun, açık kokpitin üstünde siperlik,
##             arkaya doğru kavisle inen kubbe, iri tekerler dışarıda
##
## Tekerler (wheels) fizik için de kullanılır: her birinin yerdeki
## temas noktası (contact), yarıçapı ve süspansiyon/dönüş düğümleri var.

@export_range(1, 4) var variant := 1:
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
	tire_material.albedo_color = Color("1c1d20")
	match variant:
		1:
			_build_box()
		2:
			_build_rover()
		3:
			_build_concept()
		_:
			_build_roadster()


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


func _build_roadster() -> void:
	var r := 0.5
	# Gövde: önden arkaya kesitler (z, alt yarı genişlik, üst yarı genişlik, alt y, üst y).
	# Üstte pahlı kenarlar: üst yüz dar, yanlar dikey; burun sivrilip alçalır.
	var hull := [
		[-2.05, 0.6, 0.46, 0.36, 0.7],
		[-1.25, 0.64, 0.5, 0.36, 0.8],
		[-0.25, 0.8, 0.64, 0.34, 0.98],
		[1.7, 0.82, 0.66, 0.38, 1.0],
		[1.95, 0.82, 0.66, 0.42, 0.98],
	]
	_hull(hull, paint_material)
	# Kabin: yanları turuncu, tavandan arkaya kavisle gövdeye iner
	_hull([
		[-0.3, 0.66, 0.6, 0.95, 1.41],
		[0.6, 0.67, 0.6, 0.95, 1.44],
		[1.0, 0.69, 0.6, 0.95, 1.36],
		[1.35, 0.71, 0.6, 0.95, 1.2],
		[1.65, 0.72, 0.6, 0.95, 1.02],
	], paint_material)
	# Kokpit açıklığı: kabinin ön yüzünde koyu boşluk (yandan görünmez)
	_box(Vector3(1.08, 0.4, 0.04), Vector3(0, 1.17, -0.32), _glass)
	# Siperlik: açıklığın üstünde öne taşan ince tavan
	_hull([[-0.62, 0.68, 0.64, 1.4, 1.48], [-0.1, 0.68, 0.64, 1.4, 1.5]], paint_material)
	# Ön farlar ve arkada alçak difüzör plakası
	_lights(Vector3(0.26, 0.56, -2.06), Vector3(0.2, 0.12, 0.04))
	_box(Vector3(1.5, 0.06, 0.3), Vector3(0, 0.46, 2.05), paint_material)
	tire_material.albedo_color = Color("4a4c50")
	_wheels(1.02, 1.25, r, 0.46, true, 10)


## Kesitlerden düz yüzlü gövde: her kesit (z, alt yarı genişlik, üst yarı genişlik,
## alt y, üst y). Kesitler arası üst, pah, yan ve alt yüzler; iki uç kapalı.
func _hull(sections: Array, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for sec in sections:
		var z: float = sec[0]
		var wb: float = sec[1]
		var wt: float = sec[2]
		var yb: float = sec[3]
		var yt: float = sec[4]
		var ych := yt - (yt - yb) * 0.22   # pahın başladığı yükseklik
		# Kesit çevresi (soldan saat yönünün tersine): alt sol, pah sol, üst sol, üst sağ, pah sağ, alt sağ
		rings.append([Vector3(-wb, yb, z), Vector3(-wb, ych, z), Vector3(-wt, yt, z),
			Vector3(wt, yt, z), Vector3(wb, ych, z), Vector3(wb, yb, z)])
	var center := Vector3.ZERO
	for ring in rings:
		for p in ring:
			center += p
	center /= rings.size() * 6.0
	for i in rings.size() - 1:
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		for k in 6:
			var k2 := (k + 1) % 6
			_face(st, [a[k], a[k2], b[k2], b[k]], center)
	_face(st, rings[0], center)
	_face(st, rings[rings.size() - 1], center)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)


## Dışbükey çokgen yüz: gövde merkezinden dışarı bakacak sırayla üçgenlere bölünür
func _face(st: SurfaceTool, pts: Array, center: Vector3) -> void:
	var p0: Vector3 = pts[0]
	var mid := Vector3.ZERO
	for p in pts:
		mid += p
	mid /= pts.size()
	for i in range(1, pts.size() - 1):
		var p1: Vector3 = pts[i]
		var p2: Vector3 = pts[i + 1]
		var n := (p1 - p0).cross(p2 - p0)
		if n.length() < 0.000001:
			continue
		var out := mid - center
		# Godot'da ön yüz saat yönünde: normal dışarı bakıyorsa sırayı çevir
		if n.dot(out) > 0.0:
			var t := p1
			p1 = p2
			p2 = t
		else:
			n = -n
		n = n.normalized()
		for p in [p0, p1, p2]:
			st.set_normal(n)
			st.add_vertex(p)


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
func _wheels(track: float, base: float, radius: float, width: float, hubs: bool, hub_segments := 6) -> void:
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
	hub.radial_segments = hub_segments
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
