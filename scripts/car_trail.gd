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


## Arka lamba izi gövdenin arka yüzünün bu kadar gerisinden (m) başlar, bu boyda (m) yumuşakça belirir
const REAR_GAP := 0.03
## Kökteki parlak, doygun bölümün boyu (m)
const REAR_HOT := 0.6

## Kanat izi: genişlik (m); kanadın gerisinde bu mesafeler (m) arasında solar. Kamera uçağın
## hemen arkasında: uzun iz kameranın yanından geçerken perspektifle ekranın kenarlarına açılıp
## kanadın ötesine taşmış gibi görünür. Kısa ve uca yakın kalınca kanadın arkasında bir çizgi olur.
const WING_TRAIL_W := 0.24
const WING_FADE_FROM := 2.4
const WING_FADE_TO := 4.4
## İz kanada değmez: kanat ucunun bu kadar gerisinde (m) yumuşakça belirir
const WING_GAP := Vector2(1.1, 1.6)
## Uçarken iki parmak (yükselme): iz arabadaki gibi uzar ve genişler (sönme mesafeleri, genişlik katı)
const WING_CLIMB_FADE := Vector2(5.5, 9.5)
const WING_CLIMB_WIDTH := 1.5
## Yükselme etkisi (0..1): basınca ~0.35 sn'de dolar, bırakınca ~0.5 sn'de söner
var _wing_boost := 0.0
## Kanat izinin görünürlüğü (0..1), kökteki parıltı bununla açılıp kapanır
var _wing_vis := 0.0
## Kanat izinin kök tasarımı (motordan çıkan enerji): 0 eski (uzakta, eriyerek başlar),
## 1 parlak çekirdek + yuvarlak parıltı, 2 alev dili (uzun parlak kök), 3 ince çekirdek + geniş hale,
## 4 eskisi gibi ama kanada değmesine ramak kala başlar, başlangıcı hafif yumuşak (parıltı yok)
@export_range(0, 4) var wing_style := 4
## [boşluk başı, boşluk sonu (m), içeri kayma (m), parlak kök boyu (m), parıltı boyu (m), parıltı biçimi]
const WING_STYLES := [
	[1.1, 1.6, 0.0, 0.0, 0.0, 0],
	[0.25, 0.4, 0.3, 0.9, 0.9, 0],
	[0.05, 0.15, 0.4, 1.8, 0.7, 1],
	[0.2, 0.35, 0.3, 1.2, 1.3, 0],
	[0.1, 0.45, 0.0, 0.0, 0.0, 0],
]
var _wing_glow: Array[MeshInstance3D] = []
var _wing_halo_ribbons: Array[Dictionary] = []


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	global_transform = Transform3D.IDENTITY
	car = get_parent()
	var light := Color(Palette.ENERGY, 0.95)
	for x in [-0.55, 0.55]:
		var lt := _make_ribbon(1, Vector3(x, 0.55, 1.75), 0.16, light)
		lt.lx = x
		lt.body = true  # arka lambalara bağlı: gövdeyle yatar ve döner (Car.body_point)
		_ribbons.append(lt)
	_ribbons.append(_make_ribbon(3, Vector3(0, 0.06, 1.5), 1.7, Color(Palette.SNOW, 0.5)))
	for side in [-1.0, 1.0]:
		var w := _make_ribbon(0, Vector3.ZERO, WING_TRAIL_W, light)
		w.wing = true
		w.side = side  # iz kanadın ucundan çıkar (Car.wing_tip)
		_ribbons.append(w)
		# Kökte parıltı (motorun yandığı yer): kameraya bakan, eklemeli yumuşak leke
		var g := MeshInstance3D.new()
		var q := QuadMesh.new()
		g.mesh = q
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		gm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		gm.no_depth_test = false
		gm.albedo_texture = _radial_tex()
		g.material_override = gm
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.visible = false
		add_child(g)
		_wing_glow.append(g)
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
	if not car.reserve_on:
		return 0.9  # enerjiyle boost: tam uzunluk
	return lerpf(0.12, 0.9, clampf(car.reserve / car.reserve_max, 0.0, 1.0))


## Arka lamba izinin gövdeye göre çıkış noktası: modelin arka yüzünün hemen gerisi
func _rear_offset(r: Dictionary) -> Vector3:
	var y := 0.55
	# Gövdenin bu x'teki en arka noktası, iz yüksekliğinin altında ve üstünde (alt kısmı daha geride
	# olan arabalarda iz gövdenin üstünde kalıp içinden çıkıyormuş gibi görünmesin)
	var z := -INF
	for yy in [0.2, 0.35, 0.55, 0.75, 0.9]:
		z = maxf(z, car.rear_z(float(r.lx), yy))
	return Vector3(float(r.lx), y, z + REAR_GAP)


## Yumuşak yuvarlak parıltı dokusu (ortası beyaz, kenara doğru saydam)
static func _radial_tex() -> GradientTexture2D:
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	gr.add_point(0.25, Color(1, 1, 1, 0.75))
	gr.add_point(0.55, Color(1, 1, 1, 0.22))
	var t := GradientTexture2D.new()
	t.gradient = gr
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


## Kanat izi ne zaman çıkar: uçarken boost (iki parmak) ya da kanat yedeği açıkken
func _wing_trail_on() -> bool:
	return car.reserve_on or car.climbing


