class_name Hud
extends CanvasLayer
## Skor, çarpan, anlık mesajlar ve oyun sonu ekranı.
## Sade tipografi; yazı rengi katmana göre koyudan açığa geçer.

const BAR_WIDTH := 300.0

signal garage_pressed
signal again_pressed

var _labels: Array[Label] = []
var _score: Label
var _mult: Label
var _dist: Label
var _captions: Array[Label] = []
var _popup: Label
var _hint: Label
var _energy: Control
var _energy_back: ColorRect
var _energy_fill: ColorRect
var speedometer: Speedometer
var _speedo: Speedometer
var gauge: EnergyGauge
var _speedo_shown := true

var _hint_tween: Tween
var _over: Control
var _over_bg: ColorRect
var _over_reason: Label
var _over_score: Label
var _over_best: Label
var _over_dist: Label
var _popup_tween: Tween
var _ink := Palette.INK_DARK
var _mood := -1.0
var _energy_fraction := 1.0
var _spaced: FontVariation


## Üst köşelerdeki mesafe ve puanın boyu ve kenardan uzaklığı
const TOP_SIZE := 48
const TOP_MARGIN := 36.0


func _ready() -> void:
	_spaced = FontVariation.new()
	_spaced.spacing_glyph = 4
	# Üstte iki köşe, aynı boy: solda gidilen mesafe (km), sağda puan.
	# Çarpan (x2..x5) puanı etkiler ama ekranda gösterilmez
	_dist = _make_label(TOP_SIZE, Vector2(0, 84))
	_dist.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_dist.offset_left = TOP_MARGIN
	_score = _make_label(TOP_SIZE, Vector2(0, 84))
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_score.offset_right = -TOP_MARGIN
	# Rakamların üstünde ne olduklarını söyleyen küçük başlıklar
	for c in [["DISTANCE", HORIZONTAL_ALIGNMENT_LEFT], ["SCORE", HORIZONTAL_ALIGNMENT_RIGHT]]:
		var cap := _make_label(15, Vector2(0, 40), true)
		cap.text = c[0]
		cap.horizontal_alignment = c[1]
		cap.offset_left = TOP_MARGIN + 2.0
		cap.offset_right = -TOP_MARGIN - 2.0
		cap.modulate.a = 0.55
		_captions.append(cap)
	_mult = _make_label(26, Vector2(0, 162), true)
	_mult.visible = false
	_popup = _make_label(40, Vector2(0, 420), true)
	_popup.modulate.a = 0.0
	_hint = _make_label(20, Vector2(0, 330), true)
	_build_energy_bar()
	_build_game_over()
	# Hız kadranı solda, enerji deposu sağda (alt köşeler)
	_speedo = Speedometer.new()
	_speedo.show_fuel = false
	add_child(_speedo)
	_place_bottom(_speedo, 0.0)
	speedometer = _speedo
	gauge = EnergyGauge.new()
	add_child(gauge)
	_place_bottom(gauge, 1.0)
	set_mood(0.0)
	hint("TAP LEFT      |      TAP RIGHT", 3.0)


## Alt köşeye 220x190'lık gösterge (side 0 sol, 1 sağ), biraz büyütülmüş
func _place_bottom(c: Control, side: float) -> void:
	const SCALE := 1.35
	c.anchor_left = side
	c.anchor_right = side
	c.anchor_top = 1.0
	c.anchor_bottom = 1.0
	c.size = Vector2(220, 190)
	c.scale = Vector2.ONE * SCALE
	var w := 220.0 * SCALE
	c.offset_left = 4.0 if side == 0.0 else -w - 4.0
	c.offset_top = -190.0 * SCALE - 20.0
	c.offset_right = c.offset_left + 220.0
	c.offset_bottom = c.offset_top + 190.0


## Ekranın üstünden y kadar aşağıda, yatayda ortalı yazı
func _make_label(size: int, at: Vector2, spaced := false, parent: Node = self) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	if spaced:
		l.add_theme_font_override("font", _spaced)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.offset_top = at.y - size
	l.offset_bottom = at.y + size
	_labels.append(l)
	return l


func _build_energy_bar() -> void:
	_energy = Control.new()
	_energy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_energy)
	_energy.anchor_left = 0.5
	_energy.anchor_right = 0.5
	_energy.offset_left = -BAR_WIDTH * 0.5
	_energy.offset_right = BAR_WIDTH * 0.5
	_energy.offset_top = 200
	_energy.offset_bottom = 204
	_energy_back = ColorRect.new()
	_energy_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_energy.add_child(_energy_back)
	_energy_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_energy_fill = ColorRect.new()
	_energy_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_energy_fill.size = Vector2(BAR_WIDTH, 4)
	_energy.add_child(_energy_fill)
	var label := _make_label(16, Vector2(0, 0), true, _energy)
	label.text = "ENERGY"
	label.offset_top = 14
	label.offset_bottom = 34
	label.modulate.a = 0.6
	_energy.visible = false


