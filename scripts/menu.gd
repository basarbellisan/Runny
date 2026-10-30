extends Node3D
## Başlangıç ekranı (garaj): araba modelleri platformlarında kendi ekseninde
## döner. Sağa/sola kaydırınca (ya da oklarla) diğer model yumuşakça gelir.
## BAŞLA seçilen modelle oyunu açar; seçim kaydedilir.

const SAVE_PATH := "user://save.cfg"
const GAME_SCENE := "res://scenes/main.tscn"
## [ad, açıklama, CarModel.variant]
const MODELS := [
	["GEZGİN", "Yavaş ama çakılda tank gibi", 2],
	["DRAGSTER", "Hızlı ve sağlam, direksiyonu ağır", 6],
	["DARK ROSE", "En iyi direksiyon, kolay devrilir", 7],
	["LATTE", "Dengeli, her işi iyi yapar", 8],
	["FALCON", "En hızlı, çakılda buz pateni", 9],
]
## Platformlar arası mesafe (m)
const SPACING := 7.0
## Kaydırırken parmağın her pikseli kaç metre
const DRAG_SCALE := 0.016
## Bu kadar piksel kaydırınca model değişir
const SWIPE_MIN := 60.0

var index := 0
var _carousel: Node3D
var _turntables: Array[Node3D] = []
var _tween: Tween
var _text_tween: Tween
var _dragging := false
var _drag_start := Vector2.ZERO
var _drag_from := 0.0
var _starting := false
var _name: Label
var _desc: Label
var _info: Control
var _dots: Array[ColorRect] = []
## Arabanın özellikleri (hız, tutuş, çakıl, denge)
var _stats: Control
var _fade: ColorRect
var _args := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""
	# Testler (otomatik pilot) garajı atlayıp doğrudan oyuna girer
	if _args.has("autopilot"):
		get_tree().change_scene_to_file.call_deferred(GAME_SCENE)
		return
	# Bölüm Tasarımcısından ("Oyna", "Test et"): garajı atla, tasarım oyunda açılsın
	if OS.has_feature("web") and str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('level') || ''")) != "":
		get_tree().change_scene_to_file.call_deferred(GAME_SCENE)
		return
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	index = 0
	var saved := int(cfg.get_value("car", "model", MODELS[0][2]))
	for i in MODELS.size():
		if MODELS[i][2] == saved:
			index = i
	_build_world()
	_build_ui(int(cfg.get_value("score", "best", 0)))
	_carousel.position.x = -index * SPACING
	_refresh(false)
	_fade.modulate.a = 1.0
	create_tween().tween_property(_fade, "modulate:a", 0.0, 0.5)


func _process(delta: float) -> void:
	for i in _turntables.size():
		var t := _turntables[i]
		t.rotate_y(0.55 * delta)
		# Ortadaki model tam boy, kenara kaydıkça küçülür
		var x := _carousel.position.x + i * SPACING
		var k := clampf(1.0 - absf(x) / SPACING, 0.0, 1.0)
		t.scale = Vector3.ONE * lerpf(0.72, 1.0, k * k * (3.0 - 2.0 * k))
	Audio.update_menu(delta)
	if _args.has("shots"):
		_capture_shots()


func _unhandled_input(event: InputEvent) -> void:
	if _starting:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_dragging = true
			_drag_start = event.position
			_drag_from = _carousel.position.x
			if _tween:
				_tween.kill()
		elif _dragging:
			_dragging = false
			var dx: float = event.position.x - _drag_start.x
			if dx < -SWIPE_MIN:
				select(index + 1)
			elif dx > SWIPE_MIN:
				select(index - 1)
			else:
				select(index)
	elif event is InputEventScreenDrag and _dragging:
		var x: float = _drag_from + (event.position.x - _drag_start.x) * DRAG_SCALE
		# Uçlarda esneyerek dirensin
		var lo := -(MODELS.size() - 1) * SPACING
		if x > 0.0:
			x *= 0.35
		elif x < lo:
			x = lo + (x - lo) * 0.35
		_carousel.position.x = x
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_LEFT, KEY_A:
				select(index - 1)
			KEY_RIGHT, KEY_D:
				select(index + 1)
			KEY_ENTER, KEY_SPACE:
				start()


