extends SceneTree
## Her araba modelinde arka lamba izinin çıkış noktası (gövdenin arka yüzü) — kontrol için


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	var car: Car = main.car
	for v in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]:
		car.model.variant = v
		for i in 3:
			await process_frame
		print("MODEL %d  rear_z(±0.55, 0.55) = %.2f / %.2f   half_length %.2f" % [v, car.rear_z(-0.55, 0.55), car.rear_z(0.55, 0.55), car.half_length])
	quit()
