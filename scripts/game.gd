extends Node3D
## Oyun akışı: skor, çarpan, oyun sonu ve yeniden başlatma.

const SAVE_PATH := "user://save.cfg"
## Üst katmanda bu kadar saniye kalınca çarpan bir artar
const MULTIPLIER_STEP_TIME := 10.0
const MAX_MULTIPLIER := 5
const PERFECT_BONUS := 50

@onready var car: Car = $Car
@onready var roads: RoadGenerator = $RoadGenerator
@onready var hud: Hud = $HUD

var score := 0.0
var multiplier := 1
var game_over := false
var _mult_timer := 0.0
var _over_time := 0.0
var _start_z := 0.0
var _args := {}


func _ready() -> void:
	_parse_args()
	car.roads = roads
	car.autopilot = _args.has("autopilot")
	car.landed.connect(_on_landed)
	car.crashed.connect(_on_game_over.bind("ÇARPTIN!"))
	car.fell.connect(_on_game_over.bind("DÜŞTÜN!\n(uçuş modu yakında)"))
	_start_z = car.global_position.z
	roads.start(car, int(_args.get("seed", "-1")))


func _physics_process(delta: float) -> void:
	if game_over:
		_over_time += delta
		return
	roads.update(car.global_position)
	score += car.speed * delta * multiplier
	_mult_timer += delta
	if _mult_timer >= MULTIPLIER_STEP_TIME and multiplier < MAX_MULTIPLIER:
		_mult_timer = 0.0
		multiplier += 1
		hud.popup("x%d" % multiplier, Color("ffd166"))
	hud.set_score(int(score), multiplier)


func _on_landed(air_time: float) -> void:
	if air_time < 0.3:
		return
	var seg := roads.segment_under(car.global_position)
	if seg == null:
		return
	var off := absf(car.global_position.x - seg.x) / (seg.width * 0.5)
	if off < 0.3:
		score += PERFECT_BONUS * multiplier
		hud.popup("PERFECT!", Color("7cf29c"))


func _on_game_over(reason: String) -> void:
	game_over = true
	var final := int(score)
	var best := final
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best = maxi(best, int(cfg.get_value("score", "best", 0)))
	cfg.set_value("score", "best", best)
	cfg.save(SAVE_PATH)
	hud.show_game_over(reason, final, best)
	print("GAME_OVER reason=%s distance=%.0f score=%d" % [reason.get_slice("\n", 0), _start_z - car.global_position.z, final])
	if car.autopilot:
		_dump_state()


func _unhandled_input(event: InputEvent) -> void:
	if not game_over or _over_time < 0.8:
		return
	var tapped: bool = event is InputEventScreenTouch and event.pressed
	var key: bool = event is InputEventKey and event.pressed and not event.echo
	if tapped or key:
		get_tree().reload_current_scene()


func _process(_delta: float) -> void:
	if _args.has("shots"):
		_capture_shots()


## Belirtilen karelerde ekran görüntüsü alır, sonuncuda çıkar
func _capture_shots() -> void:
	var frames := Array(_args["shots"].split(",")).map(func(f): return int(f))
	var frame := Engine.get_process_frames()
	if frame in frames:
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/shot_%d.png" % [_args.get("shot_dir", "user://"), frame])
		if frame == frames.max():
			get_tree().quit()


## Komut satırı: -- autopilot seed=42 shots=120,600 shot_dir=/tmp
func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""


func _exit_tree() -> void:
	if car.autopilot and not game_over:
		print("ALIVE distance=%.0f score=%d speed=%.1f" % [_start_z - car.position.z, int(score), car.speed])


func _dump_state() -> void:
	print("  car pos=%v vel=%v speed=%.1f" % [car.global_position, car.velocity, car.speed])
	for s in roads.segments:
		if s.z_end < car.global_position.z + 150.0 and s.z_start > car.global_position.z - 40.0:
			print("  seg main=%s x=%.1f top=%.2f w=%.1f z=[%.1f .. %.1f]" % [s.main, s.x, s.top, s.width, s.z_start, s.z_end])
