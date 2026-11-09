class_name MusicButton
extends Button
## Müzik aç / kapat düğmesi (garaj ve oyun sonu ekranı): nota simgesi, kapalıyken üstü çizili.
## Seçim kaydedilir (Audio.set_music).

## Simgenin rengi (garajda koyu, oyun sonunda beyaz)
var color := Palette.INK_DARK


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	flat = true
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())
	pressed.connect(func():
		Audio.set_music(not Audio.music_on)
		queue_redraw())


## Sağ üst köşeye yerleştir (kenardan uzaklık ve boy, piksel)
func place_top_right(margin := 24.0, top := 36.0, size_px := 84.0) -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_right = -margin
	offset_left = -margin - size_px
	offset_top = top
	offset_bottom = top + size_px


func _draw() -> void:
	var s := size
	var c := s * 0.5
	var u := minf(s.x, s.y) / 84.0
	var col := color if Audio.music_on else Color(color, 0.55)
	var w := 4.0 * u
	# Çift nota: iki baş, iki sap, üstte kalın kiriş
	var h1 := c + Vector2(-14, 16) * u
	var h2 := c + Vector2(12, 11) * u
	for h: Vector2 in [h1, h2]:
		draw_set_transform(h, -0.35, Vector2(1.25, 0.9))
		draw_circle(Vector2.ZERO, 7.5 * u, col)
		draw_set_transform(Vector2.ZERO)
	var top1 := c + Vector2(-6.5, -17) * u
	var top2 := c + Vector2(19.5, -22) * u
	draw_line(h1 + Vector2(7.0, -2.0) * u, top1, col, w)
	draw_line(h2 + Vector2(7.0, -2.0) * u, top2, col, w)
	draw_colored_polygon(PackedVector2Array([top1 + Vector2(-2, 0) * u, top2 + Vector2(2, 0) * u,
		top2 + Vector2(2, 7) * u, top1 + Vector2(-2, 7) * u]), col)
	if not Audio.music_on:
		# Kapalı: çapraz çizgi
		draw_line(c + Vector2(-26, -26) * u, c + Vector2(26, 26) * u, color, w * 1.2)
