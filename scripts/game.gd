extends Node3D
## Oyun akışı: katmanlar arası geçiş, skor, çarpan, kanat enerjisi,
## oyun sonu ve yeniden başlatma.

const SAVE_PATH := "user://save.cfg"
const PERFECT_BONUS := 50
const CRYSTAL_BONUS := 25
const MAX_ENERGY := 100.0
## Oyuncu bu kadar başarılı inişe ulaşana kadar gaz ipucu gösterilir
const TUTORIAL_LANDINGS := 5
## İki katmanı ayıran bulut tabakasının yüksekliği
const CLOUD_LAYER_Y := -42.0
## Ortam renkleri bu yükseklikler arasında üst katmandan alt katmana geçer
const MOOD_HEIGHTS := Vector2(-22.0, -48.0)

## Üst ve alt katmanın ortam ayarları: "nesne:özellik" -> [üst, alt]
const MOODS := {
	"sky:sky_top_color": [Color("e4e1db"), Color("141518")],
	"sky:sky_horizon_color": [Palette.PAPER, Color("2c2e33")],
	"sky:ground_horizon_color": [Palette.PAPER, Color("2c2e33")],
	"sky:ground_bottom_color": [Color("d6d2ca"), Color("0e0f11")],
	"env:fog_light_color": [Palette.PAPER, Color("26282c")],
	"env:fog_density": [0.0028, 0.005],
	"env:fog_height": [-30.0, -160.0],
	"env:ambient_light_color": [Color("ebe8e2"), Color("8a8f97")],
	"env:ambient_light_energy": [0.55, 0.95],
	"sun:light_color": [Color("fffaf2"), Color("dfe4ea")],
	"sun:light_energy": [1.3, 0.95],
	# Bulut tabakası: üstten bakınca sise karışır, alttan açık gri bir tavan olur
	"cloud:albedo_color": [Color(0.97, 0.96, 0.95, 0.35), Color(0.78, 0.77, 0.75, 0.55)],
}

@onready var car: Car = $Car
@onready var roads: RoadGenerator = $RoadGenerator
@onready var lower: LowerLayer = $LowerLayer
@onready var hud: Hud = $HUD
@onready var clouds: Node3D = $CloudLayer
@onready var _mood_targets := {
	"sky": ($WorldEnvironment as WorldEnvironment).environment.sky.sky_material,
	"env": ($WorldEnvironment as WorldEnvironment).environment,
	"sun": $Sun,
	"cloud": ($CloudLayer as MeshInstance3D).mesh.surface_get_material(0),
}

# Ayar panelinden (Tuning) değiştirilebilen değerler
## Üst katmanda bu kadar saniye kalınca çarpan bir artar
var multiplier_step_time := 10.0
var max_multiplier := 5
## Uçarken saniyede harcanan kanat enerjisi
var energy_drain := 6.0
var crystal_energy := 15.0
## Uçarken gaza basılırsa enerji bu kat hızlı harcanır
var boost_drain_factor := 2.5

var score := 0.0
var multiplier := 1
var energy := MAX_ENERGY
var game_over := false
var _mult_timer := 0.0
var _over_time := 0.0
var _mood := -1.0
var _energy_warned := false
var _landings_total := 0
var _hint_shown := false
var _start_z := 0.0
var _stats := {"falls": 0, "returns": 0, "crystals": 0}
var _args := {}


