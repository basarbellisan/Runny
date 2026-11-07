extends Camera3D
## Arabayı arkadan ve yukarıdan takip eden kamera. Hız arttıkça görüş açısı genişler.

@export var target_path: NodePath
@export var offset := Vector3(0.0, 6.0, 10.0)
@export var look_ahead := 22.0
@export var follow_x := 7.0
## Yükseklik takibi biraz gecikmeli: rampada araba ekranda yükselir, eğim hissedilir
@export var follow_y := 2.5
@export var fov_per_speed := 0.35
## Kamera yatık yolla birlikte bu oranda yana yatar
@export var bank_follow := 0.15

var _target: Car
## Hız eklenmeden önceki görüş açısı
var base_fov := 0.0
var _trauma := 0.0
## Roket ateşlenince görüş açısı bir anda açılır, yavaşça geri gelir
var _fov_kick := 0.0
## Vuruş hedefi: açı buna doğru ~0.2 sn'de açılır (birden sıçramaz), sonra söner
var _fov_kick_target := 0.0
var _roll := 0.0
var _fov_kick_shown := 0.0
## Oyun sonu: kamera yavaşça göğe döner (0 → 1); ekranın altında dağlar ve güneş kalır
var sky_view := 0.0
## Göğe dönünce bakış açısı (derece, yatayın üstü)
@export var sky_pitch := 40.0
var _sky_from := Vector3.ZERO
## Son baktığı nokta: araba patlayınca bakış buradan arabaya yumuşakça kayar (birden atlamaz)
var _look := Vector3.ZERO


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_target = get_node(target_path)
	base_fov = fov
	global_position = _target.global_position + offset


func _process(delta: float) -> void:
	var t := _target.get_global_transform_interpolated().origin
	var p := global_position
	if _target.alive or _target.shattering:
		p.z = t.z + offset.z
		p.x = lerpf(p.x, t.x + offset.x, 1.0 - exp(-follow_x * delta))
		# Hızlı yükselip alçalırken (dalış, portal) kamera arabayı kaçırmasın
		var k := follow_y + absf(_target.velocity.y) * 0.15
		p.y = lerpf(p.y, t.y + offset.y, 1.0 - exp(-k * delta))
		global_position = p
		var want_fov := base_fov + (_target.forward_speed - _target.start_speed) * fov_per_speed
		_fov_kick_target = lerpf(_fov_kick_target, 0.0, 1.0 - exp(-2.5 * delta))
		_fov_kick = lerpf(_fov_kick, _fov_kick_target, 1.0 - exp(-12.0 * delta))
		fov = lerpf(fov, want_fov, 1.0 - exp(-2.0 * delta)) + (_fov_kick - _fov_kick_shown)
		_fov_kick_shown = _fov_kick
		_look = Vector3(lerpf(p.x, t.x, 0.6), t.y - 1.0, t.z - look_ahead)
		look_at(_look)
		_roll = lerpf(_roll, _target.surface_roll * bank_follow, 1.0 - exp(-4.0 * delta))
		rotate_object_local(Vector3(0, 0, 1), _roll)
	else:
		# Patlama: bakış önceki noktadan arabanın kalıntısına yavaşça döner
		if _look == Vector3.ZERO:
			_look = t
		_look = _look.lerp(t, 1.0 - exp(-1.5 * delta))
		var look := _look
		if sky_view > 0.0:
			# Göğe dönüş: kaza anındaki bakış noktasından ufkun üstüne
			var k_sky := sky_view * sky_view * (3.0 - 2.0 * sky_view)
			if _sky_from == Vector3.ZERO:
				_sky_from = t
			var up := global_position + Vector3(0, tan(deg_to_rad(sky_pitch)), -1).normalized() * 200.0
			look = _sky_from.lerp(up, k_sky)
			fov = lerpf(fov, base_fov, 1.0 - exp(-2.0 * delta))
		look_at(look)
	# Sarsıntı: hızla söner
	_trauma = maxf(_trauma - delta * 1.8, 0.0)
	var k := _trauma * _trauma
	h_offset = randf_range(-1.0, 1.0) * 0.6 * k
	v_offset = randf_range(-1.0, 1.0) * 0.6 * k


## Oyun sonu: kamerayı süre boyunca göğe çevir
func look_sky(duration: float) -> void:
	_sky_from = Vector3.ZERO
	create_tween().tween_property(self, "sky_view", 1.0, duration).set_trans(Tween.TRANS_SINE)


func fov_kick(degrees: float) -> void:
	_fov_kick_target += degrees


func shake(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)
