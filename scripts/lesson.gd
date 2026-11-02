class_name Lesson
extends CanvasLayer
## Nasıl oynanır: oyunun içinde, oynanarak geçilen dersler. Her ders kendi yolunda (el yapımı
## kalıp, editördeki biçimde) bir görev verir; büyük yuvarlaklar nereye dokunulacağını gösterir.
## Görev bitince ✓ ve NEXT; yoldan düşmek ya da çarpmak dersi baştan başlatır.
## Ders sırası: Lesson.current (sahne değişse de kalır); -1 = ders yok (normal oyun).

static var current := -1
## Önceki deneme düştü/çarptı: ders açık renkten yumuşakça açılır, araba yanıp söner
static var retry := false

const COUNT := 5
## [başlık, kalıp, hedef sayısı]
const LESSONS := [
	["STEER", {"pieces": [{"id": 1, "w": 12, "len": 4000, "h0": 0, "h1": 0, "x": 0, "z0": 0}], "obstacles": []}, 5],
	["BOOST", {"pieces": [
		{"id": 1, "w": 10, "len": 130, "h0": 0, "h1": 0, "x": 0, "z0": 0},
		{"id": 2, "w": 10, "len": 170, "h0": 0, "h1": 0, "x": 0, "z0": 176},
		{"id": 3, "w": 10, "len": 170, "h0": 0, "h1": 0, "x": 0, "z0": 392},
		{"id": 4, "w": 10, "len": 170, "h0": 0, "h1": 0, "x": 0, "z0": 608},
		{"id": 5, "w": 10, "len": 900, "h0": 0, "h1": 0, "x": 0, "z0": 824}], "obstacles": []}, 3],
	["ENERGY", {"pieces": [
		{"id": 1, "w": 10, "len": 150, "h0": 0, "h1": 0, "x": 0, "z0": 0},
		{"id": 2, "w": 10, "len": 260, "h0": 0, "h1": 0, "x": 0, "z0": 196},
		{"id": 3, "w": 10, "len": 260, "h0": 0, "h1": 0, "x": 0, "z0": 502},
		{"id": 4, "w": 10, "len": 900, "h0": 0, "h1": 0, "x": 0, "z0": 808}], "obstacles": []}, 15],
	# Sırayla: iki blok, iki çakıl, iki tümsek (yazı sıradaki engele göre değişir)
	["OBSTACLES", {"pieces": [{"id": 1, "w": 10, "len": 1600, "h0": 0, "h1": 0, "x": 0, "z0": 0}], "obstacles": [
		{"id": 10, "kind": "block", "w": 3.6, "len": 1.2, "x": -2.6, "z0": 110},
		{"id": 11, "kind": "block", "w": 3.6, "len": 1.2, "x": 2.6, "z0": 250},
		{"id": 12, "kind": "gravel", "w": 4.5, "len": 30, "x": -2.4, "z0": 400},
		{"id": 13, "kind": "gravel", "w": 4.5, "len": 30, "x": 2.4, "z0": 560},
		{"id": 14, "kind": "bump", "w": 10, "len": 12, "rise": 1.2, "x": 0, "z0": 720},
		{"id": 15, "kind": "bump", "w": 10, "len": 12, "rise": 1.2, "x": 0, "z0": 860}]}, 6],
	["WINGS", {"pieces": [
		{"id": 1, "w": 10, "len": 5, "h0": 0, "h1": 0, "x": 0, "z0": 0},
		{"id": 2, "w": 10, "len": 300, "h0": 0, "h1": 0, "x": 0, "z0": 330}], "obstacles": []}, 3],
]
## Enerji dersinin kristalleri: 5'li setler (sol, sağ, sol), setlerin arası açık. [x, ilk z]; set içinde 7 m ara
const CRYSTAL_SETS := [[-2.5, 60.0], [2.5, 250.0], [-2.5, 380.0]]
const CRYSTAL_STEP := 7.0
## Direksiyon dersinin adımları
const STEER_STEPS := ["LEFT", "RIGHT", "LEFT", "RIGHT", "STRAIGHT"]
## Yolun ortasından bu kadar yana gidince o yön tamam
const STEER_REACH := 2.8

