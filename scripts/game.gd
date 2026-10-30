extends Node3D
## Oyun akışı: katmanlar arası geçiş, skor, çarpan, kanat enerjisi,
## oyun sonu ve yeniden başlatma.

const SAVE_PATH := "user://save.cfg"
const PERFECT_BONUS := 50
const CRYSTAL_BONUS := 25
## Çatalda yüksek yolu bitirince (çarpanla çarpılır)
const HIGH_ROUTE_BONUS := 250
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
	"env:ambient_light_energy": [0.6, 0.95],
	"sun:light_color": [Color("fffaf2"), Color("dfe4ea")],
	"sun:light_energy": [1.0, 0.95],
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
## Kanat yedeği: uçarken depo bitince kanatlar bu kadar yedek enerjiyle "çısss" diye
## açılır (kanat uçlarından iz çıkar, yedek bittikçe kısalır); bitince uçuruma düşülür.
## Aşağıda kristal yok: düşerkenki depo + bu yedek, aşağıdaki hayat süresidir.
## Süre olarak verilir: düz uçuşta yedek bu kadar saniye yeter (yükselmek daha hızlı yakar).
var wing_reserve_time := 10.0
## Uçarken yükselirken (iki parmak) enerji bu kat hızlı harcanır
var boost_drain_factor := 2.5

var score := 0.0
var multiplier := 1
var game_over := false
var _mult_timer := 0.0
var _over_time := 0.0
var _mood := -1.0
var _energy_warned := false
var _landings_total := 0
var _hint_shown := false
var _start_z := 0.0
## Çatalın yüksek kolundayız (puan iki kat)
var _on_high_route := false
var _was_on_gravel := false
var _stats := {"falls": 0, "returns": 0, "crystals": 0, "clean": 0, "hard": 0, "high": 0, "empty": 0,
	"wasted": 0.0, "time": 0.0, "full_time": 0.0}
var _args := {}
## Bölüm Tasarımcısı testi: denenen tasarım (editörden "Oyna"/"Test et" ya da --level=dosya)
var _level_test := false
var _level_done := false
var _level_auto := false
## Web: editörle paylaşılan tarayıcı hafızası anahtarları (aynı adres: Runny/ ve Runny/editor/)
const LEVEL_KEY := "runny_level_test"
const RESULT_KEY := "runny_level_result"
## Otomatik pilot testinde koşular sırayla bu arabalarla yapılır
const TEST_MODELS := [1, 2, 3, 4, 6, 7]
## JavaScript'ten yeniden başlatma çağrısı (silinirse çağrı kaybolur, bu yüzden tutulur)
var _restart_cb: JavaScriptObject


func _ready() -> void:
	_parse_args()
	var seed_value := int(_args.get("seed", "-1"))
	if seed_value >= 0:
		seed(seed_value)  # testler tekrarlanabilir olsun (sendeleme vb. randf kullanır)
	car.roads = roads
	if _args.has("autopilot"):
		car.autopilot = Autopilot.new(car, roads, lower, float(_args.get("dive", "0")), not _args.has("noboost"))
		car.autopilot.seek_dead_ends = _args.has("deadend")
		car.autopilot.seek_side = _args.has("side")
		car.autopilot.collect_crystals = not _args.has("nocrystal")
	car.landed.connect(_on_landed)
	car.mode_changed.connect(_on_mode_changed)
	car.died.connect(_on_game_over)
	hud.garage_pressed.connect(_to_garage)
	car.jumped.connect(Audio.play.bind("jump", -6.0))
	car.exploded.connect(_on_exploded)
	car.boosted.connect(_on_boosted)
	car.boost_empty.connect(_on_boost_empty)
	lower.setup(car, roads, seed_value)
	lower.crystal_collected.connect(_on_crystal)
	lower.rock_hit.connect(_on_rock_hit)
	lower.portal_entered.connect(_on_portal)
	Tuning.register({"game": self, "car": car, "roads": roads, "lower": lower,
		"camera": $Camera, "audio": Audio, "trail": car.trail, "speedo": hud.speedometer})
	# Garajda seçilen araba
	car.model.variant = int(_args.get("model", _load_save().get_value("car", "model", 1)))
	if _args.has("trail"):
		car.trail.style = int(_args.trail)
	roads.keep_history = _args.has("dump_roads")
	if _args.has("crystal_color"):
		roads.crystal_color = Color(_args.crystal_color)
	hud.gauge.color = roads.crystal_color
	if _args.has("nohud"):
		hud.visible = false  # tasarım taslakları için temiz arka plan
	car.speed = car.start_speed
	car.energy = car.max_energy
	roads.car = car
	roads.load_levels()
	_setup_level_test()
	_start_z = car.global_position.z
	_landings_total = int(_load_save().get_value("tutorial", "landings", 0))
	roads.set_crystal_color(roads.crystal_color)
	roads.start(car, seed_value)
	_apply_mood(0.0)


