class_name CarTrail
extends Node3D
## Arabanın arkasından çıkan iz: hızı ve gazı görünür kılar.
## İz dünyada geride kalır; gaz arttıkça ömrü (dolayısıyla boyu) uzar.
##  style 1 – ışık izi: arka lambalardan iki ince şerit (kristallerin yeşili)
##  style 2 – egzoz küpleri: küçülerek kaybolan low poly küpler
##  style 3 – rüzgâr izi: yolun üstünde geniş, yarı saydam beyaz iz
## Ayrıca kanat yedeği yanarken kanat uçlarından iki yeşil iz: yedek azaldıkça kısalır.

@export_range(1, 3) var style := 1:
	set(v):
		style = v
		_apply_style()
## Gazsızken ve tam gazdayken izin ömrü (sn)
@export var min_life := 0.1
@export var max_life := 0.25
## Tam gazda ışık izinin genişlik katı (boyunca eşit: uca doğru incelmez)
@export var boost_width := 3.2

const MAX_CUBES := 220

var car: Car
var _ribbons: Array[Dictionary] = []
var _cubes: MultiMeshInstance3D
var _particles: Array[Dictionary] = []
var _emit_acc := 0.0
var _time := 0.0
var _side := 1.0


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	global_transform = Transform3D.IDENTITY
	car = get_parent()
	var light := Color(Palette.ENERGY, 0.95)
	for x in [-0.55, 0.55]:
		_ribbons.append(_make_ribbon(1, Vector3(x, 0.55, 1.75), 0.16, light))
	_ribbons.append(_make_ribbon(3, Vector3(0, 0.06, 1.5), 1.7, Color(Palette.SNOW, 0.5)))
	for side in [-1.0, 1.0]:
		var w := _make_ribbon(0, Vector3(side * car.wing_half_span * 0.95, 0.3, 0.6), 0.45, light)
		w.wing = true
		_ribbons.append(w)
	_cubes = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = MAX_CUBES
	mm.visible_instance_count = 0
	_cubes.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 1.0
	_cubes.material_override = mat
	_cubes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cubes)
	_apply_style()


## Şu an izin ömrü: gazla uzar
func life() -> float:
	return lerpf(min_life, max_life, car.boost_level)


## Kanat izinin ömrü: kalan yedekle kısalır
func wing_life() -> float:
	return lerpf(0.12, 0.9, clampf(car.reserve / car.reserve_max, 0.0, 1.0))


func _physics_process(delta: float) -> void:
	_time += delta
	var emitting := car.alive
	var l := life()
	for r in _ribbons:
		if r.get("wing", false):
			var wl := wing_life()
			if emitting and car.reserve_on:
				var wp: Vector3 = car.global_position + r.offset
				if r.points.is_empty() or r.points[-1].p.distance_to(wp) > 0.25:
					r.points.append({"p": wp, "t": _time})
			while not r.points.is_empty() and _time - r.points[0].t > wl:
				r.points.pop_front()
			continue
		if r.style != style:
			continue
		var pts: Array = r.points
		if emitting:
			var p: Vector3 = car.global_position + r.offset
			if pts.is_empty() or pts[-1].p.distance_to(p) > 0.25:
				pts.append({"p": p, "t": _time})
		while not pts.is_empty() and _time - pts[0].t > l:
			pts.pop_front()
	if style == 2:
		_update_cubes(delta, emitting, l)


func _process(_delta: float) -> void:
	var head := car.get_global_transform_interpolated().origin
	for r in _ribbons:
		if r.get("wing", false):
			_draw_ribbon(r, head + r.offset if car.alive and car.reserve_on else Vector3.INF)
		elif r.style == style:
			_draw_ribbon(r, head + r.offset if car.alive else Vector3.INF)


func _make_ribbon(for_style: int, offset: Vector3, width: float, color: Color) -> Dictionary:
	var mi := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return {"style": for_style, "offset": offset, "width": width, "color": color,
		"points": [], "mesh": mesh, "node": mi}


## Yassı şerit: en yeni nokta arabada, eskiler saydamlaşarak incelir
func _draw_ribbon(r: Dictionary, head: Vector3) -> void:
	var mesh: ImmediateMesh = r.mesh
	mesh.clear_surfaces()
	var pts: Array = []
	for q in r.points:
		pts.append(q)
	if head != Vector3.INF:
		pts.append({"p": head, "t": _time})
	if pts.size() < 2:
		return
	var wing: bool = r.get("wing", false)
	var l := maxf(wing_life() if wing else life(), 0.01)
	var color: Color = r.color
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in pts.size():
		var a: Vector3 = pts[maxi(i - 1, 0)].p
		var b: Vector3 = pts[mini(i + 1, pts.size() - 1)].p
		var dir := (b - a)
		dir.y = 0.0
		var side := dir.normalized().cross(Vector3.UP) if dir.length_squared() > 1e-6 else Vector3.RIGHT
		var k := clampf(1.0 - (_time - pts[i].t) / l, 0.0, 1.0)
		# Gazda iz genişler ve boyunca eşit kalır; sönük ucu yalnız saydamlaşır
		var bl := car.boost_level if r.style == 1 and not wing else 0.0
		var half: float = r.width * 0.5 * lerpf(1.0, boost_width, bl) * lerpf(0.35 + 0.65 * k, 1.0, bl)
		var alpha := color.a * lerpf(k * k, sqrt(k), bl)
		mesh.surface_set_color(Color(color, alpha))
		mesh.surface_add_vertex(pts[i].p - side * half)
		mesh.surface_set_color(Color(color, alpha))
		mesh.surface_add_vertex(pts[i].p + side * half)
	mesh.surface_end()


func _update_cubes(delta: float, emitting: bool, l: float) -> void:
	var boost := car.boost_level
	if emitting:
		_emit_acc += delta * (18.0 + 70.0 * boost)
		while _emit_acc >= 1.0:
			_emit_acc -= 1.0
			_side = -_side
			_particles.append({
				"p": car.global_position + Vector3(0.45 * _side, 0.3, 1.85),
				"v": Vector3(randf_range(-0.8, 0.8), randf_range(0.2, 1.2), randf_range(1.0, 3.0)),
				"age": 0.0, "life": l * randf_range(1.0, 1.6),
				"size": randf_range(0.16, 0.3), "spin": randf_range(-6.0, 6.0),
				"color": Palette.SNOW.lerp(Palette.ENERGY, boost),
			})
	var mm := _cubes.multimesh
	var alive_particles: Array[Dictionary] = []
	for q in _particles:
		q.age += delta
		if q.age < q.life:
			q.p += q.v * delta
			alive_particles.append(q)
	_particles = alive_particles.slice(maxi(0, alive_particles.size() - MAX_CUBES))
	for i in _particles.size():
		var q := _particles[i]
		var k: float = 1.0 - q.age / q.life
		var s: float = q.size * (0.3 + 0.7 * k)
		var basis := Basis(Vector3(0.3, 1, 0.2).normalized(), q.spin * q.age).scaled(Vector3.ONE * s)
		mm.set_instance_transform(i, Transform3D(basis, q.p))
		mm.set_instance_color(i, Color(q.color, 0.9 * k))
	mm.visible_instance_count = _particles.size()


func _apply_style() -> void:
	if not is_node_ready():
		return
	for r in _ribbons:
		if r.get("wing", false):
			continue
		r.node.visible = r.style == style
		if r.style != style:
			r.points.clear()
			(r.mesh as ImmediateMesh).clear_surfaces()
	_cubes.visible = style == 2
	if style != 2:
		_particles.clear()
		_cubes.multimesh.visible_instance_count = 0