func _ready() -> void:
	_parse_args()
	var seed_value := int(_args.get("seed", "-1"))
	car.roads = roads
	if _args.has("autopilot"):
		car.autopilot = Autopilot.new(car, roads, lower, float(_args.get("dive", "0")), not _args.has("noboost"))
	car.landed.connect(_on_landed)
	car.mode_changed.connect(_on_mode_changed)
	car.died.connect(_on_game_over)
	hud.garage_pressed.connect(_to_garage)
	car.jumped.connect(Audio.play.bind("jump", -6.0))
	car.exploded.connect(_on_exploded)
	lower.setup(car, roads, seed_value)
	lower.crystal_collected.connect(_on_crystal)
	lower.rock_hit.connect(_on_rock_hit)
	lower.portal_entered.connect(_on_portal)
	Tuning.register({"game": self, "car": car, "roads": roads, "lower": lower,
		"camera": $Camera, "audio": Audio, "trail": car.trail})
	# Garajda seçilen araba
	car.model.variant = int(_args.get("model", _load_save().get_value("car", "model", 1)))
	if _args.has("trail"):
		car.trail.style = int(_args.trail)
	car.speed = car.start_speed
	_start_z = car.global_position.z
	_landings_total = int(_load_save().get_value("tutorial", "landings", 0))
	roads.start(car, seed_value)
	_apply_mood(0.0)


func _physics_process(delta: float) -> void:
	if game_over:
		_over_time += delta
		return
	roads.update(car.global_position)
	lower.update(delta)
	score += maxf(-car.velocity.z, 0.0) * delta * multiplier

	match car.mode:
		Car.Mode.DRIVE:
			_mult_timer += delta
			if _mult_timer >= multiplier_step_time and multiplier < max_multiplier:
				_mult_timer = 0.0
				multiplier += 1
				hud.popup("x%d" % multiplier)
				Audio.play("multiplier")
		Car.Mode.FLYING:
			energy -= energy_drain * delta * (boost_drain_factor if car.boosting else 1.0)
			if energy < MAX_ENERGY * 0.3 and not _energy_warned:
				_energy_warned = true
				Audio.play("energy_low")
			if energy <= 0.0:
				energy = 0.0
				car.lose_wings()
				hud.popup("ENERJİ BİTTİ", true)
				Audio.play("fall")

	hud.set_score(int(score), multiplier)
	hud.set_energy(energy / MAX_ENERGY)
	hud.set_boost(car.boost_level)
	_update_hint()
	clouds.position = Vector3(car.global_position.x, CLOUD_LAYER_Y, car.global_position.z)


func _process(delta: float) -> void:
	var target := clampf(inverse_lerp(MOOD_HEIGHTS.x, MOOD_HEIGHTS.y, car.global_position.y), 0.0, 1.0)
	var m := lerpf(_mood, target, 1.0 - exp(-3.0 * delta))
	if absf(m - _mood) > 0.003:
		_apply_mood(m)
	Audio.update(delta, car, _mood, not game_over)
	if _args.has("shots"):
		_capture_shots()


## 0 = üst katman, 1 = alt katman
func _apply_mood(m: float) -> void:
	_mood = m
	hud.set_mood(m)
	for key: String in MOODS:
		var parts := key.split(":")
		var pair: Array = MOODS[key]
		_mood_targets[parts[0]].set(parts[1], lerp(pair[0], pair[1], m))


func _on_mode_changed(mode: Car.Mode, previous: Car.Mode) -> void:
	match mode:
		Car.Mode.FALLING:
			if previous == Car.Mode.DRIVE:
				_stats.falls += 1
				Audio.play("fall", -4.0)
				if multiplier > 1:
					hud.popup("x1")
				multiplier = 1
				_mult_timer = 0.0
		Car.Mode.FLYING:
			lower.activate()
			hud.show_energy(true)
			hud.popup("KANATLAR")
			Audio.play("wings")
		Car.Mode.LAUNCH:
			hud.show_energy(false)
			hud.popup("YUKARI", true)
			Audio.play("portal")


func _on_landed(air_time: float) -> void:
	if lower.active:
		# Alt katmandan yola döndük
		lower.deactivate()
		energy = MAX_ENERGY
		_energy_warned = false
		hud.show_energy(false)
		Audio.play("return")
		Audio.touchdown(1.3)
		hud.popup("TEKRAR YOLDA")
		_stats.returns += 1
		return
	if air_time < 0.3:
		return
	_landings_total += 1
	Audio.touchdown(clampf(air_time / 0.8, 0.6, 1.3))
	var seg := roads.segment_under(car.global_position)
	if seg == null:
		return
	var off := absf(car.global_position.x - seg.x) / (seg.width * 0.5)
	if off < 0.3:
		score += PERFECT_BONUS * multiplier
		hud.popup("PERFECT", true)
		Audio.play("perfect", -2.0)


