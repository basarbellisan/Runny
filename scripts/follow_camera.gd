extends Camera3D
## Arabayı arkadan ve yukarıdan takip eden kamera. Hız arttıkça görüş açısı genişler.

@export var target_path: NodePath
@export var offset := Vector3(0.0, 6.0, 10.0)
@export var look_ahead := 22.0
## Parçalanmada kameranın buluta göre yeri, bakış uzaklığı ve yaklaşma hızı (1/sn)
@export var smash_offset := Vector3(0.0, 3.5, 6.0)
@export var smash_look_ahead := 12.0
@export var smash_approach := 1.2
## Kanatlar kapanıp araba dalınca kamera bu kadar sn izler, sonra durup aşağı bakar
@export var dive_follow := 1.0
## Aşağı dönen bakışın hızı
@export var dive_look := 2.5
var _off := Vector3.ZERO
var _ahead := 22.0
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
## Işık bariyerinde kesilme bitince: kamera aynı hızla düz gitmeyi sürdürür, bir süre sonra
## yavaşlar ama akmaya devam eder (oyun sonu ekranı yolun üstüne gelir).
var _fly := -1.0
## Önce bu kadar (gerçek sn) aynı hızla düz gider: yandığı anlaşılsın, dağılan parçalar görünsün
@export var fly_straight := 1.0
## Düz giderken parça bulutuna (araba noktası onu izler) en fazla bu kadar yaklaşır
@export var fly_gap := 6.0
var _straight := 0.0
## Yavaşlayınca kalan hız (kesilme anındaki hızın kesri) ve yavaşlama hızı
@export var fly_drift := 0.18
@export var fly_brake := 1.6
var _fly_speed := 1.0
## Akarken arabadan en fazla bu kadar uzaklaşır (yolların bittiği yere gelmesin), son bu kadar
## metrede yavaşlayıp durur
@export var fly_max := 300.0
@export var fly_ease := 60.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_target = get_node(target_path)
	_off = offset
	_ahead = look_ahead
	base_fov = fov
	global_position = _target.global_position + offset


func _process(delta: float) -> void:
	var t := _target.get_global_transform_interpolated().origin
	var p := global_position
	# Işık bariyerinde kesilme: kamera akar (düz gider, yavaşlar). Parçalanmada (smashing) değil: bulutu
	# normal takiple izler (bulut yavaşladıkça kendisi de yavaşlar, geride kalmaz)
	if _fly < 0.0 and _target.shattering and not _target.is_cutting() and not _target.smashing:
		_fly = 0.0
	if _fly >= 0.0:
		_fly_away(delta)
	elif _target.nosedive and _target.nosedive_time >= dive_follow:
		# Enerji bitti, araba baş aşağı dalıyor: kamera dive_follow sn izledi, şimdi yerinde durur ve
		# arabanın ardından aşağı, sonsuz boşluğa bakar (araba sisin içinde küçülüp kaybolur)
		_look = _look.lerp(t, 1.0 - exp(-dive_look * delta))
		look_at(_look)
	elif _target.alive or _target.shattering:
		# Parçalanmada kamera buluta yavaşça yaklaşır (parçalar küçülüp dağılırken ekranda kalsın)
		var want_off := smash_offset if _target.smashing else offset
		_off = _off.lerp(want_off, 1.0 - exp(-smash_approach * delta))
		_ahead = lerpf(_ahead, smash_look_ahead if _target.smashing else look_ahead, 1.0 - exp(-smash_approach * delta))
		p.z = t.z + _off.z
		p.x = lerpf(p.x, t.x + _off.x, 1.0 - exp(-follow_x * delta))
		# Hızlı yükselip alçalırken (dalış, portal) kamera arabayı kaçırmasın
		var k := follow_y + absf(_target.velocity.y) * 0.15
		p.y = lerpf(p.y, t.y + _off.y, 1.0 - exp(-k * delta))
		global_position = p
		var want_fov := base_fov + (_target.forward_speed - _target.start_speed) * fov_per_speed
		_fov_kick_target = lerpf(_fov_kick_target, 0.0, 1.0 - exp(-2.5 * delta))
		_fov_kick = lerpf(_fov_kick, _fov_kick_target, 1.0 - exp(-12.0 * delta))
		fov = lerpf(fov, want_fov, 1.0 - exp(-2.0 * delta)) + (_fov_kick - _fov_kick_shown)
		_fov_kick_shown = _fov_kick
		_look = Vector3(lerpf(p.x, t.x, 0.6), t.y - 1.0, t.z - _ahead)
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


func _fly_away(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)
	var v := _target.shatter_velocity()
	var t := _target.get_global_transform_interpolated().origin
	var p := global_position
	_straight += real
	# Kesilme anındaki hızla düz devam; fly_straight sn sonra yavaşlamaya başlar ama durmaz,
	# hızın fly_drift kadarıyla akmayı sürdürür. Yükselmez, bakış aynı kalır.
	if _straight > fly_straight:
		_fly_speed = lerpf(_fly_speed, fly_drift, 1.0 - exp(-fly_brake * real))
	# Yollar arabanın view_distance (450 m) önüne kadar üretilir ve araba ölünce orada kalır:
	# kamera arabanın fly_max metre ötesine geçmez, son fly_ease metrede yumuşakça durur
	var gone := (t.z + offset.z) - p.z
	var room := clampf((fly_max - gone) / fly_ease, 0.0, 1.0)
	p.z += v.z * delta * _fly_speed * room
	if _target.shattering:
		p.z = maxf(p.z, t.z + fly_gap)  # parça bulutunu geçip kaçırmaz
	p.x = lerpf(p.x, t.x + offset.x, 1.0 - exp(-follow_x * delta))
	global_position = p
	_look = Vector3(lerpf(p.x, t.x, 0.6), _look.y, p.z - offset.z - look_ahead)
	look_at(_look)


## Oyun sonu akışında mı (kamera arabadan ayrılıp ileri gidiyor): arka plan buna göre yerleşir
func is_drifting() -> bool:
	return _fly >= 0.0


## Oyun sonu: kamerayı süre boyunca göğe çevir
func look_sky(duration: float) -> void:
	_sky_from = Vector3.ZERO
	create_tween().tween_property(self, "sky_view", 1.0, duration).set_trans(Tween.TRANS_SINE)


func fov_kick(degrees: float) -> void:
	_fov_kick_target += degrees


func shake(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)
