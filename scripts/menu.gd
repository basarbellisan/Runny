extends Node3D
## Başlangıç ekranı (garaj): araba modelleri platformlarında kendi ekseninde
## döner. Sağa/sola kaydırınca (ya da oklarla) diğer model yumuşakça gelir.
## BAŞLA seçilen modelle oyunu açar; seçim kaydedilir.

const SAVE_PATH := "user://save.cfg"
const GAME_SCENE := "res://scenes/main.tscn"
## [ad, açıklama, CarModel.variant]
## Sıra CarModel.GARAGE ile aynı: önce açık temel arabalar (ağır, orta, hafif), sonra kilitli özel arabalar
const MODELS := [
	["GEZGİN", "Heavy: steady in the air flow and hard to tip, but flying burns a lot of energy.", 2],
	["LATTE", "Medium: balanced in everything.", 8],
	["DARK ROSE", "Light: flies far on little energy and turns fast, but tips over easily.", 7],
	["DRAGSTER", "Heavy and fast.", 6],
	["GEM", "Medium, with a great grip.", 10],
	["FALCON", "Light and the fastest.", 9],
	["DELTA", "A wing on wheels: the best flyer.", 12],
]
## Geliştirme kartları: [özellik, kart adı, çubuk adı]; üst satır parçalar, alt satır parçasız özellikler
const PARTS := [["grip", "GRIP", "GRIP"], ["tank", "TANK", "TANK"], ["flight", "WINGS", "WINGS"],
	["agility", "AGILITY", "AGILITY"], ["balance", "BALANCE", "BALANCE"]]
const CARD_ROWS := [["grip", "tank", "flight"], ["agility", "balance"]]
## Özellik çubukları (SPEED'den sonra; 10 kademe)
const STAT_PARTS := ["agility", "balance", "grip", "tank", "flight"]
## Özellik çubuğunun renkleri: arabanın kendi değeri, alınan geliştirme
const UP_COLOR := Color("3aa65b")
## Platformlar arası mesafe (m)
const SPACING := 7.0
## Kaydırırken parmağın her pikseli kaç metre
const DRAG_SCALE := 0.016
## Bu kadar piksel kaydırınca model değişir
const SWIPE_MIN := 60.0

var index := 0
## Döngülü kaydırma: sınırsız konum (index = _slot mod araba sayısı); sondan başa, baştan sona geçer
var _slot := 0
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
var _ui: CanvasLayer
var _pill: CoinPill
var _chips: HBoxContainer
var _weight_chip: PanelContainer
var _lock_chip: PanelContainer
var _start_btn: Button
var _price_row: HBoxContainer
var _price_lbl: Label
var _lock_icon: LockIcon
var _models: Array[CarModel] = []
## Geliştirme kartları: {part, stat, root, btn, price: Label, coin: CoinIcon, have / max: seviye yazıları}
var _cards: Array[Dictionary] = []
var _ups_title: Label
var _ups: Control
var _busy := false
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
	_slot = index
	_carousel.position.x = -_slot * SPACING
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
	# Uçuştaki kırık yol parçalarının kalıpları menüde beklerken hazırlanır (oyunda takılmasın)
	DebrisField.pool_step()
	var n := _turntables.size()
	var center := -_carousel.position.x / SPACING
	for i in n:
		var t := _turntables[i]
		t.rotate_y(0.55 * delta)
		# Döngü: her platform ortadakine en yakın tekrarına yerleşir (iki yanda hep araba olur)
		t.position.x = (i + n * roundf((center - i) / n)) * SPACING
		# Ortadaki model tam boy, kenara kaydıkça küçülür
		var x := _carousel.position.x + t.position.x
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
		# Döngülü: uç yok, serbest kayar
		_carousel.position.x = _drag_from + (event.position.x - _drag_start.x) * DRAG_SCALE
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				_buy(PARTS[event.keycode - KEY_1][0])
			KEY_LEFT, KEY_A:
				select(index - 1)
			KEY_RIGHT, KEY_D:
				select(index + 1)
			KEY_ENTER, KEY_SPACE:
				start()


