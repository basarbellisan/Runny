class_name CoinPill
extends PanelContainer
## Sağ üstte para: beyaz zeminli, koyu çerçeveli hap içinde jeton ve sayı. Değişince sayarak gelir
## ve kısa bir zıplama yapar (garaj ve oyun sonu ekranı).

var value := 0
var _label: Label
var icon: CoinIcon
var _tween: Tween
var _shown := 0.0


func _init(v := 0) -> void:
	value = v
	_shown = v
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.border_color = Palette.INK_DARK
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(40)
	sb.content_margin_left = 9
	sb.content_margin_right = 18
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	icon = CoinIcon.new("coin", 32)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 28)
	_label.add_theme_color_override("font_color", Palette.INK_DARK)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_label)
	_set_shown(v)


## Sağ üst köşeye (sağ kenara yaslı, sola doğru büyür)
func place_top_right(margin := 24.0, top := 42.0) -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_right = -margin
	offset_left = -margin
	offset_top = top


func set_value(v: int, animate := true, seconds := 0.5) -> void:
	value = v
	if _tween:
		_tween.kill()
	if not animate:
		_set_shown(v)
		return
	_tween = create_tween().set_ignore_time_scale(true)
	_tween.tween_method(_set_shown, _shown, float(v), seconds)
	bump()


func bump() -> void:
	pivot_offset = size * 0.5
	var t := create_tween().set_ignore_time_scale(true)
	t.tween_property(self, "scale", Vector2.ONE * 1.12, 0.12)
	t.tween_property(self, "scale", Vector2.ONE, 0.2)


func _set_shown(v: float) -> void:
	_shown = v
	_label.text = fmt(int(round(v)))


## 12,345
static func fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out
