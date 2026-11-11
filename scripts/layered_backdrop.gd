class_name LayeredBackdrop
extends CanvasLayer
## Düz dünya denemesi (FlatStyle "layered_bg"): 3D dünyanın arkasına çizilen 2D katmanlı arka plan.
## Sıra (arkadan öne): 1 gökyüzü, 2 gezegen(ler), 3 en arka dağ sırası, 4 orta sıra, 5 ön sıra ve
## aşağısının rengi. Ortam arka planı "canvas" olur (game.gd): 3D yollar, araba ve parçalar bunun
## önüne çizilir.
##
## Paralaks: her katmanın iki hedef yeri var (yol yüksekliği ve uçuş yüksekliği; ekran yüksekliğinin
## payı olarak, kameranın gerçek ufuk çizgisine göre). Arabanın yüksekliği ikisi arasında nerede ise
## katman o oranda kayar. Uçuşta orta sıra ekranın üstünden taşar: geride onun rengi kalır, önünde
## yalnız ön sıranın sırtı görünür. Yana: araba sağa sola gittikçe katmanlar derinliklerine göre kayar.

## Dağ yamaçlarının eğimi (derece; tepe sivri, yamaçlar eşit)
const SLOPE_DEG := 48.0
## [taban genişliği aralığı (ekran yüksekliğinin payı), yol yüksekliğinde taban yeri, uçuşta taban yeri,
##  yana kayma (piksel / metre), tohum]; tabanlar ufka göre (eksi: ufkun üstü)
const RIDGES := [
	[Vector2(0.12, 0.19), -0.15, -0.75, 0.6, 3],
	[Vector2(0.15, 0.24), -0.08, -0.80, 1.2, 7],
	[Vector2(0.20, 0.31), -0.01, -0.07, 2.2, 11],
]
## Gezegen: yarıçap (ekran yüksekliğinin payı), yatay yer (ekran genişliğinin payı), yol ve uçuşta
## merkezin yeri (ufka göre), yana kayma
const PLANET := {"r": 0.067, "x": 0.28, "y0": -0.27, "y1": -0.85, "slide": 0.3}
## Desenin yatay tekrar boyu (ekran genişliğinin katı)
const PERIOD_K := 2.0

var car: Car
var _sky: ColorRect
var _planet: Polygon2D
## Her sıra: [kopyalar (Polygon2D x3), desen boyu (px)]
var _ridges: Array = []
var _size := Vector2.ZERO


func setup(p_car: Car, colors: Array) -> void:
	car = p_car
	layer = -10
	_sky = ColorRect.new()
	_sky.color = colors[0]
	_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sky)
	_planet = Polygon2D.new()
	_planet.color = colors[1]
	_planet.antialiased = true
	add_child(_planet)
	for i in RIDGES.size():
		var copies: Array[Polygon2D] = []
		for k in 3:
			var p := Polygon2D.new()
			p.color = colors[2 + i]
			p.antialiased = true
			add_child(p)
			copies.append(p)
		_ridges.append([copies, 0.0])


## Ekran boyu değişince dağ sırtları ve gezegen yeniden kurulur (boyutlar ekran yüksekliğine göre)
func _rebuild(size: Vector2) -> void:
	_size = size
	_sky.size = size
	var r: float = PLANET.r * size.y
	var pts := PackedVector2Array()
	for k in 72:
		var a := TAU * k / 72.0
		pts.append(Vector2(cos(a), sin(a)) * r)
	_planet.polygon = pts
	var period := ceilf(size.x * PERIOD_K)
	var k_slope := tan(deg_to_rad(SLOPE_DEG))
	for i in RIDGES.size():
		var spec: Array = RIDGES[i]
		var rng := RandomNumberGenerator.new()
		rng.seed = spec[4]
		# Tepeler: [merkez x, yarı taban]; desen dikişsiz tekrar etsin diye her tepe bir boy sağda ve solda da sayılır
		var peaks: Array[Vector2] = []
		var x := 0.0
		while x < period:
			var b := rng.randf_range(spec[0].x, spec[0].y) * size.y
			peaks.append(Vector2(x + b * 0.5, b * 0.5))
			x += b * rng.randf_range(0.45, 0.8)
		var all: Array[Vector2] = []
		for p in peaks:
			for s in [-period, 0.0, period]:
				all.append(Vector2(p.x + s, p.y))
		# Sırt: tepelerin üst zarfı (her x'te en yüksek üçgen); tepe ve tabanlar kesin noktalar
		var xs: Array[float] = []
		for p in all:
			for v in [p.x - p.y, p.x, p.x + p.y]:
				if v >= 0.0 and v <= period:
					xs.append(v)
		var step := 2.0
		var sx := 0.0
		while sx <= period:
			xs.append(sx)
			sx += step
		xs.sort()
		var line := PackedVector2Array()
		var last := -1.0
		for xx in xs:
			if xx - last < 0.25:
				continue
			last = xx
			var h := 0.0
			for p in all:
				h = maxf(h, (p.y - absf(xx - p.x)) * k_slope)
			line.append(Vector2(xx, -h))
		# Altı ekranın dibine kadar dolu
		line.append(Vector2(period, size.y * 3.0))
		line.append(Vector2(0.0, size.y * 3.0))
		for c: Polygon2D in _ridges[i][0]:
			c.polygon = line
		_ridges[i][1] = period


func _process(_delta: float) -> void:
	var size := get_viewport().get_visible_rect().size
	if size != _size:
		_rebuild(size)
	var cam := get_viewport().get_camera_3d()
	if cam == null or car == null:
		return
	# Kameranın ufuk çizgisi (göz hizasında çok uzak bir nokta)
	var far := cam.global_position + Vector3(0.0, 0.0, -100000.0)
	var horizon := cam.unproject_position(far).y if not cam.is_position_behind(far) else size.y * 0.5
	# Yol (0) ile uçuş yüksekliği (1) arasında; yumuşak geçiş
	var t := clampf(inverse_lerp(RoadGenerator.MAIN_LEVEL, car.flight_altitude, car.global_position.y), -0.4, 1.1)
	var e := smoothstep(0.0, 1.0, clampf(t, 0.0, 1.0)) + minf(t, 0.0) + maxf(t - 1.0, 0.0)
	var cx := car.global_position.x
	_planet.position = Vector2(PLANET.x * size.x - cx * PLANET.slide,
		horizon + lerpf(PLANET.y0, PLANET.y1, e) * size.y)
	for i in RIDGES.size():
		var spec: Array = RIDGES[i]
		var period: float = _ridges[i][1]
		var y := horizon + lerpf(spec[1], spec[2], e) * size.y
		var ox := fposmod(-cx * float(spec[3]), period)
		var copies: Array = _ridges[i][0]
		for k in 3:
			(copies[k] as Polygon2D).position = Vector2(ox + (k - 1) * period, y)
