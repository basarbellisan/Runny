class_name Hud
extends CanvasLayer
## Skor, çarpan, anlık mesajlar ve oyun sonu ekranı.

var _score: Label
var _mult: Label
var _popup: Label
var _hint: Label
var _over: Label
var _energy: Control
var _energy_fill: ColorRect
var _popup_tween: Tween


func _ready() -> void:
	_score = _make_label(64, Control.PRESET_CENTER_TOP, Vector2(0, 40))
	_mult = _make_label(40, Control.PRESET_CENTER_TOP, Vector2(0, 120))
	_mult.modulate = Color("ffd166")
	_popup = _make_label(72, Control.PRESET_CENTER, Vector2(0, -260))
	_popup.modulate.a = 0.0
	_hint = _make_label(34, Control.PRESET_CENTER_BOTTOM, Vector2(0, -120))
	_hint.text = "◀  Sola dokun        Sağa dokun  ▶"
	_over = _make_label(52, Control.PRESET_CENTER, Vector2.ZERO)
	_over.visible = false
	_build_energy_bar()
	var tw := create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(_hint, "modulate:a", 0.0, 1.0)


func _make_label(size: int, preset: Control.LayoutPreset, offset: Vector2) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", size / 5)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.12, 0.2, 0.85))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	l.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.position += offset
	return l


func _build_energy_bar() -> void:
	_energy = Control.new()
	_energy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_energy)
	_energy.anchor_left = 0.5
	_energy.anchor_right = 0.5
	_energy.offset_left = -190
	_energy.offset_right = 190
	_energy.offset_top = 190
	_energy.offset_bottom = 216
	var back := ColorRect.new()
	back.color = Color(0.1, 0.12, 0.2, 0.6)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_energy.add_child(back)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_energy_fill = ColorRect.new()
	_energy_fill.color = Color("5ff5e6")
	_energy_fill.position = Vector2(4, 4)
	_energy_fill.size = Vector2(372, 18)
	_energy_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_energy.add_child(_energy_fill)
	var label := Label.new()
	label.text = "KANAT ENERJİSİ"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_color_override("font_outline_color", Color(0.1, 0.12, 0.2, 0.85))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_energy.add_child(label)
	label.anchor_right = 1.0
	label.offset_top = 30
	_energy.visible = false


func show_energy(visible_: bool) -> void:
	_energy.visible = visible_


func set_energy(fraction: float) -> void:
	_energy_fill.size.x = 372.0 * clampf(fraction, 0.0, 1.0)
	_energy_fill.color = Color("5ff5e6") if fraction > 0.3 else Color("ff6b6b")


func set_score(score: int, multiplier: int) -> void:
	_score.text = str(score)
	_mult.text = "x%d" % multiplier


func popup(text: String, color := Color.WHITE) -> void:
	_popup.text = text
	_popup.modulate = color
	_popup.scale = Vector2(0.6, 0.6)
	_popup.pivot_offset = _popup.size * 0.5
	if _popup_tween:
		_popup_tween.kill()
	_popup_tween = create_tween()
	_popup_tween.tween_property(_popup, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_popup_tween.tween_interval(0.5)
	_popup_tween.tween_property(_popup, "modulate:a", 0.0, 0.35)


func show_game_over(reason: String, score: int, best: int) -> void:
	_over.text = "%s\n\nSkor: %d\nEn iyi: %d\n\nTekrar için dokun" % [reason, score, best]
	_over.visible = true
	_over.modulate.a = 0.0
	create_tween().tween_property(_over, "modulate:a", 1.0, 0.4)