var game: Node
var car: Car
var roads: RoadGenerator
var index := 0
var done := 0
var finished := false
var failed := false
var _straight_time := 0.0
var _blocks_passed := {}
var _flew := false
var _climb_time := 0.0
var _crystals_placed := false
## Kanat dersinde öndeki kaya (geçilince sıradaki konur)
var _rock: Dictionary = {}
var _t := 0.0
## Yuvarlakların görünürlüğü (yumuşak belirip kaybolur): -1 sol, 1 sağ
var _pad_alpha := {-1: 0.0, 1: 0.0}
## Araba dersin yoluna girdi mi (başlangıç pistinde görev yok)
var started := false

var _ui: Control
var _pads: Control
var _head: Label
var _title: Label
var _say: Label
var _say_box: PanelContainer
var _pips: HBoxContainer
var _panel: Control
## Solma perdesi ve ortadaki MISSED yazısı
var _fade: ColorRect
var _bot := false
## Test: bot hep sola basar (yoldan düşmeyi görmek için)
var bot_fall := false


## Oyun kurulurken (roads.start'tan önce) çağrılır
func setup(p_game: Node, p_car: Car, p_roads: RoadGenerator, bot := false) -> void:
	game = p_game
	car = p_car
	roads = p_roads
	_bot = bot
	index = clampi(current, 0, COUNT - 1)
	var level: Dictionary = (LESSONS[index][1] as Dictionary).duplicate(true)
	level.merge({"format": "runny-level", "version": 1, "name": "lesson %d" % (index + 1), "at": 0,
		"crystals": false, "flush_entry": true,
		"no_lights": LESSONS[index][0] == "WINGS"})
	roads.start_lights = false  # başlangıç pisti ışıksız ve kısa: ders yolu onun düz devamı
	roads.start_length = 50.0
	AudioServer.set_bus_mute(0, false)
	roads.test_level = level
	if LESSONS[index][0] == "ENERGY":
		car.energy = car.max_energy * 0.35  # göstergenin dolduğu görülsün
	if LESSONS[index][0] == "WINGS":
		game.lower.first_portal_time = Vector2(5.0, 6.0)  # tünel tırmanmayı öğrendikten sonra gelsin
		roads.start_length = 32.0  # yol ~1 sn'de biter
		game.lower.scripted = true  # yalnız dersin iki kayası (tam uçağın önünde), sonra tünel
		game.lower.first_portal_time = Vector2(60.0, 61.0)  # tüneli ders, ikinci kayadan sonra planlar
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_refresh()
	Engine.time_scale = 1.0
	if retry:
		retry = false
		_fade.color.a = 1.0
		var tw := create_tween()
		tw.tween_property(_fade, "color:a", 0.0, 0.5).set_delay(0.1)
		# Araba yerine "geri konmuş" gibi birkaç kez yanıp söner
		var blink := create_tween().set_loops(4)
		blink.tween_callback(func(): car.model.visible = false).set_delay(0.12)
		blink.tween_callback(func(): car.model.visible = true).set_delay(0.12)


func _goal() -> int:
	return int(LESSONS[index][2])


func _process(delta: float) -> void:
	_t += delta
	var target := _pad_target()
	for side in [-1, 1]:
		var want := 1.0 if (target == side or target == 2) else 0.0
		_pad_alpha[side] = move_toward(_pad_alpha[side], want, delta * 5.0)
	_pads.queue_redraw()
	if finished or failed or get_tree().paused:
		return
	if not started:
		# Araba yola indiği an (başlangıç pisti dersin yolunun düz devamı)
		if _t > 0.5 and car.mode == Car.Mode.DRIVE and car.is_on_floor():
			started = true
			print("LESSON_START %d F%d" % [index, Engine.get_process_frames()])
			_refresh()
		return
	match LESSONS[index][0]:
		"STEER":
			_update_steer(delta)
		"OBSTACLES":
			_update_blocks()
		"WINGS":
			_update_rocks()
		"ENERGY":
			_place_crystals()
			# Son setin ardından eksik kaldıysa: ders baştan
			if done < _goal() and not roads.custom_log.is_empty() and roads.to_design(car.global_position).y > CRYSTAL_SETS[-1][1] + 5.0 * CRYSTAL_STEP + 10.0:
				fail("MISSED CRYSTALS")
	if _bot:
		_bot_input()


