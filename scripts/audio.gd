extends Node
## Ses yöneticisi (autoload: Audio). Müzik, motor/rüzgâr döngüleri ve efektler.
## Sahne yeniden yüklense de müzik kesilmeden devam eder.
## Seslerin hepsi tools/make_sounds.py ile üretilir.

const SFX := {
	"jump": preload("res://audio/sfx_jump.wav"),
	"land": preload("res://audio/sfx_land.wav"),
	"perfect": preload("res://audio/sfx_perfect.wav"),
	"multiplier": preload("res://audio/sfx_multiplier.wav"),
	"return": preload("res://audio/sfx_return.wav"),
	"wings": preload("res://audio/sfx_wings.wav"),
	"crystal": preload("res://audio/sfx_crystal.wav"),
	"portal": preload("res://audio/sfx_portal.wav"),
	"fall": preload("res://audio/sfx_fall.wav"),
	"explosion": preload("res://audio/sfx_explosion.wav"),
	"energy_low": preload("res://audio/sfx_energy_low.wav"),
	"game_over": preload("res://audio/sfx_game_over.wav"),
	"climb": preload("res://audio/sfx_climb.wav"),
	"boost": preload("res://audio/sfx_boost.wav"),
}
## Art arda toplanan kristaller minör pentatonik dizide yükselir
const CRYSTAL_STEPS := [1.0, 1.2, 1.335, 1.498, 1.782, 2.0]

@export var music_volume_db := -10.0
@export var sfx_volume_db := -3.0
@export var engine_volume_db := -9.0
@export var road_volume_db := -11.0
## Direksiyonda lastik sürtünmesi/cıyaklaması
@export var tire_volume_db := -12.0
@export var wind_volume_db := -17.0
## Uçuş modunda pervane sesi ve yükselirken üstüne binen türbin katmanı
@export var plane_volume_db := -10.0
@export var climb_volume_db := -13.0
## Çakılda taş çıtırtısı
@export var gravel_volume_db := -8.0

var _music_upper: AudioStreamPlayer
var _music_lower: AudioStreamPlayer
var _engine: AudioStreamPlayer
var _road: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _plane: AudioStreamPlayer
var _climb: AudioStreamPlayer
## Her efektin kendi oynatıcısı (ses dosyası hazır bekler: gecikme olmaz)
var _players := {}
var _tire: AudioStreamPlayer
var _gravel: AudioStreamPlayer
var _gravel_level := 0.0
var _tire_level := 0.0
var _last_vx := 0.0
var _engine_level := 0.0
var _engine_pitch := 1.0
var _road_level := 0.0
var _wind_level := 0.0
var _plane_level := 0.0
var _plane_pitch := 0.9
## 0..1: yükselmenin yumuşatılmış gücü (uçak gaz kolu gibi yavaş açılır)
var _climb_amount := 0.0
var _was_climbing := false
var _music_level := 1.0
var _crystal_combo := 0
var _last_crystal_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music_upper = _make_loop(preload("res://audio/music_upper.ogg"))
	_music_lower = _make_loop(preload("res://audio/music_lower.ogg"))
	_engine = _make_loop(preload("res://audio/loop_engine.ogg"))
	_road = _make_loop(preload("res://audio/loop_road.ogg"))
	_wind = _make_loop(preload("res://audio/loop_wind.ogg"))
	_plane = _make_loop(preload("res://audio/loop_plane.ogg"))
	_climb = _make_loop(preload("res://audio/loop_climb.ogg"))
	_tire = _make_loop(preload("res://audio/loop_tire.ogg"))
	_gravel = _make_loop(preload("res://audio/loop_gravel.ogg"))
	for key in SFX:
		var p := AudioStreamPlayer.new()
		p.stream = SFX[key]
		p.max_polyphony = 4
		add_child(p)
		_players[key] = p
		# Web'de sesi baştan kaydet ki ilk çalışta gecikmesin
		if AudioServer.has_method("register_stream_as_sample"):
			AudioServer.call("register_stream_as_sample", SFX[key])


func play(sfx: String, volume_db := 0.0, pitch := 1.0) -> void:
	var p: AudioStreamPlayer = _players[sfx]
	p.volume_db = sfx_volume_db + volume_db
	p.pitch_scale = pitch
	p.play()


func crystal() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_crystal_ms > 1500:
		_crystal_combo = 0
	_last_crystal_ms = now
	play("crystal", -2.0, CRYSTAL_STEPS[mini(_crystal_combo, CRYSTAL_STEPS.size() - 1)])
	_crystal_combo += 1


