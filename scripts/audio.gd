extends Node
## Ses yöneticisi (autoload: Audio). Müzik, motor/rüzgâr döngüleri ve efektler.
## Sahne yeniden yüklense de müzik kesilmeden devam eder.
## Seslerin hepsi tools/make_sounds.py ile üretilir.

const SFX := {
	"jump": preload("res://audio/sfx_jump.wav"),
	"land_gezgin": preload("res://audio/sfx_land_gezgin.wav"),
	"land_dragster": preload("res://audio/sfx_land_dragster.wav"),
	"land_latte": preload("res://audio/sfx_land_latte.wav"),
	"land_gem": preload("res://audio/sfx_land_gem.wav"),
	"land_dark_rose": preload("res://audio/sfx_land_dark_rose.wav"),
	"land_falcon": preload("res://audio/sfx_land_falcon.wav"),
	"perfect": preload("res://audio/sfx_perfect.wav"),
	"multiplier": preload("res://audio/sfx_multiplier.wav"),
	"return": preload("res://audio/sfx_return.wav"),
	"wings": preload("res://audio/sfx_wings.wav"),
	"crystal": preload("res://audio/sfx_crystal.wav"),
	"portal": preload("res://audio/sfx_portal.wav"),
	"fall": preload("res://audio/sfx_fall.wav"),
	"energy_low": preload("res://audio/sfx_energy_low.wav"),
	"game_over": preload("res://audio/sfx_game_over.wav"),
	"climb": preload("res://audio/sfx_climb.wav"),
	"boost": preload("res://audio/sfx_boost.wav"),
	"empty": preload("res://audio/sfx_empty.wav"),
	"hiss": preload("res://audio/sfx_hiss.wav"),
	"shatter": preload("res://audio/sfx_shatter.wav"),
	"drain": preload("res://audio/sfx_drain.wav"),
	"debris": preload("res://audio/sfx_debris.wav"),
	"smash": preload("res://audio/sfx_smash.wav"),
	"bounce": preload("res://audio/sfx_bounce.wav"),
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
## Müzik açık mı (oyuncunun seçimi, kaydedilir: garaj ve oyun sonu ekranındaki düğme)
var music_on := true
var _music_gain := 1.0
const SAVE_PATH := "user://save.cfg"
## Arabanın motor sesi: her araba kendi motoruyla (CarModel varyantı -> motor). Hibrit ailesi:
## GEZGİN, LATTE, GEM; FM ailesi: DRAGSTER, DARK ROSE, FALCON (tools/engine_land_designs.py CARS)
## İniş sesi (gerçekçi lastik: yumuşak konuş + hafif kayma), arabaya göre; motorun üstünde duyulsun
const LANDS := {2: "land_gezgin", 8: "land_latte", 10: "land_gem", 6: "land_dragster", 7: "land_dark_rose", 9: "land_falcon"}
const LAND_BOOST_DB := 7.0
var _land_key := "land_latte"
const ENGINES := {
	2: preload("res://audio/loop_engine_gezgin.ogg"),
	8: preload("res://audio/loop_engine_latte.ogg"),
	10: preload("res://audio/loop_engine_dark_rose.ogg"),
	6: preload("res://audio/loop_engine_dragster.ogg"),
	7: preload("res://audio/loop_engine_gem.ogg"),
	9: preload("res://audio/loop_engine_falcon.ogg"),
}
## Test (--audtrace): motor devri / seviyesi ve iniş anları günlüğü (ses tasarımı denemeleri için)
var _aud_trace := OS.get_cmdline_user_args().has("--audtrace")
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
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		music_on = bool(cfg.get_value("audio", "music", true))
	_music_gain = 1.0 if music_on else 0.0
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music_upper = _make_loop(preload("res://audio/music_upper.ogg"))
	_music_lower = _make_loop(preload("res://audio/music_lower.ogg"))
	_engine = _make_loop(ENGINES[8])
	_road = _make_loop(preload("res://audio/loop_road.ogg"))
	_wind = _make_loop(preload("res://audio/loop_wind.ogg"))
	_plane = _make_loop(preload("res://audio/loop_plane.ogg"))
	_climb = _make_loop(preload("res://audio/loop_climb.ogg"))
	_tire = _make_loop(preload("res://audio/loop_tire.ogg"))
	# Düz dünya denemesi: çakıl yerine hava akımı sesi
	_gravel = _make_loop(preload("res://audio/loop_airwave.ogg") if FlatStyle.on() else preload("res://audio/loop_gravel.ogg"))
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
	if _aud_trace:
		print("SFX f=%d %s" % [Engine.get_process_frames(), sfx])
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
	_music_gain = move_toward(_music_gain, 1.0 if music_on else 0.0, delta * 2.0)
	_music_upper.volume_db = music_volume_db + linear_to_db(maxf((1.0 - mood) * _music_level * _music_gain, 0.001))
	_music_lower.volume_db = music_volume_db + linear_to_db(maxf(mood * _music_level * _music_gain, 0.001))
	_pause_music_if_off()

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
	_loop_volume(_engine, engine_volume_db, _engine_level)
	# Gazda devir yükselir; sınırı aşmasın
	_engine_pitch = minf(_engine_pitch, 1.9)
	_engine.pitch_scale = _engine_pitch
	if _aud_trace:
		print("AUD f=%d pitch=%.3f level=%.3f mode=%d" % [Engine.get_process_frames(), _engine_pitch, _engine_level, car.mode])
	_loop_volume(_road, road_volume_db, _road_level)
	_road.pitch_scale = 0.8 + 0.5 * speed01
	_loop_volume(_wind, wind_volume_db, _wind_level)
	_wind.pitch_scale = 0.85 + 0.35 * speed01 + 0.15 * _climb_amount
	_update_plane(delta, car, speed01, playing)
	_update_tire(delta, car, speed01, grounded and playing)
	_gravel_level = move_toward(_gravel_level, (0.6 + 0.4 * speed01) if car.on_gravel and (grounded or car.air_wheels > 0) and playing else 0.0, delta * 10.0)
	_loop_volume(_gravel, gravel_volume_db, _gravel_level)
	_gravel.pitch_scale = 0.85 + 0.3 * speed01


## Lastik: direksiyonla yana ivmelenince sürtünme/cıyaklama (sert manevrada güçlü)
func _update_tire(delta: float, car: Car, speed01: float, grounded: bool) -> void:
	var lateral_accel := absf(car.velocity.x - _last_vx) / maxf(delta, 0.001)
	_last_vx = car.velocity.x
	var target := 0.0
	if grounded:
		target = clampf(lateral_accel / car.steer_accel, 0.0, 1.0) * (0.5 + 0.5 * speed01)
	_tire_level = move_toward(_tire_level, target, delta * (14.0 if target > _tire_level else 4.0))
	_loop_volume(_tire, tire_volume_db, _tire_level)
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
	_loop_volume(_plane, plane_volume_db, _plane_level)
	_plane.pitch_scale = _plane_pitch
	var climb_level := _climb_amount if flying else 0.0
	_loop_volume(_climb, climb_volume_db, climb_level)
	_climb.pitch_scale = 0.85 + 0.35 * _climb_amount


## Müziği aç / kapat (yumuşakça söner / açılır); seçim kaydedilir
func set_music(on: bool) -> void:
	music_on = on
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("audio", "music", on)
	cfg.save(SAVE_PATH)


## Oyundaki arabanın motor ve iniş sesi (araba modeline göre)
func set_engine_for_model(variant: int) -> void:
	_land_key = LANDS.get(variant, "land_latte")
	var stream: AudioStream = ENGINES.get(variant, ENGINES[8])
	if _engine.stream == stream:
		return
	(stream as AudioStreamOggVorbis).loop = true
	_engine.stream = stream
	_engine.play()
	if _aud_trace:
		print("ENGINE model=%d %s" % [variant, stream.resource_path.get_file()])


## Garaj ekranı: sadece üst katman müziği
func update_menu(delta: float) -> void:
	_music_level = move_toward(_music_level, 1.0, delta * 0.5)
	_music_gain = move_toward(_music_gain, 1.0 if music_on else 0.0, delta * 2.0)
	_music_upper.volume_db = music_volume_db + linear_to_db(maxf(_music_level * _music_gain, 0.001))
	_music_lower.volume_db = -60.0
	_pause_music_if_off()
	_engine_level = move_toward(_engine_level, 0.0, delta * 3.0)
	_road_level = 0.0
	_wind_level = move_toward(_wind_level, 0.0, delta * 1.5)
	_loop_volume(_engine, engine_volume_db, _engine_level)
	_loop_volume(_road, 0.0, 0.0)
	_loop_volume(_wind, wind_volume_db, _wind_level)
	_plane_level = 0.0
	_climb_amount = 0.0
	_loop_volume(_plane, 0.0, 0.0)
	_loop_volume(_climb, 0.0, 0.0)
	_tire_level = 0.0
	_loop_volume(_tire, 0.0, 0.0)
	_gravel_level = 0.0
	_loop_volume(_gravel, 0.0, 0.0)


## Tekerlekler yere değdi: devir bir an düşer (yük bindi)
func touchdown(strength := 1.0) -> void:
	if _aud_trace:
		print("LAND f=%d strength=%.2f" % [Engine.get_process_frames(), strength])
	_engine_pitch -= 0.12 * strength
	play(_land_key, LAND_BOOST_DB + 1.0 + 3.0 * (strength - 1.0), randf_range(0.95, 1.05))


## Döngü sesinin seviyesi; sessizken durur (çok kısık çalan döngüler sessiz ortamda vızıltı gibi duyuluyordu)
func _loop_volume(p: AudioStreamPlayer, base_db: float, level: float) -> void:
	var silent := level <= 0.001
	p.volume_db = -80.0 if silent else base_db + linear_to_db(level)
	# Duraklatmak yerine durdur / baştan çal: web'de duraklatılan ses yeniden başlamıyordu
	# (çakıl sesi kayboluyordu); döngü olduğu için baştan başlaması fark edilmez
	if silent and p.playing:
		p.stop()
	elif not silent and not p.playing:
		p.play()


## Müzik kapalı ve tamamen söndüyse iki müzik katmanı da durur (birlikte, senkron kalsınlar)
func _pause_music_if_off() -> void:
	var off := not music_on and _music_gain <= 0.0
	if off:
		_music_upper.volume_db = -80.0
		_music_lower.volume_db = -80.0
	# Duraklatmak yerine durdur / baştan çal (web'de duraklatılan ses yeniden başlamayabiliyor);
	# iki katman birlikte baştan başlar: senkron kalır
	if off and _music_upper.playing:
		_music_upper.stop()
		_music_lower.stop()
	elif not off and not _music_upper.playing:
		_music_upper.play()
		_music_lower.play()


func _make_loop(stream: AudioStreamOggVorbis) -> AudioStreamPlayer:
	stream.loop = true
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = -60.0
	add_child(p)
	p.play()
	return p

