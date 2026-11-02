class_name Backdrop
extends Node3D
## Üst katmanın uzak manzarası: ufukta üst üste binen üçgen dağ silüetleri (3 kat, öndeki koyu),
## aralarında batan büyük güneş diski ve arabanın çevresinde süzülen küçük parıltılar.
## Renkler o anki bölge paletinden (Palette.SKIES: mountains, sun_disc, sparkle); arabayla birlikte
## yürür (hep ufukta durur). Alt katmana inerken yavaşça kaybolur (mood).

## Dağ katları: [uzaklık (m), tepe yüksekliği aralığı (m), tepe aralığı (m)]; ilk kat en uzak
## (kameranın görüş sınırı 900 m: hepsi onun içinde)
const LAYERS := [[840.0, Vector2(310, 490), 320.0], [720.0, Vector2(190, 320), 240.0], [600.0, Vector2(105, 200), 165.0]]
const SPAN := 2600.0          # dağ sırasının yatay genişliği
const BASE_Y := -46.0         # dağların dibi (bulut tabakasının altı: sisten çıkıyormuş gibi)
const SUN_DIST := 875.0
## Katman geçişinde dağlar kaybolurken bu kadar yukarı kayar (çıkarken yukarıdan yerine iner)
const FADE_LIFT := 70.0
const VALLEY := 520.0         # vadinin yarı genişliği (m): ortada dağlar alçalır
## Güneşin yolu: sol alttan (dibi hep dağların dibinden yukarıda) sağ yukarıya; bir geçiş SUN_PERIOD saniye, sonra baştan.
## Oyun başında yolun ~%30'unda (vadide, dibi dağlarda) başlar
const SUN_PERIOD := 200.0
## En alçakta güneşin dibi dağların dibine (BASE_Y) değer, aşağı inmez
const SUN_FROM := Vector2(-520.0, BASE_Y + 105.0)
const SUN_TO := Vector2(560.0, 420.0)
const SUN_START := 0.3
const SUN_RADIUS := 105.0
const SUN_Y := 55.0          # güneşin merkezi (dibi dağların arkasında kalır)

var car: Node3D
var _layers: Array[MeshInstance3D] = []
var _layer_mats: Array[ShaderMaterial] = []
var _sun: MeshInstance3D
var _sun_mat := StandardMaterial3D.new()
var _halo: MeshInstance3D
var _halo_mat := StandardMaterial3D.new()
var _sparkles: CPUParticles3D
var _sparkle_mat := StandardMaterial3D.new()
var _rng := RandomNumberGenerator.new()
var _sun_t := SUN_START


func setup(p_car: Node3D) -> void:
	car = p_car
	_rng.seed = 7
	for i in LAYERS.size():
		# Opak: arkasında kalan güneşi tamamen örter; dibi sis rengine erir
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/mountain.gdshader")
		# Çizim sırası: hale, güneş, sonra dağlar uzaktan yakına
		m.render_priority = i - 3
		var mi := MeshInstance3D.new()
		mi.mesh = _ridge(LAYERS[i])
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_layers.append(mi)
		_layer_mats.append(m)
	# Güneş: dağların en arkasında, düz bir disk
	var disc := CylinderMesh.new()
	disc.top_radius = SUN_RADIUS
	disc.bottom_radius = SUN_RADIUS
	disc.height = 0.5
	disc.radial_segments = 64
	_sun_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sun_mat.disable_fog = true
	_sun_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_sun_mat.render_priority = -5

	_sun = MeshInstance3D.new()
	_sun.mesh = disc
	_sun.rotation.x = PI * 0.5
	_sun.material_override = _sun_mat
	_sun.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sun)
	# Hale: güneşin arkasında geniş, soluk bir disk
	var hd := QuadMesh.new()
	hd.size = Vector2.ONE * SUN_RADIUS * 5.0
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.55))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 128
	tex.height = 128
	_halo_mat.albedo_texture = tex
	_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_mat.disable_fog = true
	_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_mat.render_priority = -6

	_halo = MeshInstance3D.new()
	_halo.mesh = hd
	_halo.material_override = _halo_mat
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_halo)
	# Parıltılar: arabanın önünde ve çevresinde yavaş süzülen küçük elmaslar
	_sparkle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sparkle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_sparkle_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_sparkle_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_sparkle_mat.vertex_color_use_as_albedo = true
	_sparkle_mat.disable_fog = true
	var q := QuadMesh.new()
	q.size = Vector2(0.45, 0.45)
	q.material = _sparkle_mat
	_sparkles = CPUParticles3D.new()
	_sparkles.mesh = q
	_sparkles.amount = 140
	_sparkles.lifetime = 7.0
	_sparkles.preprocess = 7.0
	_sparkles.local_coords = false
	_sparkles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_sparkles.emission_box_extents = Vector3(50, 16, 95)
	_sparkles.direction = Vector3(0, 1, 0)
	_sparkles.spread = 180.0
	_sparkles.gravity = Vector3.ZERO
	_sparkles.initial_velocity_min = 0.2
	_sparkles.initial_velocity_max = 0.8
	_sparkles.scale_amount_min = 0.5
	_sparkles.scale_amount_max = 1.4
	_sparkles.angle_min = 45.0
	_sparkles.angle_max = 45.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.2, Color(1, 1, 1, 1))
	fade.add_point(0.8, Color(1, 1, 1, 1))
	_sparkles.color_ramp = fade
	add_child(_sparkles)


