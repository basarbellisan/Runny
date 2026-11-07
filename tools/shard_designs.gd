extends SceneTree
## Işık bariyerinde kesilen arabanın parça ikizi: tasarım görselleri.
## Her araba için: asıl araba, yatay çubuklu ikiz, çubuklar dağılırken, küplü ikiz.
## Kullanım: godot --path . --resolution 720x720 --script res://tools/shard_designs.gd -- --out=/tmp --variants=10,2,1

var _out := "user://"
var _variants := [10, 2, 1]
## Dağılma görseli: parçalar ayrılma itkisinin bu kadar saniyelik yolunu almış gibi
var _spread := 0.06
## Kamera: arkadan çapraz (oyun kamerasına yakın) ya da yandan
var _view := "rear"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a.begins_with("--variants="):
			_variants = Array(a.trim_prefix("--variants=").split(",")).map(func(v): return int(v))
		elif a.begins_with("--spread="):
			_spread = float(a.trim_prefix("--spread="))
		elif a.begins_with("--view="):
			_view = a.trim_prefix("--view=")
	_shoot.call_deferred()


func _shoot() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("a462b5")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c9a8e0")
	env.ambient_light_energy = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.49, 1.08, 0)
	sun.light_color = Color(1, 0.847, 0.659)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	world.add_child(sun)
	var road := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(8, 0.2, 16)
	road.mesh = rm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color("3a2c4e")
	road.material_override = rmat
	road.position = Vector3(0, -0.1, -2)
	world.add_child(road)
	var cam := Camera3D.new()
	cam.fov = 34
	world.add_child(cam)
	if _view == "side":
		cam.look_at_from_position(Vector3(-7.5, 2.6, 1.0), Vector3(0, 0.45, -0.2))
	else:
		cam.look_at_from_position(Vector3(5.2, 4.4, 8.6), Vector3(0, 0.4, -0.4))
	var car: Car = load("res://scenes/car.tscn").instantiate()
	world.add_child(car)
	car.set_physics_process(false)
	car.set_process(false)
	for v: int in _variants:
		car.model.variant = v
		for i in 3:
			await process_frame
		var body: Node3D = car.get_node("Body")
		body.visible = true
		await _snap("%s/parca_%d_0_araba.png" % [_out, v])
		for style in ["bars", "cube"]:
			Car.shard_bars = style == "bars"
			var vox: Dictionary = car._voxels()
			var spreads := [0.0, _spread] if style == "bars" else [0.0]
			for sp: float in spreads:
				var mmi := _twin(vox, sp)
				body.add_child(mmi)
				body.get_node("Model").visible = false
				var name := "1_cubuk" if style == "bars" and sp == 0.0 else ("2_cubuk_dagilma" if style == "bars" else "3_kup")
				await _snap("%s/parca_%d_%s.png" % [_out, v, name])
				print("parca %d %s n=%d" % [v, name, vox.n])
				mmi.queue_free()
				body.get_node("Model").visible = true
		await process_frame
	quit()


## Parça ikizi: ekran kartı verisinden (yerel dönüşüm, renk, itki) basit ışıklı çizim
func _twin(vox: Dictionary, spread: float) -> MultiMeshInstance3D:
	var buf: PackedFloat32Array = vox.buf
	var n: int = vox.n
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	mm.mesh = box
	mm.instance_count = n
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in n:
		var o := i * 20
		var basis := Basis(Vector3(buf[o], buf[o + 4], buf[o + 8]), Vector3(buf[o + 1], buf[o + 5], buf[o + 9]), Vector3(buf[o + 2], buf[o + 6], buf[o + 10]))
		var pos := Vector3(buf[o + 3], buf[o + 7], buf[o + 11])
		if spread > 0.0:
			var kick := Vector3(buf[o + 16], buf[o + 17], buf[o + 18])
			pos += kick * spread
			basis = Basis(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.6)) * basis
		mm.set_instance_transform(i, Transform3D(basis, pos))
		mm.set_instance_color(i, Color(buf[o + 12], buf[o + 13], buf[o + 14]))
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.6
	box.surface_set_material(0, mat)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	return mmi


func _snap(path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)