## i: index'e göre (index + 1 sağdaki, index - 1 soldaki); sondan başa, baştan sona döner
func select(i: int) -> void:
	_slot += i - index
	var changed := posmod(_slot, MODELS.size()) != index
	index = posmod(_slot, MODELS.size())
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_carousel, "position:x", -_slot * SPACING, 0.55) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if changed:
		Audio.play("multiplier", -10.0, 0.8 + 0.1 * index)
	_refresh(changed)


func start() -> void:
	if _starting:
		return
	# Kilitli araba: düğme "UNLOCK" (parası yetiyorsa açar)
	if not Progress.owns(MODELS[index][2]):
		_unlock()
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
	_fill_upgrades()
	var v: int = MODELS[index][2]
	var locked := not Progress.owns(v)
	_lock_icon.visible = locked
	_lock_icon.reset()
	_price_row.visible = locked
	_start_btn.text = "" if locked else "START"
	var can := Progress.get_coins() >= Progress.car_price(v)
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := _start_btn.get_theme_stylebox(state) as StyleBoxFlat
		if locked:
			sb.bg_color = Palette.INK_DARK if can else Palette.STONE
		else:
			sb.bg_color = Palette.ACCENT.darkened(0.15) if state == "pressed" else Palette.ACCENT
	_price_lbl.text = CoinPill.fmt(Progress.car_price(v))
	var apply := func():
		_name.text = MODELS[index][0]
		_desc.text = "SPECIAL CAR\nUnlock it to drive and upgrade. Outlined steps show how far each stat can go." if locked else ""
		_weight_chip.get_child(0).text = CarModel.weight_label(v)
		_lock_chip.visible = locked
		for i in _dots.size():
			var mine := Progress.owns(MODELS[i][2])
			var col := Palette.ACCENT if i == index else Color(Palette.INK_DARK, 0.25)
			_dots[i].bg_color = col if mine else Color(0, 0, 0, 0)
			_dots[i].border_color = col
			_dots[i].set_border_width_all(0 if mine else 2)
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
	cam.v_offset = -2.6

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
		_models.append(model)
		if not Progress.owns(MODELS[i][2]):
			_set_locked_look(model, true)


