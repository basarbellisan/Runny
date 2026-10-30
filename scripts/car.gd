class_name Car
extends CharacterBody3D
## Kendiliğinden ileri giden araba. Oyuncu sağ/sol yapar; iki parmakla
## (iki yarıya birden) basınca yolda gaz verir, uçarken yükselir.
## İki parmakla basarken direksiyon çalışmaz.
##
## Modlar:
##  DRIVE   – üst katmanda yolda (yolun sonunda hızıyla havaya fırlar)
##  FALLING – yoldan düştük, birkaç metre serbest düşüş
##  FLYING  – kanatlar açık, alt katmanda uçuş
##  LAUNCH  – portal bizi yukarı fırlattı, havada arabaya dönüyoruz
##  DEAD

## quality: 0 = temiz iniş, 1 = çok sert/yamuk iniş; impact: dikey çarpma hızı (m/s)
signal landed(air_time: float, quality: float, impact: float)
## Yolun sonundan havaya fırladık
signal jumped
## Bir yere çarpıp patladık
signal exploded
## Roket gaz ateşlendi (yakıt varken gaza basıldı)
signal boosted
## Enerji yokken gaza basıldı (roket yanmadı)
signal boost_empty
signal mode_changed(mode: Mode, previous: Mode)
signal died(reason: String)

enum Mode { DRIVE, FALLING, FLYING, LAUNCH, DEAD }

@export var start_speed := 40.0  # 144 km/sa
@export var max_speed := 80.0
## En yüksek hıza varınca hız yavaşça artmaya devam eder (m/s, her saniye), top_speed'e kadar
@export var late_acceleration := 0.15
@export var top_speed := 80.0
## Saniyede hız artışı (m/s)
@export var acceleration := 1.5
@export var steer_speed := 11.0
@export var steer_accel := 85.0
## Havadayken direksiyonun etkisi (0-1)
@export_range(0.0, 1.0) var air_control := 0.8
@export var gravity := 28.0
## Yolun kenarından çıkarken verilen küçük yukarı itiş
@export var launch_velocity := 8.0
## Yolun kenarını az farkla kaçırıyorsak yola doğru hafif çekim (0: kapalı)
@export var landing_assist := 0.0
@export var assist_margin := 1.5

@export_group("Tekerler")
## Bir yanın tekerleri boşluğa çıkınca arabayı o yana çeken kuvvet (m/s²)
@export var tip_pull := 12.0
## Boşluktaki her teker için direksiyon tutuşu kaybı (0-1)
@export var grip_loss := 0.2
## Süspansiyon: tekerin aşağı sarkabileceği mesafe (m)
@export var suspension_travel := 0.42
## Süspansiyon yayı ve sönümü (gövdenin yatma/kalkma salınımı)
@export var suspension_stiffness := 80.0
@export var suspension_damping := 8.0
## Bir yanın iki tekeri boşta: araba kenarın üstünden devrilir (rad/sn²)
@export var tip_roll_accel := 9.0
## Ön tekerler boşta (yolun sonu): burun düşer (rad/sn²)
@export var nose_drop_accel := 5.0
## Roket ateşlenince burun kalkar (G kuvveti): yanarken burun açısı (°) ve ilk vuruş
@export var boost_squat_deg := 12.0
@export var boost_kick := 1.4

@export_group("Havada")
## Havada direksiyon arabayı o yana yatırır (en fazla bu kadar derece)
@export var air_lean_deg := 40.0
## Direksiyon bırakılınca yatmanın sönme süresi (sn)
@export var air_lean_time := 0.35
## Havada kendiliğinden düzelme (1/sn). 0: hiç yardım yok
@export var air_self_level := 0.0

@export_group("İniş")
## Bu açıdan (derece) az sapmayla inersen temiz iniş
@export var clean_landing_deg := 2.0
## Bu açıdan fazla yan/ters inersen araba patlar
@export var crash_landing_deg := 75.0
## Bu dikey hızın üstünde (m/s) düzgün inişte bile sendeleme başlar
@export var hard_impact := 24.0

@export_group("Gaz")
## Roket gaz: kısa ve çok güçlü. Tam gazda hız bu oran kadar artar
@export var boost_bonus := 1.35
## Gazın ekleyebileceği en fazla hız (m/s)
@export var boost_max_extra := 45.0
## Gazın tam güce çıkma ve sönme süreleri (sn)
@export var boost_rise_time := 0.5
@export var boost_fall_time := 0.35
## Dolu yakıtla gaz bu kadar saniye yanar; erken basan yolun sonuna yakıtsız varır
@export var boost_burn_time := 1.35
## Yolda, gaza basmazken yakıtın boştan dolma süresi (sn)
@export var boost_recharge_time := 1.6
## Enerji: roket ve kanatlar bunu harcar, yalnız kristallerden dolar
@export var max_energy := 100.0
## Roket yanarken saniyede harcanan enerji
@export var boost_energy_rate := 45.0

@export_group("Zemin")
## Çakılda ileri hız bu orana düşer, direksiyon tutuşu bu orana iner
@export var gravel_speed := 0.8
@export var gravel_grip := 0.05
## Çakılda arabayı sağa sola savuran itiş (m/s²) ve çakıldan çıkınca süren sendeleme (sn)
@export var gravel_shove := 30.0
@export var gravel_after := 1.3
## Çakıl etkisi hızla artar: en yüksek hızda savurma bu kat güçlü
@export var gravel_speed_gain := 1.4
## Arka savrulma (görsel): çakılda burun sağa sola bu kadar döner (rad)
@export var gravel_fishtail := 0.22

