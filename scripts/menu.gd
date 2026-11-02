extends Node3D
## Başlangıç ekranı (garaj): araba modelleri platformlarında kendi ekseninde
## döner. Sağa/sola kaydırınca (ya da oklarla) diğer model yumuşakça gelir.
## BAŞLA seçilen modelle oyunu açar; seçim kaydedilir.

const SAVE_PATH := "user://save.cfg"
const GAME_SCENE := "res://scenes/main.tscn"
## [ad, açıklama, CarModel.variant]
const MODELS := [
	["GEZGİN", "Rock steady off-road, good steering. But the slowest: long gaps burn a lot of energy.", 2],
	["DRAGSTER", "Fast, solid off-road and on the edges. But heavy steering makes tight spots hard.", 6],
	["DARK ROSE", "The best steering, and fast too. But its narrow track tips over easily at the edge.", 7],
	["LATTE", "Balanced: solid off-road and on the edges, needs just enough energy on jumps.", 8],
	["FALCON", "The fastest: jumps on little energy, saving the rest for the wings. But slides like on ice off-road.", 9],
	["GEM", "Fast and agile, its low body rarely tips over. But it gets shaken up off-road.", 10],
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
## Sayfa noktaları (yuvarlak; seçili araba turuncu)
var _dots: Array[StyleBoxFlat] = []
## Arabanın özellikleri (hız, tutuş, çakıl, denge)
var _stats: Control
## Özellik çubuklarının parçaları: [özellik][0..4]
var _segs: Array = []
var _bar_tween: Tween
var _fade: ColorRect
var _args := {}
## Tutorial açıkken garaj kaydırılmaz
var _tutorial_open := false
## Giriş sayfası (oyun adı, HOW TO PLAY / PLAY) oturumda bir kez, ilk açılışta gösterilir
static var _title_done := false
var _title: Control


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
	if _args.has("car"):
		saved = int(_args.car)  # görüntü almak için: --car=8
	for i in MODELS.size():
		if MODELS[i][2] == saved:
			index = i
	_build_world()
	_build_ui(int(cfg.get_value("score", "best", 0)))
	_carousel.position.x = -index * SPACING
	_refresh(false)
	_fade.modulate.a = 1.0
	create_tween().tween_property(_fade, "modulate:a", 0.0, 0.5)
	if _args.has("tutorial"):
		show_tutorial(int(_args.tutorial) if _args.tutorial != "" else 0)  # görüntü için: --tutorial=N
	elif _args.has("title") or (not _title_done and not _args.has("shots")):
		_show_title()


## Giriş sayfası: kocaman oyun adı, altında HOW TO PLAY (oynanarak dersler) ve PLAY (garaj)
func _show_title() -> void:
	_title_done = true
	_tutorial_open = true
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_title = Control.new()
	_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_title)
	var bg := ColorRect.new()
	bg.color = Palette.PAPER
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title.add_child(bg)
	for row in [["SKY", 420.0], ["RUNNER", 560.0]]:
		var l := _label(_title, row[0], 120, row[1], true)
		l.add_theme_color_override("font_color", Palette.INK_DARK)
	var bar := ColorRect.new()
	bar.color = Palette.ACCENT
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.offset_left = -60
	bar.offset_right = 60
	bar.offset_top = 668
	bar.offset_bottom = 676
	_title.add_child(bar)
	var how := _big_button("HOW TO PLAY", false)
	how.offset_top = -345
	how.offset_bottom = -240
	how.pressed.connect(start_lessons)
	_title.add_child(how)
	var play := _big_button("PLAY", true)
	play.offset_top = -205
	play.offset_bottom = -100
	play.pressed.connect(func():
		var tw := create_tween()
		tw.tween_property(_title, "modulate:a", 0.0, 0.35)
		tw.tween_callback(func():
			_tutorial_open = false
			layer.queue_free()))
	_title.add_child(play)


## Nasıl oynanır: oyunun içinde ilk ders
func start_lessons() -> void:
	Lesson.current = 0
	get_tree().change_scene_to_file(GAME_SCENE)


