class_name Car
extends CharacterBody3D
## Kendiliğinden ileri giden araba. Oyuncu sadece sağ/sol yapar.
## Yolun sonuna gelince hızıyla havaya fırlar.

signal landed(air_time: float)
signal crashed
signal fell

@export var start_speed := 22.0
@export var max_speed := 55.0
## Saniyede hız artışı (m/s)
@export var acceleration := 0.35
@export var steer_speed := 11.0
@export var steer_accel := 70.0
## Havadayken direksiyonun etkisi (0-1)
@export_range(0.0, 1.0) var air_control := 0.6
@export var gravity := 28.0
## Yolun kenarından çıkarken verilen küçük yukarı itiş
@export var launch_velocity := 8.0
## Son yoldan bu kadar metre aşağı düşünce "düştü" sayılır
@export var fall_limit := 12.0
## Yolun kenarını az farkla kaçırıyorsak yola doğru hafif çekim
@export var landing_assist := 6.0
@export var assist_margin := 1.5

var speed := 0.0
var half_length := 1.8
var roads: RoadGenerator
var alive := true
var autopilot := false
var air_time := 0.0
var last_floor_y := 0.0
var _was_on_floor := true
var _crashed := false
var _touches := {}  # dokunma index -> ekran x

@onready var _body: Node3D = $Body


func _ready() -> void:
	speed = start_speed
	floor_snap_length = 0.4
	var box := ($Collision as CollisionShape3D).shape as BoxShape3D
	half_length = box.size.z * 0.5
	last_floor_y = global_position.y


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position.x
		else:
			_touches.erase(event.index)
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position.x


func _physics_process(delta: float) -> void:
	if not alive:
		_dead_motion(delta)
		return

	speed = minf(speed + acceleration * delta, max_speed)
	var on_floor := is_on_floor()
	var steer := _autopilot_steer() if autopilot else _read_steer()
	var control := 1.0 if on_floor else air_control
	velocity.x = move_toward(velocity.x, steer * steer_speed, steer_accel * control * delta)
	if not on_floor:
		velocity.y -= gravity * delta
		air_time += delta
		_apply_landing_assist(delta)
	velocity.z = -speed

	move_and_slide()

	if _hit_wall_front():
		_die(true)
		return

	var now_on_floor := is_on_floor()
	if _was_on_floor and not now_on_floor and velocity.y <= 0.5:
		velocity.y = launch_velocity
	if not _was_on_floor and now_on_floor:
		landed.emit(air_time)
	if now_on_floor:
		air_time = 0.0
		last_floor_y = global_position.y
	_was_on_floor = now_on_floor

	if global_position.y < last_floor_y - fall_limit:
		_die(false)
		return

	_update_visual(delta)


func _read_steer() -> float:
	var s := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		s -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		s += 1.0
	var half := get_viewport().get_visible_rect().size.x * 0.5
	for x in _touches.values():
		s += -1.0 if x < half else 1.0
	return clampf(s, -1.0, 1.0)


func _hit_wall_front() -> bool:
	for i in get_slide_collision_count():
		if get_slide_collision(i).get_normal().z > 0.6:
			return true
	return false


func _die(by_crash: bool) -> void:
	alive = false
	_crashed = by_crash
	if by_crash:
		velocity = Vector3(velocity.x * 0.2, 4.0, speed * 0.15)
		crashed.emit()
	else:
		fell.emit()


func _dead_motion(delta: float) -> void:
	# Ölünce de düşmeye devam etsin (ileride burada kanatlar açılacak)
	velocity.y -= gravity * delta
	if _crashed:
		velocity.x = move_toward(velocity.x, 0.0, 5.0 * delta)
		_body.rotate_x(-4.0 * delta)
	position += velocity * delta


## Havada, iniş noktası bir yolun kenarını az farkla kaçırıyorsa yola doğru çek
func _apply_landing_assist(delta: float) -> void:
	if roads == null:
		return
	var pos := global_position
	for s in roads.segments:
		if s.z_end >= pos.z or s.top >= pos.y - 0.05:
			continue
		var t := _time_to_fall_to(s.top)
		var land := pos + Vector3(velocity.x * t, 0, -speed * t)
		if land.z > s.z_start or land.z < s.z_end:
			continue
		var outside := absf(land.x - s.x) - s.width * 0.5
		if outside > -0.4 and outside < assist_margin:
			velocity.x += signf(s.x - land.x) * landing_assist * delta
		return


func _time_to_fall_to(y: float) -> float:
	var h := global_position.y - y
	return (velocity.y + sqrt(maxf(velocity.y * velocity.y + 2.0 * gravity * h, 0.0))) / gravity


func _update_visual(delta: float) -> void:
	var yaw := -atan2(velocity.x, speed) * 0.8
	var pitch := 0.0 if is_on_floor() else atan2(velocity.y, speed) * 0.7
	var roll := -velocity.x / steer_speed * 0.08
	var w := 1.0 - exp(-12.0 * delta)
	_body.rotation = _body.rotation.lerp(Vector3(pitch, yaw, roll), w)


## Test için otomatik pilot: bir sonraki ana yolun ortasına nişan alır
func _autopilot_steer() -> float:
	if roads == null:
		return 0.0
	var pos := global_position
	var current: RoadGenerator.Segment = roads.segment_under(pos) if is_on_floor() else null
	var target: RoadGenerator.Segment = null
	for s in roads.main_segments_ahead(pos.z + 2.0):
		if s == current:
			continue
		if s.z_start < pos.z or s.contains(pos):
			target = s
			break
	if target == null:
		return 0.0
	var aim := target.x
	if current != null:
		var lim := current.width * 0.5 - 1.2
		aim = clampf(aim, current.x - lim, current.x + lim)
	var err := aim - pos.x
	if absf(err) < 0.25:
		return 0.0
	return signf(err)
