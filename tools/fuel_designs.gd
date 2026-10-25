extends SceneTree
## Roket yakıtı göstergesi için 10 tasarım taslağı: her biri kadranın (stil 1)
## etrafında, üç durumda (dolu / yanıyor / doluyor). Oyunda kullanılmaz.
## Kullanım: godot --path . --resolution 720x2300 --script res://tools/fuel_designs.gd -- --out=/tmp/x.png

const C := Vector2(110, 95)   # kadran merkezi (Speedometer içinde)
const R := 70.0               # kadran yarıçapı
const NAMES := [
	"Alt yay (dışta)", "Tam halka", "İç yay (rakamın altında)", "Nokta dizisi",
	"Yan dikey çubuk", "İki yan parantez", "Kapsül + ROKET yazısı", "Kenar halesi",
	"Alev ikonu + çubuk", "Çentik yayı",
]
const STATES := [["DOLU", 1.0, 0], ["YANIYOR", 0.45, 1], ["DOLUYOR", 0.6, 2]]

var _font: Font


func _initialize() -> void:
	_draw_sheet.call_deferred()


func _draw_sheet() -> void:
	var out := "user://yakit.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	var bg := ColorRect.new()
	bg.color = Color("5f6166")
	bg.size = Vector2(720, 2300)
	root.add_child(bg)
	_font = bg.get_theme_default_font()
	for st in 3:
		var l := _label(STATES[st][0], Vector2(st * 240 + 90, 12), 18, Color(Palette.SNOW, 0.7))
		bg.add_child(l)
	for i in 10:
		var y := 40 + i * 226
		bg.add_child(_label("%d  %s" % [i + 1, NAMES[i]], Vector2(14, y), 20, Palette.SNOW))
		for st in 3:
			var g := Speedometer.new()
			g.style = 1
			g.position = Vector2(st * 240 + 10, y + 26)
			g.size = Vector2(220, 190)
			bg.add_child(g)
			g.snap([120.0, 260.0, 150.0][st])
			var overlay := Control.new()
			overlay.size = g.size
			g.add_child(overlay)
			overlay.draw.connect(_draw_fuel.bind(overlay, i + 1, STATES[st][1], STATES[st][2]))
	for i in 3:
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


## state 0: dolu (hazır), 1: yanıyor (boşalıyor), 2: doluyor
func _fill_color(state: int) -> Color:
	match state:
		0: return Palette.ACCENT
		1: return Color("fff1dc")
		_: return Color(Palette.ACCENT, 0.5)


func _arc(ci: Control, r: float, a0: float, a1: float, w: float, col: Color) -> void:
	if absf(a1 - a0) < 0.001:
		return
	ci.draw_arc(C, r, deg_to_rad(a0), deg_to_rad(a1), 48, col, w, true)


func _capsule(ci: Control, rect: Rect2, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(minf(rect.size.x, rect.size.y) * 0.5))
	ci.draw_style_box(sb, rect)


func _draw_fuel(ci: Control, design: int, fuel: float, state: int) -> void:
	var col := _fill_color(state)
	var track := Color(0, 0, 0, 0.28)
	var light_track := Color(1, 1, 1, 0.18)
	match design:
		1:
			# Kadranın alt yarısını dıştan saran kalın yay; soldan sağa dolar
			_arc(ci, R + 10, 160, 20, 7, track)
			_arc(ci, R + 10, 160, 160 - 140 * fuel, 7, col)
		2:
			# Kadranı çevreleyen ince tam halka; tepeden saat yönünde dolar
			_arc(ci, R + 8, -90, 270, 4, track)
			_arc(ci, R + 8, -90, -90 + 360 * fuel, 4, col)
		3:
			# Beyaz yüzün içinde, hız rakamının altında yay
			_arc(ci, R - 10, 145, 35, 6, Color(0, 0, 0, 0.12))
			_arc(ci, R - 10, 145, 145 - 110 * fuel, 6, Palette.ACCENT if state != 1 else Color("ff9a5c"))
		4:
			# Alt yayda 7 nokta; her biri yakıtın 1/7'si
			for k in 7:
				var a := deg_to_rad(150 - k * 20)
				var p := C + Vector2.from_angle(a) * (R + 13)
				var lit := clampf(fuel * 7 - k, 0, 1)
				ci.draw_circle(p, 6, track)
				if lit > 0:
					ci.draw_circle(p, 6 * (0.5 + 0.5 * lit), col)
		5:
			# Sağda dikey kapsül, aşağıdan yukarı dolar
			var rect := Rect2(C + Vector2(R + 12, -R + 6), Vector2(10, 2 * R - 12))
			_capsule(ci, rect, track)
			var h := rect.size.y * fuel
			if h > 1:
				_capsule(ci, Rect2(rect.position + Vector2(0, rect.size.y - h), Vector2(10, h)), col)
		6:
			# İki yanda parantez yaylar, alttan yukarı dolar
			_arc(ci, R + 10, 115, 215, 6, track)
			_arc(ci, R + 10, 65, -35, 6, track)
			_arc(ci, R + 10, 115, 115 + 100 * fuel, 6, col)
			_arc(ci, R + 10, 65, 65 - 100 * fuel, 6, col)
		7:
			# Altında kalın kapsül ve ROKET yazısı
			var rect := Rect2(C + Vector2(-58, R + 14), Vector2(116, 10))
			_capsule(ci, rect, track)
			if fuel > 0.02:
				_capsule(ci, Rect2(rect.position, Vector2(rect.size.x * fuel, 10)), col)
			ci.draw_string(_font, rect.position + Vector2(0, 28), "ROKET", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(Palette.SNOW, 0.75))
		8:
			# Beyaz yüzün kenarında hale: alttan iki yana doğru büyür
			_arc(ci, R + 3, 90 - 180 * fuel, 90 + 180 * fuel, 6, col)
		9:
			# Solda küçük alev ikonu, yanında çubuk
			var base := C + Vector2(-60, R + 20)
			var flame := PackedVector2Array([base + Vector2(0, -12), base + Vector2(6, 0), base + Vector2(3, 6),
				base + Vector2(-3, 6), base + Vector2(-6, 0)])
			ci.draw_colored_polygon(flame, col if state != 2 else Color(Palette.SNOW, 0.5))
			var rect := Rect2(base + Vector2(14, -4), Vector2(104, 7))
			_capsule(ci, rect, track)
			if fuel > 0.02:
				_capsule(ci, Rect2(rect.position, Vector2(rect.size.x * fuel, 7)), col)
		10:
			# Alt yayda 15 çentik, dolu olanlar yanar
			for k in 15:
				var a := deg_to_rad(160 - k * 10)
				var d := Vector2.from_angle(a)
				var lit := fuel * 15 > k + 0.5
				ci.draw_line(C + d * (R + 6), C + d * (R + 18), col if lit else light_track, 4, true)