## Her kare çağrılır. mood: 0 = üst katman, 1 = alt katman
func update(delta: float, car: Car, mood: float, playing: bool) -> void:
	_music_level = move_toward(_music_level, 1.0 if playing else 0.45, delta * 0.5)
	_music_upper.volume_db = music_volume_db + linear_to_db(maxf((1.0 - mood) * _music_level, 0.001))
	_music_lower.volume_db = music_volume_db + linear_to_db(maxf(mood * _music_level, 0.001))

	var speed01 := clampf(inverse_lerp(car.start_speed, car.max_speed, car.speed), 0.0, 1.0)
	var grounded := car.mode == Car.Mode.DRIVE and car.is_on_floor()
	# Motor: hızla devir yükselir; havada tekerler boşta döner, devir fırlar
	var engine_target := 0.0
	var pitch_target := 0.75 + 0.6 * speed01 + 0.35 * car.boost_level
	var wind_target := 0.0
	match car.mode:
		Car.Mode.DRIVE:
			engine_target = 1.0 + 0.4 * car.boost_level
			if not grounded:
				pitch_target += 0.22
			wind_target = 0.2 + 0.3 * speed01
		Car.Mode.FALLING:
			engine_target = 0.5
			pitch_target += 0.3
			wind_target = 0.9
		Car.Mode.FLYING:
			# Araba motoru susar, yerini uçak sesi alır (aşağıda)
			engine_target = 0.0
			wind_target = 0.5 + 0.25 * speed01 + 0.25 * _climb_amount
		Car.Mode.LAUNCH:
			engine_target = 0.7
			pitch_target += 0.45
			wind_target = 1.0
	if not playing:
		engine_target = 0.0
		wind_target *= 0.3
	_engine_level = move_toward(_engine_level, engine_target, delta * 3.0)
	# Devir yükselişi hızlı, düşüşü daha yavaş: gaz verilmiş gibi
	var rate := 3.0 if pitch_target > _engine_pitch else 1.2
	_engine_pitch = move_toward(_engine_pitch, pitch_target, delta * rate)
	_road_level = move_toward(_road_level, (0.4 + 0.6 * speed01) if grounded and playing else 0.0, delta * 12.0)
	_wind_level = move_toward(_wind_level, wind_target, delta * 1.5)
	_engine.volume_db = engine_volume_db + linear_to_db(maxf(_engine_level, 0.001))
	# Gazda devir yükselir; sınırı aşmasın
	_engine_pitch = minf(_engine_pitch, 1.9)
	_engine.pitch_scale = _engine_pitch
	_road.volume_db = road_volume_db + linear_to_db(maxf(_road_level, 0.001))
	_road.pitch_scale = 0.8 + 0.5 * speed01
	_wind.volume_db = wind_volume_db + linear_to_db(maxf(_wind_level, 0.001))
	_wind.pitch_scale = 0.85 + 0.35 * speed01 + 0.15 * _climb_amount
	_update_plane(delta, car, speed01, playing)
	_update_tire(delta, car, speed01, grounded and playing)
	_gravel_level = move_toward(_gravel_level, (0.6 + 0.4 * speed01) if car.on_gravel and grounded and playing else 0.0, delta * 10.0)
	_gravel.volume_db = gravel_volume_db + linear_to_db(maxf(_gravel_level, 0.001))
	_gravel.pitch_scale = 0.85 + 0.3 * speed01


## Lastik: direksiyonla yana ivmelenince sürtünme/cıyaklama (sert manevrada güçlü)
func _update_tire(delta: float, car: Car, speed01: float, grounded: bool) -> void:
	var lateral_accel := absf(car.velocity.x - _last_vx) / maxf(delta, 0.001)
	_last_vx = car.velocity.x
	var target := 0.0
	if grounded:
		target = clampf(lateral_accel / car.steer_accel, 0.0, 1.0) * (0.5 + 0.5 * speed01)
	_tire_level = move_toward(_tire_level, target, delta * (14.0 if target > _tire_level else 4.0))
	_tire.volume_db = tire_volume_db + linear_to_db(maxf(_tire_level, 0.001))
	_tire.pitch_scale = 0.9 + 0.25 * speed01 + 0.1 * _tire_level


## Uçuş: pervane sesi; yükselirken uçak gibi yavaşça devirlenir, türbin ıslığı biner
func _update_plane(delta: float, car: Car, speed01: float, playing: bool) -> void:
	var flying := car.mode == Car.Mode.FLYING and playing
	var climbing := car.climbing and playing
	if climbing and not _was_climbing:
		play("climb", -3.0)
	_was_climbing = climbing
	var climb_target := 1.0 if climbing else 0.0
	_climb_amount = move_toward(_climb_amount, climb_target,
		delta * (1.1 if climb_target > _climb_amount else 0.7))
	_plane_level = move_toward(_plane_level, (0.75 + 0.25 * _climb_amount) if flying else 0.0, delta * 1.5)
	var pitch_target := 0.9 + 0.15 * speed01 + 0.3 * _climb_amount
	_plane_pitch = move_toward(_plane_pitch, pitch_target, delta * 0.6)
	_plane.volume_db = plane_volume_db + linear_to_db(maxf(_plane_level, 0.001))
	_plane.pitch_scale = _plane_pitch
	var climb_level := _climb_amount if flying else 0.0
	_climb.volume_db = climb_volume_db + linear_to_db(maxf(climb_level, 0.001))
	_climb.pitch_scale = 0.85 + 0.35 * _climb_amount


## Garaj ekranı: sadece üst katman müziği
func update_menu(delta: float) -> void:
	_music_level = move_toward(_music_level, 1.0, delta * 0.5)
	_music_upper.volume_db = music_volume_db + linear_to_db(maxf(_music_level, 0.001))
	_music_lower.volume_db = -60.0
	_engine_level = move_toward(_engine_level, 0.0, delta * 3.0)
	_road_level = 0.0
	_wind_level = move_toward(_wind_level, 0.0, delta * 1.5)
	_engine.volume_db = engine_volume_db + linear_to_db(maxf(_engine_level, 0.001))
	_road.volume_db = -60.0
	_wind.volume_db = wind_volume_db + linear_to_db(maxf(_wind_level, 0.001))
	_plane_level = 0.0
	_climb_amount = 0.0
	_plane.volume_db = -60.0
	_climb.volume_db = -60.0
	_tire_level = 0.0
	_tire.volume_db = -60.0
	_gravel_level = 0.0
	_gravel.volume_db = -60.0


## Tekerlekler yere değdi: devir bir an düşer (yük bindi)
func touchdown(strength := 1.0) -> void:
	_engine_pitch -= 0.12 * strength
	play("land", 1.0 + 3.0 * (strength - 1.0), randf_range(0.95, 1.05))


func _make_loop(stream: AudioStreamOggVorbis) -> AudioStreamPlayer:
	stream.loop = true
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = -60.0
	add_child(p)
	p.play()
	return p

