class_name Lesson
extends CanvasLayer
## Nasıl oynanır: oyunun içinde, oynanarak geçilen dersler. Her ders kendi yolunda (el yapımı
## kalıp, editördeki biçimde) bir görev verir; büyük yuvarlaklar nereye dokunulacağını gösterir.
## Görev bitince ✓ ve NEXT; yoldan düşmek ya da çarpmak dersi baştan başlatır.
## Ders sırası: Lesson.current (sahne değişse de kalır); -1 = ders yok (normal oyun).

static var current := -1

const COUNT := 5
## [başlık, kalıp, hedef sayısı]
const LESSONS := [
	["STEER", {"pieces": [{"id": 1, "w": 12, "len": 4000, "h0": 0, "h1": 0, "x": 0, "z0": 0}], "obstacles": []}, 5],
	["BOOST", {"pieces": [
		{"id": 1, "w": 10, "len": 220, "h0": 0, "h1": 0, "x": 0, "z0": 0},
		{"id": 2, "w": 10, "len": 170, "h0": 0, "h1": 0, "x": 0, "z0": 266},
		{"id": 3, "w": 10, "len": 170, "h0": 0, "h1": 0, "x": 0, "z0": 482},
		{"id": 4, "w": 10, "len": 170, "h0": 0, "h1": 0, "x": 0, "z0": 698},
		{"id": 5, "w": 10, "len": 900, "h0": 0, "h1": 0, "x": 0, "z0": 914}], "obstacles": []}, 3],
	["ENERGY", {"pieces": [
		{"id": 1, "w": 10, "len": 260, "h0": 0, "h1": 0, "x": 0, "z0": 0},
		{"id": 2, "w": 10, "len": 260, "h0": 0, "h1": 0, "x": 0, "z0": 306},
		{"id": 3, "w": 10, "len": 260, "h0": 0, "h1": 0, "x": 0, "z0": 612},
		{"id": 4, "w": 10, "len": 900, "h0": 0, "h1": 0, "x": 0, "z0": 918}], "obstacles": []}, 15],
	["OBSTACLES", {"pieces": [{"id": 1, "w": 10, "len": 2000, "h0": 0, "h1": 0, "x": 0, "z0": 0}], "obstacles": [
		{"id": 10, "kind": "block", "w": 3.6, "len": 1.2, "x": -2.6, "z0": 220},
		{"id": 11, "kind": "block", "w": 3.6, "len": 1.2, "x": 2.6, "z0": 360},
		{"id": 12, "kind": "block", "w": 3.6, "len": 1.2, "x": -2.6, "z0": 500},
		{"id": 13, "kind": "block", "w": 3.6, "len": 1.2, "x": 2.6, "z0": 640},
		{"id": 14, "kind": "block", "w": 3.6, "len": 1.2, "x": -2.6, "z0": 780},
		{"id": 15, "kind": "block", "w": 3.6, "len": 1.2, "x": 2.6, "z0": 920}]}, 4],
	["WINGS", {"pieces": [
		{"id": 1, "w": 10, "len": 320, "h0": 0, "h1": 0, "x": 0, "z0": 0},
		{"id": 2, "w": 10, "len": 300, "h0": 0, "h1": 0, "x": 0, "z0": 640}], "obstacles": []}, 1],
]
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
var _t := 0.0
## Araba dersin yoluna girdi mi (başlangıç pistinde görev yok)
var started := false

var _ui: Control
var _pads: Control
var _head: Label
var _title: Label
var _say: Label
var _pips: HBoxContainer
var _panel: Control
var _bot := false


## Oyun kurulurken (roads.start'tan önce) çağrılır
func setup(p_game: Node, p_car: Car, p_roads: RoadGenerator, bot := false) -> void:
	game = p_game
	car = p_car
	roads = p_roads
	_bot = bot
	index = clampi(current, 0, COUNT - 1)
	var level: Dictionary = (LESSONS[index][1] as Dictionary).duplicate(true)
	level.merge({"format": "runny-level", "version": 1, "name": "lesson %d" % (index + 1), "at": 0,
		"crystals": LESSONS[index][0] == "ENERGY", "flush_entry": true})
	roads.test_level = level
	if LESSONS[index][0] == "ENERGY":
		car.energy = car.max_energy * 0.35  # göstergenin dolduğu görülsün
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_refresh()