## Geniş buton: dolu turuncu (filled) ya da turuncu çerçeveli
func _big_button(text: String, filled: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	var font := FontVariation.new()
	font.spacing_glyph = 6
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 32)
	var fg := Palette.SNOW if filled else Palette.ACCENT
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, fg)
	for state in [["normal", 0.0], ["hover", 0.0], ["pressed", 0.15], ["focus", 0.0]]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(6)
		if filled:
			sb.bg_color = Palette.ACCENT.darkened(state[1])
		else:
			sb.bg_color = Color(Palette.ACCENT, 0.08 + state[1])
			sb.set_border_width_all(3)
			sb.border_color = Palette.ACCENT
		b.add_theme_stylebox_override(state[0], sb)
	b.anchor_left = 0.5
	b.anchor_right = 0.5
	b.anchor_top = 1.0
	b.anchor_bottom = 1.0
	b.offset_left = -210
	b.offset_right = 210
	return b


## Nasıl oynanır sayfaları garajın üstünde açılır
func show_tutorial(start_page := 0) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var t := Tutorial.new()
	t.page = start_page
	_tutorial_open = true
	t.finished.connect(func():
		_tutorial_open = false
		layer.queue_free()
		# Bir kez görüldü (atlandıysa da): bir daha kendiliğinden açılmaz
		var c := ConfigFile.new()
		c.load(SAVE_PATH)
		c.set_value("tutorial", "intro_seen", true)
		c.save(SAVE_PATH))
	layer.add_child(t)


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
	if _starting or _tutorial_open:
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
	# Özellikler ekranda kalır: çubuklar yeni arabaya göre dolar/boşalır
	_fill_stats(MODELS[index][2], animate)
	var apply := func():
		_name.text = MODELS[index][0]
		_desc.text = MODELS[index][1]
		for i in _dots.size():
			_dots[i].bg_color = Palette.ACCENT if i == index else Color(Palette.INK_DARK, 0.25)
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
	cam.v_offset = -0.72

	# Oklar sahnede, kaidelerin arkasında: araba kayarken önlerinden geçer.
	# Geniş açılı, ince ok başı (iki ince çubuk)
	var arrow_mat := StandardMaterial3D.new()
	arrow_mat.albedo_color = Palette.INK_DARK.lerp(Palette.PAPER, 0.6)
	arrow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var arm := BoxMesh.new()
	arm.size = Vector3(0.42, 0.07, 0.07)
	for side in [-1.0, 1.0]:
		var head := Node3D.new()
		head.position = Vector3(side * 4.7, -0.15, -1.6)
		add_child(head)
		for up in [-1.0, 1.0]:
			var a := MeshInstance3D.new()
			a.mesh = arm
			a.material_override = arrow_mat
			# Uçtan geriye ±40° açılan iki kol
			a.rotation.z = -up * deg_to_rad(40.0) * side
			a.position = Vector3(-side * 0.16, up * 0.135, 0)
			head.add_child(a)

	var disc := CylinderMesh.new()
	disc.top_radius = 2.9
	disc.bottom_radius = 2.9
	disc.height = 0.25
	disc.radial_segments = 48
	disc.rings = 0
	# Kaide: kenarı turuncu, üstü beyaz
	var disc_mat := StandardMaterial3D.new()
	disc_mat.albedo_color = Palette.ACCENT
	disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var top := CylinderMesh.new()
	top.top_radius = 2.9
	top.bottom_radius = 2.9
	top.height = 0.01
	top.radial_segments = 48
	top.rings = 0
	var top_mat := StandardMaterial3D.new()
	top_mat.albedo_color = Palette.SNOW
	top_mat.roughness = 1.0

	_carousel = Node3D.new()
	add_child(_carousel)
	for i in MODELS.size():
		var stand := Node3D.new()
		stand.position.x = i * SPACING
		_carousel.add_child(stand)
		var d := MeshInstance3D.new()
		d.mesh = disc
		d.material_override = disc_mat
		d.position.y = -0.135
		stand.add_child(d)
		var t := MeshInstance3D.new()
		t.mesh = top
		t.material_override = top_mat
		t.position.y = -0.005
		stand.add_child(t)
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
		var b := _label(ui, "BEST  %d" % best, 18, 190, true)
		b.modulate.a = 0.55

	_info = Control.new()
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(_info)
	_name = _label(_info, "", 50, 782, true)
	_desc = _label(_info, "", 20, 850, false)
	# Açıklama iki satıra sarılır
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.offset_left = 90
	_desc.offset_right = -90
	_desc.offset_top = 826
	_desc.offset_bottom = 886
	_desc.modulate.a = 0.6
	_stats = Control.new()
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats.anchor_right = 1.0
	_stats.offset_top = 910
	_stats.offset_bottom = 1010
	ui.add_child(_stats)

	var dots := HBoxContainer.new()
	dots.add_theme_constant_override("separation", 14)
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	dots.anchor_right = 1.0
	dots.offset_top = 365
	dots.offset_bottom = 377
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(dots)
	for i in MODELS.size():
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(12, 12)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(6)
		dot.add_theme_stylebox_override("panel", sb)
		dots.add_child(dot)
		_dots.append(sb)

	for side in [-1, 1]:
		# Görünmez dokunma alanı: ok sahnede (kaidelerin arkasında) çizilir
		var arrow := Button.new()
		arrow.flat = true
		arrow.focus_mode = Control.FOCUS_NONE
		for st in ["normal", "hover", "pressed", "focus"]:
			arrow.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		arrow.anchor_top = 0.5
		arrow.anchor_bottom = 0.5
		arrow.anchor_left = 0.0 if side < 0 else 1.0
		arrow.anchor_right = arrow.anchor_left
		arrow.offset_left = 10 if side < 0 else -110
		arrow.offset_right = 110 if side < 0 else -10
		# Platformun (elipsin) ortası hizasında
		arrow.offset_top = -62
		arrow.offset_bottom = 58
		arrow.pressed.connect(func(): select(index + side))
		ui.add_child(arrow)

	var start_btn := Button.new()
	start_btn.text = "START"
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
	start_btn.offset_top = -195
	start_btn.offset_bottom = -90
	start_btn.pressed.connect(start)
	ui.add_child(start_btn)

	# Oyun adının altında, araçların üstünde: turuncu çerçeveli "nasıl oynanır" butonu
	var how := _big_button("HOW TO PLAY", false)
	how.add_theme_font_size_override("font_size", 20)
	how.anchor_top = 0.0
	how.anchor_bottom = 0.0
	how.offset_left = -140
	how.offset_right = 140
	how.offset_top = 236
	how.offset_bottom = 296
	how.pressed.connect(start_lessons)
	ui.add_child(how)

	var ver := Label.new()
	ver.text = Version.BUILD
	ver.add_theme_font_size_override("font_size", 14)
	ver.add_theme_color_override("font_color", Color(Palette.INK_DARK, 0.35))
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.offset_left = 16
	ver.offset_top = -34
	ver.offset_bottom = -12
	ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(ver)

	_fade = ColorRect.new()
	_fade.color = Palette.PAPER
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(_fade)