func _physics_process(delta: float) -> void:
	if game_over:
		_over_time += delta
		return
	roads.update(car.global_position)
	lower.update(delta)
	_check_level_test()
	score += maxf(-car.velocity.z, 0.0) * delta * multiplier
	_update_high_route(delta)
	_update_gravel(delta)
	var got := 0 if _args.has("nocrystal") else roads.collect_crystals(car.global_position, car.model.half_width, car.half_length)
	_stats.time += delta
	if car.energy >= car.max_energy - 1.0:
		_stats.full_time += delta
	if got > 0:
		# Depo doluyken boşa giden kristaller (denge ölçümü)
		_stats.wasted += maxf(got * roads.crystal_value - (car.max_energy - car.energy), 0.0) / roads.crystal_value
		car.add_energy(got * roads.crystal_value)
		hud.gauge.gained(got * roads.crystal_value)
		_stats.crystals += got
		for i in got:
			Audio.crystal()

	match car.mode:
		Car.Mode.DRIVE:
			_mult_timer += delta
			if _mult_timer >= multiplier_step_time and multiplier < max_multiplier:
				_mult_timer = 0.0
				multiplier += 1
				hud.popup("x%d" % multiplier)
				Audio.play("multiplier")
		Car.Mode.FLYING:
			var burn := energy_drain * delta * (boost_drain_factor if car.climbing else 1.0)
			if car.energy > 0.0:
				car.energy = maxf(car.energy - burn, 0.0)
			elif not car.reserve_on:
				car.start_reserve(energy_drain * wing_reserve_time)
				hud.popup("YEDEK", true)
				Audio.play("hiss")
			else:
				car.reserve -= burn
				if car.reserve <= 0.0:
					car.reserve = 0.0
					car.lose_wings()
					hud.popup("ENERJİ BİTTİ", true)
					Audio.play("fall")

	if car.energy < EnergyGauge.LOW_AT and not _energy_warned:
		_energy_warned = true
		Audio.play("energy_low")
	elif car.energy > EnergyGauge.LOW_AT + 10.0:
		_energy_warned = false
	hud.set_score(int(score), multiplier)
	hud.gauge.collect_hint = not lower.active
	hud.set_energy_value(car.energy, car.max_energy)
	var driving := car.mode == Car.Mode.DRIVE
	hud.set_speed(car.forward_speed * car.surface_drag if driving else -car.velocity.z, car.speed, car.boost_level, driving)
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
	print("F%d MODE %d->%d z=%.0f x=%.1f y=%.1f vz=%.1f energy=%.0f" % [Engine.get_process_frames(), previous, mode, car.position.z, car.position.x, car.position.y, car.velocity.z, car.energy])
	# Tasarım testinde yoldan düşmek de başarısızlık (uçuşa düşen tasarımı geçemedi)
	if mode == Car.Mode.FALLING and _level_test and not _level_done and not roads.custom_log.is_empty():
		_level_result(false, "DÜŞTÜN")
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
			if _args.has("fly_energy"):
				car.energy = minf(car.energy, float(_args.fly_energy))  # test: az enerjiyle düş
			hud.popup("KANATLAR")
			Audio.play("wings")
			_flight_hint()
		Car.Mode.LAUNCH:
			hud.popup("YUKARI", true)
			Audio.play("portal")