func _physics_process(delta: float) -> void:
	_time += delta
	var climbing := car.climbing
	_wing_boost = move_toward(_wing_boost, 1.0 if climbing else 0.0, delta / (0.35 if climbing else 0.5))
	var on := car.alive and _wing_trail_on()
	_wing_vis = move_toward(_wing_vis, 1.0 if on else 0.0, delta / (0.12 if on else 0.3))
	var emitting := car.alive
	var l := life()
	for r in _ribbons:
		if r.get("wing", false):
			var wl := wing_life()
			if emitting and _wing_trail_on():
				var wp: Vector3 = car.wing_tip(r.side)
				if r.points.is_empty() or r.points[-1].p.distance_to(wp) > 0.25:
					r.points.append({"p": wp, "t": _time})
			while not r.points.is_empty() and _time - r.points[0].t > wl:
				r.points.pop_front()
			continue
		if r.style != style:
			continue
		var pts: Array = r.points
		if emitting:
			var p: Vector3 = car.body_point(_rear_offset(r)) if r.get("body", false) else car.global_position + r.offset
			if pts.is_empty() or pts[-1].p.distance_to(p) > 0.25:
				pts.append({"p": p, "t": _time})
		while not pts.is_empty() and _time - pts[0].t > l:
			pts.pop_front()
	if style == 2:
		_update_cubes(delta, emitting, l)


func _process(_delta: float) -> void:
	var head := car.get_global_transform_interpolated().origin
	_place_wing_glow()
	for r in _ribbons:
		if r.get("wing", false):
			_draw_ribbon(r, car.wing_tip(r.side, true) if car.alive and _wing_trail_on() else Vector3.INF)
		elif r.style == style:
			var hp: Vector3 = car.body_point(_rear_offset(r), true) if r.get("body", false) else head + r.offset
			_draw_ribbon(r, hp if car.alive else Vector3.INF)


## Kökteki parıltı: kanat ucunun gerisinde, iz başladığı yerde; boostta büyür ve hafifçe titrer
func _place_wing_glow() -> void:
	var ws: Array = WING_STYLES[clampi(wing_style, 0, WING_STYLES.size() - 1)]
	for i in _wing_glow.size():
		var g := _wing_glow[i]
		var size: float = ws[4]
		if size <= 0.0 or _wing_vis <= 0.01 or not car.alive:
			g.visible = false
			continue
		var side := -1.0 if i == 0 else 1.0
		var tip := car.wing_tip(side, true)
		var flick := 0.92 + 0.08 * sin(_time * 37.0 + side * 2.0)
		var s := size * lerpf(1.0, 1.35, _wing_boost) * flick
		g.visible = true
		g.global_position = tip + Vector3(-side * float(ws[2]), 0.0, float(ws[0]) + 0.05)
		(g.mesh as QuadMesh).size = Vector2(s, s * (0.6 if int(ws[5]) == 1 else 1.0))
		var gm := g.material_override as StandardMaterial3D
		gm.albedo_color = Color(Palette.ENERGY.lerp(Color.WHITE, 0.35), 0.85 * _wing_vis)


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
	var tip: Vector3 = pts[-1].p
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
		if wing:
			half *= lerpf(1.0, WING_CLIMB_WIDTH, _wing_boost)
		var alpha := color.a * lerpf(k * k, sqrt(k), bl)
		var col: Color = color
		var c: Vector3 = pts[i].p
		if r.get("body", false):
			# Gövdenin dibinden en parlak ve doygun haliyle çıkar (yanıcı bir şey gibi); geriye doğru söner
			var hot := 1.0 - smoothstep(0.0, REAR_HOT, c.z - tip.z)
			col = color.lerp(Color(Palette.ENERGY.lightened(0.15), 1.0), hot)
			alpha = minf(1.0, alpha + hot * 0.35)
		if wing:
			# Dış kenar kanat ucunda: şerit içeri (gövdeye doğru) kayık
			var inward := -signf(float(r.side)) * Vector3.RIGHT
			c += inward * half
			var ws: Array = WING_STYLES[clampi(wing_style, 0, WING_STYLES.size() - 1)]
			c += inward * float(ws[2])
			var behind := c.z - tip.z
			var f0 := lerpf(WING_FADE_FROM, WING_CLIMB_FADE.x, _wing_boost)
			var f1 := lerpf(WING_FADE_TO, WING_CLIMB_FADE.y, _wing_boost)
			alpha *= smoothstep(float(ws[0]), float(ws[1]), behind) * (1.0 - smoothstep(f0, f1, behind))
			# Parlak kök: başladığı yerde beyaza yakın ve tam opak, geriye doğru enerji yeşiline döner
			var root: float = ws[3]
			if root > 0.0:
				var hot := 1.0 - smoothstep(float(ws[1]), float(ws[1]) + root, behind)
				col = color.lerp(Color(1.0, 1.0, 0.85), hot * 0.75)
				alpha = minf(1.0, alpha * (1.0 + hot * 0.6))
				if int(ws[5]) == 1:
					half *= 1.0 + hot * 0.7  # alev dili: kökte kalın, geriye incelir
		mesh.surface_set_color(Color(col, alpha))
		mesh.surface_add_vertex(c - side * half)
		mesh.surface_set_color(Color(col, alpha))
		mesh.surface_add_vertex(c + side * half)
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
