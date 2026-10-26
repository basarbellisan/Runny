extends SceneTree
## Enerji (kristal) deposu için tasarım taslakları: solda hız kadranı, sağda
## yuvarlak enerji göstergesi. Her satır bir tasarım, sütunlar üç durum
## (dolu / azaldı, uyarı / kristal alındı). Oyunda kullanılmaz.
## Kullanım: godot --path . --resolution 1340x2380 --script res://tools/energy_designs.gd -- --bg=/tmp/oyun.png --out=/tmp/x.png

const W := 432.0               # telefon ekranı genişliği (oyun görüntüsü)
const CROP := 380.0            # ekranın alt kısmı
const R := 66.0                # gösterge yarıçapı
const NAMES := [
	"Beyaz disk + kalın halka", "Hücreli halka (her hücre bir roket)", "Sıvı dolum",
	"Siyah disk", "Açık yay + kristal ikonu", "İki katlı: halka + iç dolum",
]
const STATES := [["DOLU", 100, ""], ["AZALDI · UYARI", 18, ""], ["KRİSTAL ALINDI", 64, "+8"]]
const LOW := Color("e8392b")
const BLACK := Color("1c1d20")

var _font: Font
var _bold: FontVariation


func _initialize() -> void:
	_draw_sheet.call_deferred()


func _draw_sheet() -> void:
	var out := "user://enerji.png"
	var bg_path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		if a.begins_with("--bg="):
			bg_path = a.trim_prefix("--bg=")
	var bg_img := Image.load_from_file(bg_path)
	var bg_tex := ImageTexture.create_from_image(bg_img)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var sheet := ColorRect.new()
	sheet.color = Color("f4f2ee")
	sheet.size = Vector2(1340, 2380)
	root.add_child(sheet)
	_font = sheet.get_theme_default_font()
	_bold = FontVariation.new()
	_bold.base_font = _font
	_bold.variation_embolden = 0.6
	for st in 3:
		sheet.add_child(_label(STATES[st][0], Vector2(st * 446 + 20, 10), 18, Color(BLACK, 0.6)))
	for i in NAMES.size():
		var y := 40.0 + i * (CROP + 0.0 + 6.0)
		for st in 3:
			var cell := Control.new()
			cell.position = Vector2(st * 446 + 10, y + 30)
			cell.size = Vector2(W, CROP - 30)
			cell.clip_contents = true
			sheet.add_child(cell)
			var tr := TextureRect.new()
			tr.texture = bg_tex
			tr.position = Vector2(0, -(bg_img.get_height() - CROP) - 30)
			cell.add_child(tr)
			var speedo := Speedometer.new()
			speedo.style = 1
			speedo.show_fuel = false
			speedo.size = Vector2(220, 190)
			speedo.position = Vector2(-10, CROP - 30 - 190 - 10)
			cell.add_child(speedo)
			speedo.snap([176.0, 150.0, 198.0][st])
			var gauge := Control.new()
			gauge.size = cell.size
			cell.add_child(gauge)
			gauge.draw.connect(_draw_energy.bind(gauge, i + 1, STATES[st][1], STATES[st][2]))
		sheet.add_child(_label("%d  %s" % [i + 1, NAMES[i]], Vector2(20, y + 4), 20, BLACK))
	for k in 3:
		await process_frame
	root.get_texture().get_image().save_png(out)
	quit()


func _label(text: String, pos: Vector2, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _text(ci: Control, s: String, pos: Vector2, fs: int, color: Color) -> void:
	var f: Font = _bold if fs >= 22 else _font
	var sz := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	ci.draw_string(f, pos + Vector2(-sz.x * 0.5, fs * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


## Küçük kristal ikonu (baklava)
func _crystal(ci: Control, c: Vector2, r: float, col: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 1.3), c + Vector2(r * 0.8, 0),
		c + Vector2(0, r * 1.3), c + Vector2(-r * 0.8, 0)]), col)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.7), c + Vector2(r * 0.35, 0),
		c + Vector2(0, r * 0.15), c + Vector2(-r * 0.3, -r * 0.1)]), Color(1, 1, 1, 0.75))


func _ring(ci: Control, c: Vector2, r: float, frac: float, w: float, col: Color, track: Color) -> void:
	ci.draw_arc(c, r, 0.0, TAU, 96, track, w, true)
	if frac > 0.002:
		ci.draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * frac, 96, col, w, true)


