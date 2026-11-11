class_name FlatStyle
extends Node
## Deneme (?stil=N / --stil=N): düz, minimal dünya. Parıltı, bulanıklık ve degrade yok; yalnız
## gökyüzünün yukarıdan aşağı geçişi, dağların sise erimesi ve sis kalır. Geometri (oranlar) aynı,
## yalnız malzemeler değişir: yol üstü düz tek renk, yan duvarlar düz tek renk, alt yüz ve uçlar
## ayrı renk, çizgiler tek renk. Engeller renkli ama doygunluğu düşük. Araba olduğu gibi.
##
## Oyun sahnesine eklenince (game.gd) sahnedeki ve sonradan eklenen her görünen düğümün malzemesini
## bu kurallarla değiştirir (yol üreticisi vb. kendi kodunu değiştirmeden).

const STYLES := [
	{"name": "şimdiki"},
	{"name": "beton",
		"sky_top": "8f8d88", "horizon": "c4c1ba", "ground": "b8b5ae",
		"mountains": ["a9a6a0", "9c9993", "8e8b85"], "decor": "7d7a75", "sun": "ecebe7",
		"road": "121214", "line": "ffffff", "side": "f7f6f2", "under": "121214", "ends": "121214",
		"lower_top": "d8d6d1", "lower_horizon": "a8a5a0", "lower_ground": "98958f",
		"rocks": ["151515", "1b1b1c", "222224"]},
	{"name": "gece",
		"sky_top": "0b0b0d", "horizon": "2b2b30", "ground": "333338",
		"mountains": ["26262b", "1d1d21", "151518"], "decor": "3a3a40", "sun": "d9d9d4",
		"road": "121214", "line": "ffffff", "side": "f7f6f2", "under": "121214", "ends": "121214",
		"lower_top": "bcbcc0", "lower_horizon": "85858b", "lower_ground": "77777d",
		"rocks": ["0f0f10", "151517", "1b1b1e"]},
	{"name": "toz mavi",
		"sky_top": "4f6278", "horizon": "a3b1bf", "ground": "98a6b4",
		"mountains": ["8697a9", "74859a", "63748a"], "decor": "5c6d82", "sun": "eef1f4",
		"road": "121214", "line": "ffffff", "side": "f7f6f2", "under": "121214", "ends": "121214",
		"lower_top": "d6dde3", "lower_horizon": "a7b4c0", "lower_ground": "98a6b4",
		"rocks": ["161a20", "1b2027", "21272f"]},
	{"name": "kiremit",
		"sky_top": "a4553c", "horizon": "e0a587", "ground": "d8997a",
		"mountains": ["c8836a", "b8735a", "a4634c"], "decor": "8e4f3a", "sun": "f6e3d6",
		"road": "121214", "line": "ffffff", "side": "f7f6f2", "under": "121214", "ends": "121214",
		"lower_top": "f0d9c6", "lower_horizon": "d9a98c", "lower_ground": "cf9a7c",
		"rocks": ["1d1412", "241916", "2b1f1b"]},
	{"name": "ters (beyaz yol)",
		"sky_top": "c9c6bf", "horizon": "eceae5", "ground": "e4e1db",
		"mountains": ["d6d3cc", "c9c6bf", "bcb9b2"], "decor": "a9a6a0", "sun": "fbfaf7",
		"road": "f4f3ef", "line": "121214", "side": "121214", "under": "121214", "ends": "121214",
		"lower_top": "e8e6e1", "lower_horizon": "b9b6b0", "lower_ground": "aaa7a1",
		"rocks": ["151515", "1b1b1c", "222224"]},
	{"name": "zeytin",
		"sky_top": "5d6146", "horizon": "b3b494", "ground": "a8a989",
		"mountains": ["9c9d7d", "8a8b6c", "787a5c"], "decor": "6b6d50", "sun": "f2f1e4",
		"road": "121214", "line": "ffffff", "side": "f7f6f2", "under": "121214", "ends": "121214",
		"lower_top": "e3e3cf", "lower_horizon": "b2b393", "lower_ground": "a3a485",
		"rocks": ["181913", "1e1f18", "25261e"]},
]
## Engellerin doygunluğu bu kadar düşer (0 aynı, 1 gri)
const OBSTACLE_DESAT := 0.4

