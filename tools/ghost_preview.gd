extends SceneTree
## Hayalet modeli (models/ghosts/ghost.glb) oyuncunun kamerasından: alt katmanın mercan ortamında,
## başı önde, ekseni yataydan 20° yukarı eğik bize doğru uçar; etek dalgalanır. Gövdenin
## saydamlığı --alpha=orta,kenar ile denenir (1 opak). Kareler --out klasörüne.
## Kullanım: godot --path . --resolution 360x640 --script res://tools/ghost_preview.gd -- --out=/tmp --alpha=0.7,0.95 --frames=72

var _out := "user://"
var _alpha := Vector2(0.7, 0.95)
var _frames := 72


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a.begins_with("--alpha="):
			var v := a.trim_prefix("--alpha=").split(",")
			_alpha = Vector2(float(v[0]), float(v[1]))
		elif a.begins_with("--frames="):
			_frames = int(a.trim_prefix("--frames="))
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
	world.add_child(sun)
	# Oyun kamerası gibi: arabanın arkasında ve yukarısında, ileri ve hafif aşağı bakar
	var cam := Camera3D.new()
	cam.fov = 62
	world.add_child(cam)
	cam.look_at_from_position(Vector3(0, 6, 10), Vector3(0, 1.0, -22))
	# Hayaletler: farklı uzaklıklardan bize doğru, farklı hızlarda
	var scene: PackedScene = load("res://models/ghosts/ghost.glb")
	var mats: Array[ShaderMaterial] = []
	var ghosts: Array = []
	var starts := [Vector3(-2.5, 1.5, -70), Vector3(4.5, 3.5, -110), Vector3(-6.0, 0.5, -150)]
	for p: Vector3 in starts:
		var g: Node3D = scene.instantiate()
		world.add_child(g)
		var mi := g.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		for si in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(si)
			if m and m.resource_name == "Body":
				mi.set_surface_override_material(si, _body_mat(mats))
		# Baş (+Y) bize (+Z) doğru, 20° yukarı
		g.rotation = Vector3(deg_to_rad(70), 0, 0)
		g.position = p
		ghosts.append(g)
	for f in _frames:
		var t := float(f) / 24.0
		for m in mats:
			m.set_shader_parameter("t", t)
		for k in ghosts.size():
			var g: Node3D = ghosts[k]
			g.position.z = starts[k].z + t * 38.0
			g.position.y = starts[k].y + 0.25 * sin(t * 2.2 + k)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png("%s/p_%03d.png" % [_out, f])
	quit()


func _body_mat(mats: Array[ShaderMaterial]) -> ShaderMaterial:
	var front := ShaderMaterial.new()
	front.shader = preload("res://shaders/ghost.gdshader")
	var back := ShaderMaterial.new()
	back.shader = preload("res://shaders/ghost_back.gdshader")
	for m: ShaderMaterial in [front, back]:
		m.set_shader_parameter("color", Color("f7f4ff"))
		m.set_shader_parameter("glow", 1.0)
		m.set_shader_parameter("alpha_center", _alpha.x)
		m.set_shader_parameter("alpha_edge", _alpha.y)
		m.set_shader_parameter("eyes", 0.0)
		m.set_shader_parameter("hem", 0)
		m.set_shader_parameter("scallops", 8.0)
		m.set_shader_parameter("wave_amp", 0.12)
		m.set_shader_parameter("trail", 0.0)
		mats.append(m)
	back.next_pass = front
	return back
