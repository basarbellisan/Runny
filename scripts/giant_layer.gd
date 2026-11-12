class_name GiantLayer
extends SubViewport
## Düz dünya denemesi (katmanlı arka plan): devler (models/giants/giant.glb) oyun kamerasından
## tamamen bağımsız, kendi küçük dünyalarında ve kendi sabit kameralarıyla çizilir; arka plan katmanı
## olarak ön dağ sırasının önüne konur (LayeredBackdrop). Araba zıplasa, kamera sarsılsa, eğilse,
## hızlanınca görüş açısı açılsa da oynamazlar; yalnız kendi ağır hızlarıyla yaklaşıp yanımızdan
## geçerler. Ekrandaki yükseklikleri arka planın yumuşatılmış ufuk çizgisine bağlı (dağlar gibi).

const GIANT_SCENE := preload("res://models/giants/giant.glb")
const MODEL_HEIGHT := 10.0   # modelin baş tepesinden çizimdeki gövde dibine boyu (m)
const MODEL_LEG := 5.0       # gövdenin aşağı uzayan, eriyen kısmı (m)
## Kendi kameralarının yüksekliği (m): bakış yatay, ufuk görüntünün ortasında
const EYE := 8.0
## Dev boyu (m), yana uzaklık (m), yolun (y = 0) üstünde görünen pay
const HEIGHT := Vector2(70.0, 120.0)
const SIDE := Vector2(38.0, 80.0)
const ABOVE := Vector2(0.5, 0.85)
## Doğduğu uzaklık, yaklaşma hızı (m/sn, arabadan bağımsız), arkada kalınca silinme
const SPAWN_Z := 520.0
const SPEED := 22.0
const BEHIND := 40.0
## İki dev arası süre (sn) ve aynı anda en çok kaç dev
const GAP := Vector2(5.0, 11.0)
const MAX_ALIVE := 4
## Yola doğru dönüklük (derece)
const TURN := 14.0
## Uzaktan beliriş: bu uzaklıkta görünmez, şu uzaklıkta tam (m)
const FAR_FADE := Vector2(380.0, 500.0)

var _cam: Camera3D
## Oyunun güneşi ve ortamı (renkleri ruh hâline göre değişir: her karede aynen kopyalanır)
var _src_sun: DirectionalLight3D
var _src_env: Environment
var _sun: DirectionalLight3D
var _env: Environment
var _rng := RandomNumberGenerator.new()
var _giants: Array[Node3D] = []
var _timer := 0.5
var _mat: ShaderMaterial
var _side := 1.0


func setup(color: Color, sun: DirectionalLight3D, env: Environment, seed_value := -1) -> void:
	own_world_3d = true
	transparent_bg = true
	msaa_3d = Viewport.MSAA_2X
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if seed_value >= 0:
		_rng.seed = seed_value * 17 + 3
	else:
		_rng.randomize()
	_cam = Camera3D.new()
	_cam.position = Vector3(0, EYE, 0)
	_cam.far = 900.0
	add_child(_cam)
	_cam.current = true
	# Oyunun ışığı (güneş ve ortam) aynen
	_src_sun = sun
	_src_env = env
	_sun = DirectionalLight3D.new()
	add_child(_sun)
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_CLEAR_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.tonemap_mode = env.tonemap_mode
	we.environment = _env
	add_child(we)
	_copy_light()
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/giant_fade.gdshader")
	_mat.set_shader_parameter("color", color)
	_mat.set_shader_parameter("shade", preload("res://models/giants/giant_shade.png"))
	_mat.set_shader_parameter("fade_from", 0.0)
	_mat.set_shader_parameter("fade_to", MODEL_LEG + 1.0)
	_mat.set_shader_parameter("far_fade", Vector2(FAR_FADE.y, FAR_FADE.x))
	_side = -1.0 if _rng.randf() < 0.5 else 1.0
	# Başta birkaç dev yolda ilerlemiş olsun (boş başlamasın)
	for z in [140.0, 300.0, 450.0]:
		_spawn(z)


## Ekran boyu ve oyun kamerasının (hızla açılmayan) görüş açısı
func sync(size: Vector2i, fov: float) -> void:
	if self.size != size:
		self.size = size
	_cam.fov = fov


func _spawn(dist: float) -> void:
	var g: Node3D = GIANT_SCENE.instantiate()
	for mi in g.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in mesh.get_surface_count():
			(mi as MeshInstance3D).set_surface_override_material(i, _mat)
	# Sırayla iki yanda (arada bir aynı yanda)
	if _rng.randf() < 0.75:
		_side = -_side
	var h := _rng.randf_range(HEIGHT.x, HEIGHT.y)
	var k := h / MODEL_HEIGHT
	g.scale = Vector3.ONE * k
	g.rotation.y = -_side * deg_to_rad(TURN)
	var head := h * _rng.randf_range(ABOVE.x, ABOVE.y)
	g.position = Vector3(_side * _rng.randf_range(SIDE.x, SIDE.y), head - h - MODEL_LEG * k, -dist)
	add_child(g)
	_giants.append(g)


func _copy_light() -> void:
	_sun.rotation = _src_sun.rotation
	_sun.light_color = _src_sun.light_color
	_sun.light_energy = _src_sun.light_energy
	_env.ambient_light_color = _src_env.ambient_light_color
	_env.ambient_light_energy = _src_env.ambient_light_energy


func _process(delta: float) -> void:
	_copy_light()
	_timer -= delta
	if _timer <= 0.0:
		_timer = _rng.randf_range(GAP.x, GAP.y)
		if _giants.size() < MAX_ALIVE:
			_spawn(SPAWN_Z)
	for i in range(_giants.size() - 1, -1, -1):
		var g := _giants[i]
		g.position.z += SPEED * delta
		if g.position.z > BEHIND:
			g.queue_free()
			_giants.remove_at(i)