func _build_ui(best: int) -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	_ui = ui
	var title := _label(ui, "SKY RUNNER", 36, 120, true)
	title.add_theme_color_override("font_color", Palette.INK_DARK)
	if best > 0:
		var b := _label(ui, "BEST  %d" % best, 16, 168, true)
		b.modulate.a = 0.55
	# Sağ üstte para
	_pill = CoinPill.new(Progress.get_coins())
	_pill.place_top_right()
	ui.add_child(_pill)

	_info = Control.new()
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(_info)
	_name = _label(_info, "", 44, 516, true)
	# Ağırlık (ve kilitliyse LOCKED) etiketleri
	_chips = HBoxContainer.new()
	_chips.alignment = BoxContainer.ALIGNMENT_CENTER
	_chips.add_theme_constant_override("separation", 12)
	_chips.anchor_right = 1.0
	_chips.offset_top = 560
	_chips.offset_bottom = 592
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_child(_chips)
	_weight_chip = _chip(true)
	_lock_chip = _chip(false)
	_lock_chip.get_child(0).text = "LOCKED"
	# Açıklama (kilitli arabada: özel araba yazısı)
	_desc = _label(_info, "", 19, 900, false)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.offset_left = 80
	_desc.offset_right = -80
	_desc.offset_top = 850
	_desc.offset_bottom = 940
	_desc.modulate.a = 0.7
	_stats = Control.new()
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats.anchor_right = 1.0
	_stats.offset_top = 600
	_stats.offset_bottom = 800
	ui.add_child(_stats)
	_build_upgrades(ui)

	var dots := HBoxContainer.new()
	dots.add_theme_constant_override("separation", 14)
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	dots.anchor_right = 1.0
	dots.offset_top = 206
	dots.offset_bottom = 218
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(dots)
	for i in MODELS.size():
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(12, 12)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		# Kilitli araba: içi boş kare
		sb.set_corner_radius_all(6 if Progress.owns(MODELS[i][2]) else 2)
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
		arrow.anchor_top = 0.0
		arrow.anchor_bottom = 0.0
		arrow.anchor_left = 0.0 if side < 0 else 1.0
		arrow.anchor_right = arrow.anchor_left
		arrow.offset_left = 10 if side < 0 else -110
		arrow.offset_right = 110 if side < 0 else -10
		# Platformun (elipsin) ortası hizasında
		arrow.offset_top = 270
		arrow.offset_bottom = 410
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
	start_btn.offset_top = -154
	start_btn.offset_bottom = -64
	start_btn.pressed.connect(start)
	ui.add_child(start_btn)
	_start_btn = start_btn
	# Kilitli arabada düğmenin üstünde fiyat: jeton ve sayı
	_price_row = HBoxContainer.new()
	_price_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_price_row.add_theme_constant_override("separation", 14)
	_price_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_price_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	start_btn.add_child(_price_row)
	var ul := Label.new()
	ul.text = "UNLOCK"
	ul.add_theme_font_override("font", font)
	ul.add_theme_font_size_override("font_size", 28)
	ul.add_theme_color_override("font_color", Palette.SNOW)
	_price_row.add_child(ul)
	var pc := CoinIcon.new("coin", 34)
	pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_price_row.add_child(pc)
	_price_lbl = Label.new()
	_price_lbl.add_theme_font_size_override("font_size", 30)
	_price_lbl.add_theme_color_override("font_color", Palette.SNOW)
	_price_row.add_child(_price_lbl)
	_lock_icon = LockIcon.new()
	_lock_icon.anchor_left = 0.5
	_lock_icon.anchor_right = 0.5
	_lock_icon.offset_left = -40
	_lock_icon.offset_right = 40
	_lock_icon.offset_top = 296
	_lock_icon.offset_bottom = 392
	ui.add_child(_lock_icon)

	# (Nasıl oynanır giriş sayfasında; garajda yer parçalara kaldı)
	# Sol üstte müzik aç / kapat (sağ üstte para)
	var music := MusicButton.new()
	music.place_top_left()
	ui.add_child(music)

	var ver := Label.new()
	ver.text = Version.BUILD
	ver.add_theme_font_size_override("font_size", 24)
	ver.add_theme_color_override("font_color", Color(Palette.INK_DARK, 0.7))
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.offset_left = 16
	ver.offset_top = -52
	ver.offset_bottom = -14
	ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(ver)

	_fade = ColorRect.new()
	_fade.color = Palette.PAPER
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(_fade)


## Özellik çubukları (10 kademe): hız arabanın doğası; tutuş, depo ve uçuş parçalardan
const STAT_NAMES := ["SPEED", "AGILITY", "BALANCE", "GRIP", "TANK", "WINGS"]
const SEGS := 10
## Bu arabanın tavanının üstündeki kademeler (hiç çıkılamaz): çok soluk
const CAP_COLOR := Color(0.137, 0.145, 0.161, 0.05)