## Dağ silüeti: SPAN boyunca rastgele tepeler; her tepe dibe inen düz bir üçgen yelpazesi
func _ridge(layer: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h: Vector2 = layer[1]
	var step: float = layer[2]
	var x := -SPAN * 0.5
	var prev := Vector3(x, 0.0, 0.0)
	while x < SPAN * 0.5:
		var w := step * _rng.randf_range(0.7, 1.3)
		var px := x + w * _rng.randf_range(0.35, 0.65)
		# Ortada V biçimli vadi: güneş aradan görünür (kenarlara doğru dağlar yükselir)
		var valley := clampf(absf(px) / VALLEY, 0.0, 1.0)
		var peak := Vector3(px, _rng.randf_range(h.x, h.y) * lerpf(0.12, 1.0, valley), 0.0)
		var end := Vector3(x + w, 0.0, 0.0)
		# Dipte saydam: dağ aşağıda sise karışıp kaybolur
		for v: Vector3 in [prev, peak, end]:
			st.set_color(Color(1, 1, 1, clampf(v.y / (h.x * 0.55), 0.0, 1.0)))
			st.add_vertex(v)
		prev = end
		x += w * _rng.randf_range(0.55, 0.85)  # tepeler üst üste biner
		prev = Vector3(x, 0.0, 0.0)
	return st.commit()


## Her kare: arabayla yürü; renkler paletten; alt katmana inerken (mood 0 → 1) kaybol
func update(pal: Dictionary, mood: float) -> void:
	if car == null:
		return
	# Katmanlar arası geçişte yavaşça saydamlaşır / belirir (arkasındaki gök ne renkse ona erir)
	var seen := 1.0 - smoothstep(0.05, 0.75, mood)
	visible = seen > 0.002
	if not visible:
		return
	var c := car.global_position
	var mtn: Array = pal.mountains
	for i in _layers.size():
		var lift: float = FADE_LIFT * (1.0 - seen) * (1.0 + 0.25 * i)  # öndeki biraz daha çok
		_layers[i].global_position = Vector3(c.x * 0.6, BASE_Y + lift, c.z - float(LAYERS[i][0]))
		# Alt katmana inerken dağlar sis rengine karışıp kaybolur
		_layer_mats[i].set_shader_parameter("color", mtn[i])
		_layer_mats[i].set_shader_parameter("fog", pal.fog)
		_layer_mats[i].set_shader_parameter("alpha", seen)
	_sun_t = fmod(_sun_t + get_process_delta_time() / SUN_PERIOD, 1.0)
	# Hafif yay: önce yana, sonra daha dik yükselir
	var sx := lerpf(SUN_FROM.x, SUN_TO.x, _sun_t)
	var sy := lerpf(SUN_FROM.y, SUN_TO.y, _sun_t * _sun_t * 0.4 + _sun_t * 0.6)
	_sun.global_position = Vector3(c.x * 0.6 + sx, sy, c.z - SUN_DIST)
	_sun_mat.albedo_color = Color(pal.sun_disc, seen)
	_halo.global_position = _sun.global_position + Vector3(0, 0, -10.0)
	_halo_mat.albedo_color = Color(pal.sun_disc, 0.5 * seen)
	# Kameranın önünden uzakta başlar (yakında büyük kare gibi görünmesin)
	_sparkles.global_position = c + Vector3(0, 6.0, -125.0)
	_sparkle_mat.albedo_color = Color(pal.sparkle, 0.9 * seen)
