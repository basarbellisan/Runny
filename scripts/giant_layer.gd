class_name GiantLayer
extends SubViewport
## Düz dünya denemesi (katmanlı arka plan): devler (models/giants/giant.glb), eski uzun kaya blokları
## gibi yolun iki yanında durur ve araba ilerledikçe gerçek hızıyla yanımızdan geçer. Ama oyun
## kamerasının sarsıntısından, zıplamadan, rampadan, eğilmeden ve hızla açılan görüş açısından
## etkilenmez: kendi küçük dünyalarında, oyun kamerasının yalnız ileri ilerleyişini (z) aynen izleyen,
## yanı ve yüksekliği çok yumuşak izleyen, bakışı sabit ikinci bir kamerayla çizilir. Görüntü arka
## plan katmanı olarak ön dağ sırasının önüne konur (LayeredBackdrop); ufku arka planın ufkuyla hizalı.

const GIANT_SCENE := preload("res://models/giants/giant.glb")
const MODEL_HEIGHT := 10.0   # modelin baş tepesinden çizimdeki gövde dibine boyu (m)
const MODEL_LEG := 5.0       # gövdenin aşağı uzayan, eriyen kısmı (m)
## Dev boyu (m), yana uzaklık (m, yolun ortasından), yolun üstünde görünen pay
const HEIGHT := Vector2(50.0, 90.0)
const SIDE := Vector2(35.0, 65.0)
const ABOVE := Vector2(0.5, 0.85)
## Kameranın bu kadar önünde doğar; bu kadar arkada kalınca silinir (m)
const SPAWN_AHEAD := 1150.0
const BEHIND := 40.0
## İki dev arası yol boyu (m)
const GAP := Vector2(380.0, 650.0)
## Yola doğru dönüklük (derece)
const TURN := 14.0
## Ufukta, çok uzakta doğar (nokta kadar küçük): yalnız doğduğu yerde kısa bir beliriş (bu uzaklıkta tam,
## şunda görünmez; m)
const FAR_FADE := Vector2(1100.0, 1180.0)
## Kameranın yolun üstündeki yüksekliği ve sabit bakış açısı (oyun kamerasının olağan duruşu)
const EYE := 6.0
const PITCH := -10.0
## Yan ve yükseklik takibinin yumuşatma süresi (sn): zıplama ve sarsıntı geçmez
const SMOOTH := 1.2

var car: Car
var _cam: Camera3D
var _src_sun: DirectionalLight3D
var _src_env: Environment
var _sun: DirectionalLight3D
var _env: Environment
var _rng := RandomNumberGenerator.new()
var _giants: Array[Node3D] = []
var _next_z := INF
var _road_y := NAN
var _x := NAN
var _mat: ShaderMaterial


func setup(p_car: Car, color: Color, sun: DirectionalLight3D, env: Environment, seed_value := -1) -> void:
	car = p_car
	own_world_3d = true
	transparent_bg = true
	msaa_3d = Viewport.MSAA_2X
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if seed_value >= 0:
		_rng.seed = seed_value * 17 + 3
	else:
		_rng.randomize()
	_cam = Camera3D.new()
	_cam.far = 1200.0
	_cam.rotation_degrees = Vector3(PITCH, 0, 0)
	add_child(_cam)
	_cam.current = true
	# Oyunun ışığı (güneş ve ortam): her karede aynen kopyalanır (renkler ruh hâline göre değişir)
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
	_mat.set_shader_parameter("far_fade", Vector2(FAR_FADE.x, FAR_FADE.y))
	_road_y = car.last_floor_y
	_x = car.global_position.x
	# Başta yol boyunca dizili (boş başlamasın)
	var z := car.global_position.z - 200.0
	while z > car.global_position.z - SPAWN_AHEAD:
		_spawn(z)
		z -= _rng.randf_range(GAP.x, GAP.y)
	_next_z = z


func _copy_light() -> void:
	_sun.rotation = _src_sun.rotation
	_sun.light_color = _src_sun.light_color
	_sun.light_energy = _src_sun.light_energy
	_env.ambient_light_color = _src_env.ambient_light_color
	_env.ambient_light_energy = _src_env.ambient_light_energy


func _spawn(z: float) -> void:
	var g: Node3D = GIANT_SCENE.instantiate()
	for mi in g.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in mesh.get_surface_count():
			(mi as MeshInstance3D).set_surface_override_material(i, _mat)
	var side := -1.0 if _rng.randf() < 0.5 else 1.0
	var h := _rng.randf_range(HEIGHT.x, HEIGHT.y)
	var k := h / MODEL_HEIGHT
	g.scale = Vector3.ONE * k
	g.rotation.y = -side * deg_to_rad(TURN)
	var head := _road_y + h * _rng.randf_range(ABOVE.x, ABOVE.y)
	g.position = Vector3(_x + side * _rng.randf_range(SIDE.x, SIDE.y), head - h - MODEL_LEG * k, z)
	add_child(g)
	_giants.append(g)


## Ekran boyu ve görüş açısı (oyun kamerasının hızla açılmayan açısı)
func sync(size: Vector2i, fov: float) -> void:
	if self.size != size:
		self.size = size
	_cam.fov = fov


## Kendi kameranın ufku (ekranda y): arka planın ufkuyla hizalamak için
func horizon_y() -> float:
	var far := _cam.global_position + Vector3(0.0, 0.0, -100000.0)
	return _cam.unproject_position(far).y


func _process(delta: float) -> void:
	if car == null:
		return
	_copy_light()
	var main := car.get_viewport().get_camera_3d()
	if main == null:
		return
	var ks := 1.0 - exp(-delta / SMOOTH)
	_road_y = lerpf(_road_y, car.last_floor_y, ks)
	_x = lerpf(_x, car.global_position.x, ks)
	# İleri ilerleyiş oyun kamerasıyla aynı (devler gerçek hızla geçer); yan ve yükseklik yumuşak
	var cz := main.global_position.z
	_cam.global_position = Vector3(_x, _road_y + EYE, cz)
	while cz - SPAWN_AHEAD < _next_z:
		_spawn(_next_z)
		_next_z -= _rng.randf_range(GAP.x, GAP.y)
	for i in range(_giants.size() - 1, -1, -1):
		if _giants[i].position.z > cz + BEHIND:
			_giants[i].queue_free()
			_giants.remove_at(i)