@export_group("Tümsek")
## Tümsek tepesinden kalkışta: eğimin verdiği dikey hızın katı ve sarsıntı gücü
@export var bump_launch := 1.4
@export var bump_shake := 2.6
## Yatık yolda araba alçak tarafa kayar: yatma açısının sinüsü × bu hız (m/s)
@export var bank_slide := 45.0

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
## Uçarken iki parmakla uçuş yüksekliğinin en fazla bu kadar üstüne çıkılır (m)
@export var climb_height := 8.5
## Yükselme hızı (m/s)
@export var climb_speed := 9.0
## Kanatsız düşerken uçuş yüksekliğinin bu kadar altı: uçurum
@export var abyss_depth := 30.0
## Açık kanatların yandan uzanabildiği mesafe (duvar kontrolü için)
@export var wing_half_span := 3.6
## Gövde yolun içine girmesin (devrilirken, takla atarken, kenardan düşerken)
@export var hull_guard := true

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
## Roket yakıtı (0-1): bir basışta en çok boost_burn_time yanar, bırakınca dolar
var fuel := 1.0
## Enerji (0-max_energy): roket ve kanatlar harcar, kristaller doldurur
var energy := 100.0
var _empty_signaled := false
## Roket şu an yanıyor mu
var burning := false
## Çakılın üstündeyiz
var on_gravel := false
## Çakılın savurması: yavaş değişen yana itiş
var _gravel_push := 0.0
var _gravel_push_target := 0.0
var _gravel_timer := 0.0
## Zeminin ileri hıza etkisi (1: asfalt)
var surface_drag := 1.0
## Altımızdaki yolun yana yatıklığı (rad, artı = sağ kenar yukarı)
var surface_roll := 0.0
## Uçarken iki parmak: yükseliyor muyuz
var climbing: bool:
	get:
		return boosting and mode == Mode.FLYING
var forward_speed: float:
	get:
		return speed + boost_extra()
var half_length := 1.8
var roads: RoadGenerator
var autopilot: Autopilot
var trail: CarTrail
var model: CarModel
## Tekerlerin yerle teması (sırası: ön sol, ön sağ, arka sol, arka sağ)
var wheel_contact: Array[bool] = [true, true, true, true]
var _wheel_ground: Array[float] = [0.0, 0.0, 0.0, 0.0]
## Her tekerin altındaki rampanın (yol üstü) yüksekliği, rampa yoksa 0; sıra: 0,2 sol, 1,3 sağ
var _ramp_lift: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _wheel_ramp: RoadGenerator.Segment
## Yarım rampa: omurga yolda ama bir yanın tekerleri rampada (o yan yükselir)
var _partial: RoadGenerator.Segment
var _partial_side := 0.0
var _partial_frac := 0.0
## Yarım rampada gövdenin yatması (rampadaki yan yukarıda)
var _side_tilt := 0.0
## Yarım rampada gövdenin yükselmesi: bir yan h kalkınca ağırlık merkezi h/2 kalkar
var _part_lift := 0.0
## -1..1: yan yatma (eksi: sol taraf boşta)
var _tip := 0.0
## 0..1: ön tekerler boşta
var _nose := 0.0
var _bounce := 0.0
var _bounce_v := 0.0
## Gövdenin gerçek duruşu (rad): pitch artı = burun yukarı, roll eksi = sağ yan aşağı
var pitch := 0.0
var roll := 0.0
var pitch_rate := 0.0
var roll_rate := 0.0
## Havada direksiyonun verdiği yatma (roll'un içinde)
var _air_lean := 0.0
## İnişten sonra sendeleme: kalan süre ve şiddet
var _stumble_time := 0.0
var _stumble := 0.0
var _yaw := 0.0
var _fishtail := 0.0
## Eğik rampadan atıldıktan sonra yana hızın korunduğu süre (yere değince biter)
var _kick_hold := 0.0
## Yerde ileri gidemediğimiz süre (fizik motoru yatık yol yüzeyinde takabiliyor)
var _stuck_time := 0.0
## Tümsekten fırlarken kısa bir süre zemine yapışma kapalı
var _snap_off := 0.0
var fx: CarFx
var _wheel_spin := 0.0
var _last_segment: RoadGenerator.Segment
var air_time := 0.0
var last_floor_y := 0.0
var _was_on_floor := true
var _mode_time := 0.0
var _has_wings := true
var _steer := 0.0
var _debris: Array[Dictionary] = []
var _launch_target := Vector3.ZERO
var _launch_clear_y := 0.0
## Portal tüneli: araba önce bu çizgi boyunca kayar, sonra fırlatılır
var _tube: PackedVector3Array = []
var _tube_i := 0
## Kanat yedeği: depo bitince açılır (kanat uçlarından iz), yanınca kanatlar kapanır
var reserve := 0.0
var reserve_max := 15.0
var reserve_on := false
var _launch_vz := 0.0
## Gövdenin dış noktaları (Body'ye göre; model değişince yeniden hesaplanır)
var _hull_body := PackedVector3Array()
var _hull_wheels := PackedVector3Array()
var _hull_model := -1
## Gövdenin yolun içine girmemesi için görsel kaldırma (m)
var _hull_lift := 0.0
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
	# Omurga: boyuna yatık ince kapsül. Altı yuvarlak olduğu için kıvrılan (yatık)
	# yol yüzeyinin üçgen kenarlarına takılmaz.
	var keel := ($Collision as CollisionShape3D).shape as CapsuleShape3D
	half_length = keel.height * 0.5
	last_floor_y = global_position.y
	_default_mask = collision_mask
	_set_wings(false, true)
	trail = CarTrail.new()
	add_child(trail)
	fx = CarFx.new()
	add_child(fx)
	model = $Body/Model


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
	if speed < max_speed:
		speed = minf(speed + acceleration * delta, max_speed)
	else:
		speed = minf(speed + late_acceleration * delta, maxf(top_speed, max_speed))
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
## tube verilirse önce tünelin içinden (yukarı kıvrılarak) geçer, ucundan fırlar.
func launch_to(target: Vector3, clear_y: float, tube := PackedVector3Array()) -> void:
	_launch_target = target
	_launch_clear_y = clear_y
	collision_mask = 0
	_tube = tube
	_tube_i = 0
	if _tube.is_empty():
		_ballistic_to(target, clear_y)
	_set_mode(Mode.LAUNCH)


## Kanat yedeğini aç (depo bitti)
func start_reserve(amount: float) -> void:
	reserve = amount
	reserve_max = maxf(amount, 0.01)
	reserve_on = true


func _ballistic_to(target: Vector3, clear_y: float) -> void:
	var y := global_position.y
	var dist := global_position.z - target.z
	var t := maxf(dist / speed, 1.5)
	var vy := (target.y - y + 0.5 * gravity * t * t) / t
	# Tepe noktası yolların hizasının epey üstünde olsun ki yana kayacak vakit kalsın
	# (hedef alçak bir yolsa fırlatma daha dik olur, ileri hız biraz düşer)
	var apex_min := clear_y + 4.0
	if y + vy * vy / (2.0 * gravity) < apex_min:
		vy = sqrt(2.0 * gravity * (apex_min - y))
		t = (vy + sqrt(maxf(vy * vy - 2.0 * gravity * (target.y - y), 0.0))) / gravity
	_launch_vz = -dist / t
	velocity = Vector3(0.0, vy, _launch_vz)