## Her satır: AD  ▮▮▮▮▮▮▯▯▯▯ — turuncu arabanın kendi değeri, yeşil alınan geliştirmeler, çerçeveli boş
## kademeler tavana kadar alınabilecekler, en soluk kademeler tavanın üstü. Kilitli arabada da görünür
## (oyuncu almadan önce arabanın nereye kadar gelişebileceğini bilir). Hız sabit
func _fill_stats(variant: int, animate := false) -> void:
	if _segs.is_empty():
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 10)
		_center(col)
		for i in STAT_NAMES.size():
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 14)
			row.add_child(_small(STAT_NAMES[i], 17, 0.6, 112))
			var bar := HBoxContainer.new()
			bar.add_theme_constant_override("separation", 5)
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var segs: Array = []
			for k in SEGS:
				var seg := Panel.new()
				seg.custom_minimum_size = Vector2(36, 12)
				seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
				var sb := StyleBoxFlat.new()
				sb.set_corner_radius_all(2)
				seg.add_theme_stylebox_override("panel", sb)
				bar.add_child(seg)
				segs.append(seg)
			row.add_child(bar)
			_segs.append(segs)
			col.add_child(row)
	if _bar_tween:
		_bar_tween.kill()
	_bar_tween = null
	for i in STAT_NAMES.size():
		var base := CarModel.speed_bar(variant)
		var up := 0
		var slots := 0
		var cap := SEGS
		if i > 0:
			var part: String = STAT_PARTS[i - 1]
			base = CarModel.part_base(variant, part)
			up = Progress.level(variant, part)
			cap = CarModel.part_cap(variant, part)
			slots = cap - base - up
		for k in SEGS:
			var seg: Panel = _segs[i][k]
			var sb := seg.get_theme_stylebox("panel") as StyleBoxFlat
			var want := Color(Palette.INK_DARK, 0.12) if k < cap else CAP_COLOR
			var border := 0
			if k < base:
				want = Palette.ACCENT
			elif k < base + up:
				want = UP_COLOR
			elif k < base + up + slots:
				want = Color(0, 0, 0, 0)
				border = 2
			sb.border_color = Color(Palette.INK_DARK, 0.3)
			sb.set_border_width_all(border)
			if not animate or sb.bg_color.is_equal_approx(want):
				sb.bg_color = want
			else:
				var filling := k < base + up
				var delay := (k if filling else SEGS - 1 - k) * 0.04
				if _bar_tween == null:
					_bar_tween = create_tween().set_parallel()
				_bar_tween.tween_property(sb, "bg_color", want, 0.2).set_delay(delay)


## Etiket: dolu koyu (ağırlık) ya da çerçeveli soluk (LOCKED)
func _chip(filled: bool) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 3
	sb.content_margin_bottom = 4
	if filled:
		sb.bg_color = Palette.INK_DARK
	else:
		sb.bg_color = Color(0, 0, 0, 0)
		sb.set_border_width_all(2)
		sb.border_color = Palette.STONE
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	var f := FontVariation.new()
	f.spacing_glyph = 4
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Palette.PAPER if filled else Palette.SLATE)
	p.add_child(l)
	_chips.add_child(p)
	return p


