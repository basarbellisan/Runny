extends SceneTree
## Test: arabanın gövdesi yolların içine giriyor mu. Her araba için birkaç durum
## (kenardan devrilme, ters / yan / burun üstü düşüş, yolun yanından dönerek düşme)
## gövde koruması kapalı ve açıkken denenir; her durumda gövdenin yola en çok
## girdiği derinlik ve sonuç yazılır.
## Kullanım: godot --headless --path . --fixed-fps 60 --script res://tools/hull_test.gd [-- --models=1,9 --shots=DIR]
## --shots ile (ekranlı çalıştırınca) her durumun en derin anının görüntüsü kaydedilir.

const CASES := ["devrilme", "ters", "yan", "burun", "duvar"]
var _result := ""
var _args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""
	_run.call_deferred()


func _run() -> void:
	var models := Array(_args.get("models", "1,2,3,4,6,7,8,9").split(",")).map(func(m): return int(m))
	var cases: Array = Array(_args["cases"].split(",")) if _args.has("cases") else CASES
	for model in models:
		for c in cases:
			var line := "model %d  %-9s" % [model, c]
			var at := -1
			for guard in [false, true]:
				var r: Array = await _one(model, c, guard, at)
				at = r[2]
				line += "  |  koruma %s: en derin %.2f m, %s" % ["açık " if guard else "kapalı", r[0], r[1]]
			print(line)
	quit()


## shot_at: korumalı koşuda görüntü, korumasız koşunun en derin anındaki karede alınır
func _one(model: int, c: String, guard: bool, shot_at := -1) -> Array:
	_result = "sağ"
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 3:
		await physics_frame
	var car: Car = main.car
	car.model.variant = model
	car.hull_guard = guard
	var roads: RoadGenerator = main.roads
	car.died.connect(func(reason: String): _result = "PATLADI: " + reason)
	for i in 30:
		await physics_frame
	var s: RoadGenerator.Segment = roads.segment_under(car.global_position)
	var top := car.global_position.y
	var edge := s.x + s.width * 0.5
	car.speed = 30.0
	match c:
		"devrilme":
			# Sağ tekerler yolun dışında: araba kenardan devrilir
			car.global_position.x = edge - 0.25
		"ters", "yan", "burun":
			car.global_position.y = top + 2.5
			car.velocity = Vector3(0, 0, -30)
			car._was_on_floor = false
			if c == "ters":
				car.roll = PI
			elif c == "yan":
				car.roll = PI * 0.5
			else:
				car.pitch = -1.3
		"duvar":
			# Yolun yanında, dönerek düşer
			car.global_position = Vector3(edge + 0.9, top + 0.5, car.global_position.z)
			car.velocity = Vector3(-2, 0, -30)
			car.roll = 1.2
			car.roll_rate = -4.0
			car._set_mode(Car.Mode.FALLING)
	var deepest := 0.0
	var deepest_frame := -1
	for f in 150:
		await physics_frame
		if car.mode == Car.Mode.DEAD or car.mode == Car.Mode.FLYING:
			break
		var d := car.hull_depth()
		var shot := f == shot_at
		if d > deepest:
			deepest = d
			deepest_frame = f
			shot = shot or not guard
		if shot and _args.has("shots"):
			await process_frame
			var img := root.get_viewport().get_texture().get_image()
			img.save_png("%s/m%d_%s_%s.png" % [_args.shots, model, c, "acik" if guard else "kapali"])
	var out := [deepest, _result if _result != "sağ" else ("uçuyor" if car.mode == Car.Mode.FLYING else "sağ"), deepest_frame]
	main.queue_free()
	await process_frame
	return out