const STAT_NAMES := ["SPEED", "STEERING", "OFF-ROAD", "STABILITY"]


## Özellikler (CarModel.STATS, 1-5), 2x2: AD  ▮▮▮▮▯
func _fill_stats(variant: int, animate := false) -> void:
	var st: Array = CarModel.STATS.get(variant, [3, 3, 3, 3])
	if _segs.is_empty():
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 40)
		grid.add_theme_constant_override("v_separation", 22)
		_center(grid)
		for i in 4:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			row.add_child(_small(STAT_NAMES[i], 22, 0.6, 128))
			var bar := _bar(0, Vector2(26, 13), 5)
			row.add_child(bar)
			_segs.append(bar.get_children())
			grid.add_child(row)
	if _bar_tween:
		_bar_tween.kill()
	_bar_tween = null
	for i in 4:
		for k in 5:
			var seg: ColorRect = _segs[i][k]
			var want := Palette.ACCENT if k < int(st[i]) else Color(Palette.INK_DARK, 0.15)
			if not animate:
				seg.color = want
			elif not seg.color.is_equal_approx(want):
				# Dolarken soldan sağa, boşalırken sağdan sola sırayla
				var filling := k < int(st[i])
				var delay := (k if filling else 4 - k) * 0.07
				if _bar_tween == null:
					_bar_tween = create_tween().set_parallel()
				_bar_tween.tween_property(seg, "color", want, 0.2).set_delay(delay)


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