## Kanat enerjisi bitti: kanatlar kapanır, uçuruma düşeriz
func lose_wings() -> void:
	_has_wings = false
	_set_mode(Mode.FALLING)


## Ekrandaki parmakları unut (ör. ayar paneli kapanınca)
func clear_touches() -> void:
	_touches.clear()


## Gaz tam güçteyken eklenen hız (level verilirse o güçteki)
func boost_extra(level := boost_level) -> float:
	# Yumuşak giriş: hız birden atmaz, ~0.2 sn'de ivmelenerek tam güce çıkar
	var eased := level * level * (3.0 - 2.0 * level)
	return minf(speed * boost_bonus, boost_max_extra) * eased


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
	_sense_wheels()
	var control := 1.0 if on_floor else air_control
	if on_floor:
		# Boşluktaki tekerler: tutuş azalır, araba boş tarafa doğru yatar ve çekilir
		var left_off := int(not wheel_contact[0]) + int(not wheel_contact[2])
		var right_off := int(not wheel_contact[1]) + int(not wheel_contact[3])
		_tip = (right_off - left_off) * 0.5
		_nose = (int(not wheel_contact[0]) + int(not wheel_contact[1])) * 0.5
		control *= 1.0 - grip_loss * (left_off + right_off)
		on_gravel = roads != null and roads.gravel_at(global_position)
		if on_gravel:
			control *= gravel_grip
			# Taşlar arabayı sağa sola savurur (her ~0.25 sn yön değişir), gövdeyi sarsar
			_gravel_timer -= delta
			if _gravel_timer <= 0.0:
				_gravel_timer = randf_range(0.15, 0.35)
				_gravel_push_target = randf_range(-1.0, 1.0) * gravel_shove * _gravel_gain()
			_bounce_v += randf_range(-1.0, 1.0) * 70.0 * delta * _gravel_gain()
			roll_rate += randf_range(-1.0, 1.0) * 14.0 * delta * _gravel_gain()
			# Çakıldan çıkınca da bir süre sendeler
			_stumble = maxf(_stumble if _stumble_time > 0.0 else 0.0, 0.45)
			_stumble_time = maxf(_stumble_time, gravel_after)
		else:
			_gravel_push_target = 0.0
		_gravel_push = lerpf(_gravel_push, _gravel_push_target, 1.0 - exp(-8.0 * delta))
		velocity.x += _gravel_push * delta
		# Sert inişten sonra araba sendeler: tutuş azalır, gövde yana savrulur
		if _stumble_time > 0.0:
			_stumble_time -= delta
			control *= 1.0 - 0.8 * _stumble
			velocity.x += randf_range(-1.0, 1.0) * 18.0 * _stumble * delta
		if _tip != 0.0:
			velocity.x += _tip * tip_pull * delta + randf_range(-3.0, 3.0) * absf(_tip) * delta
		# Son üstünde olunan yol (yolun ucunu geçerken sorgu boş dönebilir; eskisi kalsın)
		var under: RoadGenerator.Segment = roads.segment_under(global_position) if roads else null
		if under:
			# Tümsek tepesi: yokuş parçasından inişe geçtik. Zemine yapışma (snap) arabayı
			# yüzeyde tutacağından fırlatmayı burada kendimiz veririz; gövde sarsılır.
			if _last_segment and _last_segment.next_flush == under and _last_segment.slope() > 0.04:
				velocity.y = forward_speed * _last_segment.slope() * bump_launch + 1.0
				# Havada dönme sürer: yatma ve burun vuruşu ölçülü (havada toparlanabilsin)
				roll_rate += randf_range(-1.0, 1.0) * bump_shake * 0.3
				pitch_rate += randf_range(0.05, 0.15) * bump_shake
				velocity.x += randf_range(-1.0, 1.0) * bump_shake
				_bounce_v -= 1.5
				_snap_off = 0.15
				jumped.emit()
			_last_segment = under
	# Yatık yolda araba kendiliğinden alçak tarafa kayar: ters direksiyonla yolda tut
	var slide := 0.0
	if on_floor:
		var fn := get_floor_normal()
		surface_roll = atan2(-fn.x, fn.y)
		slide = fn.x * bank_slide
	else:
		surface_roll = 0.0
	if _kick_hold > 0.0 and not on_floor:
		# Eğik rampadan atıldık: yana hız korunur; direksiyon yalnız ona ekler ya da ters basınca keser
		_kick_hold -= delta
		if _steer != 0.0 and signf(_steer) != signf(velocity.x):
			velocity.x = move_toward(velocity.x, _steer * steer_speed, steer_accel * control * delta)
		elif _steer != 0.0:
			velocity.x = move_toward(velocity.x, signf(_steer) * maxf(absf(velocity.x), steer_speed), steer_accel * control * delta)
	else:
		if on_floor and _kick_hold > 0.0:
			# Eğik rampa inişi: lastikler tutar, yana kalan hız çoğunlukla söner (kısa adadan kaymasın)
			_kick_hold = 0.0
			velocity.x *= 0.35
		velocity.x = move_toward(velocity.x, _steer * steer_speed + slide, steer_accel * control * delta)
	surface_drag = move_toward(surface_drag, gravel_speed if on_gravel and on_floor else 1.0,
		delta * (1.5 if on_gravel else 1.4))
	if on_floor:
		velocity.z = -forward_speed * surface_drag
	else:
		# Havada araba kalkıştaki hızıyla uçar
		velocity.y -= gravity * delta
		air_time += delta
		_apply_landing_assist(delta)

	var forward_before := -velocity.z
	var vy_before := velocity.y
	_snap_off = maxf(_snap_off - delta, 0.0)
	floor_snap_length = 0.0 if _snap_off > 0.0 else 0.4
	move_and_slide()

	# Yolun ön yüzüne çakıldık (yeterince gaz verilmedi). İleri hızın aniden
	# kesilmesi de çarpma sayılır: köşeye değince normal çapraz gelebiliyor.
	# (Yalnız zemine değiyorsak sayılmaz: kıvrılan yatık yol yüzeyinde fizik
	# motoru bazen bir karelik hızı sıfırlıyor, bir sonraki karede düzeliyor.)
	var hit_side := false
	for i in get_slide_collision_count():
		if absf(get_slide_collision(i).get_normal().y) < 0.7:
			hit_side = true
	if _hit_wall_front() or (hit_side and -velocity.z < forward_before * 0.5):
		crash("ÇAKILDIN!")
		return
	if _keep_out_of_walls():
		return
	# Yatık yolun üçgenli yüzeyinde fizik motoru arabayı bazen bir noktaya takıyor
	# (duvar değil, zemin): ~0.12 sn ileri gidemiyorsak hafifçe kaldır ve ileri it
	var want := forward_speed * surface_drag
	if is_on_floor() and _mode_time > 0.3 and want > 5.0 and -get_real_velocity().z < want * 0.3:
		_stuck_time += delta
		if _stuck_time > 0.12:
			global_position += Vector3(0.0, 0.12, -want * delta)
			_stuck_time = 0.0
	else:
		_stuck_time = 0.0

	_partial_ramp()

	var now_on_floor := is_on_floor()
	if _was_on_floor and not now_on_floor and _left_through_end():
		# Yolun sonundan çıktık: hızla havalan, rampanın açısı da dikey hıza eklenir.
		# Yandan kayınca zıplama yok, düşülür.
		var slope := _last_segment.slope() if _last_segment else 0.0
		if _last_segment and _last_segment.next_flush:
			# Yol bitmedi, bitişik parçası var. Tümsek tepesi: fırlar, gövde sarsılır
			# (toparlamak gerekir). Daralmada boşta kalan kenar: zıplama yok, düşülür.
			velocity.y = maxf(velocity.y, forward_speed * slope)
		else:
			velocity.y = launch_velocity + forward_speed * slope
			# Yol üstü eğik rampa yana da atar
			if _last_segment and _last_segment.ramp:
				velocity.x += _last_segment.kick
				# Uçuş boyunca bu yana hız sönmesin
				_kick_hold = 2.0 if _last_segment.kick != 0.0 else 0.0
				# Rampanın burgusu gövdeyi döndürmüş olur; havada takla attırmasın
				roll_rate *= 0.15
				# Bir yanın tekerleri rampanın dışında kaldıysa o yan desteksiz: o yana yatarak uçar
				var off_l := int(_ramp_lift[0] <= 0.0) + int(_ramp_lift[2] <= 0.0)
				var off_r := int(_ramp_lift[1] <= 0.0) + int(_ramp_lift[3] <= 0.0)
				if off_l != off_r:
					roll_rate += (1.0 if off_l > off_r else -1.0) * 0.45 * absf(off_l - off_r)
			jumped.emit()
	if not _was_on_floor and now_on_floor:
		if not _touchdown(vy_before):
			return
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
	var vy_before := velocity.y
	move_and_slide()
	_keep_out_of_walls()
	if is_on_floor():
		_back_on_road(vy_before)
	elif _has_wings and _mode_time >= wing_delay:
		_set_mode(Mode.FLYING)
	elif not _has_wings and global_position.y < flight_altitude - abyss_depth:
		_die("UÇURUMA DÜŞTÜN!")


