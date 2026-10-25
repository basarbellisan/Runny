extends Camera3D
## Arabayı arkadan ve yukarıdan takip eden kamera. Hız arttıkça görüş açısı genişler.

@export var target_path: NodePath
@export var offset := Vector3(0.0, 6.0, 10.0)
@export var look_ahead := 22.0
@export var follow_x := 7.0
## Yükseklik takibi biraz gecikmeli: rampada araba ekranda yükselir, eğim hissedilir
@export var follow_y := 2.5
@export var fov_per_speed := 0.35

var _target: Car
## Hız eklenmeden önceki görüş açısı
var base_fov := 0.0
var _trauma := 0.0
## Roket ateşlenince görüş açısı bir anda açılır, yavaşça geri gelir
var _fov_kick := 0.0
var _fov_kick_shown := 0.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_target = get_node(target_path)
	base_fov = fov
	global_position = _target.global_position + offset


func _process(delta: float) -> void:
	var t := _target.get_global_transform_interpolated().origin
	var p := global_position
	if _target.alive:
		p.z = t.z + offset.z
		p.x = lerpf(p.x, t.x + offset.x, 1.0 - exp(-follow_x * delta))
		# Hızlı yükselip alçalırken (dalış, portal) kamera arabayı kaçırmasın
		var k := follow_y + absf(_target.velocity.y) * 0.15
		p.y = lerpf(p.y, t.y + offset.y, 1.0 - exp(-k * delta))
		global_position = p
		var want_fov := base_fov + (_target.forward_speed - _target.start_speed) * fov_per_speed
		_fov_kick = lerpf(_fov_kick, 0.0, 1.0 - exp(-2.5 * delta))
		fov = lerpf(fov, want_fov, 1.0 - exp(-2.0 * delta)) + (_fov_kick - _fov_kick_shown)
		_fov_kick_shown = _fov_kick
		look_at(Vector3(lerpf(p.x, t.x, 0.6), t.y - 1.0, t.z - look_ahead))
	else:
		look_at(t)
	# Sarsıntı: hızla söner
	_trauma = maxf(_trauma - delta * 1.8, 0.0)
	var k := _trauma * _trauma
	h_offset = randf_range(-1.0, 1.0) * 0.6 * k
	v_offset = randf_range(-1.0, 1.0) * 0.6 * k


func fov_kick(degrees: float) -> void:
	_fov_kick += degrees


func shake(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)
