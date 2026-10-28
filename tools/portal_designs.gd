extends SceneTree
## Tasarım taslağı: alt katmanda portal tüneli seçenekleri ve kanat izi.
## Oyunun kendi sahnesi (alt katman ışığı, kayalar, kanatlı araba) üstüne kurulur.
## Kullanım: godot --path . --resolution 720x1280 --script res://tools/portal_designs.gd -- --out=/tmp

var _out := "user://"
var _main: Node
var _car: Car
var _cam: Camera3D
var _lower: LowerLayer
var _built: Array[Node] = []
var _ring_mat: StandardMaterial3D
var _glass_mat: StandardMaterial3D
var _trail_mat: StandardMaterial3D
const FLY_Y := -55.0
## Portal halkasının yeri (arabanın önünde)
const P := Vector3(4.0, FLY_Y, -330.0)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	_go.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _go() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await _frames(4)
	_main.set_physics_process(false)
	_main.set_process(false)
	_main.hud.visible = false
	_car = _main.car
	_car.set_physics_process(false)
	_lower = _main.lower
	_cam = _main.get_node("Camera")
	_cam.set_process(false)
	_main._apply_mood(1.0)
	_car._set_wings(true, true)
	if _car.trail:
		_car.trail.visible = false
	_ring_mat = _lower._portal_mat
	_glass_mat = StandardMaterial3D.new()
	_glass_mat.albedo_color = Color(Palette.ACCENT, 0.16)
	_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_mat = StandardMaterial3D.new()
	_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_mat.vertex_color_use_as_albedo = true
	_rocks()
	for v in ["a", "b", "c"]:
		_clear()
		var path := _path(v)
		_build(v, path)
		_main.clouds.position = Vector3(P.x, -42.0, P.z)
		# 1) Oyuncunun gördüğü: portala ~1 sn kala, takip kamerasının açısı
		_place_car(P + Vector3(-1.0, 0.0, 42.0))
		await _shot("%s_1" % v, _car.global_position + Vector3(0, 6, 10), _car.global_position + Vector3(0, -1, -22), 62.0)
		# 2) İçinden: tünelin içinde, yukarı kıvrılırken
		var k := mini(path.size() - 3, int(path.size() * 0.55))
		_place_car(path[k], (path[k + 1] - path[k]).normalized())
		var back := (path[k] - path[k - 2]).normalized()
		await _shot("%s_2" % v, path[k] - back * 11.0 + Vector3(0, 3.0, 0), path[k] + back * 14.0, 68.0)
		# 3) Yandan: tünelin biçimi ve arabanın yolu
		_place_car(P + Vector3(0, 0, 30.0))
		_dots(path)
		await _shot("%s_3" % v, P + Vector3(62.0, 14.0, -38.0), P + Vector3(0, 14.0, -38.0), 62.0)
	# Kanat izi: yedek enerji dolu, yarı, bitmek üzere
	_clear()
	for lvl in [1.0, 0.5, 0.15]:
		_clear()
		_place_car(Vector3(0, FLY_Y, -150.0))
		_wing_trails(lvl)
		await _shot("w_%d" % int(lvl * 100), _car.global_position + Vector3(7, 7, -12), _car.global_position + Vector3(-1.5, 0, 7), 44.0)
	quit()


func _clear() -> void:
	for n in _built:
		if is_instance_valid(n):
			n.queue_free()
	_built.clear()


func _add(n: Node3D) -> Node3D:
	_main.add_child(n)
	_built.append(n)
	return n


func _place_car(p: Vector3, dir := Vector3(0, 0, -1)) -> void:
	_car.global_position = p
	var pitch := atan2(dir.y, -dir.z)
	_car.rotation = Vector3(pitch, 0, 0)


func _shot(name: String, from: Vector3, at: Vector3, fov: float) -> void:
	_cam.fov = fov
	_cam.global_position = from
	_cam.look_at(at)
	await _frames(6)
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/portal_%s.png" % [_out, name])


## Tünelin orta çizgisi (portal halkasından başlar, -z ileri)
func _path(v: String) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var straight := 40.0 if v == "a" else (8.0 if v == "b" else 42.0)
	var radius := 24.0 if v == "a" else 26.0
	var turn := deg_to_rad(55.0)
	var exit_len := 14.0 if v != "c" else 18.0
	var z := 0.0
	while z <= straight:
		pts.append(P + Vector3(0, 0, -z))
		z += 3.0
	var c := P + Vector3(0, radius, -straight)
	var a := 0.0
	while a <= turn:
		pts.append(c + Vector3(0, -radius * cos(a), -radius * sin(a)))
		a += deg_to_rad(6.0)
	var dir := Vector3(0, sin(turn), -cos(turn))
	var last := pts[pts.size() - 1]
	var d := 3.0
	while d <= exit_len:
		pts.append(last + dir * d)
		d += 3.0
	return pts