func _to_garage() -> void:
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _on_exploded() -> void:
	Audio.play("explosion")
	$Camera.shake(1.0)


## İlk yolun sonuna yaklaşırken, oyuncu gazı öğrenene kadar ipucu göster
func _update_hint() -> void:
	if _hint_shown or _landings_total >= TUTORIAL_LANDINGS or car.mode != Car.Mode.DRIVE:
		return
	var seg := roads.segment_under(car.global_position)
	if seg and (car.global_position.z - seg.z_end) / car.forward_speed < 2.2:
		_hint_shown = true
		hud.hint("İKİ PARMAKLA BAS  ·  GAZ", 2.2)


func _load_save() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	return cfg


func _on_crystal() -> void:
	energy = minf(energy + crystal_energy, MAX_ENERGY)
	score += CRYSTAL_BONUS
	_stats.crystals += 1
	Audio.crystal()


func _on_rock_hit() -> void:
	if car.mode == Car.Mode.FLYING:
		car.crash("KAYAYA ÇARPTIN!")


func _on_portal(p: LowerLayer.Portal) -> void:
	if car.mode == Car.Mode.FLYING:
		car.launch_to(p.land, p.clear_y)


func _on_game_over(reason: String) -> void:
	game_over = true
	hud.show_energy(false)
	var final := int(score)
	var cfg := _load_save()
	var best := maxi(final, int(cfg.get_value("score", "best", 0)))
	cfg.set_value("score", "best", best)
	cfg.set_value("tutorial", "landings", _landings_total)
	cfg.save(SAVE_PATH)
	# Patlamanın görülmesi için oyun sonu ekranı biraz gecikmeli gelir
	get_tree().create_timer(1.0).timeout.connect(hud.show_game_over.bind(reason, final, best))
	get_tree().create_timer(1.0).timeout.connect(Audio.play.bind("game_over"))
	print("GAME_OVER reason=%s %s frame=%d" % [reason, _stats_text(), Engine.get_process_frames()])
	if car.autopilot:
		print("  car pos=%v vel=%v mode_time=%.2f" % [car.global_position, car.velocity, car._mode_time])
		for r in lower.rocks:
			if absf(r.z - car.global_position.z) < 40.0:
				print("  rock x=%.1f z=%.1f r=%.1f y=%.1f" % [r.x, r.z, r.r, r.node.position.y])


func _unhandled_input(event: InputEvent) -> void:
	if not game_over or _over_time < 1.6:
		return
	var tapped: bool = event is InputEventScreenTouch and event.pressed
	var key: bool = event is InputEventKey and event.pressed and not event.echo
	if tapped or key:
		get_tree().reload_current_scene()


## Belirtilen karelerde ekran görüntüsü alır, sonuncuda çıkar
func _capture_shots() -> void:
	var frames := Array(_args["shots"].split(",")).map(func(f): return int(f))
	var frame := Engine.get_process_frames()
	if frame in frames:
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/shot_%d.png" % [_args.get("shot_dir", "user://"), frame])
		if frame == frames.max():
			get_tree().quit()


## Komut satırı: -- --autopilot --dive=12 --seed=42 --shots=120,600 --shot_dir=/tmp
func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""


func _stats_text() -> String:
	return "distance=%.0f score=%d speed=%.1f falls=%d returns=%d crystals=%d" % [
		_start_z - car.position.z, int(score), car.speed,
		_stats.falls, _stats.returns, _stats.crystals]


func _exit_tree() -> void:
	if car.autopilot and not game_over:
		print("ALIVE %s" % _stats_text())
