extends SceneTree
## Test: arabanın rampaya yarım girmesi. Başlangıç pistine bir rampa konur, araba
## rampanın ortasına göre farklı kaydırmalarla direksiyonsuz rampaya sürülür.
## Kullanım: godot --headless --path . --fixed-fps 60 --script res://tools/ramp_test.gd

const OFFSETS := [0.0, 0.4, 0.8, 1.2, 1.6, 2.0, 2.4, 2.8, -1.2, -2.0, -2.4]
var _result := ""


## Oyuncu taklidi: yolda direksiyon yok; havada yatmaya karşı direksiyon kırar
class Corrector extends Autopilot:
	func input() -> Vector2:
		if car.is_on_floor() or absf(car.roll) < 0.15:
			return Vector2.ZERO
		return Vector2(signf(car.roll), 0.0)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for fix in [false, true]:
		print("--- havada düzeltme: %s" % ("var" if fix else "yok"))
		for off in OFFSETS:
			for kick in [0.0, 6.0]:
				await _one(off, kick, fix)
	quit()


func _one(off: float, kick: float, fix: bool) -> void:
	if true:
		if true:
			_result = "sağ"
			var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
			root.add_child(main)
			for i in 3:
				await physics_frame
			var car: Car = main.car
			var roads: RoadGenerator = main.roads
			car.died.connect(func(reason: String): _result = "PATLADI: " + reason)
			var ramp_x := 0.0
			var z0 := car.global_position.z - 45.0
			# Rampanın yüksekliği üstüne kurulduğu yoldan alınır: z0'daki yolu bul
			var host: RoadGenerator.Segment = null
			for s in roads.segments:
				if not s.ramp and s.contains(Vector3(ramp_x, car.global_position.y, z0)):
					host = s
					break
			var ramp := roads._add_ramp(host, ramp_x, 3.0, z0, 8.0, 1.6, 7.0 if kick != 0.0 else 0.0, kick)
			car.global_position.x = ramp.x + off
			if fix:
				var c := Corrector.new(car, roads, main.lower)
				car.autopilot = c
			var max_roll := 0.0
			var on_ramp := false
			var max_y := -INF
			var start_z := car.global_position.z
			for f in 300:
				await physics_frame
				max_roll = maxf(max_roll, absf(car.roll))
				max_y = maxf(max_y, car.global_position.y)
				if car.global_position.z < z0 and car.global_position.z > z0 - 8.0:
					on_ramp = true
				if _result != "sağ":
					break
			print("kaydırma %+.1f m  kick %.0f  ->  %s  (en çok yatma %.0f°, en yüksek %.1f m, gidilen %.0f m, rampa %.0f m ötede, x=%.1f, mod=%d)" % [
				off, kick, _result, rad_to_deg(max_roll), max_y, start_z - car.global_position.z, start_z - z0, car.global_position.x, car.mode])
			main.queue_free()
			await process_frame
