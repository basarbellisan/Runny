extends SceneTree
## Kalıp türevlerini oyunun kurallarıyla üretir ve oyunun kontrolüyle değerlendirir; JSON yazar.
## editor/physics.js ile karşılaştırmak için (tools/variant_compare.js).
##   godot --headless --path . -s tools/variant_dump.gd -- levels/kalip.json 50 /tmp/turevler.json


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var level := RoadGenerator.parse_level(FileAccess.get_file_as_string(args[0]))
	var n := int(args[1]) if args.size() > 1 else 50
	var out_path: String = args[2] if args.size() > 2 else "user://turevler.json"
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var seen := {LevelCheck.signature(level): true}
	var out: Array = [{"level": level, "check": LevelCheck.analyze(level), "tags": ["asıl"]}]
	var ok := 0
	for i in n:
		var res := LevelCheck.vary(level, rng, seen)
		if res.is_empty():
			continue
		ok += 1
		seen[res.sig] = true
		out.append({"level": res.level, "check": LevelCheck.analyze(res.level), "tags": res.tags})
	# Kontrolün kendisini sınamak için kurallara bakmadan rastgele türevler de (çoğu hatalı olmalı)
	for i in n:
		var ops: Array = LevelCheck.VARY_OPS.filter(func(_op): return rng.randf() < 0.6)
		var raw := LevelCheck.vary_once(level, rng, ops)
		var lv: Dictionary = raw.level
		for p in lv.pieces:
			if rng.randf() < 0.3:
				p["z0"] = float(p.z0) + rng.randf_range(-25.0, 25.0)
			if rng.randf() < 0.2:
				p["w"] = rng.randf_range(2.0, 7.0)
		for o in lv.obstacles:
			if rng.randf() < 0.3:
				o["z0"] = float(o.z0) + rng.randf_range(-30.0, 30.0)
		out.append({"level": lv, "check": LevelCheck.analyze(lv), "tags": ["karışık"]})
	var fa := FileAccess.open(out_path, FileAccess.WRITE)
	fa.store_string(JSON.stringify(out, "", true, true))
	fa.close()
	print("VARIANTS valid=%d/%d written=%d" % [ok, n, out.size()])
	quit()
