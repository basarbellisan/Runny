class_name Speedometer
extends Control
## Hız kadranı. 10 stil (ayar panelinden seçilir), hepsinde büyük, okunaklı rakam:
##  1 beyaz yay (0: saat 9, en yüksek: saat 3)   2 siyah yay
##  3 yarım ay + rakam bandı                     4 turuncu yüz
##  5 sadece yay (yüzsüz)                        6 dijital kutu + hız çizgisi
##  7 siyah klasik 270°                          8 beyaz klasik 270°
##  9 cetvel (yatay skala)                       10 halka

const MAX_KMH := 300.0
const BLACK := Color("1c1d20")
const GREY := Color("8a8d92")

@export_range(1, 10) var style := 1:
	set(v):
		style = v
		queue_redraw()

## Roket yakıtı (0-1): kadranı çevreleyen halka. Tepeden saat yönünde dolar,
## gaza basınca azalır. İki renk: koyu iz + turuncu dolgu.
var fuel := 1.0
var _shown_kmh := 0.0
var _needle_v := 0.0
var _kmh := 0.0
var _font: Font
var _bold: FontVariation


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()
	_bold = FontVariation.new()
	_bold.base_font = _font
	_bold.variation_embolden = 0.6


## kmh: gerçek hız (gaz dahil)
func set_values(kmh: float, _base_kmh: float = 0.0, _boost: float = 0.0) -> void:
	_kmh = kmh


func set_fuel(value: float) -> void:
	fuel = clampf(value, 0.0, 1.0)


## Test/görsel için: ibreyi beklemeden doğrudan bu hıza getir
func snap(kmh: float) -> void:
	_kmh = kmh
	_shown_kmh = kmh
	queue_redraw()


func _process(delta: float) -> void:
	# İbre: kritik sönümlü yay, gerçek bir ibre gibi hafif gecikmeli
	# Kare hızı düşse de (takılma) yay patlamasın: küçük adımlarla ilerle
	var k := 90.0
	var steps := ceili(minf(delta, 0.25) / 0.016)
	var dt := minf(delta, 0.25) / maxf(steps, 1)
	for i in steps:
		_needle_v += (k * (_kmh - _shown_kmh) - 2.0 * sqrt(k) * _needle_v) * dt
		_shown_kmh += _needle_v * dt
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var t := clampf(_shown_kmh / MAX_KMH, 0.0, 1.0)
	var speed := str(int(round(_shown_kmh)))
	var orange := Palette.ACCENT
	var white := Palette.SNOW
	match style:
		1:
			draw_circle(c, 70, white)
			_dial(c, 70, 180, 180, BLACK, orange, t)
			_text(speed, c + Vector2(0, 34), 34, BLACK)
		2:
			draw_circle(c, 70, BLACK)
			_dial(c, 70, 180, 180, white, orange, t)
			_text(speed, c + Vector2(0, 34), 34, white)
		3:
			var top := c + Vector2(0, 10)
			_half_disc(top, 78, white)
			draw_rect(Rect2(top.x - 78, top.y + 4, 156, 40), BLACK)
			_dial(top, 78, 180, 180, BLACK, orange, t, 8.0)
			_text(speed, top + Vector2(0, 25), 30, white)
		4:
			draw_circle(c, 70, orange)
			_dial(c, 70, 135, 270, white, BLACK, t)
			_text(speed, c + Vector2(0, 38), 30, white)
		5:
			var r := 66.0
			draw_arc(c + Vector2(0, 14), r, PI, TAU, 64, Color(white, 0.35), 7.0, true)
			draw_arc(c + Vector2(0, 14), r, PI, PI + PI * t, 64, orange, 7.0, true)
			_text(speed, c + Vector2(2, 12), 44, Color(0, 0, 0, 0.35))
			_text(speed, c + Vector2(0, 10), 44, white)
		6:
			var box := Rect2(c - Vector2(80, 38), Vector2(160, 76))
			_round_rect(box, 10, BLACK)
			_text(speed, c + Vector2(0, -4), 40, white)
			var bar := Rect2(box.position + Vector2(16, 58), Vector2(128, 4))
			draw_rect(bar, Color(white, 0.2))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * t, 4)), orange)
		7:
			draw_circle(c, 72, BLACK)
			_dial(c, 72, 135, 270, white, orange, t, 7.0, true)
			_text(speed, c + Vector2(0, 46), 26, white)
		8:
			draw_circle(c, 72, white)
			_dial(c, 72, 135, 270, BLACK, orange, t)
			_text(speed, c + Vector2(0, 42), 28, BLACK)
		9:
			var box := Rect2(c - Vector2(100, 40), Vector2(200, 80))
			_round_rect(box, 8, white)
			var x0 := box.position.x + 14
			var w := box.size.x - 28
			var base := box.end.y - 12
			for v in range(0, int(MAX_KMH) + 1, 25):
				var x := x0 + w * v / MAX_KMH
				var tall := 12.0 if v % 100 == 0 else 6.0
				draw_line(Vector2(x, base), Vector2(x, base - tall), BLACK, 2.0 if v % 100 == 0 else 1.0, true)
			var px := x0 + w * t
			draw_line(Vector2(px, base + 4), Vector2(px, box.position.y + 40), orange, 3.0, true)
			_text(speed, Vector2(c.x, box.position.y + 24), 30, BLACK)
		_:
			draw_circle(c, 68, BLACK)
			draw_arc(c, 56, deg_to_rad(135), deg_to_rad(405), 72, Color(white, 0.15), 9.0, true)
			draw_arc(c, 56, deg_to_rad(135), deg_to_rad(135 + 270 * t), 72, orange, 9.0, true)
			_text(speed, c + Vector2(0, 4), 36, white)
			_text("KM/SA", c + Vector2(0, 30), 12, Color(white, 0.5))
	_draw_fuel(c)