func _on_landed(air_time: float, quality: float, impact: float) -> void:
	# Kamera: çarpma hızı ve yamukluk kadar sarsılır
	var shake := clampf(impact / 40.0, 0.0, 0.35) + quality * 0.5
	if shake > 0.08:
		$Camera.shake(shake)
	if lower.active:
		# Alt katmandan yola döndük
		lower.deactivate()
		Audio.play("return")
		Audio.touchdown(1.3)
		hud.popup("TEKRAR YOLDA")
		_stats.returns += 1
		return
	if air_time < 0.3:
		return
	_landings_total += 1
	Audio.touchdown(clampf(air_time / 0.8, 0.6, 1.3) + quality * 0.3)
	if quality > 0.05:
		_stats.hard += 1
		hud.popup("SERT İNİŞ" if quality < 0.5 else "SENDELEDİN")
		return
	_stats.clean += 1
	var seg := roads.segment_under(car.global_position)
	if seg == null:
		return
	var off := absf(car.global_position.x - seg.x) / (seg.width * 0.5)
	if off < 0.3:
		score += PERFECT_BONUS * multiplier
		hud.popup("PERFECT", true)
		Audio.play("perfect", -2.0)


## Çakıl: kamera hafif titrer; ilk birkaç seferde ne olduğu yazılır
func _update_gravel(delta: float) -> void:
	if car.on_gravel and car.is_on_floor():
		$Camera.shake(delta * 2.2)
		if not _was_on_gravel:
			var cfg := _load_save()
			var seen := int(cfg.get_value("tutorial", "gravel", 0))
			if seen < 3:
				hud.popup("ÇAKIL  ·  YAVAŞLATIR")
				cfg.set_value("tutorial", "gravel", seen + 1)
				cfg.save(SAVE_PATH)
	_was_on_gravel = car.on_gravel and car.is_on_floor()


## Çatalın yüksek (dar, zor) kolu: üstünde puan iki kat, bitirince ödül
func _update_high_route(delta: float) -> void:
	if car.mode != Car.Mode.DRIVE or not car.is_on_floor():
		return
	var seg := roads.segment_under(car.global_position)
	if seg == null:
		return
	if seg.bonus:
		score += maxf(-car.velocity.z, 0.0) * delta * multiplier
		if not _on_high_route:
			_on_high_route = true
			_stats.high += 1
			hud.popup("YÜKSEK YOL  ×2", true)
			Audio.play("multiplier")
	elif _on_high_route:
		_on_high_route = false
		if seg.route == 0:
			score += HIGH_ROUTE_BONUS * multiplier
			hud.popup("+%d" % (HIGH_ROUTE_BONUS * multiplier), true)
			Audio.play("perfect", -2.0)


func _to_garage() -> void:
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


## Roket ateşlendi: kükreme (kamera oynamaz)
func _on_boosted() -> void:
	Audio.play("boost", -2.0, randf_range(0.97, 1.03))


## Enerji yokken gaza basıldı: roket yanmaz
func _on_boost_empty() -> void:
	_stats.empty += 1
	hud.gauge.empty()
	Audio.play("empty")


func _on_exploded() -> void:
	Audio.play("explosion")
	$Camera.shake(1.0)


## İlk birkaç uçuşta yükselme ipucu
func _flight_hint() -> void:
	var cfg := _load_save()
	var flights := int(cfg.get_value("tutorial", "flights", 0))
	if flights < 3:
		hud.hint("İKİ PARMAKLA BAS  ·  YÜKSEL", 2.5)
		cfg.set_value("tutorial", "flights", flights + 1)
		cfg.save(SAVE_PATH)