func _flying(delta: float) -> void:
	# İki parmak: yüksel; bırakınca uçuş yüksekliğine süzül
	var target := flight_altitude + (climb_height if climbing else 0.0)
	var dy := target - global_position.y
	# Yukarıdan ilk dalış (alt katmana iniş) sırasında ileri hız düşük
	var diving := global_position.y > flight_altitude + climb_height + 2.0
	velocity.y = move_toward(velocity.y, clampf(dy * 2.0, -dive_speed, climb_speed), 40.0 * delta)
	var forward := speed * dive_forward_scale if diving else speed
	velocity.z = move_toward(velocity.z, -forward, 20.0 * delta)
	velocity.x = move_toward(velocity.x, _steer * steer_speed, flight_steer_accel * delta)
	var vy_before := velocity.y
	move_and_slide()
	_keep_out_of_walls()
	if is_on_floor():
		_back_on_road(vy_before)


func _launch(delta: float) -> void:
	if not _tube.is_empty():
		# Tünelin içinde: çizgi boyunca kay (direksiyon yok), ucunda fırla
		var step := maxf(speed, 40.0) * delta
		var p := global_position
		while step > 0.0 and _tube_i < _tube.size():
			var to := _tube[_tube_i] - p
			if to.length() <= step:
				p = _tube[_tube_i]
				step -= to.length()
				_tube_i += 1
			else:
				p += to.normalized() * step
				step = 0.0
		var dir := (p - global_position).normalized() if p != global_position else Vector3.FORWARD
		velocity = dir * maxf(speed, 40.0)
		global_position = p
		if _tube_i >= _tube.size():
			_tube = PackedVector3Array()
			_ballistic_to(_launch_target, _launch_clear_y)
		return
	velocity.y -= gravity * delta
	velocity.z = _launch_vz
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


func _back_on_road(vy_before: float) -> void:
	_tip = 0.0
	last_floor_y = global_position.y
	_was_on_floor = true
	_set_mode(Mode.DRIVE)
	_touchdown(vy_before)


## Tekerler yere değdi: duruşa ve çarpma hızına göre iniş kalitesi.
## Yan ya da ters inersek patlarız (false döner).
func _touchdown(vy_before: float) -> bool:
	var impact := maxf(-vy_before, 0.0)
	var n := get_floor_normal()
	var surface := atan2(n.z, n.y)
	var roll_err := absf(wrapf(roll - atan2(-n.x, n.y), -PI, PI))
	var pitch_err := absf(wrapf(pitch - surface, -PI, PI))
	# Burun/kuyruk sapması yan yatmadan daha az önemli (önce bir aks değer, öbürü iner)
	var err := rad_to_deg(maxf(roll_err, pitch_err * 0.5))
	if err > crash_landing_deg:
		crash("TAKLA ATTIN!" if roll_err > pitch_err else "ÇAKILDIN!")
		return false
	var quality := clampf((err - clean_landing_deg) / 40.0, 0.0, 1.0) \
		+ clampf((impact - hard_impact) / 25.0, 0.0, 0.6)
	quality = minf(quality, 1.0)
	# Süspansiyon çöker; yamuk inişte ilk değen yan/aks sert yaylanır
	_bounce_v = -minf(1.2 + impact * 0.13, 5.0)
	pitch_rate *= 0.3
	roll_rate *= 0.3
	if quality > 0.05:
		_stumble = quality
		_stumble_time = 0.35 + 0.9 * quality
		# İlk değen (alçak) yana doğru savrul
		var side := -signf(roll) if absf(roll) > 0.05 else (1.0 if randf() < 0.5 else -1.0)
		velocity.x += side * 5.0 * quality
		boost_level *= 1.0 - quality
		roll_rate += -side * 3.0 * quality
	_landing_fx(impact, quality)
	landed.emit(air_time, quality, impact)
	air_time = 0.0
	return true


