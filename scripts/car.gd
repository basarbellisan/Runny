class_name Car
extends CharacterBody3D
## Kendiliğinden ileri giden araba. Oyuncu sağ/sol yapar; iki parmakla
## (iki yarıya birden) basınca gaz verir. Gaz verirken direksiyon çalışmaz.
##
## Modlar:
##  DRIVE   – üst katmanda yolda (yolun sonunda hızıyla havaya fırlar)
##  FALLING – yoldan düştük, birkaç metre serbest düşüş
##  FLYING  – kanatlar açık, alt katmanda uçuş
##  LAUNCH  – portal bizi yukarı fırlattı, havada arabaya dönüyoruz
##  DEAD

signal landed(air_time: float)
## Yolun sonundan havaya fırladık
signal jumped
## Bir yere çarpıp patladık
signal exploded
signal mode_changed(mode: Mode, previous: Mode)
signal died(reason: String)

enum Mode { DRIVE, FALLING, FLYING, LAUNCH, DEAD }

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
## Yolun kenarını az farkla kaçırıyorsak yola doğru hafif çekim
@export var landing_assist := 6.0
@export var assist_margin := 1.5

@export_group("Gaz")
## Tam gazda hız bu oran kadar artar
@export var boost_bonus := 0.6
## Gazın ekleyebileceği en fazla hız (m/s)
@export var boost_max_extra := 20.0
## Gazın tam güce çıkma ve sönme süreleri (sn)
@export var boost_rise_time := 0.7
@export var boost_fall_time := 1.2

@export_group("Uçuş")
## Alt katmanın uçuş yüksekliği
@export var flight_altitude := -55.0
## Son yoldan bu kadar metre aşağı düşünce düşüş başlar
@export var fall_trigger := 7.0
## Düşüş başladıktan kaç saniye sonra kanatlar açılır
@export var wing_delay := 0.35
## Kanatlar açılınca uçuş yüksekliğine dalış hızı
@export var dive_speed := 24.0
## Dalış sırasında ileri hız oranı
@export_range(0.0, 1.0) var dive_forward_scale := 0.4
@export var flight_steer_accel := 45.0
## Kanatsız düşerken uçuş yüksekliğinin bu kadar altı: uçurum
@export var abyss_depth := 30.0

var mode := Mode.DRIVE
var alive: bool:
	get:
		return mode != Mode.DEAD
## Temel hız (zamanla artar). Gerçek ileri hız için forward_speed
var speed := 0.0
## 0-1: gazın şu anki gücü
var boost_level := 0.0
## Oyuncu şu an gaza basıyor mu
var boosting := false
var forward_speed: float:
	get:
		return speed + boost_extra()
var half_length := 1.8
var roads: RoadGenerator
var autopilot: Autopilot
var air_time := 0.0
var last_floor_y := 0.0
var _was_on_floor := true
var _mode_time := 0.0
var _has_wings := true
var _steer := 0.0
var _debris: Array[Dictionary] = []
var _launch_target := Vector3.ZERO
var _launch_clear_y := 0.0
var _default_mask := 1
var _wing_tween: Tween
var _touches := {}  # dokunma index -> ekran x

@onready var _body: Node3D = $Body
@onready var _wing_l: Node3D = $Body/WingL
@onready var _wing_r: Node3D = $Body/WingR
@onready var _tail: Node3D = $Body/Tail