## İlk yolun sonuna yaklaşırken, oyuncu gazı öğrenene kadar ipucu göster
func _update_hint() -> void:
	if _hint_shown or _landings_total >= TUTORIAL_LANDINGS or car.mode != Car.Mode.DRIVE:
		return
	var seg := roads.segment_under(car.global_position)
	if seg and (car.global_position.z - seg.road_end_z()) / car.forward_speed < 1.1:
		_hint_shown = true
		hud.hint("KIRMIZI IŞIKLARDA İKİ PARMAK  ·  ROKET", 1.6)


func _load_save() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	return cfg


func _on_crystal() -> void:
	car.add_energy(crystal_energy)
	hud.gauge.gained(crystal_energy)
	score += CRYSTAL_BONUS
	_stats.crystals += 1
	Audio.crystal()


func _on_rock_hit() -> void:
	if car.mode == Car.Mode.FLYING:
		car.crash("KAYAYA ÇARPTIN!")


func _on_portal(p: LowerLayer.Portal) -> void:
	if car.mode == Car.Mode.FLYING:
		car.launch_to(p.land, p.clear_y, p.path)


func _on_game_over(reason: String) -> void:
	game_over = true
	if _level_test and not _level_done:
		_level_result(false, reason)
	hud.hide_gauges()
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
		print("  car pos=%v vel=%v boost=%.2f" % [car.global_position, car.velocity, car.boost_level])
		for sg in roads.segments:
			if sg.z_end < car.global_position.z + 200.0 and sg.z_start > car.global_position.z - 60.0:
				print("  seg main=%s dead=%s x=%.1f w=%.1f top=%.2f->%.2f z=[%.0f..%.0f] slope=%.3f" % [sg.main, sg.dead_end, sg.x, sg.width, sg.top, sg.top_end, sg.z_start, sg.z_end, sg.slope()])
				for o in sg.obstacles:
					print("    obs x=%.1f..%.1f z=%.0f..%.0f gravel=%s ramp=%s" % [o.x0, o.x1, o.z0, o.z1, o.gravel, o.get("ramp", false)])
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
## Tasarım testi: --level=dosya.json ya da web'de ?level=test (tasarım tarayıcı hafızasında).
## Tasarım başlangıç pistinden hemen sonra gelir; araba tasarımın hızıyla başlar.
func _setup_level_test() -> void:
	var text := ""
	if _args.has("level"):
		text = FileAccess.get_file_as_string(_args.level)
	elif _web_param("level") != "":
		text = str(JavaScriptBridge.eval("localStorage.getItem('%s') || ''" % LEVEL_KEY))
		if _web_param("autopilot") != "":
			_level_auto = true
			var done := int(JavaScriptBridge.eval("JSON.parse(localStorage.getItem('%s') || '[]').length" % RESULT_KEY))
			car.model.variant = TEST_MODELS[done % TEST_MODELS.size()]
			car.autopilot = Autopilot.new(car, roads, lower, 0.0, true)
			Engine.time_scale = 2.0
	if text == "":
		return
	var level := RoadGenerator.parse_level(text)
	if level.is_empty():
		return
	roads.test_level = level
	_level_test = true
	if OS.has_feature("web") and not _level_auto:
		# Editördeki "Baştan" düğmesi (ve R tuşu) bölümü sayfayı yenilemeden yeniden başlatır
		_restart_cb = JavaScriptBridge.create_callback(_js_restart)
		JavaScriptBridge.get_interface("window").runnyRestart = _restart_cb
	if car.autopilot:
		car.autopilot.full_ramps = true
	car.speed = roads.speed_at_distance(float(level.get("at", 0.0)))


func _js_restart(_args: Array) -> void:
	get_tree().reload_current_scene.call_deferred()


