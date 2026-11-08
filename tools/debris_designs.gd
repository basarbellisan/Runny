extends SceneTree
## Kırık yol parçaları (RoadDebris) tasarım çalışması: 4 boyut × 3 tohum, alt katmanın mercan
## ortamında, kendi eksenlerinde (rastgele eksen ve hızla) dönerken. Kareler --out klasörüne
## d<boyut><tohum>_<kare>.png. Kullanım:
## godot --path . --resolution 420x420 --script res://tools/debris_designs.gd -- --out=/tmp --frames=48

var _out := "user://"
var _frames := 48
var _seeds := [1, 2, 3]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a.begins_with("--frames="):
			_frames = int(a.trim_prefix("--frames="))
		elif a.begins_with("--seeds="):
			_seeds = Array(a.trim_prefix("--seeds=").split(",")).map(func(v): return int(v))
	_shoot.call_deferred()


func _shoot() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("f7c7b2")
	sky_mat.sky_horizon_color = Color("f08976")
	sky_mat.ground_horizon_color = Color("f08976")
	sky_mat.ground_bottom_color = Color("e6685c")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("f2a08e")
	env.ambient_light_energy = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color("f08976")
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_density = 1.0
	env.fog_depth_begin = 0.0
	env.fog_depth_end = 400.0
	env.fog_depth_curve = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.49, 1.08, 0)
	sun.light_color = Color("fff0e6")
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	world.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 40
	world.add_child(cam)
	var dist := [15.0, 26.0, 38.0, 56.0]
	for size in 4:
		for sd: int in _seeds:
			# Şerit düzenleri parçalara sırayla, eşit dağılır
			var style: int = (size * _seeds.size() + _seeds.find(sd)) % RoadGenerator.LINE_STYLES.size()
			var piece := RoadDebris.build(size, sd, style)
			world.add_child(piece)
			var rng := RandomNumberGenerator.new()
			rng.seed = sd * 31 + size
			# Kendi ekseninde dönüş: rastgele eksen ve hız (yavaş, ağırbaşlı)
			var axis := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
			var spin := rng.randf_range(0.15, 0.45) * (1.0 if rng.randf() < 0.5 else -1.0)
			var base := Basis.from_euler(Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(-0.4, 0.4)))
			var dd: float = dist[size]
			cam.look_at_from_position(Vector3(dd * 0.55, dd * 0.42, dd * 0.75), Vector3.ZERO)
			for f in _frames:
				var t := float(f) / 24.0
				piece.basis = Basis(axis, spin * t) * base
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_viewport().get_texture().get_image().save_png("%s/d%d%d_%03d.png" % [_out, size, sd, f])
			print("parça %s %d" % [RoadDebris.NAMES[size], sd])
			var rr := RandomNumberGenerator.new()
			rr.seed = sd * 7919 + size * 104729 + 1
			var dm: Array = RoadDebris.DIMS[size]
			print("OLCU %d %d %.0fx%.0f %s" % [size, sd, rr.randf_range(dm[0].x, dm[0].y), rr.randf_range(dm[1].x, dm[1].y), RoadGenerator.LINE_STYLES[style].name.replace(" ", "_")])
			piece.queue_free()
			await process_frame
	# Bağımsız molozlar (parçalardan ayrı yüzer)
	var group := Node3D.new()
	world.add_child(group)
	for i in 7:
		var r := RoadDebris.build_rubble(i + 1)
		r.position = Vector3((i - 3) * 1.9, sin(i * 1.7) * 0.8, cos(i * 2.3) * 0.8)
		r.rotation = Vector3(i * 0.9, i * 1.3, i * 0.4)
		group.add_child(r)
	cam.look_at_from_position(Vector3(5.5, 4.5, 9.0), Vector3.ZERO)
	for f in _frames:
		var t := float(f) / 24.0
		for k in group.get_child_count():
			var c: Node3D = group.get_child(k)
			c.rotate(Vector3(0.3, 1.0, 0.2).normalized(), 0.02 * (1 + k % 3))
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png("%s/r_%03d.png" % [_out, f])
	quit()