func _ready() -> void:
	speed = start_speed
	floor_snap_length = 0.4
	var box := ($Collision as CollisionShape3D).shape as BoxShape3D
	half_length = box.size.z * 0.5
	last_floor_y = global_position.y
	_default_mask = collision_mask
	_set_wings(false, true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position.x
		else:
			_touches.erase(event.index)
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position.x


func _physics_process(delta: float) -> void:
	if mode == Mode.DEAD:
		_dead_motion(delta)
		return
	_mode_time += delta
	speed = minf(speed + acceleration * delta, max_speed)
	var input := autopilot.input() if autopilot else _read_input()
	_steer = input.x
	boosting = input.y > 0.5
	_update_boost(delta)
	match mode:
		Mode.DRIVE:
			_drive(delta)
		Mode.FALLING:
			_falling(delta)
		Mode.FLYING:
			_flying(delta)
		Mode.LAUNCH:
			_launch(delta)
	if mode != Mode.DEAD:
		_update_visual(delta)


## Portala girince çağrılır: araba, target noktasındaki yola inecek şekilde fırlatılır.
## clear_y'nin üstüne çıkana kadar yana kaymaz (yolların içinden geçmemek için).
func launch_to(target: Vector3, clear_y: float) -> void:
	var t := maxf((global_position.z - target.z) / speed, 1.5)
	velocity = Vector3(0.0, (target.y - global_position.y + 0.5 * gravity * t * t) / t, -speed)
	_launch_target = target
	_launch_clear_y = clear_y
	collision_mask = 0
	_set_mode(Mode.LAUNCH)


## Kanat enerjisi bitti: kanatlar kapanır, uçuruma düşeriz
func lose_wings() -> void:
	_has_wings = false
	_set_mode(Mode.FALLING)


## Ekrandaki parmakları unut (ör. ayar paneli kapanınca)
func clear_touches() -> void:
	_touches.clear()


## Gaz tam güçteyken eklenen hız (level verilirse o güçteki)
func boost_extra(level := boost_level) -> float:
	return minf(speed * boost_bonus, boost_max_extra) * level


## Çarpıp patla: araba parçalara ayrılır, oyun biter
func crash(reason: String) -> void:
	if mode == Mode.DEAD:
		return
	_spawn_debris()
	_body.visible = false
	exploded.emit()
	_die(reason)


func _drive(delta: float) -> void:
	var on_floor := is_on_floor()
	var control := 1.0 if on_floor else air_control
	velocity.x = move_toward(velocity.x, _steer * steer_speed, steer_accel * control * delta)
	if on_floor:
		velocity.z = -forward_speed
	else:
		# Havada araba kalkıştaki hızıyla uçar
		velocity.y -= gravity * delta
		air_time += delta
		_apply_landing_assist(delta)

	var forward_before := -velocity.z
	move_and_slide()

	# Yolun ön yüzüne çakıldık (yeterince gaz verilmedi). İleri hızın aniden
	# kesilmesi de çarpma sayılır: köşeye değince normal çapraz gelebiliyor.
	if _hit_wall_front() or -velocity.z < forward_before * 0.5:
		crash("ÇAKILDIN!")
		return

	var now_on_floor := is_on_floor()
	if _was_on_floor and not now_on_floor and velocity.y <= 0.5:
		velocity.y = launch_velocity
		jumped.emit()
	if not _was_on_floor and now_on_floor:
		landed.emit(air_time)
	if now_on_floor:
		air_time = 0.0
		last_floor_y = global_position.y
	_was_on_floor = now_on_floor

	if global_position.y < last_floor_y - fall_trigger:
		_set_mode(Mode.FALLING)


func _falling(delta: float) -> void:
	velocity.y -= gravity * delta
	velocity.x = move_toward(velocity.x, _steer * steer_speed, steer_accel * air_control * delta)
	velocity.z = move_toward(velocity.z, -speed, 25.0 * delta)
	move_and_slide()
	if is_on_floor():
		_back_on_road()
	elif _has_wings and _mode_time >= wing_delay:
		_set_mode(Mode.FLYING)
	elif not _has_wings and global_position.y < flight_altitude - abyss_depth:
		_die("UÇURUMA DÜŞTÜN!")


func _flying(delta: float) -> void:
	var dy := flight_altitude - global_position.y
	var diving := dy < -3.0
	velocity.y = move_toward(velocity.y, clampf(dy * 2.0, -dive_speed, 8.0), 40.0 * delta)
	var forward := speed * dive_forward_scale if diving else forward_speed
	velocity.z = move_toward(velocity.z, -forward, 20.0 * delta)
	velocity.x = move_toward(velocity.x, _steer * steer_speed, flight_steer_accel * delta)
	move_and_slide()
	if is_on_floor():
		_back_on_road()


func _launch(delta: float) -> void:
	velocity.y -= gravity * delta
	velocity.z = -speed
	if global_position.y > _launch_clear_y:
		# Yolların üstüne çıktık: tepe noktasına kadar hedef yolun hizasına kay
		var t_apex := maxf(velocity.y / gravity, 0.05)
		velocity.x = clampf((_launch_target.x - global_position.x) / t_apex, -25.0, 25.0)
	move_and_slide()
	if velocity.y <= 0.0:
		velocity.x = 0.0
		collision_mask = _default_mask
		last_floor_y = _launch_target.y
		_was_on_floor = false
		air_time = 0.0
		_set_mode(Mode.DRIVE)


func _back_on_road() -> void:
	last_floor_y = global_position.y
	_was_on_floor = true
	_set_mode(Mode.DRIVE)
	landed.emit(air_time)
	air_time = 0.0


func _set_mode(m: Mode) -> void:
	if m == mode:
		return
	var previous := mode
	mode = m
	_mode_time = 0.0
	if m == Mode.FLYING:
		_set_wings(true)
	elif previous == Mode.FLYING:
		_set_wings(false)
	mode_changed.emit(m, previous)


func _die(reason: String) -> void:
	_set_mode(Mode.DEAD)
	died.emit(reason)


func _dead_motion(delta: float) -> void:
	if _debris.is_empty():
		# Uçuruma düşüş: araba düşmeye devam eder
		velocity.y -= gravity * delta
		position += velocity * delta
		return
	for d in _debris:
		var n: Node3D = d.node
		d.vel.y -= gravity * delta
		n.global_position += d.vel * delta
		n.rotate(d.axis, d.spin * delta)


## Yerde ve uçarken basılı tuttukça gaz dolar; yoldan havalanınca olduğu gibi kalır
func _update_boost(delta: float) -> void:
	if mode == Mode.DRIVE and not is_on_floor():
		return
	if boosting and (mode == Mode.DRIVE or mode == Mode.FLYING):
		boost_level = minf(boost_level + delta / boost_rise_time, 1.0)
	else:
		boost_level = maxf(boost_level - delta / boost_fall_time, 0.0)


## x: direksiyon (-1..1), y: gaz (0/1). İki yarıya birden basmak = gaz.
func _read_input() -> Vector2:
	var left := Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)
	var right := Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)
	var gas := Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_SPACE)
	var half := get_viewport().get_visible_rect().size.x * 0.5
	for x in _touches.values():
		if x < half:
			left = true
		else:
			right = true
	if gas or (left and right):
		return Vector2(0.0, 1.0)
	return Vector2(float(right) - float(left), 0.0)


