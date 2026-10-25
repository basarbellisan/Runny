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
var _tail := StandardMaterial3D.new()


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
	_tail.albedo_color = Color("d8322a")
	_tail.emission_enabled = true
	_tail.emission = Color("a01e16")


func _ready() -> void:
	_build()


func _build() -> void:
	for c in get_children():
		c.free()
	wheels.clear()
	half_width = 0.0
	tire_material.albedo_color = Color("1c1d20")
	paint_material.albedo_color = Palette.ACCENT
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
	paint_material.albedo_color = Color("ff6f2e")
	tire_material.albedo_color = Color("4d4f53")
	# Gövde + burun tek parça: üst çizgi sivri burundan kabine düz bir rampa gibi yükselir,
	# alt çizgi düz ve yerden yüksek. Yanlar dik, üst kenarlar pahlı.
	_hull([
		[-2.4, 0.48, 0.36, 0.38, 0.6],
		[-1.35, 0.6, 0.46, 0.4, 0.78],
		[-0.1, 0.74, 0.6, 0.42, 1.0],
		[1.6, 0.76, 0.62, 0.42, 1.0],
		[2.02, 0.74, 0.6, 0.44, 0.82],
	], paint_material, 0.28)
	# Kabin: ön yüzü (pencere) geriye yatık, tavanı düz, arkası büyük bir kavisle arka uca iner
	var cabin := [
		[-0.1, 0.72, 0.6, 0.98, 1.02],
		[0.04, 0.72, 0.6, 0.98, 1.56],
		[0.7, 0.72, 0.6, 0.98, 1.6],
		[1.15, 0.72, 0.58, 0.98, 1.57],
		[1.5, 0.72, 0.54, 0.98, 1.44],
		[1.75, 0.72, 0.5, 0.98, 1.22],
		[1.93, 0.72, 0.47, 0.98, 1.0],
		[2.02, 0.72, 0.46, 0.84, 0.86],
	]
	_hull(cabin, paint_material, 0.34)
	# Siperlik: pencerenin üstünde öne taşan ince tavan
	_hull([[-0.38, 0.71, 0.69, 1.55, 1.62], [0.72, 0.71, 0.69, 1.58, 1.65]], paint_material, 0.0)
	# Ön pencere: yatık ön yüzde koyu yamuk (kabin yüzünün biraz önünde)
	var n_front := Vector3(0, 0.25, -1.0).normalized()
	_panel([Vector3(-0.58, 1.06, -0.1), Vector3(0.58, 1.06, -0.1), Vector3(0.54, 1.52, 0.02),
		Vector3(-0.54, 1.52, 0.02)], n_front, _glass)
	# Arka cam: kubbenin sırtında, kavisi izleyerek
	var top_at := func(z: float) -> float:
		for i in range(1, cabin.size()):
			if z <= cabin[i][0]:
				var t := inverse_lerp(float(cabin[i - 1][0]), float(cabin[i][0]), z)
				return lerpf(float(cabin[i - 1][4]), float(cabin[i][4]), t) + 0.015
		return float(cabin[cabin.size() - 1][4])
	var rows := [[1.25, 0.42], [1.5, 0.39], [1.72, 0.34]]
	for i in rows.size() - 1:
		var z0: float = rows[i][0]
		var z1: float = rows[i + 1][0]
		var w0: float = rows[i][1]
		var w1: float = rows[i + 1][1]
		_panel([Vector3(-w0, top_at.call(z0), z0), Vector3(w0, top_at.call(z0), z0),
			Vector3(w1, top_at.call(z1), z1), Vector3(-w1, top_at.call(z1), z1)],
			Vector3(0, 0.7, 0.7).normalized(), _glass)
	# Arka yüz: iki stop lambası; altta dışa taşan ince plaka
	for sx in [-1.0, 1.0]:
		_panel([Vector3(sx * 0.3, 0.58, 2.03), Vector3(sx * 0.6, 0.58, 2.03), Vector3(sx * 0.6, 0.7, 2.03),
			Vector3(sx * 0.3, 0.7, 2.03)], Vector3.BACK, _tail)
	_box(Vector3(1.8, 0.05, 0.3), Vector3(0, 0.45, 2.1), dark_material)
	# Ön farlar: sivri burnun ön yüzünde iki küçük beyaz dörtgen
	for sx in [-1.0, 1.0]:
		_panel([Vector3(sx * 0.08, 0.44, -2.41), Vector3(sx * 0.3, 0.44, -2.41), Vector3(sx * 0.28, 0.53, -2.41),
			Vector3(sx * 0.1, 0.53, -2.41)], Vector3.FORWARD, _light)
	_wheels(1.04, 1.32, 0.57, 0.52, true, 10, 0.6)


## Düz panel (pencere, lamba): verilen yöne bakan dışbükey çokgen
func _panel(pts: Array, normal: Vector3, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mid := Vector3.ZERO
	for p in pts:
		mid += p
	mid /= pts.size()
	_face(st, pts, mid - normal)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)


## Kesitlerden düz yüzlü gövde: her kesit (z, alt yarı genişlik, üst yarı genişlik,
## alt y, üst y). Kesitler arası üst, pah, yan ve alt yüzler; iki uç kapalı.
func _hull(sections: Array, mat: Material, chamfer := 0.22) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for sec in sections:
		var z: float = sec[0]
		var wb: float = sec[1]
		var wt: float = sec[2]
		var yb: float = sec[3]
		var yt: float = sec[4]
		var ych := yt - (yt - yb) * chamfer   # pahın başladığı yükseklik
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
func _wheels(track: float, base: float, radius: float, width: float, hubs: bool, hub_segments := 6, hub_ratio := 0.5) -> void:
	var tire := CylinderMesh.new()
	tire.top_radius = radius
	tire.bottom_radius = radius
	tire.height = width
	tire.radial_segments = 10
	tire.rings = 0
	var hub := CylinderMesh.new()
	hub.top_radius = radius * hub_ratio
	hub.bottom_radius = radius * hub_ratio
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