static var style: int = _read()


static func on() -> bool:
	return style != 0


static func cfg() -> Dictionary:
	return STYLES[style]


static func _read() -> int:
	var v := ""
	if OS.has_feature("web"):
		var r: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('stil') || ''")
		v = "" if r == null else str(r)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stil="):
			v = a.get_slice("=", 1)
	return clampi(int(v), 0, STYLES.size() - 1) if v.is_valid_int() else 0


static func _col(key: String) -> Color:
	return Color(cfg()[key])


static func line_color() -> Color:
	return _col("line")


static func _ink(bg: Color) -> Color:
	return Palette.INK_LIGHT if bg.get_luminance() < 0.45 else Palette.INK_DARK


## Üst katman paleti (Palette.SKIES yerine)
static func skies(default: Array) -> Array:
	if not on():
		return default
	var p := (default[0] as Dictionary).duplicate()
	p.name = cfg().name
	p.sky_top = _col("sky_top")
	p.sky_horizon = _col("horizon")
	p.ground_horizon = p.sky_horizon
	p.ground_bottom = _col("ground")
	p.fog = p.sky_horizon
	# Araba eskisi gibi aydınlansın (nötr ışık; renkli ortam ışığı yok)
	p.ambient = Color(0.72, 0.72, 0.75)
	p.sun = Color(1, 0.97, 0.93)
	p.road_top = _col("road")
	p.road_side = _col("side")
	p.decor = _col("decor")
	p.cloud = Color(_col("horizon"), 0.25)
	p.mountains = (cfg().mountains as Array).map(func(h): return Color(h))
	p.sun_disc = _col("sun")
	p.sparkle = _col("sun")
	p.ink = _ink(p.sky_top)
	return [p]


## Alt katman (uçuş) paleti (Palette.LOWER yerine)
static func lower(default: Dictionary) -> Dictionary:
	if not on():
		return default
	var p := default.duplicate()
	p.sky_top = _col("lower_top")
	p.sky_horizon = _col("lower_horizon")
	p.ground_horizon = p.sky_horizon
	p.ground_bottom = _col("lower_ground")
	p.fog = p.sky_horizon
	p.ambient = Color(0.72, 0.72, 0.75)
	p.sun = Color(1, 0.97, 0.93)
	p.cloud = Color(_col("lower_top"), 0.4)
	p.rocks = (cfg().rocks as Array).map(func(h): return Color(h))
	p.ink = _ink(p.sky_top)
	return p


# --- Sahnedeki malzemeleri düzleştirme ---

const HIDE := "hide"
var _car: Node
var _cache := {}
var _wall_mat: ShaderMaterial
var _invisible: StandardMaterial3D


func _enter_tree() -> void:
	_car = get_parent().get_node_or_null("Car")
	_wall_mat = ShaderMaterial.new()
	_wall_mat.shader = preload("res://shaders/flat_wall.gdshader")
	_wall_mat.set_shader_parameter("side", _col("side"))
	_wall_mat.set_shader_parameter("rim", _col("side"))
	_wall_mat.set_shader_parameter("under", _col("under"))
	_wall_mat.set_shader_parameter("ends", _col("ends"))
	_invisible = StandardMaterial3D.new()
	_invisible.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_invisible.albedo_color = Color(0, 0, 0, 0)
	get_tree().node_added.connect(_on_added)
	_walk(get_parent())


func _walk(n: Node) -> void:
	_on_added(n)
	for c in n.get_children():
		_walk(c)


