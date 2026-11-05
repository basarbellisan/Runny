extends SceneTree
## Çakıl tasarımlarının yakın plan animasyonu (oyunun sahnesi ve ışığında).
## Kullanım: godot --path . --resolution 1920x1080 --script res://tools/gravel_designs.gd -- --out=DIR --style=2 [--frames=90]

var _out := "user://"
var _style := 2
var _frames := 90
var _layout := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a.begins_with("--style="):
			_style = int(a.trim_prefix("--style="))
		elif a.begins_with("--layout="):
			_layout = int(a.trim_prefix("--layout="))
		elif a.begins_with("--frames="):
			_frames = int(a.trim_prefix("--frames="))
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
	roads.set_process(false)
	roads.gravel_style = _style
	roads.gravel_layout = _layout
	var base := car.global_position + Vector3(0, 120, 0)
	var stage := Node3D.new()
	main.add_child(stage)
	stage.global_position = base
	var road_mat := StandardMaterial3D.new()
	road_mat.albedo_color = Palette.SKIES[0].road_top
	road_mat.roughness = 0.95
	roads._add_box(stage, Vector3(0, -0.2, -20), Vector3(10, 0.4, 80), road_mat)
	if _style == 3:
		roads._gravel_zigzag(stage, Vector3(0, 0, -8.0), 10.0, 16.0)
	else:
		roads._gravel_holes(stage, Vector3(0, 0, -8.0), 10.0, 16.0)
	cam.global_position = base + Vector3(0.0, 2.6, 6.5)
	cam.look_at(base + Vector3(0, 0.3, -6.0))
	for i in _frames:
		roads._light_time = float(i) / 30.0
		roads._process(0.0)
		for k in 3:
			await process_frame
		root.get_texture().get_image().save_png("%s/anim_%03d.png" % [_out, i])
	quit()
