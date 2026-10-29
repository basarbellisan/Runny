extends SceneTree
## Araba modellerinin vitrin görüntüleri.
## Kullanım: godot --path . --resolution 720x720 --script res://tools/showroom.gd -- --out=/tmp

var _out := "user://"
var _variants := [1, 2, 3]
## Stüdyo ışığı: açık zemin, yumuşak ışık (referans görsellerle karşılaştırmak için)
var _studio := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a == "--studio":
			_studio = true
		elif a.begins_with("--glb="):
			# --glb=1:res://models/cars/kutu.glb  (Blender modelini önizle)
			var kv := a.trim_prefix("--glb=").split(":", true, 1)
			CarModel.glb_models[int(kv[0])] = kv[1]
		elif a.begins_with("--variants="):
			_variants = Array(a.trim_prefix("--variants=").split(",")).map(func(v): return int(v))
	_shoot.call_deferred()


func _shoot() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Palette.PAPER
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("ebe8e2")
	env.ambient_light_energy = 0.9 if _studio else 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-1.0, -0.5, 0) if _studio else Vector3(-0.9, 0.75, 0)
	sun.light_energy = 0.9 if _studio else 1.3
	sun.shadow_enabled = true
	world.add_child(sun)
	var road := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(6, 0.2, 14)
	road.mesh = rm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Palette.PAPER if _studio else Palette.ASPHALT
	road.material_override = mat
	road.position = Vector3(0.8, -0.1, 0)
	if _studio:
		rm.size = Vector3(60, 0.2, 60)
	world.add_child(road)
	var cam := Camera3D.new()
	cam.fov = 32
	world.add_child(cam)
	var car_scene: PackedScene = load("res://scenes/car.tscn")
	for v in _variants:
		var car: Car = car_scene.instantiate()
		world.add_child(car)
		car.set_physics_process(false)
		car.model.variant = v
		# [ad, kamera konumu, bakılan nokta]; "oyun": oyundaki takip kamerasının açısı
		for view in [["yan", Vector3(-7.5, 3.2, -6.5), Vector3(0, 0.7, 0)],
				["arka", Vector3(0, 4.5, 9.5), Vector3(0, 0.7, 0)],
				["on", Vector3(-6.0, 2.4, -7.5), Vector3(0, 0.7, 0)],
				["profil", Vector3(-10.0, 1.6, 0.0), Vector3(0, 0.7, 0)],
				["arka_alcak", Vector3(2.5, 1.8, 8.0), Vector3(0, 0.8, 0)],
				["oyun", Vector3(0, 6.0, 10.0), Vector3(0, -1.0, -22.0)]]:
			cam.position = view[1]
			cam.look_at(view[2])
			cam.fov = 62.0 if view[0] == "oyun" else 32.0
			for i in 4:
				await process_frame
			var img := root.get_texture().get_image()
			img.save_png("%s/model_%d_%s.png" % [_out, v, view[0]])
		car.queue_free()
		await process_frame
	quit()