func select(i: int) -> void:
	var changed := clampi(i, 0, MODELS.size() - 1) != index
	index = clampi(i, 0, MODELS.size() - 1)
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_carousel, "position:x", -index * SPACING, 0.55) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if changed:
		Audio.play("multiplier", -10.0, 0.8 + 0.1 * index)
	_refresh(changed)


func start() -> void:
	if _starting:
		return
	_starting = true
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("car", "model", MODELS[index][2])
	cfg.save(SAVE_PATH)
	Audio.play("return", -4.0)
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 1.0, 0.35)
	tw.tween_callback(get_tree().change_scene_to_file.bind(GAME_SCENE))


## Model adı, açıklaması ve noktalar; değişince kısa bir geçişle
func _refresh(animate: bool) -> void:
	var apply := func():
		_name.text = MODELS[index][0]
		_desc.text = MODELS[index][1]
		_fill_stats(MODELS[index][2])
		for i in _dots.size():
			_dots[i].color = Palette.ACCENT if i == index else Color(Palette.INK_DARK, 0.25)
	if not animate:
		apply.call()
		return
	if _text_tween:
		_text_tween.kill()
	_text_tween = create_tween()
	_text_tween.tween_property(_info, "modulate:a", 0.0, 0.12)
	_text_tween.tween_callback(apply)
	_text_tween.tween_property(_info, "modulate:a", 1.0, 0.25)


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Palette.PAPER
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d4dceb")
	# Arabalar soluk görünmesin: ortam ışığı ve sis kısık (sis yalnız uzaktaki
	# platformları yumuşatır, öndeki arabanın rengini bozmaz)
	env.ambient_light_energy = 0.38
	env.fog_enabled = true
	env.fog_light_color = Palette.PAPER
	env.fog_density = 0.006
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	# Oyunla aynı "altın saat": sıcak, alçaktan gelen güneş
	sun.rotation = Vector3(-0.55, 0.6, 0)
	sun.light_color = Color("ffd8a8")
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)

	var cam := Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = 56
	add_child(cam)
	cam.position = Vector3(0, 2.7, 8.0)
	cam.look_at(Vector3(0, 0.25, 0))
	# Araba biraz yukarıda: altında özelliklere yer kalsın
	cam.v_offset = -0.55

	var disc := CylinderMesh.new()
	disc.top_radius = 2.9
	disc.bottom_radius = 2.9
	disc.height = 0.25
	disc.radial_segments = 48
	disc.rings = 0
	var disc_mat := StandardMaterial3D.new()
	disc_mat.albedo_color = Palette.SNOW
	disc_mat.roughness = 1.0
	var rim := CylinderMesh.new()
	rim.top_radius = 2.95
	rim.bottom_radius = 2.95
	rim.height = 0.06
	rim.radial_segments = 48
	rim.rings = 0
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Palette.ACCENT
	rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_carousel = Node3D.new()
	add_child(_carousel)
	for i in MODELS.size():
		var stand := Node3D.new()
		stand.position.x = i * SPACING
		_carousel.add_child(stand)
		var d := MeshInstance3D.new()
		d.mesh = disc
		d.material_override = disc_mat
		d.position.y = -0.125
		stand.add_child(d)
		var r := MeshInstance3D.new()
		r.mesh = rim
		r.material_override = rim_mat
		r.position.y = -0.2
		stand.add_child(r)
		var table := Node3D.new()
		stand.add_child(table)
		table.rotation.y = 0.6 + i * 0.9
		var model := CarModel.new()
		model.variant = MODELS[i][2]
		table.add_child(model)
		_turntables.append(stand)