## Yakıt halkası: yuvarlak kadranlarda çevresinde, köşeli olanlarda altında çubuk
func _draw_fuel(c: Vector2) -> void:
	var track := Color(BLACK, 0.3)
	var ring := {1: [c, 78.0], 2: [c, 78.0], 4: [c, 78.0], 5: [c + Vector2(0, 14), 76.0],
		7: [c, 80.0], 8: [c, 80.0], 10: [c, 76.0]}
	if ring.has(style):
		var center: Vector2 = ring[style][0]
		var r: float = ring[style][1]
		draw_arc(center, r, 0.0, TAU, 96, track, 5.0, true)
		if fuel > 0.002:
			draw_arc(center, r, -PI * 0.5, -PI * 0.5 + TAU * fuel, 96, Palette.ACCENT, 5.0, true)
		return
	var bar := Rect2(c + Vector2(-60, 56), Vector2(120, 5))
	draw_rect(bar, track)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fuel, bar.size.y)), Palette.ACCENT)


## Çentikli kadran ve ibre. start/sweep derece (0 = saat 3, 180 = saat 9).
func _dial(c: Vector2, r: float, start: float, sweep: float, ink: Color, needle: Color,
		t: float, inset := 7.0, numbers := false) -> void:
	for v in range(0, int(MAX_KMH) + 1, 25):
		var dir := Vector2.from_angle(deg_to_rad(start + sweep * v / MAX_KMH))
		var major := v % 100 == 0
		var outer := r - inset
		var inner := outer - (11.0 if major else 5.0)
		draw_line(c + dir * inner, c + dir * outer, ink, 2.5 if major else 1.2, true)
		if numbers and major and v > 0 and v < MAX_KMH:
			_text(str(v), c + dir * (inner - 14), 14, Color(ink, 0.7))
	var nd := Vector2.from_angle(deg_to_rad(start + sweep * t))
	draw_line(c - nd * 8.0, c + nd * (r - inset - 3.0), needle, 3.0, true)
	draw_circle(c, 5.0, ink)


## Ortalanmış yazı; pos yazının dikey ortası
func _text(s: String, pos: Vector2, fs: int, color: Color) -> void:
	var f: Font = _bold if fs >= 24 else _font
	var sz := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(f, pos + Vector2(-sz.x * 0.5, fs * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


func _half_disc(c: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 41:
		pts.append(c + Vector2.from_angle(PI + PI * i / 40.0) * r)
	pts.append(c + Vector2(r, 4))
	pts.append(c + Vector2(-r, 4))
	draw_colored_polygon(pts, color)


func _round_rect(rect: Rect2, radius: float, color: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	draw_style_box(sb, rect)
