extends SceneTree
## 10 kadran stilini yan yana çizer (karşılaştırma görseli).
## Kullanım: godot --path . --resolution 720x1280 --script res://tools/gauge_sheet.gd -- --out=/tmp/x.png --kmh=140

func _initialize() -> void:
	_draw_sheet.call_deferred()


func _draw_sheet() -> void:
	var out := "user://kadranlar.png"
	var kmh := 140.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--kmh="):
			kmh = float(a.trim_prefix("--kmh="))
	var bg := ColorRect.new()
	bg.color = Color("5f6166")  # yol rengi
	bg.size = Vector2(720, 1280)
	root.add_child(bg)
	var names := ["Beyaz yay", "Siyah yay", "Yarım ay", "Turuncu yüz", "Sadece yay",
		"Dijital", "Siyah klasik", "Beyaz klasik", "Cetvel", "Halka"]
	for i in 10:
		var col := i % 2
		var row := i / 2
		var cell := Vector2(col * 360, row * 256)
		var g := Speedometer.new()
		g.style = i + 1
		g.position = cell + Vector2(70, 46)
		g.size = Vector2(220, 180)
		bg.add_child(g)
		g.snap(kmh)
		var l := Label.new()
		l.text = "%d  %s" % [i + 1, names[i]]
		l.position = cell + Vector2(16, 10)
		l.add_theme_font_size_override("font_size", 22)
		l.add_theme_color_override("font_color", Palette.SNOW)
		bg.add_child(l)
	for i in 3:
		await process_frame
	root.get_texture().get_image().save_png(out)
	quit()