func _update_steer(delta: float) -> void:
	if car.mode != Car.Mode.DRIVE:
		return
	var seg := roads.segment_under(car.global_position)
	if seg == null:
		return
	var dx := car.global_position.x - seg.x
	match STEER_STEPS[done]:
		"LEFT":
			if dx < -STEER_REACH:
				_step()
		"RIGHT":
			if dx > STEER_REACH:
				_step()
		"STRAIGHT":
			if absf(car._steer) < 0.05 and absf(car.velocity.x) < 0.6:
				_straight_time += delta
				if _straight_time > 1.2:
					_step()
			else:
				_straight_time = 0.0


## Enerji dersi: kristal setlerini dersin yoluna koyar (tasarım koordinatından dünyaya)
func _place_crystals() -> void:
	if _crystals_placed or roads.custom_log.is_empty():
		return
	_crystals_placed = true
	var c: Dictionary = roads.custom_log[0]
	for st in CRYSTAL_SETS:
		for i in 5:
			var wx: float = float(c.ox) + float(st[0])
			var wz: float = float(c.zb) - (float(st[1]) + i * CRYSTAL_STEP)
			var host := roads.segment_under(Vector3(wx, car.global_position.y, wz))
			if host:
				roads._crystal_on(host, wx, wz)
	roads._flush_crystals()


## Kanat dersi: uçağın tam önüne (aynı hiza, aynı yükseklik) bir kaya; üstünden geçince sıradaki.
## İki kaya geçilince tünel gelir
func _update_rocks() -> void:
	if not _flew or car.mode != Car.Mode.FLYING or done >= 2:
		return
	if _rock.is_empty():
		# Uçuş yüksekliğinde (araba oraya iner), tam uçağın hizasında, ~3 sn önde
		var p := Vector3(car.global_position.x, car.flight_altitude - 0.8, car.global_position.z - maxf(car.forward_speed, 30.0) * 3.0)
		_rock = game.lower.place_rock(p, 2.6)
		return
	if car.global_position.z < float(_rock.z) - 4.0:
		_rock = {}
		car.energy = car.max_energy  # derste enerji bitmesin
		_step()
		if done == 2:
			# İki kaya geçildi: tünel ~4 sn sonra (arada nefes alınsın)
			game.lower.plan_portal_at(car.global_position.z - maxf(car.forward_speed, 30.0) * 4.0)


## Engeller dersi: geçilen engeller (tasarım koordinatında arabanın z'si engeli geçti; havadayken
## sayılmaz: tümsekten inince)
func _update_blocks() -> void:
	if roads.custom_log.is_empty() or car.mode != Car.Mode.DRIVE or not car.is_on_floor():
		return
	var z: float = roads.to_design(car.global_position).y
	for o in LESSONS[index][1].obstacles:
		if z > float(o.z0) + float(o.get("len", 1.2)) + 2.0 and not _blocks_passed.has(o.id):
			_blocks_passed[o.id] = true
			_step()


func _step() -> void:
	done += 1
	print("LESSON_STEP %d %d F%d" % [index, done, Engine.get_process_frames()])
	_straight_time = 0.0
	Audio.play("perfect", -4.0)
	_refresh()
	if done >= _goal():
		_success()


# ---------------------------------------------------------------- oyundan gelen olaylar

func on_landed(air_time: float) -> void:
	if LESSONS[index][0] == "BOOST" and started and air_time > 0.4 and not finished:
		_step()


func on_crystals(n: int) -> void:
	if LESSONS[index][0] != "ENERGY" or finished or not started:
		return
	for i in n:
		if done < _goal():
			_step()


func on_mode_changed(mode: Car.Mode, previous: Car.Mode) -> void:
	if finished or failed:
		return
	if LESSONS[index][0] == "WINGS":
		if mode == Car.Mode.FLYING:
			_flew = true
			car.energy = car.max_energy  # ilk uçuşta enerji bitmesin
			_refresh()
		elif mode == Car.Mode.DRIVE and _flew and previous == Car.Mode.LAUNCH:
			while done < _goal() and not finished:
				_step()
		return
	# Diğer derslerde yoldan düşmek: ders baştan
	if mode == Car.Mode.FALLING:
		fail("MISSED")


