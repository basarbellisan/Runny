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
	"crash": preload("res://audio/sfx_crash.wav"),
	"energy_low": preload("res://audio/sfx_energy_low.wav"),
	"game_over": preload("res://audio/sfx_game_over.wav"),
}
## Art arda toplanan kristaller pentatonik dizide yükselir
const CRYSTAL_STEPS := [1.0, 1.122, 1.26, 1.498, 1.682, 2.0]

@export var music_volume_db := -9.0
@export var sfx_volume_db := -3.0
@export var engine_volume_db := -22.0
@export var wind_volume_db := -16.0

var _music_upper: AudioStreamPlayer
var _music_lower: AudioStreamPlayer
var _engine: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer] = []
var _pool_index := 0
var _engine_level := 0.0
var _wind_level := 0.0
var _music_level := 1.0
var _crystal_combo := 0
var _last_crystal_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music_upper = _make_loop(preload("res://audio/music_upper.ogg"))
	_music_lower = _make_loop(preload("res://audio/music_lower.ogg"))
	_engine = _make_loop(preload("res://audio/loop_engine.ogg"))
	_wind = _make_loop(preload("res://audio/loop_wind.ogg"))
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)


func play(sfx: String, volume_db := 0.0, pitch := 1.0) -> void:
	var p := _pool[_pool_index]
	_pool_index = (_pool_index + 1) % _pool.size()
	p.stream = SFX[sfx]
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
	var engine_target := 0.0
	var wind_target := 0.0
	match car.mode:
		Car.Mode.DRIVE:
			engine_target = 1.0 if car.is_on_floor() else 0.6
			wind_target = 0.25 + 0.35 * speed01
		Car.Mode.FALLING:
			wind_target = 0.9
		Car.Mode.FLYING:
			wind_target = 0.55 + 0.25 * speed01
		Car.Mode.LAUNCH:
			wind_target = 1.0
	if not playing:
		engine_target = 0.0
		wind_target *= 0.3
	_engine_level = move_toward(_engine_level, engine_target, delta * 3.0)
	_wind_level = move_toward(_wind_level, wind_target, delta * 1.5)
	_engine.volume_db = engine_volume_db + linear_to_db(maxf(_engine_level, 0.001))
	_engine.pitch_scale = 0.8 + 0.55 * speed01 + (0.08 if not car.is_on_floor() else 0.0)
	_wind.volume_db = wind_volume_db + linear_to_db(maxf(_wind_level, 0.001))
	_wind.pitch_scale = 0.85 + 0.35 * speed01


func _make_loop(stream: AudioStreamOggVorbis) -> AudioStreamPlayer:
	stream.loop = true
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = -60.0
	add_child(p)
	p.play()
	return p
