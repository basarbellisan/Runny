class_name Speedometer
extends Control
## Hız kadranı, Braun tarzı: düz kırık beyaz yüz, ince çentikler,
## tek vurgu olarak turuncu ibre, altta küçük hız rakamı.

const MAX_KMH := 300.0
const START_DEG := 135.0
const SWEEP_DEG := 270.0

@export var radius := 64.0

var _shown_kmh := 0.0
var _needle_v := 0.0
var _kmh := 0.0
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()


## kmh: gerçek hız (gaz dahil)
func set_values(kmh: float, _base_kmh: float, _boost: float) -> void:
	_kmh = kmh


func _process(delta: float) -> void:
	# İbre: kritik sönümlü yay, gerçek bir ibre gibi hafif gecikmeli
	var k := 90.0
	_needle_v += (k * (_kmh - _shown_kmh) - 2.0 * sqrt(k) * _needle_v) * delta
	_shown_kmh += _needle_v * delta
	queue_redraw()


func _angle(kmh: float) -> float:
	return deg_to_rad(START_DEG + SWEEP_DEG * clampf(kmh / MAX_KMH, 0.0, 1.0))


func _draw() -> void:
	var c := size * 0.5
	var r := radius
	var ink := Palette.INK_DARK
	draw_circle(c, r, Palette.SNOW)

	for v in range(0, int(MAX_KMH) + 1, 25):
		var dir := Vector2.from_angle(_angle(v))
		var major := v % 100 == 0
		var outer := r - 7.0
		var inner := outer - (9.0 if major else 5.0)
		draw_line(c + dir * inner, c + dir * outer, ink, 2.0 if major else 1.0, true)

	var txt := str(int(round(_shown_kmh)))
	var fs := 15
	var ts := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(_font, c + Vector2(-ts.x * 0.5, r * 0.72), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)

	var nd := Vector2.from_angle(_angle(_shown_kmh))
	draw_line(c - nd * 8.0, c + nd * (r - 10.0), Palette.ACCENT, 2.5, true)
	draw_circle(c, 4.0, ink)