## Çarpma ya da düşme: ağır çekim, ekran yumuşakça açık renge solar, ortada MISSED; sonra ders
## baştan (yeni ders de aynı renkten açılır, araba birkaç kez yanıp söner)
func fail(reason: String) -> void:
	if failed or finished:
		return
	failed = true
	print("LESSON_FAIL %d %s z=%.0f x=%.1f" % [index, reason, car.global_position.z, car.global_position.x])
	_say.text = "%s  ·  TRY AGAIN" % reason.trim_suffix("!")
	_say_box.add_theme_stylebox_override("panel", _pill(Palette.ACCENT))
	var tw := create_tween().set_ignore_time_scale(true).set_parallel()
	# Ağır çekim (kanatlar açılmadan ekran solar)
	tw.tween_method(func(v: float): Engine.time_scale = v, 1.0, 0.15, 0.35).set_ease(Tween.EASE_OUT)
	tw.tween_property(_fade, "color:a", 1.0, 0.6).set_delay(0.25)
	tw.tween_method(func(v: float): AudioServer.set_bus_volume_db(0, v), 0.0, -40.0, 0.7)
	tw.chain().tween_interval(0.45)
	tw.chain().tween_callback(func():
		Engine.time_scale = 1.0
		AudioServer.set_bus_volume_db(0, 0.0)
		retry = true
		get_tree().reload_current_scene())


func _success() -> void:
	finished = true
	print("LESSON_DONE %d" % index)
	# Düşüşteki gibi: ağır çekim, sahne açık renge solar (üstteki yazılar kalır), ses kısılır;
	# sonra ✓, NICE ve butonlar belirir, oyun durur
	var tw := create_tween().set_ignore_time_scale(true).set_parallel()
	tw.tween_method(func(v: float): Engine.time_scale = v, 1.0, 0.15, 0.35).set_ease(Tween.EASE_OUT)
	tw.tween_property(_fade, "color:a", 1.0, 0.6).set_delay(0.2)
	tw.tween_method(func(v: float): AudioServer.set_bus_volume_db(0, v), 0.0, -40.0, 0.7)
	tw.chain().tween_callback(func():
		_build_panel()
		if not _bot:
			get_tree().paused = true
			Engine.time_scale = 1.0
			AudioServer.set_bus_mute(0, true))  # panelde araba sesi yok
	if _bot:
		get_tree().create_timer(1.6, true, false, true).timeout.connect(_next)


func _next() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	AudioServer.set_bus_volume_db(0, 0.0)
	AudioServer.set_bus_mute(0, false)
	if index + 1 >= COUNT:
		current = -1
		get_tree().reload_current_scene()  # gerçek oyun başlar
	else:
		current = index + 1
		get_tree().reload_current_scene()


## Aynı ders baştan
func _replay() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	AudioServer.set_bus_volume_db(0, 0.0)
	AudioServer.set_bus_mute(0, false)
	get_tree().reload_current_scene()


func _skip() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	AudioServer.set_bus_volume_db(0, 0.0)
	AudioServer.set_bus_mute(0, false)
	current = -1
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


# ---------------------------------------------------------------- görünüş

func _say_text() -> String:
	if not started:
		return "Get ready..."
	match LESSONS[index][0]:
		"STEER":
			match STEER_STEPS[mini(done, STEER_STEPS.size() - 1)]:
				"LEFT":
					return "Touch and hold the LEFT side"
				"RIGHT":
					return "Now the RIGHT side"
				_:
					return "Let go: drive straight"
		"BOOST":
			return "Red lights: hold TWO fingers to jump"
		"ENERGY":
			return "Boost uses energy: collect %d crystals" % _goal()
		"OBSTACLES":
			match _next_obstacle():
				"gravel":
					return "Gravel slows you: steer around it"
				"bump":
					return "Bumps throw you up: keep it straight"
			return "Steer around the striped blocks"
		"WINGS":
			if not _flew:
				return "Road ends: keep going, wings open"
			if done < 2:
				return "Rock ahead: hold TWO fingers to climb"
			return "Steer into the orange tunnel"
	return ""


