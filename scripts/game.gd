extends Node3D
## Oyun akışı: katmanlar arası geçiş, skor, çarpan, kanat enerjisi,
## oyun sonu ve yeniden başlatma.

const SAVE_PATH := "user://save.cfg"
## Üst katmanda bu kadar saniye kalınca çarpan bir artar
const MULTIPLIER_STEP_TIME := 10.0
const MAX_MULTIPLIER := 5
const PERFECT_BONUS := 50
const CRYSTAL_BONUS := 25
const MAX_ENERGY := 100.0
## Uçarken saniyede harcanan kanat enerjisi
const ENERGY_DRAIN := 6.0
const CRYSTAL_ENERGY := 15.0
## İki katmanı ayıran bulut tabakasının yüksekliği
const CLOUD_LAYER_Y := -42.0
## Ortam renkleri bu yükseklikler arasında üst katmandan alt katmana geçer
const MOOD_HEIGHTS := Vector2(-22.0, -48.0)

## Üst ve alt katmanın ortam ayarları: "nesne:özellik" -> [üst, alt]
const MOODS := {
	"sky:sky_top_color": [Color(0.18, 0.42, 0.85), Color(0.2, 0.14, 0.4)],
	"sky:sky_horizon_color": [Color(0.68, 0.84, 0.98), Color(0.98, 0.6, 0.48)],
	"sky:ground_horizon_color": [Color(0.68, 0.84, 0.98), Color(0.92, 0.52, 0.48)],
	"sky:ground_bottom_color": [Color(0.1, 0.22, 0.5), Color(0.08, 0.05, 0.18)],
	"env:fog_light_color": [Color(0.68, 0.83, 0.97), Color(0.86, 0.55, 0.55)],
	"env:fog_height": [-30.0, -160.0],
	"env:ambient_light_color": [Color(0.85, 0.9, 1.0), Color(0.95, 0.75, 0.8)],
	"sun:light_color": [Color(1.0, 0.96, 0.88), Color(1.0, 0.72, 0.55)],
	"sun:light_energy": [1.25, 1.0],
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
}

var score := 0.0
var multiplier := 1
var energy := MAX_ENERGY
var game_over := false
var _mult_timer := 0.0
var _over_time := 0.0
var _mood := -1.0
var _energy_warned := false
var _start_z := 0.0
var _stats := {"falls": 0, "returns": 0, "crystals": 0}
var _args := {}


func _ready() -> void:
	_parse_args()
	var seed_value := int(_args.get("seed", "-1"))
	car.roads = roads
	if _args.has("autopilot"):
		car.autopilot = Autopilot.new(car, roads, lower, float(_args.get("dive", "0")))
	car.landed.connect(_on_landed)
	car.mode_changed.connect(_on_mode_changed)
	car.died.connect(_on_game_over)
	car.jumped.connect(Audio.play.bind("jump", -6.0))
	car.bumped.connect(Audio.play.bind("crash", -8.0, 1.3))
	lower.setup(car, roads, seed_value)
	lower.crystal_collected.connect(_on_crystal)
	lower.rock_hit.connect(_on_rock_hit)
	lower.portal_entered.connect(_on_portal)
	_start_z = car.global_position.z
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
			if _mult_timer >= MULTIPLIER_STEP_TIME and multiplier < MAX_MULTIPLIER:
				_mult_timer = 0.0
				multiplier += 1
				hud.popup("x%d" % multiplier, Color("ffd166"))
				Audio.play("multiplier")
		Car.Mode.FLYING:
			energy -= ENERGY_DRAIN * delta
			if energy < MAX_ENERGY * 0.3 and not _energy_warned:
				_energy_warned = true
				Audio.play("energy_low")
			if energy <= 0.0:
				energy = 0.0
				car.lose_wings()
				hud.popup("ENERJİ BİTTİ!", Color("ff6b6b"))
				Audio.play("fall")

	hud.set_score(int(score), multiplier)
	hud.set_energy(energy / MAX_ENERGY)
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
					hud.popup("x1", Color("ff8f8f"))
				multiplier = 1
				_mult_timer = 0.0
		Car.Mode.FLYING:
			lower.activate()
			hud.show_energy(true)
			hud.popup("KANATLAR!", Color("8fe9ff"))
			Audio.play("wings")
		Car.Mode.LAUNCH:
			hud.show_energy(false)
			hud.popup("YUKARI!", Color("ff8fe0"))
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
		hud.popup("TEKRAR YOLDA!", Color("ffd166"))
		_stats.returns += 1
		return
	if air_time < 0.3:
		return
	Audio.touchdown(clampf(air_time / 0.8, 0.6, 1.3))
	var seg := roads.segment_under(car.global_position)
	if seg == null:
		return
	var off := absf(car.global_position.x - seg.x) / (seg.width * 0.5)
	if off < 0.3:
		score += PERFECT_BONUS * multiplier
		hud.popup("PERFECT!", Color("7cf29c"))
		Audio.play("perfect", -2.0)


func _on_crystal() -> void:
	energy = minf(energy + CRYSTAL_ENERGY, MAX_ENERGY)
	score += CRYSTAL_BONUS
	_stats.crystals += 1
	Audio.crystal()


func _on_rock_hit() -> void:
	if car.mode == Car.Mode.FLYING:
		Audio.play("crash")
		car.crash("KAYAYA ÇARPTIN!")


func _on_portal(p: LowerLayer.Portal) -> void:
	if car.mode == Car.Mode.FLYING:
		car.launch_to(p.land, p.clear_y)


func _on_game_over(reason: String) -> void:
	game_over = true
	hud.show_energy(false)
	var final := int(score)
	var best := final
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best = maxi(best, int(cfg.get_value("score", "best", 0)))
	cfg.set_value("score", "best", best)
	cfg.save(SAVE_PATH)
	hud.show_game_over(reason, final, best)
	get_tree().create_timer(0.6).timeout.connect(Audio.play.bind("game_over"))
	print("GAME_OVER reason=%s %s" % [reason, _stats_text()])
	if car.autopilot:
		print("  car pos=%v vel=%v mode_time=%.2f" % [car.global_position, car.velocity, car._mode_time])
		for r in lower.rocks:
			if absf(r.z - car.global_position.z) < 40.0:
				print("  rock x=%.1f z=%.1f r=%.1f y=%.1f" % [r.x, r.z, r.r, r.node.position.y])


func _unhandled_input(event: InputEvent) -> void:
	if not game_over or _over_time < 0.8:
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