func _goal() -> int:
	return int(LESSONS[index][2])


func _process(delta: float) -> void:
	_t += delta
	_pads.queue_redraw()
	if finished or failed or get_tree().paused:
		return
	if not started:
		var seg := roads.segment_under(car.global_position)
		if seg and seg.custom and car.mode == Car.Mode.DRIVE:
			started = true
			print("LESSON_START %d F%d" % [index, Engine.get_process_frames()])
			_refresh()
		return
	match LESSONS[index][0]:
		"STEER":
			_update_steer(delta)
		"OBSTACLES":
			_update_blocks()
	if _bot:
		_bot_input()


func _update_steer(delta: float) -> void:
	if car.mode != Car.Mode.DRIVE:
		return
	var seg := roads.segment_under(car.global_position)
	if seg == null or not seg.custom:
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


## Engeller dersi: geçilen bloklar (tasarım koordinatında arabanın z'si bloğu geçti)
func _update_blocks() -> void:
	if roads.custom_log.is_empty() or car.mode != Car.Mode.DRIVE:
		return
	var z: float = roads.to_design(car.global_position).y
	for o in LESSONS[index][1].obstacles:
		if z > float(o.z0) + 3.0 and not _blocks_passed.has(o.id):
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
			_step()
		return
	# Diğer derslerde yoldan düşmek: ders baştan
	if mode == Car.Mode.FALLING:
		fail("MISSED")


## Çarpma ya da düşme: kısa bir yazı, sonra ders baştan
func fail(reason: String) -> void:
	if failed or finished:
		return
	failed = true
	print("LESSON_FAIL %d %s z=%.0f x=%.1f" % [index, reason, car.global_position.z, car.global_position.x])
	_say.text = "%s  ·  TRY AGAIN" % reason.trim_suffix("!")
	_say.add_theme_color_override("font_color", Palette.ACCENT)
	get_tree().create_timer(1.6).timeout.connect(func(): get_tree().reload_current_scene())


func _success() -> void:
	finished = true
	print("LESSON_DONE %d" % index)
	_build_panel()
	get_tree().create_timer(0.5).timeout.connect(func():
		if is_instance_valid(self) and not _bot:
			get_tree().paused = true)
	if _bot:
		get_tree().create_timer(1.2).timeout.connect(_next)


func _next() -> void:
	get_tree().paused = false
	if index + 1 >= COUNT:
		current = -1
		get_tree().reload_current_scene()  # gerçek oyun başlar
	else:
		current = index + 1
		get_tree().reload_current_scene()


func _skip() -> void:
	get_tree().paused = false
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
			return "Red lights ahead: hold TWO fingers to jump"
		"ENERGY":
			return "Boost uses energy. Collect %d crystals" % _goal()
		"OBSTACLES":
			return "Steer around the striped blocks"
		"WINGS":
			if _flew:
				return "Hold TWO fingers to climb. Fly into the orange rings"
			return "The road ends. Keep going: your wings open"
	return ""


## Hangi yuvarlak(lar) yansın: -1 sol, 1 sağ, 2 ikisi birden, 0 hiçbiri (soluk)
func _pad_target() -> int:
	if not started:
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
			if seg and car.mode == Car.Mode.DRIVE and (car.global_position.z - seg.road_end_z()) / maxf(car.forward_speed, 1.0) < 1.3:
				return 2
			return 0
		"WINGS":
			return 2 if _flew else 0
	return 0