func _build_ui(best: int) -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var title := _label(ui, "SKY RUNNER", 40, 130, true)
	title.add_theme_color_override("font_color", Palette.INK_DARK)
	if best > 0:
		var b := _label(ui, "EN İYİ  %d" % best, 18, 190, true)
		b.modulate.a = 0.55

	_info = Control.new()
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(_info)
	_name = _label(_info, "", 38, 800, true)
	_desc = _label(_info, "", 20, 852, false)
	_desc.modulate.a = 0.6
	_stats = Control.new()
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats.anchor_right = 1.0
	_stats.offset_top = 885
	_stats.offset_bottom = 1010
	_info.add_child(_stats)

	var dots := HBoxContainer.new()
	dots.add_theme_constant_override("separation", 14)
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	dots.anchor_right = 1.0
	dots.offset_top = 1030
	dots.offset_bottom = 1040
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(dots)
	for i in MODELS.size():
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(28, 4)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dots.add_child(dot)
		_dots.append(dot)

	for side in [-1, 1]:
		var arrow := Button.new()
		arrow.text = "<" if side < 0 else ">"
		arrow.flat = true
		arrow.focus_mode = Control.FOCUS_NONE
		arrow.add_theme_font_size_override("font_size", 56)
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			arrow.add_theme_color_override(state, Color(Palette.INK_DARK, 0.35))
		arrow.anchor_top = 0.5
		arrow.anchor_bottom = 0.5
		arrow.anchor_left = 0.0 if side < 0 else 1.0
		arrow.anchor_right = arrow.anchor_left
		arrow.offset_left = 10 if side < 0 else -110
		arrow.offset_right = 110 if side < 0 else -10
		arrow.offset_top = -80
		arrow.offset_bottom = 40
		arrow.pressed.connect(func(): select(index + side))
		ui.add_child(arrow)

	var start_btn := Button.new()
	start_btn.text = "BAŞLA"
	start_btn.focus_mode = Control.FOCUS_NONE
	var font := FontVariation.new()
	font.spacing_glyph = 6
	start_btn.add_theme_font_override("font", font)
	start_btn.add_theme_font_size_override("font_size", 34)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		start_btn.add_theme_color_override(state, Palette.SNOW)
	for state in [["normal", Palette.ACCENT], ["hover", Palette.ACCENT],
			["pressed", Palette.ACCENT.darkened(0.15)], ["focus", Palette.ACCENT]]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = state[1]
		sb.set_corner_radius_all(6)
		start_btn.add_theme_stylebox_override(state[0], sb)
	start_btn.anchor_left = 0.5
	start_btn.anchor_right = 0.5
	start_btn.anchor_top = 1.0
	start_btn.anchor_bottom = 1.0
	start_btn.offset_left = -210
	start_btn.offset_right = 210
	start_btn.offset_top = -210
	start_btn.offset_bottom = -100
	start_btn.pressed.connect(start)
	ui.add_child(start_btn)

	_fade = ColorRect.new()
	_fade.color = Palette.PAPER
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(_fade)


const STAT_NAMES := ["HIZ", "TUTUŞ", "ÇAKIL", "DENGE"]


## Özellikler (CarModel.STATS, 1-5), 2x2: AD  ▮▮▮▮▯  4
func _fill_stats(variant: int) -> void:
	for c in _stats.get_children():
		c.queue_free()
	var st: Array = CarModel.STATS.get(variant, [3, 3, 3, 3])
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 56)
	grid.add_theme_constant_override("v_separation", 18)
	_center(grid)
	for i in 4:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(_small(STAT_NAMES[i], 17, 0.55, 74))
		row.add_child(_bar(st[i], Vector2(18, 10), 4))
		row.add_child(_small(str(st[i]), 20, 1.0, 18))
		grid.add_child(row)


## Kabı özellik alanının ortasına yerleştirir
func _center(c: Control) -> void:
	var box := CenterContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stats.add_child(box)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(c)


## Beş parçalı çubuk: n tanesi dolu
func _bar(n: int, size: Vector2, gap: int) -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", gap)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in 5:
		var seg := ColorRect.new()
		seg.custom_minimum_size = size
		seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		seg.color = Palette.ACCENT if k < n else Color(Palette.INK_DARK, 0.15)
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(seg)
	return bar


func _small(text: String, size: int, alpha: float, min_w: float) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(Palette.INK_DARK, alpha))
	l.custom_minimum_size.x = min_w
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _label(parent: Node, text: String, size: int, y: float, spaced: bool) -> Label:
	var l := Label.new()
	l.text = text
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


func _capture_shots() -> void:
	var frames := Array(_args["shots"].split(",")).map(func(f): return int(f))
	var frame := Engine.get_process_frames()
	if frame in frames:
		get_viewport().get_texture().get_image().save_png(
			"%s/menu_%d.png" % [_args.get("shot_dir", "user://"), frame])
		if frame == frames.max():
			get_tree().quit()
	# Test için: belirli karede bir sonraki modele geç
	if _args.has("swipe_at") and frame == int(_args.swipe_at):
		select(index + 1)
