extends SceneTree
## Araba modellerinin vitrin görüntüleri.
## Kullanım: godot --path . --resolution 720x720 --script res://tools/showroom.gd -- --out=/tmp

var _out := "user://"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	_shoot.call_deferred()


func _shoot() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Palette.PAPER
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("ebe8e2")
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.75, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	world.add_child(sun)
	var road := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(6, 0.2, 14)
	road.mesh = rm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Palette.ASPHALT
	road.material_override = mat
	road.position = Vector3(0.8, -0.1, 0)
	world.add_child(road)
	var cam := Camera3D.new()
	cam.fov = 32
	world.add_child(cam)
	var car_scene: PackedScene = load("res://scenes/car.tscn")
	for v in [1, 2, 3]:
		var car: Car = car_scene.instantiate()
		world.add_child(car)
		car.set_physics_process(false)
		car.model.variant = v
		for view in [["yan", Vector3(-7.5, 3.2, -6.5)], ["arka", Vector3(0, 4.5, 9.5)]]:
			cam.position = view[1]
			cam.look_at(Vector3(0, 0.7, 0))
			for i in 4:
				await process_frame
			var img := root.get_texture().get_image()
			img.save_png("%s/model_%d_%s.png" % [_out, v, view[0]])
		car.queue_free()
		await process_frame
	quit()