func _hit_wall_front() -> bool:
	for i in get_slide_collision_count():
		if get_slide_collision(i).get_normal().z > 0.6:
			return true
	return false


## Havada, iniş noktası bir yolun kenarını az farkla kaçırıyorsa yola doğru çek
func _apply_landing_assist(delta: float) -> void:
	if roads == null:
		return
	var pos := global_position
	for s in roads.segments:
		if s.z_end >= pos.z or s.top >= pos.y - 0.05:
			continue
		var t := _time_to_fall_to(s.top)
		var land := pos + Vector3(velocity.x * t, 0, velocity.z * t)
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
	var forward := maxf(-velocity.z, 1.0)
	var yaw := -atan2(velocity.x, forward) * 0.8
	var pitch := 0.0 if is_on_floor() else atan2(velocity.y, forward) * 0.7
	var roll := -velocity.x / steer_speed * (0.45 if mode == Mode.FLYING else 0.08)
	if mode == Mode.FLYING:
		pitch += sin(Time.get_ticks_msec() * 0.003) * 0.04
	var w := 1.0 - exp(-10.0 * delta)
	_body.rotation = _body.rotation.lerp(Vector3(pitch, yaw, roll), w)


## Kanatları aç/kapa. Kapalıyken kanatlar yukarı katlanmış ve küçülmüş durur.
func _set_wings(open: bool, instant := false) -> void:
	if _wing_tween:
		_wing_tween.kill()
	var fold := PI * 0.5
	var targets := {
		_wing_l: Vector3(0, 0, 0.06 if open else -fold),
		_wing_r: Vector3(0, 0, -0.06 if open else fold),
		_tail: Vector3.ZERO,
	}
	var scale_to := Vector3.ONE if open else Vector3(0.05, 0.05, 0.05)
	if instant:
		for n: Node3D in targets:
			n.rotation = targets[n]
			n.scale = scale_to
			n.visible = open
		return
	_wing_tween = create_tween().set_parallel()
	for n: Node3D in targets:
		n.visible = true
		if open:
			n.scale = Vector3(0.3, 0.3, 0.3)
		_wing_tween.tween_property(n, "rotation", targets[n], 0.5 if open else 0.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_wing_tween.tween_property(n, "scale", scale_to, 0.35 if open else 0.3) \
			.set_trans(Tween.TRANS_BACK if open else Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if not open:
		_wing_tween.chain().tween_callback(func():
			for n: Node3D in targets:
				n.visible = false)


## Patlama: araba renklerinde küçük parçalar ve turuncu bir parlama
func _spawn_debris() -> void:
	var mats: Array[Material] = []
	for path in ["Body/Chassis", "Body/Cabin", "Body/WheelFL"]:
		mats.append((get_node(path) as MeshInstance3D).mesh.surface_get_material(0))
	var origin := global_position + Vector3(0, 0.6, 0)
	for i in 16:
		var piece := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(randf_range(0.2, 0.7), randf_range(0.15, 0.5), randf_range(0.2, 0.8))
		piece.mesh = box
		piece.material_override = mats[i % mats.size()]
		piece.top_level = true
		add_child(piece)
		piece.global_position = origin + Vector3(randf_range(-0.8, 0.8), randf_range(-0.3, 0.4), randf_range(-1.5, 1.5))
		_debris.append({
			"node": piece,
			"vel": Vector3(randf_range(-7, 7), randf_range(3, 11), randf_range(-2, 9)),
			"axis": (Vector3(randf(), randf(), randf()) + Vector3(0.1, 0, 0)).normalized(),
			"spin": randf_range(4, 12),
		})
	var flash_mat := StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.albedo_color = Color(Palette.ACCENT, 0.9)
	var flash := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radial_segments = 8
	ball.rings = 4
	flash.mesh = ball
	flash.material_override = flash_mat
	flash.top_level = true
	add_child(flash)
	flash.global_position = origin
	var light := OmniLight3D.new()
	light.light_color = Palette.ACCENT
	light.light_energy = 6.0
	light.omni_range = 14.0
	light.top_level = true
	add_child(light)
	light.global_position = origin + Vector3(0, 1, 0)
	var tw := create_tween().set_parallel()
	tw.tween_property(flash, "scale", Vector3.ONE * 7.0, 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(flash_mat, "albedo_color:a", 0.0, 0.35)
	tw.tween_property(light, "light_energy", 0.0, 0.5)