func _landing_fx(impact: float, quality: float) -> void:
	if fx == null or model == null:
		return
	var strength := clampf(impact / 25.0 + quality, 0.0, 1.5)
	if strength < 0.15:
		return
	var wheels: Array = [2, 3] if quality < 0.3 else [0, 1, 2, 3]
	for i in wheels:
		var c: Vector3 = model.wheels[i].contact
		fx.dust(global_position + Vector3(c.x, 0.1, c.z), strength)
	# Gövde yere vurdu: kıvılcım
	if quality > 0.3 or impact > hard_impact + 4.0:
		fx.sparks(global_position + Vector3(0, 0.15, 0), strength)


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
	if m != Mode.FLYING:
		reserve_on = false
	# Yarım rampa durumu yalnız yolda sürerken geçerli
	_partial = null
	_side_tilt = 0.0
	_part_lift = 0.0
	mode_changed.emit(m, previous)


func _die(reason: String) -> void:
	_set_mode(Mode.DEAD)
	died.emit(reason)


func _dead_motion(delta: float) -> void:
	# Patladıysak parçalar kendi fiziğiyle hareket eder; değilse uçuruma düşüş
	if not _debris.is_empty():
		return
	velocity.y -= gravity * delta
	position += velocity * delta


## Yerde ve uçarken basılı tuttukça gaz dolar; yoldan havalanınca olduğu gibi kalır
func _update_boost(delta: float) -> void:
	if mode == Mode.DRIVE and not is_on_floor():
		return
	var was_burning := burning
	# Yol üstü rampalar gaz istemez: üstlerinde roket ateşlenmez
	var on_ramp := _last_segment != null and _last_segment.ramp
	burning = boosting and mode == Mode.DRIVE and fuel > 0.0 and energy > 0.0 and not on_ramp
	if mode == Mode.DRIVE:
		if burning:
			fuel = maxf(fuel - delta / boost_burn_time, 0.0)
			energy = maxf(energy - boost_energy_rate * delta, 0.0)
		elif not boosting:
			fuel = minf(fuel + delta / boost_recharge_time, 1.0)
		if boosting and energy <= 0.0 and not on_ramp and not _empty_signaled:
			_empty_signaled = true
			boost_empty.emit()
	if not boosting:
		_empty_signaled = false
	if burning and not was_burning:
		# Vum: arka çöker, burun havaya kalkar
		pitch_rate += boost_kick
		_bounce_v -= 0.6
		boosted.emit()
	if burning:
		boost_level = minf(boost_level + delta / boost_rise_time, 1.0)
	else:
		boost_level = maxf(boost_level - delta / boost_fall_time, 0.0)
	if fx:
		fx.gravel(on_gravel and is_on_floor(), global_position + Vector3(0, 0.15, 1.0))


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


## Her tekerin altında yol var mı (ışın ile)
func _sense_wheels() -> void:
	if model == null or collision_mask == 0:
		return
	var space := get_world_3d().direct_space_state
	var origin := global_position
	# Yokuşta düz gövde yüzeyin üstünde kalır: ışın eğim kadar uzun olsun
	var reach := 0.6
	if _last_segment:
		reach += absf(_last_segment.slope()) * 2.5
	for i in model.wheels.size():
		var c: Vector3 = model.wheels[i].contact
		var q := PhysicsRayQueryParameters3D.create(origin + c + Vector3(0, 0.5, 0),
			origin + c - Vector3(0, reach, 0), _default_mask, [get_rid()])
		var hit := space.intersect_ray(q)
		wheel_contact[i] = not hit.is_empty()
		_wheel_ground[i] = hit.position.y - origin.y if wheel_contact[i] else -INF
	# Tekerlerin altındaki rampalar (yarım girişte bir yan rampaya çıkar)
	_wheel_ramp = null
	for i in 4:
		_ramp_lift[i] = 0.0
	if roads == null or mode != Mode.DRIVE:
		return
	for s in roads.segments:
		if not s.ramp or s.z_start < origin.z - 6.0 or s.z_end > origin.z + 6.0:
			continue
		for i in model.wheels.size():
			var p: Vector3 = origin + model.wheels[i].contact
			if absf(p.x - s.x) < s.width * 0.5 and p.z <= s.z_start and p.z >= s.z_end:
				_ramp_lift[i] = maxf(_ramp_lift[i], s.top_at(p.z) - origin.y)
				_wheel_ramp = s
				# Işın rampanın içinden başlayıp alttaki yolu bulabilir: teker rampanın üstündedir
				_wheel_ground[i] = maxf(_wheel_ground[i], _ramp_lift[i])


## Yoldan önden mi (yolun sonu) yoksa yandan mı çıktık
## Çakıl etkisinin hıza göre katı (başlangıç hızında 1)
func _gravel_gain() -> float:
	return lerpf(1.0, gravel_speed_gain, clampf(inverse_lerp(start_speed, max_speed, speed), 0.0, 1.0))


func add_energy(amount: float) -> void:
	energy = clampf(energy + amount, 0.0, max_energy)