## Parça kartları: simge, ad, 5 seviye işareti, fiyatlı satın alma düğmesi
func _build_upgrades(ui: CanvasLayer) -> void:
	_ups = Control.new()
	_ups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ups.anchor_right = 1.0
	_ups.offset_top = 820
	_ups.offset_bottom = 1100
	ui.add_child(_ups)
	_ups_title = _label(_ups, "UPGRADE", 14, 16, true)
	_ups_title.modulate.a = 0.55
	# Beş dik kart tek sırada: soldan parçalar (GRIP: tekerlek, TANK, WINGS), sonra AGILITY, BALANCE
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.anchor_right = 1.0
	row.offset_top = 40
	row.offset_bottom = 276
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ups.add_child(row)
	var spaced := FontVariation.new()
	spaced.spacing_glyph = 2
	for keys in CARD_ROWS:
		for key in keys:
			var p: Array = PARTS.filter(func(x): return x[0] == key)[0]
			var card := PanelContainer.new()
			card.custom_minimum_size = Vector2(124, 236)
			card.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color.WHITE
			sb.set_border_width_all(3)
			sb.border_color = Palette.MIST
			sb.set_corner_radius_all(20)
			sb.content_margin_left = 8
			sb.content_margin_right = 8
			sb.content_margin_top = 18
			sb.content_margin_bottom = 12
			card.add_theme_stylebox_override("panel", sb)
			row.add_child(card)
			var col := VBoxContainer.new()
			col.add_theme_constant_override("separation", 10)
			col.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(col)
			var ic := CoinIcon.new(key, 48)
			ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			col.add_child(ic)
			var nm := Label.new()
			nm.text = p[1]
			nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			nm.add_theme_font_override("font", spaced)
			nm.add_theme_font_size_override("font_size", 14)
			nm.add_theme_color_override("font_color", Palette.INK_DARK)
			col.add_child(nm)
			# Seviye: alınan (yeşil) / bu arabadaki geliştirme sayısı
			var lv := HBoxContainer.new()
			lv.alignment = BoxContainer.ALIGNMENT_CENTER
			lv.add_theme_constant_override("separation", 0)
			lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.add_child(lv)
			var lv_have := Label.new()
			lv_have.add_theme_font_size_override("font_size", 17)
			lv_have.add_theme_color_override("font_color", UP_COLOR)
			lv.add_child(lv_have)
			var lv_max := Label.new()
			lv_max.add_theme_font_size_override("font_size", 17)
			lv_max.add_theme_color_override("font_color", Color(Palette.INK_DARK, 0.45))
			lv.add_child(lv_max)
			var gap := Control.new()
			gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.add_child(gap)
			var btn := Button.new()
			btn.focus_mode = Control.FOCUS_NONE
			btn.custom_minimum_size = Vector2(0, 70)
			for st in ["normal", "hover", "pressed", "focus", "disabled"]:
				var bsb := StyleBoxFlat.new()
				bsb.set_corner_radius_all(12)
				btn.add_theme_stylebox_override(st, bsb)
			col.add_child(btn)
			# Düğmede jeton üstte, fiyat altta
			var inner := VBoxContainer.new()
			inner.alignment = BoxContainer.ALIGNMENT_CENTER
			inner.add_theme_constant_override("separation", 2)
			inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(inner)
			var coin := CoinIcon.new("coin", 24)
			coin.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			inner.add_child(coin)
			var price := Label.new()
			price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			price.add_theme_font_size_override("font_size", 21)
			inner.add_child(price)
			btn.pressed.connect(func(): _buy(key))
			_cards.append({"part": key, "stat": p[2], "root": card, "btn": btn, "price": price, "coin": coin,
				"have": lv_have, "max": lv_max})


## Kartların fiyatları; tavana gelen özelliğin düğmesi pasif (MAX). Kilitli arabada kartlar yok
func _fill_upgrades() -> void:
	var v: int = MODELS[index][2]
	var locked := not Progress.owns(v)
	_ups.visible = not locked
	for c in _cards:
		var price := Progress.upgrade_price(v, c.part)
		var maxed := price < 0
		var poor := not maxed and Progress.get_coins() < price
		(c.btn as Button).disabled = maxed
		(c.coin as CoinIcon).visible = not maxed
		(c.price as Label).text = "MAX" if maxed else CoinPill.fmt(price)
		var fg := Palette.STONE if maxed else (Palette.SLATE if poor else Palette.SNOW)
		(c.price as Label).add_theme_color_override("font_color", fg)
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			var bsb := (c.btn as Button).get_theme_stylebox(st) as StyleBoxFlat
			bsb.bg_color = Color(Palette.INK_DARK, 0.05) if maxed else (Palette.MIST if poor else Palette.INK_DARK)
		(c.root as Control).modulate.a = 0.6 if maxed else 1.0
		(c.have as Label).text = str(Progress.level(v, c.part))
		(c.max as Label).text = "/%d" % Progress.max_level(v, c.part)


