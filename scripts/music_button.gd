class_name MusicButton
extends Button
## Müzik aç / kapat düğmesi (garaj ve oyun sonu ekranı): yuvarlak içinde hoparlör; açıkken ses
## dalgaları, kapalıyken çarpı.
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
	var col := color if Audio.music_on else Color(color, 0.6)
	var w := 3.5 * u
	# Yuvarlak çerçeve
	draw_arc(c, 36.0 * u, 0.0, TAU, 64, col, w, true)
	# Hoparlör: küçük gövde + açılan koni (biraz sola kaymış; sağda dalgalar ya da çarpı)
	var o := c + Vector2(-8, 0) * u
	draw_colored_polygon(PackedVector2Array([
		o + Vector2(-12, -6) * u, o + Vector2(-4, -6) * u, o + Vector2(6, -15) * u,
		o + Vector2(6, 15) * u, o + Vector2(-4, 6) * u, o + Vector2(-12, 6) * u]), col)
	if Audio.music_on:
		# Ses dalgaları
		draw_arc(o + Vector2(7, 0) * u, 9.0 * u, -0.75, 0.75, 16, col, w, true)
		draw_arc(o + Vector2(7, 0) * u, 16.0 * u, -0.8, 0.8, 20, col, w, true)
	else:
		# Kapalı: hoparlörün sağında çarpı
		var x := o + Vector2(19, 0) * u
		draw_line(x + Vector2(-6, -6) * u, x + Vector2(6, 6) * u, col, w, true)
		draw_line(x + Vector2(-6, 6) * u, x + Vector2(6, -6) * u, col, w, true)