## Yarım rampa: omurga yolda, bir yanın tekerleri rampada. O yan yükselir (gövde yatar);
## rampanın ucunda yalnız o yan fırlar: araba yana dönerek ve rampadan uzağa savrularak
## uçar. Havada direksiyonla düzeltilebilir, düzeltilmezse yan inilir.
func _partial_ramp() -> void:
	var hl := maxf(_ramp_lift[0], _ramp_lift[2])
	var hr := maxf(_ramp_lift[1], _ramp_lift[3])
	var track := maxf(model.half_width * 2.0, 1.0) if model else 2.2
	# Omurga (ince kapsül) rampanın üstünde mi: öyleyse araba rampaya tam girmiştir
	var w := _wheel_ramp
	var capsule_on_ramp := w != null and absf(global_position.x - w.x) < w.width * 0.5 + 0.25
	if is_on_floor() and not capsule_on_ramp and w != null and maxf(hl, hr) > 0.05:
		if _partial != w:
			_partial_frac = 0.0
		_partial = w
		_partial_side = signf(hr - hl)
		# Rampaya çıkan yanın kaç tekeri oldu (ikisi de çıktıysa tam etki)
		var n := 0
		for i in 4:
			n += int(_ramp_lift[i] > 0.05)
		_partial_frac = maxf(_partial_frac, clampf(n / 2.0, 0.5, 1.0))
		_side_tilt = atan2(hr - hl, track)
		_part_lift = maxf(hl, hr) * 0.5
		return
	_side_tilt = 0.0
	if _partial == null:
		_part_lift = move_toward(_part_lift, 0.0, get_physics_process_delta_time() * 3.0)
		return
	var r := _partial
	_partial = null
	# Tekerler rampanın ucundan çıktı (yanından değil): rampadaki yan fırlar
	if is_on_floor() and global_position.z < r.z_end + half_length + 1.5:
		# Rampadaki yan, tam girişteki dikey hızla ayrılır; öbür yan yolda kalır.
		# Ağırlık merkezi bunun yarısıyla kalkar, fark gövdeyi öbür yana döndürür.
		var vy := launch_velocity + forward_speed * r.slope()
		var f := _partial_frac
		velocity.y = maxf(velocity.y, vy * 0.5 * f)
		roll_rate += _partial_side * clampf(vy / track * 0.3, 1.0, 2.4) * f
		# Rampa kenarından itilir: rampadan uzağa savrulur
		velocity.x += -_partial_side * vy * 0.15 * f + r.kick * 0.5 * f
		if r.kick != 0.0:
			_kick_hold = 2.0
		# Gövde zaten yarı yükseklikte: kalkışta yere çekilmesin, görsel sıçramasın
		global_position.y += _part_lift
		_part_lift = 0.0
		_snap_off = 0.25
		jumped.emit()


func _left_through_end() -> bool:
	if _last_segment == null:
		return true
	return global_position.z < _last_segment.z_end + half_length + 0.5 \
		and absf(global_position.x - _last_segment.x) < _last_segment.width * 0.5


## Çarpışma omurgası dar (ağırlık merkezi kuralı için); gövdenin, tekerlerin ve
## uçarken kanatların duvarlara girmemesini yan ve ön ışınlarla sağlar.
## Yolda giderken ön köşe bir yolun ön yüzüne girerse çakılır (true döner).
func _keep_out_of_walls() -> bool:
	if model == null or collision_mask == 0:
		return false
	var space := get_world_3d().direct_space_state
	var hw := wing_half_span if mode == Mode.FLYING else model.half_width
	var hl := half_length
	var pos := global_position
	var push := 0.0
	for side in [-1.0, 1.0]:
		var depth := 0.0
		for z in [-hl + 0.3, 0.0, hl - 0.3]:
			for y in [0.45, 0.9]:
				var from := pos + Vector3(0, y, z)
				var hit := _ray(space, from, from + Vector3(side * (hw + 0.05), 0, 0))
				# Rampanın yanı duvar değil: yarım girişte teker üstüne çıkar
				if not hit.is_empty() and not (hit.collider as Node).has_meta("ramp"):
					depth = maxf(depth, hw - absf(hit.position.x - pos.x))
		if depth > 0.0:
			push -= side * depth
			if velocity.x * side > 0.0:
				velocity.x = 0.0
	if push != 0.0:
		global_position.x += push

	var reach := 0.3 + maxf(-velocity.z, 0.0) * get_physics_process_delta_time()
	for x in [-hw + 0.15, hw - 0.15]:
		for y in [0.3, 0.9]:
			var from := pos + Vector3(x, y, -hl + 0.4)
			var hit := _ray(space, from, from - Vector3(0, 0, 0.4 + reach))
			if hit.is_empty() or hit.normal.z < 0.6 or (hit.collider as Node).has_meta("ramp"):
				continue
			if mode == Mode.DRIVE:
				crash("ÇAKILDIN!")
				return true
			# Düşerken/uçarken: duvarın önünde dur, içine girme
			velocity.z = maxf(velocity.z, 0.0)
			global_position.z = maxf(global_position.z, hit.position.z + hl + 0.02)
	return false


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, _default_mask, [get_rid()]))


func _hit_wall_front() -> bool:
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		# Kenara yukarıdan değmek (normal çoğunlukla yukarı) iniş sayılır, çarpma değil
		if n.z > 0.6 and n.y < 0.7:
			return true
	return false


## Havada, iniş noktası bir yolun kenarını az farkla kaçırıyorsa yola doğru çek
func _apply_landing_assist(delta: float) -> void:
	if roads == null:
		return
	var pos := global_position
	for s in roads.segments:
		var s_top: float = s.top_at(pos.z)
		if s.z_end >= pos.z or s_top >= pos.y - 0.05:
			continue
		var t := _time_to_fall_to(s_top)
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
	_update_attitude(delta)
	var forward := maxf(-velocity.z, 1.0)
	# Çakılda arka savrulur: itişle birlikte burun sağa sola döner, üstüne titrek bir sallanma
	_fishtail = move_toward(_fishtail, 1.0 if on_gravel and is_on_floor() else 0.0, delta * (4.0 if on_gravel else 1.5))
	var wag := sin(_mode_time * 11.0) * gravel_fishtail * _fishtail * _gravel_gain() * 0.6
	var yaw_target := -atan2(velocity.x, forward) * 0.8 - _gravel_push * 0.012 + wag
	if mode == Mode.FLYING or mode == Mode.LAUNCH:
		# Uçarken burun hep ileri bakar, dönüşü yatma gösterir: dalışta ileri hız düşük
		# olsa da burun yana dönmesin (düşerken kalan açı da hemen düzelir)
		yaw_target = clampf(-atan2(velocity.x, maxf(forward, speed)) * 0.45, -0.26, 0.26)
	_yaw = lerpf(_yaw, yaw_target, 1.0 - exp(-10.0 * delta))
	_body.rotation = Vector3(pitch, _yaw, roll)
	# Süspansiyon yaylanması (inişte gövde çöker ve toparlanır)
	_bounce_v += (-suspension_stiffness * _bounce - suspension_damping * _bounce_v) * delta
	_bounce = clampf(_bounce + _bounce_v * delta, -0.42, 0.18)
	_body.position.y = _bounce + _part_lift
	_keep_hull_out(delta)
	_body.position.y += _hull_lift
	_update_wheels(delta)
	_update_scrape()