## Hangi yuvarlak(lar) yansın: -1 sol, 1 sağ, 2 ikisi birden, 0 hiçbiri (soluk)
func _pad_target() -> int:
	if not started or failed:
		return 0
	match LESSONS[index][0]:
		"STEER":
			match STEER_STEPS[mini(done, STEER_STEPS.size() - 1)]:
				"LEFT":
					return -1
				"RIGHT":
					return 1
			return 0
		"BOOST":
			var seg := roads.segment_under(car.global_position)
			# Yalnız dersin yolunda, roket isteyen bir boşluktan önce (başlangıç pistinin ucu boşluk değil)
			if seg and seg.custom and not seg.hop and car.mode == Car.Mode.DRIVE and (car.global_position.z - seg.road_end_z()) / maxf(car.forward_speed, 1.0) < 1.7:
				return 2
			return 0
		"WINGS":
			if not _flew or car.mode != Car.Mode.FLYING:
				return 0
			if done < 2:
				# Kaya yaklaşınca iki parmak
				if not _rock.is_empty() and (car.global_position.z - float(_rock.z)) / maxf(car.forward_speed, 1.0) < 2.3:
					return 2
				return 0
			return _tunnel_side()
	return 0


## Sıradaki geçilmemiş engelin türü (engeller dersi)
func _next_obstacle() -> String:
	for o in LESSONS[index][1].obstacles:
		if not _blocks_passed.has(o.id):
			return str(o.kind)
	return ""


## En yakın öndeki tünel hangi yanda: -1 sol, 1 sağ, 0 tam önünde
func _tunnel_side() -> int:
	var best: Variant = null
	for p in game.lower.portals:
		if p.z < car.global_position.z - 5.0 and (best == null or p.z > best.z):
			best = p
	if best == null:
		return 0
	var dx: float = best.x - car.global_position.x
	if absf(dx) < 1.5:
		return 0
	return 1 if dx > 0.0 else -1


func _refresh() -> void:
	_head.text = "LESSON %d / %d" % [index + 1, COUNT]
	_title.text = LESSONS[index][0]
	_say.text = _say_text()
	for c in _pips.get_children():
		c.queue_free()
	var n := _goal()
	if n <= 1:
		return
	var sz := 34.0 if n <= 6 else 30.0
	for i in n:
		var p := Control.new()
		p.custom_minimum_size = Vector2(sz, sz)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ok := i < done
		p.draw.connect(func():
			var c := p.size * 0.5
			var r := sz * 0.5
			if ok:
				p.draw_circle(c, r, Palette.ACCENT)
				var k := r / 17.0
				p.draw_polyline(PackedVector2Array([c + Vector2(-8, 1) * k, c + Vector2(-2.5, 6.5) * k, c + Vector2(8.5, -5.5) * k]), Palette.SNOW, 3.6 * k, true)
			else:
				p.draw_circle(c, r, Color(Palette.SNOW, 0.75))
				p.draw_arc(c, r - 1.5, 0.0, TAU, 40, Color(Palette.INK_DARK, 0.35), 3.0, true))
		_pips.add_child(p)


