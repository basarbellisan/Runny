class_name FlatStyle
extends Node
## Deneme (?stil=N / --stil=N): düz, minimal dünya. Parıltı, bulanıklık ve degrade yok; yalnız
## gökyüzünün yukarıdan aşağı geçişi, dağların sise erimesi ve sis kalır. Geometri (oranlar) aynı,
## yalnız malzemeler değişir: yol üstü düz tek renk, yan duvarlar düz tek renk, alt yüz ve uçlar
## ayrı renk, çizgiler tek renk. Engeller renkli ama doygunluğu düşük. Araba olduğu gibi.
##
## Oyun sahnesine eklenince (game.gd) sahnedeki ve sonradan eklenen her görünen düğümün malzemesini
## bu kurallarla değiştirir (yol üreticisi vb. kendi kodunu değiştirmeden).

## Atmosfer: "beton" ve "zeytin" denemelerinin ortası (gökyüzü, dağlar, dekor, uçuş katmanı)
const ATMOS := {
	"sky_top": "767767", "horizon": "bcbaa7", "ground": "b0af9c",
	"mountains": ["a2a28e", "939280", "838270"], "decor": "747462", "sun": "efeee6",
	"lower_top": "dedcd0", "lower_horizon": "adac9a", "lower_ground": "9e9c8a",
	"rocks": ["161714", "1c1d1a", "242421"],
}
const BLACK := "121214"
const WHITE := "f7f6f2"
## Koyu gökyüzü denemesi: tepede çok koyu, dağların arkasına doğru açılır; koyuluk dağlarda biter.
## Dağlar, sis, ufkun altı ve uçuş katmanı açık atmosferde kalır ("fog": ufkun altı ve sis rengi)
const DARK_SKY := {"sky_top": "1f1f1b", "horizon": "6a695d", "fog": "bcbaa7"}
const DARKER_SKY := {"sky_top": "121210", "horizon": "4a493f", "fog": "bcbaa7"}
## Dağ katmanları denemesi: gökyüzünün altında üç sıra degradesiz dağ, arkadan öne birer ton açılır;
## en öndeki sıranın rengi aşağı kadar (ufkun altı, sis) ve uçuş katmanında da devam eder
## Gökyüzü de degradesiz: tek renk (ufuk rengi; en arka dağların bir ton koyusu)
static func _layered(sky: Dictionary, far: String, mid: String, near: String) -> Dictionary:
	var d := sky.duplicate()
	var horizon: String = sky.get("horizon", ATMOS.horizon)
	d.merge({"sky_top": horizon, "horizon": horizon, "mountains": [far, mid, near], "flat_mountains": true,
		"fog": near, "ground": near, "lower_top": near, "lower_horizon": near, "lower_ground": near}, true)
	return d
static var LAYERED_LIGHT: Dictionary = _layered({}, "cac8b6", "d8d6c5", "e5e3d4")
static var LAYERED_DARK: Dictionary = _layered(DARK_SKY, "807f71", "979686", "adac9b")
## Katmanlı 2D arka plan (LayeredBackdrop): aynı renkler, paralakslı katmanlar
static var LAYERED_BG: Dictionary = LAYERED_DARK.merged({"layered_bg": true}, true)
## Bant biçimli sırtlar (LayeredBackdrop.SHAPES)
static func _bands(shape: String) -> Dictionary:
	return LAYERED_BG.merged({"bg_shape": shape}, true)
## [ad, yol üstü, yan duvarlar (ön ve arka uçlar da), çizgi ve yol işaretleri, atmosfer farkı];
## alt yüz siyah
static var COMBOS: Array = [
	["şimdiki", "", "", "", {}],
	["siyah yol, beyaz yan", BLACK, WHITE, WHITE, {}],
	["koyu gökyüzü", BLACK, WHITE, WHITE, DARK_SKY],
	["daha koyu gökyüzü", BLACK, WHITE, WHITE, DARKER_SKY],
	["dağ katmanları, açık gök", BLACK, WHITE, WHITE, LAYERED_LIGHT],
	["dağ katmanları, koyu gök", BLACK, WHITE, WHITE, LAYERED_DARK],
	["katmanlı arka plan", BLACK, WHITE, WHITE, LAYERED_BG],
	["bantlar: eğik", BLACK, WHITE, WHITE, _bands("slant")],
	["bantlar: kırık", BLACK, WHITE, WHITE, _bands("kink")],
	["bantlar: tepe", BLACK, WHITE, WHITE, _bands("peak")],
	["bantlar: düz", BLACK, WHITE, WHITE, _bands("flat")],
]
static var STYLES: Array = COMBOS.map(func(c: Array) -> Dictionary:
	var d := ATMOS.duplicate()
	d.merge(c[4], true)
	d.merge({"name": c[0], "road": c[1], "side": c[2], "line": c[3], "under": BLACK, "ends": c[2]}, true)
	return d)
## Alt katmanın derinlik sisi (game.gd FOG_LOWER yerine): yakın yol parçaları net siyah-beyaz okunsun,
## uzakta yine sise erisin. [başlangıç, bitiş, eğri]
const FOG_LOWER := Vector3(40.0, 330.0, 1.0)
## Engellerin doygunluğu bu kadar düşer (0 aynı, 1 gri)
const OBSTACLE_DESAT := 0.2

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


## Dağlar degradesiz (dibe doğru sise erimez, her sıra tek renk)
static func flat_mountains() -> bool:
	return on() and cfg().get("flat_mountains", false)


## 2D katmanlı arka plan (LayeredBackdrop) açık mı
static func layered_bg() -> bool:
	return on() and cfg().get("layered_bg", false)


## Katmanlı arka planın renkleri: [gökyüzü, gezegen, en arka sıra, orta sıra, ön sıra ve aşağısı]
static func bg_shape() -> String:
	return cfg().get("bg_shape", "tri")


static func bg_colors() -> Array:
	var m: Array = cfg().mountains
	return [_col("horizon"), _col("sun"), Color(m[0]), Color(m[1]), Color(m[2])]


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
	# Sis ve ufkun altı: ayrıca verilmişse o (koyu gökyüzü dağlarda biter), yoksa ufuk rengi
	p.fog = Color(cfg().get("fog", cfg().horizon))
	p.ground_horizon = p.fog
	p.ground_bottom = _col("ground")
	# Araba eskisi gibi aydınlansın (nötr ışık; renkli ortam ışığı yok)
	p.ambient = Color(0.72, 0.72, 0.75)
	p.sun = Color(1, 0.97, 0.93)
	p.road_top = _col("road")
	p.road_side = _col("side")
	p.decor = _col("decor")
	p.cloud = Color(p.fog, 0.25)
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
	# Duvarın asfaltın iki yanında kalan ince üst kenarı yol renginde: ekstra kenar çizgisi olmasın
	_wall_mat.set_shader_parameter("rim", _col("road"))
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
		"mark":
			# Yol üstündeki işaretler (rampa çizgileri ve okları, bordür): çizgi renginde
			if m is ShaderMaterial:
				(m as ShaderMaterial).set_shader_parameter("color", _col("line"))
				return m
			return _flat(_col("line"))
		"runway":
			# Yol sonundaki kırmızı ışıklar: hale yok, sönükken de daha parlak kırmızı
			(m as ShaderMaterial).set_shader_parameter("dim", 0.85)
			return m
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