## Gövdenin duruşu. Yolda: yay-sönümleyici, yolun eğimine oturur; bir yanın
## tekerleri boşta kalınca kenarın üstünden devrilir. Havada: dönme sürer,
## direksiyon arabayı yatırır, düzelme zayıftır. Düşerken hiç düzelmez.
## Kanatlar açılınca (ve portaldan çıkınca) araba kendini düzeltir.
func _update_attitude(delta: float) -> void:
	if mode == Mode.FLYING or mode == Mode.LAUNCH:
		roll = wrapf(roll, -PI, PI)
		pitch = wrapf(pitch, -PI, PI)
		var w := 1.0 - exp(-5.0 * delta)
		var want_roll := -velocity.x / steer_speed * 0.45 if mode == Mode.FLYING else 0.0
		var want_pitch := sin(Time.get_ticks_msec() * 0.003) * 0.04 if mode == Mode.FLYING else 0.0
		roll = lerp_angle(roll, want_roll, w)
		pitch = lerp_angle(pitch, want_pitch, w)
		roll_rate = 0.0
		pitch_rate = 0.0
		_air_lean = 0.0
		return
	if mode == Mode.DRIVE and is_on_floor():
		_air_lean = 0.0
		var n := get_floor_normal()
		var surface := atan2(n.z, n.y)
		# Gövde yolun yatıklığına oturur, üstüne direksiyon yatması eklenir
		var lean := atan2(-n.x, n.y) - velocity.x / steer_speed * 0.08 + _side_tilt
		var k := suspension_stiffness
		var c := suspension_damping
		# Bir yanın iki tekeri de boştaysa yay tutmaz: araba kenardan devrilir
		var roll_acc := -_tip * tip_roll_accel
		if absf(_tip) < 1.0:
			roll_acc += k * (lean - roll) - c * roll_rate
		var pitch_acc := -_nose * nose_drop_accel
		# Roket yanarken arka çöker, burun kalkık kalır
		var squat := deg_to_rad(boost_squat_deg) * boost_level if burning else 0.0
		if _nose < 1.0:
			pitch_acc += k * (surface + squat - pitch) - c * pitch_rate
		roll_rate += roll_acc * delta
		pitch_rate += pitch_acc * delta
		# Ağırlık merkezi kenarı geçti: araba artık yolda tutunamaz, devrilip düşer
		if absf(_tip) >= 1.0 and absf(roll) > deg_to_rad(50.0):
			velocity.x = signf(_tip) * maxf(absf(velocity.x), 7.0)
			roll = clampf(roll, -1.3, 1.3)
	else:
		# Havada: önceki dönme sürer; direksiyon yatırır, bırakınca yatma söner
		var lean_target := -_steer * deg_to_rad(air_lean_deg)
		var new_lean := lerpf(_air_lean, lean_target, 1.0 - exp(-delta / maxf(air_lean_time, 0.01)))
		roll += new_lean - _air_lean
		_air_lean = new_lean
		if mode == Mode.DRIVE:
			roll = lerp_angle(roll, 0.0, 1.0 - exp(-air_self_level * delta))
			# Burun: kalkıştaki dönme hava direnciyle söner, araba gidişine hafifçe uyar
			# (oyuncu burnu kontrol edemediği için burada daha cömertiz)
			pitch_rate *= exp(-1.5 * delta)
			var path := atan2(velocity.y, maxf(-velocity.z, 1.0)) * 0.35
			pitch = lerp_angle(pitch, path, 1.0 - exp(-0.8 * delta))
	roll_rate = clampf(roll_rate, -9.0, 9.0)
	pitch_rate = clampf(pitch_rate, -9.0, 9.0)
	roll += roll_rate * delta
	pitch += pitch_rate * delta


## Çarpışma omurgası ince bir kapsül; görünen gövde ise yerdeki orta noktasının
## etrafında döner. Döndükçe gövdenin köşeleri yolların içine girebilir. Burada
## gövdenin dış noktaları yollara karşı denetlenir:
## - yolun üstüne giren nokta: yerdeyken gövde kaldırılır (kenarın üstünde devrilir
##   gibi), havadayken önce bir teker ya da köşe değer; yolun üstüne kötü duruşla
##   (yan ya da ters) değdiyse araba o anda çakılır (eskiden gövde yola gömülünce çakılırdı)
## - yolun yan yüzüne giren nokta: araba yandan dışarı itilir
func _keep_hull_out(delta: float) -> void:
	var want := 0.0
	var active := hull_guard and model != null and collision_mask != 0 \
		and (mode == Mode.DRIVE or mode == Mode.FALLING)
	var grounded := mode == Mode.DRIVE and is_on_floor()
	if active and grounded and absf(_tip) < 0.5:
		# Yolda düz giderken gövde yola oturur: denetim gerekmez
		var n := get_floor_normal()
		active = absf(wrapf(roll - atan2(-n.x, n.y), -PI, PI)) > 0.15 \
			or absf(wrapf(pitch - atan2(n.z, n.y), -PI, PI)) > 0.15
	if active:
		var c := _hull_contacts(global_transform * _body.transform, not grounded)
		want = c.floor
		if c.left > 0.0 or c.right > 0.0:
			# Yan yüze girdik: dışarı it, duvara doğru hız söner
			global_position.x += c.right - c.left
			if velocity.x < 0.0 and c.right > 0.0 or velocity.x > 0.0 and c.left > 0.0:
				velocity.x = 0.0
		if not grounded and want > 0.05 and _over_road():
			# Havadan yolun üstüne değdik: yan ya da ters değdiysek çakıldık
			var n: Vector3 = c.normal
			var roll_err := absf(wrapf(roll - atan2(-n.x, n.y), -PI, PI))
			var pitch_err := absf(wrapf(pitch - atan2(n.z, n.y), -PI, PI))
			if rad_to_deg(maxf(roll_err, pitch_err * 0.5)) > crash_landing_deg:
				crash("TAKLA ATTIN!" if roll_err > pitch_err else "ÇAKILDIN!")
				return
	want = minf(want, 2.0)
	# Hemen kalkar, yavaşça iner (titremesin)
	_hull_lift = maxf(want, move_toward(_hull_lift, want, 4.0 * delta))


## Arabanın altında (yakında) yol var mı
func _over_road() -> bool:
	var from := global_position + Vector3(0, 0.3, 0)
	var hit := _ray(get_world_3d().direct_space_state, from, from - Vector3(0, 3.0, 0))
	return not hit.is_empty() and hit.normal.y > 0.6