## Oyun sonu ekranı tasarımı (deneme: --over_style=N): 0 gökyüzünde (kamera göğe döner; perde yok),
## 1 kart, 2 koyu perde + iki sütun, 3 sade büyük skor
var over_style := 0
var _over_new: Control
var _over_dist_lbl: Label
var _over_best_lbl: Label


func _build_game_over() -> void:
	_over = Control.new()
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_over)
	_over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_over_bg = ColorRect.new()
	_over_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.add_child(_over_bg)
	_over_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_over.visible = false


## Tasarımı kurar (show_game_over çağırır; over_style seçildikten sonra)
func _layout_game_over() -> void:
	for ch in _over.get_children():
		if ch != _over_bg:
			ch.queue_free()
	var deep := Color("2a1c50")      # paletin koyu moru
	var ink := Palette.INK_DARK
	match over_style:
		0:
			# Sahnenin üstünde: hafif koyu mor perde (beyaz yazılar okunsun), yazılar beyaz
			_over_bg.color = Color(deep, 0.5)
			_over_reason = _over_label(30, 250, true, Palette.ACCENT)
			_over_score = _over_label(150, 380, false, Palette.SNOW)
			_over_new = _badge("NEW BEST", 475)
			_over_dist_lbl = _over_label(16, 550, true, Color(Palette.SNOW, 0.6), -140)
			_over_dist = _over_label(36, 595, false, Palette.SNOW, -140)
			_over_best_lbl = _over_label(16, 550, true, Color(Palette.SNOW, 0.6), 140)
			_over_best = _over_label(36, 595, false, Palette.SNOW, 140)
			for l: Label in [_over_score, _over_dist, _over_best, _over_reason]:
				l.add_theme_color_override("font_shadow_color", Color(0.1, 0.05, 0.2, 0.35))
				l.add_theme_constant_override("shadow_offset_y", 3)
			_buttons(740, Color(Palette.SNOW, 0.95))
		1:
			# Kart: sahne koyu mor perdeyle kararır, ortada beyaz yuvarlak köşeli kart
			_over_bg.color = Color(deep, 0.72)
			var card := Panel.new()
			var sb := StyleBoxFlat.new()
			sb.bg_color = Palette.SNOW
			sb.set_corner_radius_all(28)
			sb.shadow_color = Color(0, 0, 0, 0.25)
			sb.shadow_size = 18
			card.add_theme_stylebox_override("panel", sb)
			card.anchor_left = 0.5
			card.anchor_right = 0.5
			card.offset_left = -290
			card.offset_right = 290
			card.offset_top = 330
			card.offset_bottom = 860
			card.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_over.add_child(card)
			_over_reason = _over_label(28, 400, true, Palette.ACCENT)
			_over_score = _over_label(120, 530, false, ink)
			_over_new = _badge("NEW BEST", 610)
			# İki sütun: mesafe ve en iyi
			_over_dist_lbl = _over_label(16, 690, true, Color(ink, 0.5), -140)
			_over_dist = _over_label(34, 735, false, ink, -140)
			_over_best_lbl = _over_label(16, 690, true, Color(ink, 0.5), 140)
			_over_best = _over_label(34, 735, false, ink, 140)
			var line := ColorRect.new()
			line.color = Color(ink, 0.12)
			line.anchor_left = 0.5
			line.anchor_right = 0.5
			line.offset_left = -1
			line.offset_right = 1
			line.offset_top = 670
			line.offset_bottom = 760
			_over.add_child(line)
			_buttons(930, Palette.SNOW)
		2:
			# Koyu perde: alttan koyu mora inen degrade, beyaz yazılar, sahne üstte görünür kalır
			_over_bg.color = Color(0, 0, 0, 0)
			var grad := TextureRect.new()
			var g := Gradient.new()
			g.set_color(0, Color(deep, 0.15))
			g.set_color(1, Color(deep, 0.95))
			var gt := GradientTexture2D.new()
			gt.gradient = g
			gt.fill_from = Vector2(0, 0)
			gt.fill_to = Vector2(0, 1)
			grad.texture = gt
			grad.stretch_mode = TextureRect.STRETCH_SCALE
			grad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_over.add_child(grad)
			_over_reason = _over_label(30, 470, true, Palette.ACCENT)
			_over_score = _over_label(140, 610, false, Palette.SNOW)
			_over_new = _badge("NEW BEST", 700)
			_over_dist_lbl = _over_label(16, 780, true, Color(Palette.SNOW, 0.55), -150)
			_over_dist = _over_label(36, 825, false, Palette.SNOW, -150)
			_over_best_lbl = _over_label(16, 780, true, Color(Palette.SNOW, 0.55), 150)
			_over_best = _over_label(36, 825, false, Palette.SNOW, 150)
			_buttons(960, Color(0, 0, 0, 0))
		_:
			# Sade: açık kâğıt rengi tam perde, koyu yazı, dev skor, alt çizgi ve küçük bilgiler
			_over_bg.color = Color(Palette.PAPER, 0.94)
			_over_reason = _over_label(26, 420, true, Palette.ACCENT)
			_over_score = _over_label(170, 570, false, ink)
			var bar := ColorRect.new()
			bar.color = Palette.ACCENT
			bar.anchor_left = 0.5
			bar.anchor_right = 0.5
			bar.offset_left = -60
			bar.offset_right = 60
			bar.offset_top = 680
			bar.offset_bottom = 686
			_over.add_child(bar)
			_over_new = _badge("NEW BEST", 735)
			_over_dist_lbl = _over_label(16, 800, true, Color(ink, 0.5), -140)
			_over_dist = _over_label(32, 842, false, ink, -140)
			_over_best_lbl = _over_label(16, 800, true, Color(ink, 0.5), 140)
			_over_best = _over_label(32, 842, false, ink, 140)
			_buttons(960, Color(0, 0, 0, 0))
	_over_dist_lbl.text = "DISTANCE"
	_over_best_lbl.text = "BEST"


