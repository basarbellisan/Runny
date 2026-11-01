class_name Tutorial
extends Control
## Nasıl oynanır: sayfa sayfa kısa anlatım (görsel, başlık, iki satır yazı). NEXT ile ya da
## kaydırarak sayfa değişir; SKIP ya da son sayfadaki LET'S GO ile kapanır (finished).
## Görseller: ui/tutorial/pN.png (tools/tutorial_images.py oyundan alınmış karelerden üretir).

signal finished

const PAGES := [
	["STEER", "Tap the left or right side of the screen to steer."],
	["BOOST", "Hold two fingers to boost. Red lights at the end of a road mean: boost now to make the jump."],
	["ENERGY", "Boosting and flying use energy. Drive through the green crystals to fill it up."],
	["OBSTACLES", "Steer around the striped blocks: hitting one wrecks the car. Gravel slows you down."],
	["WINGS", "Fell off? Your wings open. Hold two fingers to climb and fly through the orange rings back to the road."],
	["SCORE", "Go as far as you can. Clean landings in the middle of the road and high roads earn bonus points."],
]
const IMG_SIZE := 600.0
## Kaydırma bu kadar pikseli geçince sayfa değişir
const SWIPE := 90.0

var page := 0
var _img: TextureRect
var _title: Label
var _text: Label
var _count: Label
var _dots: Array[Panel] = []
var _next: Button
var _content: Control
var _drag_x := -1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Palette.PAPER
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var head := _label(self, "HOW TO PLAY", 18, 92, true)
	head.modulate.a = 0.55
	var skip := _text_button("SKIP", 18)
	skip.anchor_left = 1.0
	skip.anchor_right = 1.0
	skip.offset_left = -150
	skip.offset_right = -28
	skip.offset_top = 66
	skip.offset_bottom = 118
	skip.pressed.connect(_close)
	add_child(skip)

	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_content)
	_img = TextureRect.new()
	_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_img.anchor_left = 0.5
	_img.anchor_right = 0.5
	_img.offset_left = -IMG_SIZE * 0.5
	_img.offset_right = IMG_SIZE * 0.5
	_img.offset_top = 150
	_img.offset_bottom = 150 + IMG_SIZE
	_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_img)
	_count = _label(_content, "", 16, 800, true)
	_count.modulate.a = 0.45
	_title = _label(_content, "", 46, 856, true)
	_text = _label(_content, "", 22, 940, false)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.offset_left = 70
	_text.offset_right = -70
	_text.offset_top = 900
	_text.offset_bottom = 990
	_text.modulate.a = 0.7

	# Sayfa noktaları
	var dots := HBoxContainer.new()
	dots.add_theme_constant_override("separation", 14)
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	dots.anchor_right = 1.0
	dots.offset_top = 1020
	dots.offset_bottom = 1034
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dots)
	for i in PAGES.size():
		var d := Panel.new()
		d.custom_minimum_size = Vector2(12, 12)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dots.add_child(d)
		_dots.append(d)

	_next = Button.new()
	_next.focus_mode = Control.FOCUS_NONE
	var font := FontVariation.new()
	font.spacing_glyph = 6
	_next.add_theme_font_override("font", font)
	_next.add_theme_font_size_override("font_size", 32)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_next.add_theme_color_override(state, Palette.SNOW)
	for state in [["normal", Palette.ACCENT], ["hover", Palette.ACCENT],
			["pressed", Palette.ACCENT.darkened(0.15)], ["focus", Palette.ACCENT]]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = state[1]
		sb.set_corner_radius_all(6)
		_next.add_theme_stylebox_override(state[0], sb)
	_next.anchor_left = 0.5
	_next.anchor_right = 0.5
	_next.anchor_top = 1.0
	_next.anchor_bottom = 1.0
	_next.offset_left = -210
	_next.offset_right = 210
	_next.offset_top = -195
	_next.offset_bottom = -90
	_next.pressed.connect(func(): show_page(page + 1, true))
	add_child(_next)
	show_page(page)


## Sayfayı gösterir; son sayfadan ileri gidince kapanır
func show_page(i: int, animate := false) -> void:
	if i >= PAGES.size():
		_close()
		return
	i = maxi(i, 0)
	var dir := signf(i - page)
	page = i
	_img.texture = load("res://ui/tutorial/p%d.png" % (i + 1))
	_title.text = PAGES[i][0]
	_text.text = PAGES[i][1]
	_count.text = "%d / %d" % [i + 1, PAGES.size()]
	_next.text = "LET'S GO" if i == PAGES.size() - 1 else "NEXT"
	for k in _dots.size():
		var sb := StyleBoxFlat.new()
		sb.bg_color = Palette.ACCENT if k == i else Color(Palette.INK_DARK, 0.2)
		sb.set_corner_radius_all(6)
		_dots[k].add_theme_stylebox_override("panel", sb)
	if animate and dir != 0.0:
		# Yeni sayfa kaydırdığın yönden kayarak gelir
		_content.position.x = dir * 120.0
		_content.modulate.a = 0.0
		var tw := create_tween().set_parallel()
		tw.tween_property(_content, "position:x", 0.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(_content, "modulate:a", 1.0, 0.2)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if event.pressed:
			_drag_x = event.position.x
		elif _drag_x >= 0.0:
			var dx: float = event.position.x - _drag_x
			_drag_x = -1.0
			if dx < -SWIPE:
				show_page(page + 1, true)
			elif dx > SWIPE:
				show_page(page - 1, true)


func _close() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func():
		finished.emit()
		queue_free())


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


func _text_button(text: String, size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	var f := FontVariation.new()
	f.spacing_glyph = 4
	b.add_theme_font_override("font", f)
	b.add_theme_font_size_override("font_size", size)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, Color(Palette.INK_DARK, 0.5))
	return b
