class_name LockIcon
extends Control
## Kilitli arabanın üstündeki asma kilit. Açılınca sallanır, büyüyüp kaybolur (open()).


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func reset() -> void:
	modulate.a = 1.0
	scale = Vector2.ONE
	rotation = 0.0


func open() -> Tween:
	pivot_offset = size * 0.5
	var t := create_tween()
	t.tween_property(self, "rotation", -0.22, 0.12)
	t.tween_property(self, "rotation", 0.2, 0.14)
	t.tween_property(self, "rotation", 0.0, 0.1)
	t.tween_property(self, "scale", Vector2.ONE * 1.7, 0.35).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(self, "modulate:a", 0.0, 0.35)
	return t


func _draw() -> void:
	var w := size.x
	var h := size.y
	var ink := Palette.INK_DARK
	# Halka (üstte), gövde (altta), anahtar deliği
	draw_arc(Vector2(w * 0.5, h * 0.42), w * 0.27, PI, TAU, 32, ink, w * 0.11, true)
	draw_line(Vector2(w * 0.23, h * 0.42), Vector2(w * 0.23, h * 0.5), ink, w * 0.11)
	draw_line(Vector2(w * 0.77, h * 0.42), Vector2(w * 0.77, h * 0.5), ink, w * 0.11)
	draw_rect(Rect2(Vector2(w * 0.06, h * 0.46), Vector2(w * 0.88, h * 0.52)), ink)
	draw_circle(Vector2(w * 0.5, h * 0.66), w * 0.09, Palette.PAPER)
	draw_rect(Rect2(Vector2(w * 0.46, h * 0.68), Vector2(w * 0.08, h * 0.16)), Palette.PAPER)
