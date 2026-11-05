extends SceneTree
## Blok tasarımlarının görüntüleri: oyunun sahnesi ve ışığında, yakından ve oyun kamerasından,
## güneşte ve üstteki bir yolun gölgesinde (karanlıkta kalma durumu).
## Kullanım: godot --path . --resolution 720x720 --script res://tools/block_designs.gd -- --out=DIR [--styles=0,1,2]

var _out := "user://"
var _styles := [0, 1, 2, 3, 4, 5]
## --anim=N: N tasarımının yakın görünüşünden döngülü animasyon kareleri (GIF için)
var _anim := -1
## --frames=N: animasyon kare sayısı (30 kare/sn)
var _frames := 50


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a.begins_with("--anim="):
			_anim = int(a.trim_prefix("--anim="))
		elif a.begins_with("--frames="):
			_frames = int(a.trim_prefix("--frames="))
		elif a.begins_with("--styles="):
			_styles = Array(a.trim_prefix("--styles=").split(",")).map(func(v): return int(v))
	_shoot.call_deferred()


func _shoot() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	main.hud.visible = false
	var car: Node3D = main.car
	car.set_physics_process(false)
	car.visible = false
	var cam := main.get_node("Camera") as Camera3D
	cam.set_process(false)
	cam.set_physics_process(false)
	var roads: RoadGenerator = main.roads
	# Sahne: yolların çok üstünde (başka yol karışmasın) bir yol parçası ve üstünde blok
	var base := car.global_position + Vector3(0, 120, 0)
	var stage := Node3D.new()
	main.add_child(stage)
	stage.global_position = base
	var road_mat := StandardMaterial3D.new()
	road_mat.albedo_color = Palette.SKIES[0].road_top if _styles.max() >= 6 or _anim >= 6 else Palette.ASPHALT
	road_mat.roughness = 0.95
	roads._add_box(stage, Vector3(0, -0.2, -20), Vector3(9, 0.4, 80), road_mat)
	# Gölge yapan üst yol (kameranın görüş alanı dışında)
	var roof := roads._add_box(stage, Vector3(0, 14, -20), Vector3(400, 1, 400), road_mat)
	if _anim >= 0:
		await _animate(roads, stage, cam, base, roof)
		quit()
		return
	for st in _styles:
		roads.block_style = st
		var block := Node3D.new()
		stage.add_child(block)
		var size := Vector3(2.4, roads.block_height(), 1.2)
		block.position = Vector3(-1.6, size.y * 0.5, 0)
		roads._block_body(block, size)
		roads._block_lights(block, size)
		for shade in ([false] if st >= 6 else [false, true]):
			roof.visible = shade
			for view in [["yakin", Vector3(0.9, 1.25, 3.6) if st >= 12 else Vector3(1.5, 1.8, 5.5), Vector3(-1.6, 0.5, 0)],
					["oyun", Vector3(0, 6.0, 26.0), Vector3(-1.0, 0.0, -10.0)]]:
				cam.global_position = base + view[1]
				cam.look_at(base + view[2])
				for i in 6:
					await process_frame
				var img := root.get_texture().get_image()
				img.save_png("%s/blok_%d_%s_%s.png" % [_out, st, view[0], "golge" if shade else "gunes"])
		block.queue_free()
		await process_frame
	quit()


## Işık saatini elle ilerletip 30 kare/sn kareler: şeritlerin bir tam akışı (1/0.6 sn) döngü olur
func _animate(roads: RoadGenerator, stage: Node3D, cam: Camera3D, base: Vector3, roof: Node3D) -> void:
	roads.set_process(false)
	roads.block_style = _anim
	roof.visible = false
	var size := Vector3(2.4, roads.block_height(), 1.2)
	for x in [-1.6, 1.6]:
		var block := Node3D.new()
		stage.add_child(block)
		block.position = Vector3(x, size.y * 0.5, -3.0 if x > 0.0 else 0.0)
		roads._block_body(block, size)
		roads._block_lights(block, size)
	cam.global_position = base + Vector3(2.0, 1.9, 6.0)
	cam.look_at(base + Vector3(-0.3, 0.45, -1.5))
	var n := _frames
	for i in n:
		roads._light_time = float(i) / 30.0
		roads._process(0.0)
		for k in 3:
			await process_frame
		root.get_texture().get_image().save_png("%s/anim_%03d.png" % [_out, i])