func _on_added(n: Node) -> void:
	if n is GeometryInstance3D:
		# Malzeme çoğu zaman add_child'dan önce, bazen hemen sonra atanır
		_fix.call_deferred(n)


func _fix(n: Node) -> void:
	if not is_instance_valid(n):
		return
	var gi := n as GeometryInstance3D
	# Araba olduğu gibi kalır; yalnız arkasındaki degrade iz şeritleri ve eklemeli parıltılar gizlenir
	if _car and _car.is_ancestor_of(n):
		if gi.material_override and _is_glow(gi.material_override):
			gi.visible = false
		return
	if gi.material_override:
		var r: Variant = _convert(gi.material_override)
		if r is String:
			gi.visible = false
			return
		gi.material_override = r
	var mesh: Mesh = null
	if n is MeshInstance3D:
		mesh = (n as MeshInstance3D).mesh
	elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh:
		mesh = (n as MultiMeshInstance3D).multimesh.mesh
	elif n is CPUParticles3D:
		mesh = (n as CPUParticles3D).mesh
	elif n is GPUParticles3D:
		mesh = (n as GPUParticles3D).draw_pass_1
	if mesh == null:
		return
	for i in mesh.get_surface_count():
		var m: Material = mesh.surface_get_material(i)
		if n is MeshInstance3D and (n as MeshInstance3D).get_surface_override_material(i):
			m = (n as MeshInstance3D).get_surface_override_material(i)
		if m == null:
			continue
		var r: Variant = _convert(m)
		if r is String:
			if n is MeshInstance3D:
				(n as MeshInstance3D).set_surface_override_material(i, _invisible)
			else:
				gi.visible = false
		elif r != m and n is MeshInstance3D:
			(n as MeshInstance3D).set_surface_override_material(i, r)


func _convert(m: Material) -> Variant:
	if _cache.has(m):
		return _cache[m]
	var r: Variant = _convert_new(m)
	_cache[m] = r
	return r


func _flat(c: Color) -> StandardMaterial3D:
	var f := StandardMaterial3D.new()
	f.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	f.albedo_color = c
	return f


func _desat(c: Color) -> Color:
	return Color.from_hsv(c.h, c.s * (1.0 - OBSTACLE_DESAT), c.v * 0.95)


func _convert_new(m: Material) -> Variant:
	match String(m.get_meta("flat_role", "")):
		"wall":
			return _wall_mat
		"asphalt":
			return _flat(_col("road"))
		"decor":
			return _flat(_col("decor"))
		"rock":
			return _flat((m as StandardMaterial3D).albedo_color)
		"unshade":
			(m as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			return m
	if m is ShaderMaterial:
		var sm := m as ShaderMaterial
		var path := sm.shader.resource_path.get_file() if sm.shader else ""
		match path:
			"block_glow.gdshader", "runway_halo.gdshader", "gravel_curtain.gdshader":
				return HIDE
			"block_fx.gdshader", "block_neon.gdshader":
				return _flat(_desat(sm.get_shader_parameter("c_main")))
			"gravel_zigzag.gdshader", "gravel_holes.gdshader":
				var c := _desat(sm.get_shader_parameter("light"))
				for k in ["light", "core", "lit_color"]:
					sm.set_shader_parameter(k, c)
				return sm
		return m
	if _is_glow(m):
		return HIDE
	if m is StandardMaterial3D:
		var s := m as StandardMaterial3D
		if s.emission_enabled:
			s.emission_enabled = false
	return m


## Parıltı / degrade: eklemeli karışım, degrade dokulu hale, saydam renk geçişli şerit
func _is_glow(m: Material) -> bool:
	if not m is StandardMaterial3D:
		return false
	var s := m as StandardMaterial3D
	return s.blend_mode == BaseMaterial3D.BLEND_MODE_ADD or s.albedo_texture is GradientTexture2D \
		or (s.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and s.vertex_color_use_as_albedo)
