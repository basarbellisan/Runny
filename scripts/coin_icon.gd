class_name CoinIcon
extends Control
## Para (sarı-turuncu jeton: koyu halka ve ortada koyu nokta) ya da kristal (yeşil eşkenar dörtgen)
## simgesi. Boyu kontrolün boyu kadar.

const COIN := Color("ffb21f")
const COIN_DARK := Color("e08a00")

## "coin", "gem" ya da parça simgeleri: "grip" (tekerlek), "tank" (depo), "flight" (kanat)
var kind := "coin"


func _init(k := "coin", px := 40.0) -> void:
	kind = k
	custom_minimum_size = Vector2(px, px)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	if kind == "gem":
		var w := r * 0.7
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(w, -r * 0.1),
			c + Vector2(0, r), c + Vector2(-w, -r * 0.1)]), Palette.ENERGY)
		return
	if kind == "grip":
		# Tekerlek: koyu lastik, açık jant, koyu göbek
		draw_circle(c, r, Palette.INK_DARK, true, -1.0, true)
		draw_circle(c, r * 0.52, Palette.PAPER, true, -1.0, true)
		draw_circle(c, r * 0.18, Palette.INK_DARK, true, -1.0, true)
		return
	if kind == "tank":
		# Depo: çerçeveli kap, içi yeşil (kristal), üstte kapak
		var w := r * 1.1
		var h := r * 1.55
		var o := c + Vector2(-w * 0.5, -h * 0.5 + r * 0.12)
		draw_rect(Rect2(o + Vector2(w * 0.18, h * 0.42), Vector2(w * 0.64, h * 0.46)), Palette.ENERGY)
		draw_rect(Rect2(o, Vector2(w, h)), Palette.INK_DARK, false, r * 0.16)
		draw_rect(Rect2(c + Vector2(-w * 0.2, -h * 0.5 - r * 0.1), Vector2(w * 0.4, r * 0.22)), Palette.INK_DARK)
		return
	if kind == "agility":
		# Çeviklik: ileri ok ve önünde turuncu çizgi (hızlı tepki)
		var w := r * 0.18
		draw_line(c + Vector2(-r * 0.85, 0), c + Vector2(r * 0.35, 0), Palette.INK_DARK, w, true)
		draw_polyline(PackedVector2Array([c + Vector2(-r * 0.15, -r * 0.5), c + Vector2(r * 0.35, 0), c + Vector2(-r * 0.15, r * 0.5)]), Palette.INK_DARK, w, true)
		draw_line(c + Vector2(r * 0.75, -r * 0.62), c + Vector2(r * 0.75, r * 0.62), Palette.ACCENT, w, true)
		return
	if kind == "balance":
		# Denge: terazi (ortada dikme, üstte kol, iki yanda kefe)
		var w := r * 0.16
		draw_line(c + Vector2(0, -r * 0.7), c + Vector2(0, r * 0.6), Palette.INK_DARK, w, true)
		draw_line(c + Vector2(-r * 0.5, r * 0.75), c + Vector2(r * 0.5, r * 0.75), Palette.INK_DARK, w, true)
		draw_line(c + Vector2(-r * 0.9, -r * 0.35), c + Vector2(r * 0.9, -r * 0.35), Palette.INK_DARK, w, true)
		for sx in [-1.0, 1.0]:
			draw_colored_polygon(PackedVector2Array([c + Vector2(sx * r * 0.9, -r * 0.35), c + Vector2(sx * r * 0.9 - r * 0.28, r * 0.15),
				c + Vector2(sx * r * 0.9 + r * 0.28, r * 0.15)]), Palette.INK_DARK)
		return
	if kind == "flight":
		# Kanat: ok biçimli delta kanat
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.62), c + Vector2(r, r * 0.42),
			c + Vector2(r * 0.22, r * 0.24), c + Vector2(0, r * 0.62), c + Vector2(-r * 0.22, r * 0.24),
			c + Vector2(-r, r * 0.42)]), Palette.INK_DARK)
		return
	draw_circle(c, r, COIN, true, -1.0, true)
	draw_arc(c, r * 0.84, 0.0, TAU, 48, COIN_DARK, r * 0.3, true)
	draw_circle(c, r * 0.3, Color(COIN_DARK, 0.6), true, -1.0, true)