func _draw_energy(ci: Control, design: int, value: int, gain: String) -> void:
	var c := Vector2(W - 95.0, ci.size.y - 105.0 - 10.0 + 10.0)
	var f := value / 100.0
	var low := value <= 20
	var col := LOW if low else Palette.ACCENT
	var ink := LOW if low else BLACK
	var white := Palette.SNOW
	var num := str(value)
	if low:
		# Uyarı: gösterge kırmızı nabız atar (burada hale olarak)
		ci.draw_circle(c, R + 16, Color(LOW, 0.18))
	match design:
		1:
			ci.draw_circle(c, R, white)
			_ring(ci, c, R + 9, f, 9.0, col, Color(BLACK, 0.3))
			_crystal(ci, c + Vector2(0, -30), 7, col)
			_text(ci, num, c + Vector2(0, 6), 36, ink)
			_text(ci, "ENERJİ", c + Vector2(0, 34), 11, Color(BLACK, 0.5))
		2:
			ci.draw_circle(c, R, white)
			var cells := 10
			var gap := 0.07
			for k in cells:
				var a0 := -PI * 0.5 + TAU * k / cells + gap * 0.5
				var a1 := -PI * 0.5 + TAU * (k + 1) / cells - gap * 0.5
				var lit := f * cells - k
				ci.draw_arc(c, R + 9, a0, a1, 12, Color(BLACK, 0.3), 10.0, true)
				if lit > 0.0:
					ci.draw_arc(c, R + 9, a0, a0 + (a1 - a0) * clampf(lit, 0.0, 1.0), 12, col, 10.0, true)
			_crystal(ci, c + Vector2(0, -30), 7, col)
			_text(ci, num, c + Vector2(0, 6), 36, ink)
			_text(ci, "%d ROKET" % int(f * cells), c + Vector2(0, 34), 11, Color(BLACK, 0.5))
		3:
			ci.draw_circle(c, R, white)
			# Alttan dolan sıvı: dairenin seviyenin altında kalan parçası, üstü dalgalı
			var rr := R - 4.0
			var s_l := clampf(1.0 - 2.0 * f, -0.999, 0.999)
			var a_l := asin(s_l)
			var pts := PackedVector2Array()
			for k in 41:
				pts.append(c + Vector2.from_angle(lerpf(a_l, PI - a_l, k / 40.0)) * rr)
			var y_l := c.y + rr * s_l
			var half := rr * cos(a_l)
			for k in range(1, 12):
				var x := c.x - half + 2.0 * half * k / 12.0
				pts.append(Vector2(x, y_l + sin(k * 1.3) * 1.8))
			if f > 0.01:
				ci.draw_colored_polygon(pts, Color(col, 0.9))
			ci.draw_arc(c, R, 0.0, TAU, 96, Color(BLACK, 0.85), 3.0, true)
			var on_fill := f > 0.55
			_crystal(ci, c + Vector2(0, -30), 7, white if f > 0.85 else col)
			_text(ci, num, c + Vector2(0, 6), 36, white if on_fill else ink)
		4:
			ci.draw_circle(c, R + 2, BLACK)
			_ring(ci, c, R - 10, f, 10.0, col, Color(white, 0.15))
			_crystal(ci, c + Vector2(0, -26), 6, col)
			_text(ci, num, c + Vector2(0, 6), 34, white if not low else LOW)
			_text(ci, "ENERJİ", c + Vector2(0, 30), 11, Color(white, 0.5))
		5:
			ci.draw_circle(c, R, white)
			# Altta boşluklu 300° yay, boşlukta kristal ikonu
			var a0 := deg_to_rad(120.0)
			var sweep := deg_to_rad(300.0)
			ci.draw_arc(c, R - 12, a0, a0 + sweep, 80, Color(BLACK, 0.12), 12.0, true)
			if f > 0.002:
				ci.draw_arc(c, R - 12, a0, a0 + sweep * f, 80, col, 12.0, true)
			_text(ci, num, c + Vector2(0, -2), 38, ink)
			_crystal(ci, c + Vector2(0, R - 14), 8, col)
		6:
			ci.draw_circle(c, R, white)
			_ring(ci, c, R + 9, f, 7.0, col, Color(BLACK, 0.3))
			ci.draw_circle(c, R - 14, Color(col, 0.12 + 0.2 * f))
			ci.draw_arc(c, R - 14, -PI * 0.5, -PI * 0.5 + TAU * f, 80, Color(col, 0.6), 3.0, true)
			_crystal(ci, c + Vector2(0, -28), 7, col)
			_text(ci, num, c + Vector2(0, 6), 34, ink)
	if low:
		_text(ci, "KRİSTAL TOPLA!", c + Vector2(0, -R - 26), 14, LOW)
	if gain != "":
		# Kristal alındı: sayı yukarı uçar, halka parlar
		_crystal(ci, c + Vector2(-26, -R - 28), 7, Palette.ACCENT)
		_text(ci, gain, c + Vector2(6, -R - 28), 24, Palette.ACCENT)
		var flash := Color(1, 1, 1, 0.9)
		match design:
			1, 2, 6:
				ci.draw_arc(c, R + 9, -PI * 0.5 + TAU * (f - 0.08), -PI * 0.5 + TAU * f, 24, flash, 4.0, true)
			4:
				ci.draw_arc(c, R - 10, -PI * 0.5 + TAU * (f - 0.08), -PI * 0.5 + TAU * f, 24, flash, 4.0, true)
			5:
				var a0 := deg_to_rad(120.0)
				var sweep := deg_to_rad(300.0)
				ci.draw_arc(c, R - 12, a0 + sweep * (f - 0.08), a0 + sweep * f, 24, flash, 4.0, true)
			3:
				ci.draw_arc(c, R + 6, 0.0, TAU, 96, Color(Palette.ACCENT, 0.5), 4.0, true)
