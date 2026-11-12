class_name LayeredBackdrop
extends CanvasLayer
## Düz dünya denemesi (FlatStyle "layered_bg"): 3D dünyanın arkasına çizilen 2D katmanlı arka plan.
## Sıra (arkadan öne): 1 gökyüzü, 2 gezegen(ler), 3 en arka dağ sırası, 4 orta sıra, 5 ön sıra ve
## aşağısının rengi. Ortam arka planı "canvas" olur (game.gd): 3D yollar, araba ve parçalar bunun
## önüne çizilir.
##
## Paralaks: her katmanın iki hedef yeri var (yol yüksekliği ve uçuş yüksekliği; ekran yüksekliğinin
## payı olarak, kameranın gerçek ufuk çizgisine göre). Arabanın yüksekliği ikisi arasında nerede ise
## katman o oranda kayar. Aşağı inerken arkadaki sıralar (ve gökyüzü, gezegen) çok yükselmeden orta
## sıranın rengine solar: uçuşta geride onun rengi kalır, önünde yalnız ön sıranın sırtı görünür.
## Kayma ve solma aynı ilerlemeye bağlı: dağlar uçuştaki yerine oturduğu anda solma da biter.
## Yana: araba sağa sola gittikçe katmanlar derinliklerine göre kayar.
##
## Sırt biçimi (shape): "tri" eşit yamaçlı üçgen dağlar; "slant" her ekranda tek eğik çizgi; "kink" birkaç
## kırık çizgi; "peak" geniş, alçak tepeler; "flat" düz yatay bantlar.

## Dağ yamaçlarının eğimi (derece; tepe sivri, yamaçlar eşit)
const SLOPE_DEG := 48.0
## [taban genişliği aralığı (ekran yüksekliğinin payı), yol yüksekliğinde taban yeri, uçuşta taban yeri,
##  yana kayma (piksel / metre), yolda yüksekliğe tepki (ekran payı / metre), tohum];
## tabanlar ufka göre (eksi: ufkun üstü)
const RIDGES := [
	[Vector2(0.12, 0.19), -0.15, -0.25, 0.15, 0.0006, 3],
	[Vector2(0.15, 0.24), -0.08, -0.16, 0.3, 0.001, 7],
	[Vector2(0.20, 0.31), -0.01, -0.07, 0.55, 0.0015, 11],
]
## Bant biçimlerinde (tri dışı) sıraların yeri: [yol yüksekliğinde, uçuşta] (ufka göre, ekran payı)
const BANDS := [Vector2(-0.19, -0.25), Vector2(-0.085, -0.135), Vector2(0.0, -0.06)]
## Bant biçimlerinin kırık noktaları: [aralık (ekran genişliğinin payı), yükseklik oynaması (ekran yüksekliği payı)]
const SHAPES := {"slant": [Vector2(1.0, 1.0), 0.03], "kink": [Vector2(0.5, 0.8), 0.03],
	"peak": [Vector2(0.4, 0.8), 0.05], "flat": [Vector2(1.0, 1.0), 0.0]}
## İnişte geçişin başladığı yer: arabanın son durduğu yolun bu kadar altı (yoldan kopunca hemen başlar)
const DROP_START := 2.0
## Yollarda yüksekliğe hafif tepki bu aralıkta (m)
const ROAD_RANGE := Vector2(-22.0, 15.0)
## Gezegen: yarıçap (ekran yüksekliğinin payı), yatay yer (ekran genişliğinin payı), yol ve uçuşta
## merkezin yeri (ufka göre), yana kayma
const PLANET := {"r": 0.067, "x": 0.28, "y0": -0.27, "y1": -0.37, "slide": 0.08, "road": 0.0004}
## Desenin yatay tekrar boyu (ekran genişliğinin katı)
const PERIOD_K := 2.0

var car: Car
var shape := "tri"
var _sky: ColorRect
var _planet: Polygon2D
## Her sıra: [kopyalar (Polygon2D x3), desen boyu (px)]
var _ridges: Array = []
## Orta sıranın renginde perde (ön sıranın hemen arkasında): inerken belirir, arkadakileri örter
var _fade: ColorRect
var _size := Vector2.ZERO
## Devler (GiantLayer): kendi kameralarıyla çizilir, ön sıranın önünde gösterilir
var _giants: GiantLayer
var _giants_rect: TextureRect
## Yumuşatılmış ufuk ve yol yüksekliği: zıplama, iniş sarsıntısı ve kamera oynamaları dağları oynatmasın
var _horizon := NAN
var _road_y := NAN
## Yumuşatma süresi (sn): kalıcı değişimleri (uçuşta kamera açısı, yeni yol yüksekliği) yavaşça izler
const SMOOTH := 0.8


func setup(p_car: Car, colors: Array, p_shape := "tri") -> void:
	car = p_car
	shape = p_shape
	layer = -10
	_sky = ColorRect.new()
	_sky.color = colors[0]
	_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sky)
	_planet = Polygon2D.new()
	_planet.color = colors[1]
	_planet.antialiased = true
	# Bant biçimlerinde gökyüzü dar bir şerit: gezegen yok
	_planet.visible = shape == "tri"
	add_child(_planet)
	for i in RIDGES.size():
		if i == RIDGES.size() - 1:
			_fade = ColorRect.new()
			_fade.color = colors[3]
			_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_fade)
		var copies: Array[Polygon2D] = []
		for k in 3:
			var p := Polygon2D.new()
			p.color = colors[2 + i]
			p.antialiased = true
			add_child(p)
			copies.append(p)
		_ridges.append([copies, 0.0])