## Özellik geliştir: para düşer, çubuğa yeşil kademe eklenir, kart zıplar, "+1" yükselir
func _buy(part: String) -> void:
	var v: int = MODELS[index][2]
	if _busy or _starting or not Progress.owns(v):
		return
	var card: Dictionary = _cards.filter(func(c): return c.part == part)[0]
	if not Progress.buy_upgrade(v, part):
		if Progress.upgrade_price(v, part) >= 0:
			_shake(card.btn)
			Audio.play("hiss", -14.0)
		return
	var lvl := Progress.level(v, part)
	_pill.set_value(Progress.get_coins())
	_fill_upgrades()
	# Yeni kademe: çubukta parlayıp yerine oturur
	var row := 1 + STAT_PARTS.find(part)
	var seg: Panel = _segs[row][CarModel.part_base(v, part) + lvl - 1]
	var sb := seg.get_theme_stylebox("panel") as StyleBoxFlat
	sb.set_border_width_all(0)
	sb.bg_color = Palette.ENERGY
	seg.pivot_offset = seg.size * 0.5
	var t := create_tween()
	t.tween_property(seg, "scale", Vector2(1.0, 2.4), 0.15)
	t.tween_property(seg, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(sb, "bg_color", UP_COLOR, 0.5)
	# Kart
	var root: Control = card.root
	root.pivot_offset = root.size * 0.5
	var tc := create_tween()
	tc.tween_property(root, "scale", Vector2.ONE * 1.06, 0.12)
	tc.tween_property(root, "scale", Vector2.ONE, 0.25)
	_float_text("+1 " + card.stat, root)
	Audio.play("perfect", -6.0)


## Kilitli arabayı aç: kilit sallanıp kaybolur, araba renklenir
func _unlock() -> void:
	var v: int = MODELS[index][2]
	if _busy:
		return
	if not Progress.unlock(v):
		_shake(_start_btn)
		Audio.play("hiss", -14.0)
		return
	_busy = true
	_pill.set_value(Progress.get_coins())
	Audio.play("wings", -4.0)
	var t := _lock_icon.open()
	t.tween_callback(func():
		_set_locked_look(_models[index], false)
		var st := _turntables[index]
		var tw := create_tween()
		tw.tween_property(st, "scale", st.scale * 1.12, 0.15)
		tw.tween_property(st, "scale", st.scale, 0.25)
		_busy = false
		_refresh(true)
		for i in _dots.size():
			var mine := Progress.owns(MODELS[i][2])
			_dots[i].set_corner_radius_all(6 if mine else 2))


## Kilitli araba: düz gri (kil gibi); açılınca kendi malzemeleri
func _set_locked_look(model: CarModel, on: bool) -> void:
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if on:
			mi.set_meta("unlocked_override", mi.material_override)
			mi.material_override = _locked_mat()
		elif mi.has_meta("unlocked_override"):
			mi.material_override = mi.get_meta("unlocked_override")
			mi.remove_meta("unlocked_override")


var _lock_mat: StandardMaterial3D


func _locked_mat() -> StandardMaterial3D:
	if _lock_mat == null:
		_lock_mat = StandardMaterial3D.new()
		_lock_mat.albedo_color = Color("c9c6be")
		_lock_mat.roughness = 1.0
	return _lock_mat


func _shake(c: Control) -> void:
	var x := c.position.x
	var t := create_tween()
	for d in [-10.0, 10.0, -6.0, 0.0]:
		t.tween_property(c, "position:x", x + d, 0.05)


## Kartın üstünde yükselip kaybolan yazı ("+1 GRIP")
func _float_text(text: String, over: Control) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", UP_COLOR)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(l)
	l.reset_size()
	l.position = over.global_position + Vector2(over.size.x * 0.5 - l.size.x * 0.5, -30)
	var t := create_tween()
	t.tween_property(l, "position:y", l.position.y - 46, 0.9).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.3)
	t.tween_callback(l.queue_free)


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
	# Test: belirli karede parça al (--buy_at=40:grip) ya da arabayı aç (--unlock_at=40)
	if _args.has("buy_at"):
		for item in str(_args.buy_at).split(","):
			if frame == int(item.get_slice(":", 0)):
				_buy(item.get_slice(":", 1))
	if _args.has("unlock_at") and frame == int(_args.unlock_at):
		_unlock()
