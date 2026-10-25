class_name Hud
extends CanvasLayer
## Skor, çarpan, anlık mesajlar ve oyun sonu ekranı.
## Sade tipografi; yazı rengi katmana göre koyudan açığa geçer.

const BAR_WIDTH := 300.0

signal garage_pressed

var _labels: Array[Label] = []
var _score: Label
var _mult: Label
var _popup: Label
var _hint: Label
var _energy: Control
var _energy_back: ColorRect
var _energy_fill: ColorRect
var speedometer: Speedometer
var _speedo: Speedometer
var _speedo_shown := true

var _hint_tween: Tween
var _over: Control
var _over_bg: ColorRect
var _over_reason: Label
var _over_score: Label
var _over_best: Label
var _popup_tween: Tween
var _ink := Palette.INK_DARK
var _mood := -1.0
var _energy_fraction := 1.0
var _spaced: FontVariation


func _ready() -> void:
	_spaced = FontVariation.new()
	_spaced.spacing_glyph = 4
	_score = _make_label(76, Vector2(0, 56))
	_mult = _make_label(26, Vector2(0, 150), true)
	_popup = _make_label(40, Vector2(0, 420), true)
	_popup.modulate.a = 0.0
	_hint = _make_label(20, Vector2(0, 330), true)
	_build_energy_bar()
	_build_game_over()
	# Hız kadranı: alt ortada, iki başparmağın arasında
	_speedo = Speedometer.new()
	add_child(_speedo)
	_speedo.anchor_left = 0.5
	_speedo.anchor_right = 0.5
	_speedo.anchor_top = 1.0
	_speedo.anchor_bottom = 1.0
	_speedo.offset_left = -110
	_speedo.offset_right = 110
	_speedo.offset_top = -230
	_speedo.offset_bottom = -40
	speedometer = _speedo
	set_mood(0.0)
	hint("SOLA DOKUN      |      SAĞA DOKUN", 3.0)


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
	label.text = "ENERJİ"
	label.offset_top = 14
	label.offset_bottom = 34
	label.modulate.a = 0.6
	_energy.visible = false


func _build_game_over() -> void:
	_over = Control.new()
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_over)
	_over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_over_bg = ColorRect.new()
	_over_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.add_child(_over_bg)
	_over_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_over_reason = _make_label(26, Vector2(0, 480), true, _over)
	_over_score = _make_label(110, Vector2(0, 600), false, _over)
	_over_best = _make_label(20, Vector2(0, 700), true, _over)
	var again := _make_label(18, Vector2(0, 900), true, _over)
	again.text = "TEKRAR İÇİN DOKUN"
	again.modulate.a = 0.55
	# Garaja dönüş: butona basmak oyunu yeniden başlatmaz (dokunuşu buton alır)
	var garage := Button.new()
	garage.text = "GARAJ"
	garage.focus_mode = Control.FOCUS_NONE
	garage.add_theme_font_override("font", _spaced)
	garage.add_theme_font_size_override("font_size", 22)
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.set_border_width_all(2)
		sb.border_color = Palette.ACCENT
		sb.set_corner_radius_all(6)
		garage.add_theme_stylebox_override(state, sb)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		garage.add_theme_color_override(state, Palette.ACCENT)
	garage.anchor_left = 0.5
	garage.anchor_right = 0.5
	garage.offset_left = -130
	garage.offset_right = 130
	garage.offset_top = 1010
	garage.offset_bottom = 1090
	garage.pressed.connect(func(): garage_pressed.emit())
	_over.add_child(garage)
	_over.visible = false


## 0 = üst katman (açık zemin, koyu yazı), 1 = alt katman (koyu zemin, açık yazı)
func set_mood(m: float) -> void:
	if absf(m - _mood) < 0.01:
		return
	_mood = m
	_ink = Palette.INK_DARK.lerp(Palette.INK_LIGHT, smoothstep(0.3, 0.7, m))
	for l in _labels:
		l.add_theme_color_override("font_color", _ink)
	_over_reason.add_theme_color_override("font_color", Palette.ACCENT)
	_energy_back.color = Color(_ink, 0.18)
	_over_bg.color = Color(Palette.PAPER.lerp(Palette.GRAPHITE, m), 0.88)
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


## Roket yakıtı (0-1): kadranı çevreleyen halka
func set_fuel(fuel: float) -> void:
	_speedo.set_fuel(fuel)


func show_energy(visible_: bool) -> void:
	_energy.visible = visible_


func set_energy(fraction: float) -> void:
	_energy_fraction = fraction
	_energy_fill.size.x = BAR_WIDTH * clampf(fraction, 0.0, 1.0)
	_energy_fill.color = _ink if fraction > 0.3 else Palette.ACCENT


func set_score(score: int, multiplier: int) -> void:
	_score.text = str(score)
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


func show_game_over(reason: String, score: int, best: int) -> void:
	_over_reason.text = reason.trim_suffix("!")
	_over_score.text = str(score)
	_over_best.text = "EN İYİ  %d" % best
	_over.visible = true
	_over.modulate.a = 0.0
	create_tween().tween_property(_over, "modulate:a", 1.0, 0.4)