## Gövdenin (xf: Body'nin dünya dönüşümü) yollara girme derinlikleri:
## floor: yolun üstüne en çok giriş (yukarı kaldırma), normal: o yüzün normali,
## right/left: sağa/sola itilmesi gereken mesafe (yan yüzlere giriş)
func _hull_contacts(xf: Transform3D, wheels_too: bool) -> Dictionary:
	if _hull_model != model.variant or _hull_body.is_empty():
		_build_hull()
	var out := {"floor": 0.0, "normal": Vector3.UP, "left": 0.0, "right": 0.0}
	var space := get_world_3d().direct_space_state
	# Işınlar kapsülün ortasından (yolların dışında olduğu bilinen nokta) gövde noktalarına
	var src := global_position + Vector3(0, 0.3, 0)
	var pts := _hull_body + _hull_wheels if wheels_too else _hull_body
	for lp in pts:
		var p: Vector3 = xf * lp
		var hit := _ray(space, src, p)
		if hit.is_empty():
			continue
		# Işın yolun bir yüzüne girip başka bir yüzünden çıkıyorsa nokta dışarıda
		# (ör. kenarın ötesinde boşlukta): geriye atılan ışın o çıkış yüzüne çarpar
		var back := _ray(space, p, src)
		if not back.is_empty() and (back.position as Vector3).distance_to(hit.position) > 0.02:
			continue
		var n: Vector3 = hit.normal
		var depth: float = ((hit.position as Vector3) - p).dot(n)
		if depth <= 0.0:
			continue
		if n.y > 0.6:
			if depth / n.y > out.floor:
				out.floor = depth / n.y
				out.normal = n
		elif n.x > 0.6:
			out.right = maxf(out.right, depth * n.x)
		elif n.x < -0.6:
			out.left = maxf(out.left, -depth * n.x)
	return out


## Yollara çarpan dış noktalar: modelin bütün köşelerinden 26 yönde en uçtakiler
## (gövde ve tekerler ayrı: yolda giderken tekerler yere zaten değer)
func _build_hull() -> void:
	_hull_model = model.variant
	var dirs: Array[Vector3] = []
	for x in [-1, 0, 1]:
		for y in [-1, 0, 1]:
			for z in [-1, 0, 1]:
				if x != 0 or y != 0 or z != 0:
					dirs.append(Vector3(x, y, z).normalized())
	var inv := _body.global_transform.affine_inverse()
	var best := [[], []]
	for k in 2:
		for d in dirs:
			best[k].append([-INF, Vector3.ZERO])
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var k := 0
		for wh in model.wheels:
			if (wh.mount as Node3D).is_ancestor_of(m):
				k = 1
		var t := inv * m.global_transform
		for v in m.mesh.get_faces():
			var p: Vector3 = t * v
			for i in dirs.size():
				var dot := p.dot(dirs[i])
				if dot > best[k][i][0]:
					best[k][i] = [dot, p]
	_hull_body = PackedVector3Array()
	_hull_wheels = PackedVector3Array()
	for k in 2:
		var arr := _hull_body if k == 0 else _hull_wheels
		for b in best[k]:
			if b[0] > -INF and not (b[1] in arr):
				arr.append(b[1])
		if k == 0:
			_hull_body = arr
		else:
			_hull_wheels = arr


## Test için: gövdenin şu anki duruşta yollara en çok giriş derinliği (m)
func hull_depth() -> float:
	if model == null or collision_mask == 0 or mode == Mode.DEAD:
		return 0.0
	var c := _hull_contacts(global_transform * _body.transform, false)
	return maxf(c.floor, maxf(c.left, c.right))


## Bir yan boşluktayken gövde yolun kenarına sürtünür: kıvılcım
func _update_scrape() -> void:
	if fx == null:
		return
	var on := mode == Mode.DRIVE and is_on_floor() and absf(_tip) >= 0.5 and absf(roll) > 0.15
	if on:
		fx.scrape(true, global_position + Vector3(-signf(roll) * 0.6, 0.1, 0.0))
	else:
		fx.scrape(false)


## Teker görseli: dönme, ön tekerde direksiyon, süspansiyonla iniş/kalkış
func _update_wheels(delta: float) -> void:
	if model == null:
		return
	var grounded := mode == Mode.DRIVE and is_on_floor()
	for i in model.wheels.size():
		var wh: Dictionary = model.wheels[i]
		var r: float = wh.radius
		var target := r - suspension_travel
		if grounded and wheel_contact[i]:
			# Gövde yatınca/burun kalkınca teker yerde kalır: yay uzar ya da kısalır
			var c: Vector3 = wh.contact
			var lift := c.x * sin(roll) - c.z * sin(pitch)
			target = r + clampf(_wheel_ground[i] - lift - _bounce - _part_lift - _hull_lift, -suspension_travel, 0.15)
		else:
			target -= _bounce
		var mount: Node3D = wh.mount
		mount.position.y = lerpf(mount.position.y, target, 1.0 - exp(-25.0 * delta))
		if wh.front:
			(wh.steer as Node3D).rotation.y = lerpf((wh.steer as Node3D).rotation.y, -_steer * 0.35, 1.0 - exp(-12.0 * delta))
	if grounded:
		_wheel_spin += -velocity.z / model.wheels[0].radius * delta
	for wh in model.wheels:
		(wh.spin as Node3D).rotation.x = -_wheel_spin


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
	var mats: Array[Material] = [model.paint_material, model.dark_material, model.tire_material]
	var origin := global_position + Vector3(0, 0.6, 0)
	for i in 16:
		# Gerçek fizik cismi: yollara çarpıp seker, içinden geçmez
		var piece := RigidBody3D.new()
		piece.collision_layer = 2
		piece.collision_mask = _default_mask
		var size := Vector3(randf_range(0.2, 0.7), randf_range(0.15, 0.5), randf_range(0.2, 0.8))
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		piece.add_child(shape)
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mi.mesh = box
		mi.material_override = mats[i % mats.size()]
		piece.add_child(mi)
		piece.top_level = true
		add_child(piece)
		piece.global_position = origin + Vector3(randf_range(-0.8, 0.8), randf_range(-0.3, 0.4), randf_range(-1.5, 1.5))
		piece.linear_velocity = Vector3(randf_range(-7, 7), randf_range(3, 11), randf_range(-2, 9))
		piece.angular_velocity = Vector3(randf_range(-10, 10), randf_range(-10, 10), randf_range(-10, 10))
		_debris.append({"node": piece})
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