## Web adresindeki parametre (?ad=değer); yoksa ya da web değilse boş
func _web_param(key: String) -> String:
	if not OS.has_feature("web"):
		return ""
	var v: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('%s') || ''" % key)
	return "" if v == null else str(v)


## Tasarım testi bitti: geçti ya da şurada düştü/çakıldı (tasarım koordinatlarında)
func _level_result(ok: bool, reason: String) -> void:
	_level_done = true
	var d := roads.to_design(car.global_position)
	print("LEVEL_%s reason=%s x=%.1f z=%.1f model=%d" % ["PASS" if ok else "FAIL", reason, d.x, d.y, car.model.variant])
	if ok:
		hud.popup("TASARIM GEÇİLDİ", true)
	if not OS.has_feature("web"):
		return
	var rec := JSON.stringify({"ok": ok, "reason": reason, "x": snappedf(d.x, 0.1), "z": snappedf(d.y, 0.1),
		"model": car.model.variant, "auto": _level_auto})
	JavaScriptBridge.eval("(function(){var a=JSON.parse(localStorage.getItem('%s')||'[]');a.push(%s);localStorage.setItem('%s',JSON.stringify(a));})()" % [RESULT_KEY, rec, RESULT_KEY])
	if _level_auto:
		var runs := int(_web_param("runs")) if _web_param("runs") != "" else 6
		var done := int(JavaScriptBridge.eval("JSON.parse(localStorage.getItem('%s') || '[]').length" % RESULT_KEY))
		if done < runs:
			get_tree().create_timer(0.6 * Engine.time_scale).timeout.connect(get_tree().reload_current_scene)
		else:
			Engine.time_scale = 1.0


## Tasarım testinde: araba tasarımın çıkış yolunun sonuna sağ vardı mı
func _check_level_test() -> void:
	if not _level_test or _level_done or roads.custom_log.is_empty():
		return
	var c: Dictionary = roads.custom_log[0]
	# Çıkış yolunun sonuna (ya da ardından gelen yola) tekerlekler yerde varılmalı
	if car.mode == Car.Mode.DRIVE and car.is_on_floor() and car.global_position.z <= float(c.exit_z) + 6.0:
		_level_result(true, "geçti")


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""


func _stats_text() -> String:
	return "distance=%.0f score=%d speed=%.1f falls=%d returns=%d crystals=%d landings=%d/%d high=%d energy=%d empty=%d wasted=%d full=%d%%" % [
		_start_z - car.position.z, int(score), car.speed,
		_stats.falls, _stats.returns, _stats.crystals, _stats.clean, _stats.clean + _stats.hard, _stats.high,
		int(car.energy), _stats.empty, int(_stats.wasted), int(100.0 * _stats.full_time / maxf(_stats.time, 0.01))]


func _exit_tree() -> void:
	if car.autopilot and not game_over:
		print("ALIVE %s" % _stats_text())
	if car.autopilot:
		print("PATTERNS %s %s" % [roads.pattern_counts, roads.stats])
		print("SIDE_TRIPS %d" % car.autopilot.side_trips)
	if _args.has("dump_roads"):
		_dump_roads(_args.dump_roads)


## Test/analiz: üretilen bütün yolları (engeller, rampalar dahil) JSON'a yaz
func _dump_roads(path: String) -> void:
	var out := []
	for sg in roads.history:
		out.append({"x": sg.x, "w": sg.width, "top": sg.top, "top_end": sg.top_end,
			"z0": sg.z_start, "z1": sg.z_end, "main": sg.main, "ramp": sg.ramp, "kick": sg.kick,
			"side": sg.side_road, "dead_end": sg.dead_end, "bank": sg.bank_a.size() > 0 and not sg.ramp,
			"events": sg.events_log, "flush": sg.next_flush != null,
			"kind": sg.pattern, "obstacles": sg.obstacles.map(func(o: Dictionary) -> Dictionary:
				var c := o.duplicate()
				c.erase("node")
				return c)})
	out.append({"crystal_z": roads.crystal_z_history})
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