## Devleri ekle (kendi dünyaları ve kameraları; oyun kamerasından bağımsız)
func add_giants(color: Color, sun: DirectionalLight3D, env: Environment, seed_value := -1) -> void:
	_giants = GiantLayer.new()
	add_child(_giants)
	_giants.setup(color, sun, env, seed_value)
	_giants_rect = TextureRect.new()
	_giants_rect.texture = _giants.get_texture()
	_giants_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_giants_rect.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_giants_rect)


## Ekran boyu değişince dağ sırtları ve gezegen yeniden kurulur (boyutlar ekran yüksekliğine göre)
func _rebuild(size: Vector2) -> void:
	_size = size
	_sky.size = size
	_fade.size = size
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
		rng.seed = spec[5]
		if shape != "tri":
			var band := _band_line(rng, size, period)
			for c: Polygon2D in _ridges[i][0]:
				c.polygon = band
			_ridges[i][1] = period
			continue
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


## Bant biçimi: desen boyunca birkaç kırık noktalı çizgi (sonu başına bağlanır), altı dolu
func _band_line(rng: RandomNumberGenerator, size: Vector2, period: float) -> PackedVector2Array:
	var sp: Array = SHAPES.get(shape, SHAPES.flat)
	var gap: Vector2 = sp[0]
	var amp: float = sp[1] * size.y
	var line := PackedVector2Array()
	var first := rng.randf_range(-amp, amp)
	var x := 0.0
	var up := rng.randf() < 0.5
	while x < period - 1.0:
		var v := rng.randf_range(-amp, amp)
		if shape == "peak":
			# Geniş tepeler: sırayla yüksek ve alçak noktalar
			v = rng.randf_range(0.3, 1.0) * amp * (-1.0 if up else 0.4)
			up = not up
		line.append(Vector2(x, first if x == 0.0 else v))
		x += rng.randf_range(gap.x, gap.y) * size.x
		if period - x < gap.x * size.x * 0.5:
			x = period
	line.append(Vector2(period, first))
	line.append(Vector2(period, size.y * 3.0))
	line.append(Vector2(0.0, size.y * 3.0))
	return line


func _process(_delta: float) -> void:
	var size := get_viewport().get_visible_rect().size
	if size != _size:
		_rebuild(size)
	var cam := get_viewport().get_camera_3d()
	if cam == null or car == null:
		return
	# Kameranın ufuk çizgisi (göz hizasında çok uzak bir nokta)
	var far := cam.global_position + Vector3(0.0, 0.0, -100000.0)
	var raw_h := cam.unproject_position(far).y if not cam.is_position_behind(far) else size.y * 0.5
	var ks := 1.0 - exp(-get_process_delta_time() / SMOOTH)
	_horizon = raw_h if is_nan(_horizon) else lerpf(_horizon, raw_h, ks)
	var horizon := _horizon
	# Yol (0) ile uçuş yüksekliği (1) arasında; yumuşak geçiş
	# Yollardan aşağı düşüş (0) ile uçuş yüksekliği (1) arası: büyük kayma yalnız burada, yumuşak.
	# Yollarda (iniş-çıkış, rampa) yalnız hafif bir tepki
	# İlerleme: yoldan kopunca (son yolun DROP_START altı) başlar, uçuş yüksekliğinin tırmanma payı
	# üstünde biter (uçarken iki parmakla yükselince arka plan yerinden oynamaz). Kayma yumuşak,
	# solma daha erken başlar; ikisi aynı anda tamamlanır
	var cy := car.global_position.y
	var t := clampf(inverse_lerp(car.last_floor_y - DROP_START, car.flight_altitude + car.climb_height, cy), 0.0, 1.0)
	var e := smoothstep(0.0, 1.0, t)
	# Yollarda hafif tepki arabanın değil üzerinde durduğu yolun yüksekliğine (zıplamada oynamaz)
	var road := clampf(car.last_floor_y, ROAD_RANGE.x, ROAD_RANGE.y)
	_road_y = road if is_nan(_road_y) else lerpf(_road_y, road, ks)
	var ry := _road_y * size.y
	_fade.modulate.a = 1.0 - (1.0 - t) * (1.0 - t)
	_fade.visible = _fade.modulate.a > 0.001
	if _giants:
		# Devlerin görüntüsünün ufku (ortası) arka planın yumuşatılmış ufkunda; hızla açılmayan görüş açısı
		var bf: float = cam.get("base_fov") if cam.get("base_fov") else cam.fov
		_giants.sync(Vector2i(size), bf if bf > 1.0 else cam.fov)
		_giants_rect.size = size
		_giants_rect.position = Vector2(0.0, horizon - size.y * 0.5)
		_giants_rect.modulate.a = 1.0 - _fade.modulate.a
	var cx := car.global_position.x
	_planet.position = Vector2(PLANET.x * size.x - cx * PLANET.slide,
		horizon + lerpf(PLANET.y0, PLANET.y1, e) * size.y + ry * PLANET.road)
	for i in RIDGES.size():
		var spec: Array = RIDGES[i]
		var period: float = _ridges[i][1]
		var b0: float = spec[1] if shape == "tri" else BANDS[i].x
		var b1: float = spec[2] if shape == "tri" else BANDS[i].y
		var y := horizon + lerpf(b0, b1, e) * size.y + ry * float(spec[4])
		var ox := fposmod(-cx * float(spec[3]), period)
		var copies: Array = _ridges[i][0]
		for k in 3:
			(copies[k] as Polygon2D).position = Vector2(ox + (k - 1) * period, y)
