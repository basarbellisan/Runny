class_name Speedometer
extends Control
## Hız kadranı: 270° tarama, çentikler, turuncu ibre ve dijital hız.
## Dış halka temel hıza kadar beyaz, gazın eklediği kısım turuncu dolar.

const MAX_KMH := 300.0
const START_DEG := 135.0
const SWEEP_DEG := 270.0

@export var radius := 108.0

var _shown_kmh := 0.0
var _needle_v := 0.0
var _kmh := 0.0
var _base_kmh := 0.0
var _boost := 0.0
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()


## kmh: gerçek hız, base_kmh: gazsız hız, boost: 0..1
func set_values(kmh: float, base_kmh: float, boost: float) -> void:
	_kmh = kmh
	_base_kmh = base_kmh
	_boost = boost


func _process(delta: float) -> void:
	# İbre: kritik sönümlü yay, gerçek bir ibre gibi hafif gecikmeli
	var k := 90.0
	var c := 2.0 * sqrt(k)
	_needle_v += (k * (_kmh - _shown_kmh) - c * _needle_v) * delta
	_shown_kmh += _needle_v * delta
	queue_redraw()


func _angle(kmh: float) -> float:
	return deg_to_rad(START_DEG + SWEEP_DEG * clampf(kmh / MAX_KMH, 0.0, 1.0))


func _draw() -> void:
	var c := size * 0.5
	var r := radius
	var ink := Palette.SNOW
	var dim := Color(Palette.SNOW, 0.35)
	var start := deg_to_rad(START_DEG)
	var stop := deg_to_rad(START_DEG + SWEEP_DEG)

	draw_circle(c, r, Color(Palette.INK_DARK, 0.9))
	draw_arc(c, r - 3, 0, TAU, 96, Color(Palette.SNOW, 0.08), 2.0, true)

	# Dış halka: iz, temel hız (beyaz), gazın eklediği (turuncu)
	var ring := r - 14
	draw_arc(c, ring, start, stop, 96, Color(Palette.SNOW, 0.12), 6.0, true)
	draw_arc(c, ring, start, _angle(minf(_base_kmh, _shown_kmh)), 64, Color(Palette.SNOW, 0.85), 6.0, true)
	if _shown_kmh > _base_kmh + 0.5:
		draw_arc(c, ring, _angle(_base_kmh), _angle(_shown_kmh), 48, Palette.ACCENT, 6.0, true)

	# Çentikler ve rakamlar
	for v in range(0, int(MAX_KMH) + 1, 10):
		var a := _angle(v)
		var dir := Vector2(cos(a), sin(a))
		var major := v % 50 == 0
		var outer := ring - 8
		var inner := outer - (12.0 if major else 6.0)
		draw_line(c + dir * inner, c + dir * outer, ink if major else dim, 2.5 if major else 1.5, true)
		if v % 100 == 0:
			var txt := str(v)
			var fs := 15
			var tsize := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			var p := c + dir * (inner - 16) + Vector2(-tsize.x * 0.5, tsize.y * 0.3)
			draw_string(_font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, dim)

	# Dijital hız
	var speed_txt := str(int(round(_shown_kmh)))
	var big := 40
	var s := _font.get_string_size(speed_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, big)
	draw_string(_font, c + Vector2(-s.x * 0.5, r * 0.52), speed_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, big, ink)
	var unit := "KM/SA"
	var us := _font.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	draw_string(_font, c + Vector2(-us.x * 0.5, r * 0.52 + 18), unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dim)

	# İbre: tam gazda hafifçe titrer
	var jitter := deg_to_rad(randf_range(-0.8, 0.8)) * smoothstep(0.85, 1.0, _boost)
	var na := _angle(_shown_kmh) + jitter
	var nd := Vector2(cos(na), sin(na))
	draw_line(c - nd * 12, c + nd * (ring - 6), Palette.ACCENT, 4.0, true)
	draw_circle(c, 9, Palette.SNOW)
	draw_circle(c, 4, Palette.INK_DARK)