func _build(v: String, path: PackedVector3Array) -> void:
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		var dir := (b - a).normalized()
		var basis := _basis_y(dir)
		if v != "c":
			# Saydam boru
			var cyl := CylinderMesh.new()
			cyl.top_radius = 4.6
			cyl.bottom_radius = 4.6
			cyl.height = a.distance_to(b) + 0.05
			cyl.radial_segments = 20
			cyl.cap_top = false
			cyl.cap_bottom = false
			var m := MeshInstance3D.new()
			m.mesh = cyl
			m.material_override = _glass_mat
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			m.transform = Transform3D(basis, (a + b) * 0.5)
			_add(m)
		# Halkalar: a/b'de her ~6 m'de ince kaburga, c'de seyrek kalın halkalar
		var every := 2 if v != "c" else 2
		if i % every == 0:
			var t := TorusMesh.new()
			var thick := v == "c" or i == 0
			t.inner_radius = 4.4 if not thick else 4.2
			t.outer_radius = 4.75 if not thick else 5.0
			t.rings = 20
			t.ring_segments = 6
			var r := MeshInstance3D.new()
			r.mesh = t
			r.material_override = _ring_mat
			r.transform = Transform3D(basis, a)
			_add(r)
	# Ağız: girişte dolu disk (mevcut portalın yüzü)
	var disc := CylinderMesh.new()
	disc.top_radius = 4.2
	disc.bottom_radius = 4.2
	disc.height = 0.05
	var dm := MeshInstance3D.new()
	dm.mesh = disc
	dm.material_override = _lower._portal_fill_mat
	dm.transform = Transform3D(_basis_y(Vector3(0, 0, -1)), path[0])
	_add(dm)


## Y ekseni dir'e bakan dönüş
func _basis_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var z := x.cross(y).normalized()
	x = y.cross(z).normalized()
	return Basis(x, y, z)


func _dots(path: PackedVector3Array) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Palette.ENERGY
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var pts := PackedVector3Array(path)
	# Tünelden sonra yola kadar fırlatma yayı
	var last := path[path.size() - 1]
	var dir := (last - path[path.size() - 2]).normalized()
	var vel := dir * 62.0
	for i in 40:
		var t := i * 0.08
		var p := last + Vector3(0, vel.y * t - 0.5 * 28.0 * t * t, vel.z * t)
		if p.y < last.y and t > 0.5:
			break
		pts.append(p)
	for p in pts:
		var s := SphereMesh.new()
		s.radius = 0.5
		s.height = 1.0
		var m := MeshInstance3D.new()
		m.mesh = s
		m.material_override = mat
		m.position = p
		_add(m)


func _rocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var z := -170.0
	while z > -330.0:
		for i in rng.randi_range(1, 3):
			var x := P.x + rng.randf_range(-16.0, 16.0)
			if absf(z - P.z) < 50.0 and absf(x - P.x) < 9.0:
				continue
			_lower._spawn_rock(Vector3(x, FLY_Y + rng.randf_range(-1.0, 1.0), z), rng.randf_range(2.0, 3.6))
		z -= rng.randf_range(24.0, 34.0)


## Kanat uçlarından geriye yeşil iz: uzunluğu yedek enerjiyi gösterir
func _wing_trails(level: float) -> void:
	for side in [-1.0, 1.0]:
		var tip: Vector3 = _car.global_position + Vector3(side * _car.wing_half_span * 0.95, 0.25, 0.6)
		var length := lerpf(4.0, 26.0, level)
		var im := ImmediateMesh.new()
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		var n := 16
		for i in n + 1:
			var t := float(i) / n
			var w := lerpf(0.55, 0.1, t)
			var col := Color(Palette.ENERGY, lerpf(0.95, 0.0, t))
			var z := tip.z + t * length
			im.surface_set_color(col)
			im.surface_add_vertex(Vector3(tip.x - w, tip.y, z))
			im.surface_set_color(col)
			im.surface_add_vertex(Vector3(tip.x + w, tip.y, z))
		im.surface_end()
		var m := MeshInstance3D.new()
		m.mesh = im
		m.material_override = _trail_mat
		_add(m)
	# Gövdenin kendi izi (bugünkü yeşil iz, yer tutucu)
	var body := ImmediateMesh.new()
	body.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var p0: Vector3 = _car.global_position + Vector3(0, 0.3, 1.8)
	for i in 17:
		var t := i / 16.0
		var col := Color(Palette.ENERGY, lerpf(0.7, 0.0, t))
		body.surface_set_color(col)
		body.surface_add_vertex(Vector3(p0.x - 0.9, p0.y, p0.z + t * 14.0))
		body.surface_set_color(col)
		body.surface_add_vertex(Vector3(p0.x + 0.9, p0.y, p0.z + t * 14.0))
	body.surface_end()
	var bm := MeshInstance3D.new()
	bm.mesh = body
	bm.material_override = _trail_mat
	_add(bm)