## Oyun sonu yazısı: y merkez, x yatay kayma (sütunlar için)
func _over_label(size: int, y: float, spaced: bool, color: Color, x := 0.0) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if spaced:
		l.add_theme_font_override("font", _spaced)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.anchor_right = 1.0
	l.offset_left = x
	l.offset_right = x
	l.offset_top = y - size
	l.offset_bottom = y + size
	_over.add_child(l)
	return l


## "NEW BEST" rozeti (en iyi skorsa görünür)
func _badge(text: String, y: float) -> Control:
	var c := CenterContainer.new()
	c.anchor_right = 1.0
	c.offset_top = y - 20
	c.offset_bottom = y + 20
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.ACCENT
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 4
	sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _spaced)
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Palette.SNOW)
	p.add_child(l)
	c.add_child(p)
	_over.add_child(c)
	return c


## PLAY AGAIN (dolu turuncu) ve GARAGE (turuncu çerçeve) butonları
func _buttons(y: float, garage_bg: Color) -> void:
	for b in [["PLAY AGAIN", true, y], ["GARAGE", false, y + 120.0]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_override("font", _spaced)
		btn.add_theme_font_size_override("font_size", 28)
		var fg: Color = Palette.SNOW if b[1] else Palette.ACCENT
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			btn.add_theme_color_override(state, fg)
		for state in [["normal", 0.0], ["hover", 0.0], ["pressed", 0.15], ["focus", 0.0]]:
			var sb := StyleBoxFlat.new()
			sb.set_corner_radius_all(8)
			if b[1]:
				sb.bg_color = Palette.ACCENT.darkened(state[1])
			elif garage_bg.a > 0.0:
				# Açık renk: opak düz zemin, çerçevesiz (telefonda ince çerçeve köşelerde bozuluyordu)
				sb.bg_color = Color(garage_bg, 1.0).darkened(state[1] * 0.5)
			else:
				sb.bg_color = Color(Palette.ACCENT, 0.08 + state[1])
				sb.set_border_width_all(3)
				sb.border_color = Palette.ACCENT
			btn.add_theme_stylebox_override(state[0], sb)
		btn.anchor_left = 0.5
		btn.anchor_right = 0.5
		btn.offset_left = -210
		btn.offset_right = 210
		btn.offset_top = b[2] - 48
		btn.offset_bottom = b[2] + 48
		if b[1]:
			btn.pressed.connect(func(): again_pressed.emit())
		else:
			btn.pressed.connect(func(): garage_pressed.emit())
		_over.add_child(btn)


## 0 = üst katman (açık zemin, koyu yazı), 1 = alt katman (koyu zemin, açık yazı)
## ink: yazı rengi (paletten: koyu gökyüzünde açık, açık gökyüzünde koyu)
func set_mood(m: float, ink := Color.TRANSPARENT) -> void:
	if ink.a == 0.0:
		ink = Palette.INK_DARK.lerp(Palette.INK_LIGHT, smoothstep(0.3, 0.7, m))
	if absf(m - _mood) < 0.01 and ink.is_equal_approx(_ink):
		return
	_mood = m
	_ink = ink
	for l in _labels:
		l.add_theme_color_override("font_color", _ink)
	_energy_back.color = Color(_ink, 0.18)
	set_energy(_energy_fraction)


## Alt kısımda bir süre görünen ipucu yazısı
func hint(text: String, duration: float) -> void:
	_hint.text = text
	_hint.modulate.a = 1.0
	if _hint_tween:
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_interval(duration)
	_hint_tween.tween_property(_hint, "modulate:a", 0.0, 0.8)


## Kadran: hız (m/s), gazsız hız, gaz gücü; show=false iken yavaşça kaybolur
func set_speed(speed: float, base_speed: float, boost: float, show: bool) -> void:
	_speedo.set_values(speed * 3.6, base_speed * 3.6, boost)
	if show != _speedo_shown:
		_speedo_shown = show
		create_tween().tween_property(_speedo, "modulate:a", 1.0 if show else 0.0, 0.4)


## Oyun bitince kadranlar kalkar (yalnız oynarken görünür)
func hide_gauges() -> void:
	_speedo_shown = false
	for l: Control in [_score, _dist] + _captions:
		create_tween().tween_property(l, "modulate:a", 0.0, 0.4)
	for c: Control in [_speedo, gauge]:
		create_tween().tween_property(c, "modulate:a", 0.0, 0.3)


## Enerji (0-100) sağdaki depoda
func set_energy_value(v: float, max_v: float) -> void:
	gauge.set_value(v, max_v)


## Roket yakıtı (0-1): kadranı çevreleyen halka
func set_fuel(fuel: float) -> void:
	_speedo.set_fuel(fuel)


func show_energy(visible_: bool) -> void:
	_energy.visible = visible_


func set_energy(fraction: float) -> void:
	_energy_fraction = fraction
	_energy_fill.size.x = BAR_WIDTH * clampf(fraction, 0.0, 1.0)
	_energy_fill.color = _ink if fraction > 0.3 else Palette.ACCENT


## Mesafe: 1,234 m (binler virgülle)
static func distance_text(meters: float) -> String:
	var s := str(int(maxf(meters, 0.0)))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out + " m"


## Oyun içi mesafe: 1.07 km
static func km_text(meters: float) -> String:
	return "%.2f km" % (maxf(meters, 0.0) / 1000.0)


## Derste: mesafe, puan ve ilk ipucu gizli (dersin kendi yazıları var)
func lesson_mode() -> void:
	for l: Label in [_score, _dist, _hint]:
		l.visible = false
	for c in _captions:
		c.visible = false


func set_score(score: int, multiplier: int, meters := 0.0) -> void:
	_score.text = str(score)
	_dist.text = km_text(meters)
	_mult.text = "x%d" % multiplier
	_mult.modulate.a = 1.0 if multiplier > 1 else 0.45


## accent: vurgu rengiyle göster (kritik ya da özel anlar)
func popup(text: String, accent := false) -> void:
	_popup.text = text
	_popup.add_theme_color_override("font_color", Palette.ACCENT if accent else _ink)
	_popup.modulate.a = 0.0
	if _popup_tween:
		_popup_tween.kill()
	_popup_tween = create_tween()
	_popup_tween.tween_property(_popup, "modulate:a", 1.0, 0.12)
	_popup_tween.tween_interval(0.6)
	_popup_tween.tween_property(_popup, "modulate:a", 0.0, 0.3)


func show_game_over(reason: String, score: int, best: int, meters := 0.0) -> void:
	_layout_game_over()
	# Üstteki mesafe ve puan oyun sonu ekranında yok (ekranın kendi bilgileri var)
	for l: Label in [_score, _dist]:
		l.visible = false
	for c in _captions:
		c.visible = false
	_over_reason.text = reason.trim_suffix("!")
	_over_score.text = str(score)
	_over_dist.text = km_text(meters)
	_over_best.text = str(best)
	_over_new.visible = score >= best and score > 0
	_over.visible = true
	_over.modulate.a = 0.0
	create_tween().set_ignore_time_scale(true).tween_property(_over, "modulate:a", 1.0, 0.4)
