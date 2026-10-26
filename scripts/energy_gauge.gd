class_name EnergyGauge
extends Control
## Enerji deposu (sağ alt): beyaz disk, ortada sayı, çevresinde kalın turuncu halka.
## Halka tepeden saat yönünde dolar. 20'nin altında kırmızı nabız ve "KRİSTAL TOPLA!".
## Kristal alınca üstünde kazanılan enerji belirir, halkanın ucu parlar; enerji yokken gaza
## basılınca gösterge sarsılır.

const R := 66.0
const LOW := Color("e8392b")
const BLACK := Color("1c1d20")
const LOW_AT := 20.0

## Halka ve kristal ikonunun rengi (yol kristalleriyle aynı)
var color := Palette.ENERGY
## Enerji ve depo büyüklüğü
var value := 100.0
var max_value := 100.0
var _shown := 100.0
var _gain := 0.0
var _gain_t := 9.0
var _shake_t := 9.0
var _flash_t := 9.0
var _font: Font
var _bold: FontVariation


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()
	_bold = FontVariation.new()
	_bold.base_font = _font
	_bold.variation_embolden = 0.6


func set_value(v: float, max_v := 100.0) -> void:
	max_value = maxf(max_v, 1.0)
	value = clampf(v, 0.0, max_value)


## Kristal alındı: kaç enerji geldi
func gained(amount: float) -> void:
	_gain = _gain + amount if _gain_t < 0.5 else amount
	_gain_t = 0.0
	_flash_t = 0.0


## Enerji yokken gaza basıldı
func empty() -> void:
	_shake_t = 0.0


func _process(delta: float) -> void:
	_shown = move_toward(_shown, value, maxf(absf(value - _shown) * 10.0, 30.0) * delta)
	_gain_t += delta
	_shake_t += delta
	_flash_t += delta
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	if _shake_t < 0.35:
		c.x += sin(_shake_t * 60.0) * 6.0 * (1.0 - _shake_t / 0.35)
	var f := _shown / max_value
	var low := _shown <= LOW_AT
	var col := LOW if low else color
	var ink := LOW if low else BLACK
	var t := Time.get_ticks_msec() / 1000.0
	if low:
		var pulse := 0.5 + 0.5 * sin(t * 8.0)
		draw_circle(c, R + 16 + pulse * 4.0, Color(LOW, 0.12 + 0.12 * pulse))
	draw_circle(c, R, Palette.SNOW)
	draw_arc(c, R + 9, 0.0, TAU, 96, Color(BLACK, 0.3), 9.0, true)
	if f > 0.002:
		draw_arc(c, R + 9, -PI * 0.5, -PI * 0.5 + TAU * f, 96, col, 9.0, true)
	if _flash_t < 0.4 and f > 0.02:
		var a := 1.0 - _flash_t / 0.4
		draw_arc(c, R + 9, -PI * 0.5 + TAU * maxf(f - 0.08, 0.0), -PI * 0.5 + TAU * f, 24,
			Color(1, 1, 1, 0.9 * a), 4.0, true)
	_crystal(c + Vector2(0, -30), 7.0, col)
	_text(str(int(round(_shown))), c + Vector2(0, 6), 36, ink)
	_text("ENERJİ", c + Vector2(0, 34), 11, Color(BLACK, 0.5))
	if low:
		_text("KRİSTAL TOPLA!", c + Vector2(0, -R - 26), 14, LOW)
	if _gain_t < 0.8:
		var a := 1.0 - smoothstep(0.45, 0.8, _gain_t)
		var y := -R - 28 - _gain_t * 22.0
		_crystal(c + Vector2(-26, y), 7.0, Color(color, a))
		_text("+%d" % int(round(_gain)), c + Vector2(6, y), 24, Color(color.darkened(0.15), a))


func _crystal(p: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r * 1.3), p + Vector2(r * 0.8, 0),
		p + Vector2(0, r * 1.3), p + Vector2(-r * 0.8, 0)]), col)
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r * 0.7), p + Vector2(r * 0.35, 0),
		p + Vector2(0, r * 0.15), p + Vector2(-r * 0.3, -r * 0.1)]), Color(1, 1, 1, 0.75 * col.a))


func _text(s: String, pos: Vector2, fs: int, color: Color) -> void:
	var fnt: Font = _bold if fs >= 22 else _font
	var sz := fnt.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(fnt, pos + Vector2(-sz.x * 0.5, fs * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