func _refresh() -> void:
	_head.text = "LESSON %d / %d" % [index + 1, COUNT]
	_title.text = LESSONS[index][0]
	_say.text = _say_text()
	for c in _pips.get_children():
		c.queue_free()
	var n := _goal()
	if n <= 1:
		return
	for i in n:
		var p := Panel.new()
		p.custom_minimum_size = Vector2(22, 22)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(11)
		if i < done:
			sb.bg_color = Palette.ACCENT
		else:
			sb.bg_color = Color(Palette.SNOW, 0.35)
			sb.set_border_width_all(2)
			sb.border_color = Color(Palette.INK_DARK, 0.35)
		p.add_theme_stylebox_override("panel", sb)
		_pips.add_child(p)


func _build_ui() -> void:
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	# Üstte yazıların okunması için hafif bir perde
	var shade := ColorRect.new()
	shade.color = Color(Palette.PAPER, 0.72)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.anchor_right = 1.0
	shade.offset_bottom = 300
	_ui.add_child(shade)
	_head = _label(_ui, 16, 52, true)
	_head.modulate.a = 0.55
	_title = _label(_ui, 46, 110, true)
	_say = _label(_ui, 24, 186, false)
	_say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_say.offset_left = 50
	_say.offset_right = -50
	_pips = HBoxContainer.new()
	_pips.alignment = BoxContainer.ALIGNMENT_CENTER
	_pips.add_theme_constant_override("separation", 14)
	_pips.anchor_right = 1.0
	_pips.offset_top = 240
	_pips.offset_bottom = 262
	_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_pips)
	var skip := Button.new()
	skip.text = "SKIP"
	skip.flat = true
	skip.focus_mode = Control.FOCUS_NONE
	skip.add_theme_font_size_override("font_size", 18)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		skip.add_theme_color_override(state, Color(Palette.INK_DARK, 0.5))
	skip.anchor_left = 1.0
	skip.anchor_right = 1.0
	skip.offset_left = -130
	skip.offset_right = -20
	skip.offset_top = 28
	skip.offset_bottom = 76
	skip.pressed.connect(_skip)
	_ui.add_child(skip)
	_pads = Control.new()
	_pads.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pads.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pads.draw.connect(_draw_pads)
	_ui.add_child(_pads)


## Büyük dokunma yuvarlakları: ekranın iki yarısında; hedef olan turuncu ve nabız gibi atar
func _draw_pads() -> void:
	if finished:
		return
	var size := _pads.size
	var target := _pad_target()
	var y := size.y * 0.73
	for side in [-1, 1]:
		var c := Vector2(size.x * (0.5 + 0.29 * side), y)
		var on: bool = target == side or target == 2
		var r := 80.0
		if on:
			var p := fmod(_t * 1.4, 1.0)
			_pads.draw_arc(c, r + p * 60.0, 0.0, TAU, 64, Color(Palette.ACCENT, 0.6 * (1.0 - p)), 6.0, true)
			_pads.draw_circle(c, r, Color(Palette.ACCENT, 0.32))
			_pads.draw_arc(c, r, 0.0, TAU, 64, Palette.ACCENT, 7.0, true)
			_pads.draw_circle(c, 30.0, Color(Palette.SNOW, 0.95))
		else:
			_pads.draw_circle(c, r, Color(Palette.SNOW, 0.10))
			_pads.draw_arc(c, r, 0.0, TAU, 64, Color(Palette.SNOW, 0.45), 4.0, true)
		# Yön oku (direksiyon dersinde)
		if LESSONS[index][0] == "STEER" and on:
			var tip := c + Vector2(side * (r + 34.0), 0)
			var pts := PackedVector2Array([tip, tip + Vector2(-side * 30.0, -24.0), tip + Vector2(-side * 30.0, 24.0)])
			_pads.draw_colored_polygon(pts, Palette.ACCENT)


## Başarı paneli: büyük ✓, yazı ve NEXT (son derste PLAY)
func _build_panel() -> void:
	_panel = Control.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	var bg := ColorRect.new()
	bg.color = Color(Palette.PAPER, 0.86)
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
	btn.offset_top = -195
	btn.offset_bottom = -90
	btn.pressed.connect(_next)
	_panel.add_child(btn)
	_panel.modulate.a = 0.0
	create_tween().tween_property(_panel, "modulate:a", 1.0, 0.35)


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