func _build_ui() -> void:
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	# Oyun ekranı en tepeye kadar; başlık ve yönlendirme biraz aşağıda, kenarlı yazıyla
	_head = _label(_ui, 18, 104, true)
	_head.modulate.a = 0.7
	_title = _label(_ui, 50, 158, true)
	for l: Label in [_head, _title]:
		l.add_theme_color_override("font_outline_color", Palette.PAPER)
		l.add_theme_constant_override("outline_size", 10)
	# Yönlendirme: koyu yuvarlak kutuda büyük beyaz yazı
	# Kutu ve altındaki işaretler alt alta (kutu iki satıra düşse de işaretler hemen altında)
	var stack := VBoxContainer.new()
	stack.anchor_right = 1.0
	stack.offset_top = 210
	stack.offset_bottom = 420
	stack.add_theme_constant_override("separation", 16)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(stack)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(center)
	_say_box = PanelContainer.new()
	_say_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_say_box.add_theme_stylebox_override("panel", _pill(Color(Palette.INK_DARK, 0.82)))
	center.add_child(_say_box)
	_say = Label.new()
	_say.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_say.add_theme_font_size_override("font_size", 30)
	_say.add_theme_color_override("font_color", Palette.SNOW)
	_say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_say.custom_minimum_size.x = 560
	_say.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_say_box.add_child(_say)
	_pips = HBoxContainer.new()
	_pips.alignment = BoxContainer.ALIGNMENT_CENTER
	_pips.add_theme_constant_override("separation", 10)
	_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_pips)
	var skip := Button.new()
	skip.text = "SKIP"
	skip.flat = true
	skip.focus_mode = Control.FOCUS_NONE
	skip.add_theme_font_size_override("font_size", 20)
	skip.add_theme_color_override("font_outline_color", Palette.PAPER)
	skip.add_theme_constant_override("outline_size", 8)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		skip.add_theme_color_override(state, Color(Palette.INK_DARK, 0.5))
	skip.anchor_left = 1.0
	skip.anchor_right = 1.0
	skip.offset_left = -130
	skip.offset_right = -20
	skip.offset_top = 64
	skip.offset_bottom = 112
	skip.pressed.connect(_skip)
	_ui.add_child(skip)
	_pads = Control.new()
	_pads.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pads.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pads.draw.connect(_draw_pads)
	_ui.add_child(_pads)
	# Solma perdesi yazıların ve yuvarlakların arkasında (sahne solar, üstteki yazılar kalır)
	_fade = ColorRect.new()
	_fade.color = Color(Palette.PAPER, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(_fade)
	_ui.move_child(_fade, 0)



## Dokunma yuvarlakları: yalnız basılması gereken yerde belirir; parmak basar gibi küçülüp büyür,
## her basışta dışa iki yankı halkası yayılır
func _draw_pads() -> void:
	if finished:
		return
	var size := _pads.size
	var y := size.y * 0.73
	var period := 1.2
	var p := fmod(_t, period) / period
	# Basış: 0.10-0.22 arası içe çöker, 0.22-0.36 arası geri gelir
	var press := 1.0
	if p > 0.10 and p < 0.22:
		press = lerpf(1.0, 0.72, (p - 0.10) / 0.12)
	elif p >= 0.22 and p < 0.36:
		press = lerpf(0.72, 1.0, ease((p - 0.22) / 0.14, 0.5))
	for side in [-1, 1]:
		var a: float = _pad_alpha[side]
		if a < 0.01:
			continue
		var c := Vector2(size.x * (0.5 + 0.29 * side), y)
		# Yankı halkaları (basış anından başlar)
		for k in 2:
			var e := (p - 0.18 - k * 0.16) / 0.62
			if e >= 0.0 and e <= 1.0:
				_pads.draw_arc(c, 42.0 + e * 100.0, 0.0, TAU, 72, Color(Palette.ACCENT, 0.75 * (1.0 - e) * a), 2.0 + 5.0 * (1.0 - e), true)
		_pads.draw_circle(c, 64.0, Color(Palette.ACCENT, 0.22 * a))
		_pads.draw_circle(c, 36.0 * press, Color(Palette.SNOW, 0.96 * a))
		_pads.draw_arc(c, 36.0 * press, 0.0, TAU, 48, Color(Palette.ACCENT, a), 5.0, true)
		# Yön oku (direksiyon dersinde)
		if LESSONS[index][0] == "STEER":
			var tip := c + Vector2(side * 108.0, 0)
			var pts := PackedVector2Array([tip, tip + Vector2(-side * 30.0, -24.0), tip + Vector2(-side * 30.0, 24.0)])
			_pads.draw_colored_polygon(pts, Color(Palette.ACCENT, a))


## Başarı paneli: büyük ✓, yazı ve NEXT (son derste PLAY)
func _build_panel() -> void:
	_panel = Control.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	var bg := ColorRect.new()
	bg.color = Color(Palette.PAPER, 0.0)  # arka plan zaten solmuş (perde)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(bg)
	var tick := Control.new()
	tick.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tick.draw.connect(func():
		var c := Vector2(tick.size.x * 0.5, 470.0)
		tick.draw_circle(c, 120.0, Palette.ACCENT)
		var pts := PackedVector2Array([c + Vector2(-58, 4), c + Vector2(-16, 46), c + Vector2(62, -40)])
		tick.draw_polyline(pts, Palette.SNOW, 22.0, true))
	_panel.add_child(tick)
	var last := index + 1 >= COUNT
	var big := _label(_panel, 52, 680, true)
	big.text = "YOU'RE READY!" if last else "NICE!"
	var small := _label(_panel, 22, 750, false)
	small.text = "That's all you need. Have fun." if last else "%s done. Next: %s" % [LESSONS[index][0], LESSONS[index + 1][0]]
	small.modulate.a = 0.65
	var btn := Button.new()
	btn.text = "PLAY" if last else "NEXT"
	btn.focus_mode = Control.FOCUS_NONE
	var font := FontVariation.new()
	font.spacing_glyph = 6
	btn.add_theme_font_override("font", font)
	btn.add_theme_font_size_override("font_size", 34)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(state, Palette.SNOW)
	for state in [["normal", Palette.ACCENT], ["hover", Palette.ACCENT],
			["pressed", Palette.ACCENT.darkened(0.15)], ["focus", Palette.ACCENT]]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = state[1]
		sb.set_corner_radius_all(6)
		btn.add_theme_stylebox_override(state[0], sb)
	btn.anchor_left = 0.5
	btn.anchor_right = 0.5
	btn.anchor_top = 1.0
	btn.anchor_bottom = 1.0
	btn.offset_left = -210
	btn.offset_right = 210
	btn.offset_top = -255
	btn.offset_bottom = -150
	btn.pressed.connect(_next)
	_panel.add_child(btn)
	# Altında: aynı dersi tekrar oyna
	var again := Button.new()
	again.text = "REPLAY"
	again.focus_mode = Control.FOCUS_NONE
	var af := FontVariation.new()
	af.spacing_glyph = 6
	again.add_theme_font_override("font", af)
	again.add_theme_font_size_override("font_size", 28)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		again.add_theme_color_override(state, Palette.ACCENT)
	for state in [["normal", 0.0], ["hover", 0.0], ["pressed", 0.15], ["focus", 0.0]]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(6)
		sb.bg_color = Color(Palette.ACCENT, 0.06 + state[1])
		sb.set_border_width_all(3)
		sb.border_color = Palette.ACCENT
		again.add_theme_stylebox_override(state[0], sb)
	again.anchor_left = 0.5
	again.anchor_right = 0.5
	again.anchor_top = 1.0
	again.anchor_bottom = 1.0
	again.offset_left = -210
	again.offset_right = 210
	again.offset_top = -125
	again.offset_bottom = -40
	again.pressed.connect(_replay)
	_panel.add_child(again)
	_panel.modulate.a = 0.0
	create_tween().set_ignore_time_scale(true).tween_property(_panel, "modulate:a", 1.0, 0.35)


## Yönlendirme kutusu
func _pill(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 12
	sb.content_margin_bottom = 14
	return sb


func _label(parent: Control, size: int, y: float, spaced: bool) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Palette.INK_DARK)
	if spaced:
		var f := FontVariation.new()
		f.spacing_glyph = 5
		l.add_theme_font_override("font", f)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	l.anchor_right = 1.0
	l.offset_top = y - size
	l.offset_bottom = y + size
	return l


# ---------------------------------------------------------------- test: dersi kendi geçen bot

## Direksiyon dersinde tuşlara basar (diğer derslerde otomatik pilot sürer)
func _bot_input() -> void:
	if bot_fall:
		_key(KEY_A, true)
		return
	if LESSONS[index][0] == "WINGS" and _flew and car.mode == Car.Mode.FLYING:
		_key(KEY_W, _pad_target() == 2)
		var side := _tunnel_side() if done >= 1 else 0
		_key(KEY_A, side < 0)
		_key(KEY_D, side > 0)
		return
	if LESSONS[index][0] != "STEER" or not started:
		return
	var want: String = STEER_STEPS[mini(done, STEER_STEPS.size() - 1)]
	_key(KEY_A, want == "LEFT")
	_key(KEY_D, want == "RIGHT")


func _key(code: Key, down: bool) -> void:
	if Input.is_key_pressed(code) == down:
		return
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)
