class_name RoadDebris
## Üst kattaki yolların kırılmış, harabeye dönmüş parçaları (uçuşta kayaların yerine): tohumla
## (seed) üretilir, her parça farklı. 4 boyut sınıfı: küçük, orta, büyük (tam genişlik), uzun
## (ortadan kırılıp bükülmüş). Grafik ve sade: düz bir yol dilimi her kırık kenarda 1-3 düz
## kesikle kırpılır (temiz, açılı yüzler). Yolun malzemeleri: koyu mor yüzey, pembe yan duvar
## (sağlam uzun kenarlar), oyundaki şerit çizgisi düzenlerinden biri; kırık yüzler koyu ve mat.
## Moloz ayrı ve bağımsız (build_rubble). Parça orijini kütle merkezine yakın (kendi ekseninde döner).

enum Size { SMALL, MEDIUM, LARGE, LONG }
## Yüzey biçimi: düz, rampa (oyundaki zıplama rampası üstünde), tümsek (ortası kabarık),
## eğimli (bir uçta düz, öbüründe yana yatık), yokuş (düz gidip kırılarak tırmanır)
enum Feature { NONE, RAMP, BUMP, BANK, CLIMB }
const FEATURE_NAMES := ["Düz", "Rampa", "Tümsek", "Eğimli", "Yokuş"]

const NAMES := ["Küçük", "Orta", "Büyük", "Uzun"]
## [uzunluk min-max, genişlik min-max, kalınlık min-max] (m)
const DIMS := [
	[Vector2(5.0, 7.5), Vector2(3.5, 5.0), Vector2(1.0, 1.4)],
	[Vector2(10.0, 14.0), Vector2(6.0, 8.5), Vector2(1.2, 1.8)],
	[Vector2(17.0, 24.0), Vector2(9.0, 11.0), Vector2(1.4, 2.2)],
	[Vector2(32.0, 44.0), Vector2(6.5, 9.0), Vector2(1.2, 1.8)],
]

static var _mats := {}


static func _mat(key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var sky: Dictionary = Palette.SKIES[0]
	var m := StandardMaterial3D.new()
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	match key:
		"top":
			m.albedo_color = sky.road_top
		"side":
			m.albedo_color = sky.road_side
		"broken":
			# Kırık iç: yan duvarın koyusu, mora çalar (beton içi gibi düz, mat)
			m.albedo_color = (sky.road_side as Color).lerp(sky.road_top, 0.72).darkened(0.3)
		"line":
			m.albedo_color = Palette.line_for(sky.road_top)
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[key] = m
	return m


## Parça üret: size sınıfı, seed tohumu, line_style: oyundaki şerit düzeni (RoadGenerator.LINE_STYLES;
## -1: tohumdan). Dönen düğüm: tek parça (uzunda bükülmüş iki yarı)
static func build(size: int, seed_value: int, line_style := -1, feature := Feature.NONE) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + size * 104729 + 1
	var d: Array = DIMS[size]
	var L := rng.randf_range(d[0].x, d[0].y)
	var W := rng.randf_range(d[1].x, d[1].y)
	var T := rng.randf_range(d[2].x, d[2].y)
	var style := line_style if line_style >= 0 else rng.randi() % RoadGenerator.LINE_STYLES.size()
	var root := Node3D.new()
	root.name = "Debris"
	if size == Size.LONG:
		# Uzun şerit: ortadan kırılıp hafifçe bükülmüş ve burulmuş iki yarı (kopmuş köprü gibi)
		var split := rng.randf_range(0.4, 0.6)
		var la := L * split
		var lb := L * (1.0 - split)
		var a := _slab(rng, la, W, T, size, style, 0.0)
		var b := _slab(rng, lb, W, T, size, style, la, feature)
		var bend := deg_to_rad(rng.randf_range(8.0, 18.0)) * (1.0 if rng.randf() < 0.5 else -1.0)
		var twist := deg_to_rad(rng.randf_range(-6.0, 6.0))
		a.position = Vector3(0, 0, -la * 0.5)
		b.basis = Basis(Vector3.RIGHT, bend) * Basis(Vector3.FORWARD, twist)
		b.position = b.basis * Vector3(0, 0, lb * 0.5) + Vector3(0, 0, 0.3)
		var c := (a.position * la + b.position * lb) / L
		a.position -= c
		b.position -= c
		root.add_child(a)
		root.add_child(b)
	else:
		root.add_child(_slab(rng, L, W, T, size, style, 0.0, feature))
	return root


## Bağımsız moloz: küçük, sade bir yol kırıntısı (üstü yol yüzeyi, yanları kırık). Parçalardan ayrı
## yüzer; arabaya zarar vermez (oyunda çarpınca savrulur)
static func build_rubble(seed_value: int) -> MeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 3571 + 17
	var L := rng.randf_range(0.6, 1.6)
	var W := rng.randf_range(0.5, 1.2)
	var T := rng.randf_range(0.3, 0.6)
	var mi := _slab(rng, L, W, T, -1, -1, 0.0)
	return mi


## Tek yol dilimi: dikdörtgen yol, kırık kenarlarda 1-3 düz kesikle kırpılır, kalınlıkta
## yükseltilir. style: şerit düzeni (-1 çizgisiz), z_off: çizgi kesiklerinin başlangıcı (uzunda süreklilik)
static func _slab(rng: RandomNumberGenerator, L: float, W: float, T: float, size: int, style: int, z_off: float, feature := Feature.NONE) -> MeshInstance3D:
	var hl := L * 0.5
	var hw := W * 0.5
	var poly := PackedVector2Array([Vector2(-hw, -hl), Vector2(hw, -hl), Vector2(hw, hl), Vector2(-hw, hl)])
	# Uçlar: her uç 1-3 düz kesikle (açılı kırık yüz); küçükte bir yan da kesilir
	for end: float in [-1.0, 1.0]:
		var cuts := 1 + rng.randi() % 3
		var depth := L * (0.17 if size == Size.SMALL else 0.11)
		for k in cuts:
			# Kesik çizgisi: uca yakın, açılı; ikinci-üçüncü kesik köşeden pah gibi
			# Açılı kesik: iki yanı farklı derinlikte (biri uçta, öbürü içeride)
			var deep_left := rng.randf() < 0.5
			var za := end * (hl - (rng.randf_range(depth, depth * 2.0) if deep_left else rng.randf_range(0.0, depth * 0.4)))
			var zb := end * (hl - (rng.randf_range(0.0, depth * 0.4) if deep_left else rng.randf_range(depth, depth * 2.0)))
			var xa := -hw
			var xb := hw
			if k > 0:
				# Köşe kesiği: bir uzun kenardan uca
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				xa = side * hw
				za = end * (hl - rng.randf_range(depth, depth * 3.0))
				xb = side * (hw - W * rng.randf_range(0.2, 0.45))
				zb = end * (hl + 0.1)
			poly = _cut(poly, Vector2(xa, za), Vector2(xb, zb), Vector2(0, end))
	if size == Size.SMALL:
		# Küçük parça: bir yandan da kopmuş (1-2 düz kesik)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		for k in 1 + rng.randi() % 2:
			var a := Vector2(side * (hw - W * rng.randf_range(0.05, 0.3)), -hl - 0.1 + L * rng.randf_range(0.0, 0.4) * k)
			var b := Vector2(side * (hw - W * rng.randf_range(0.05, 0.3)), hl + 0.1)
			poly = _cut(poly, a, b, Vector2(side, 0))
	elif size == Size.MEDIUM and rng.randf() < 0.5:
		# Orta: bir yandan kopmuş büyük, düz bir köşe
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var z0 := rng.randf_range(-hl, hl * 0.2)
		poly = _cut(poly, Vector2(side * hw, z0), Vector2(side * (hw - W * rng.randf_range(0.25, 0.45)), z0 + L * rng.randf_range(0.3, 0.6)), Vector2(side, 0))
	# Yüzey biçimi: parçanın her noktası (x, z) bu kadar yukarı kayar (kalınlık sabit; bükülmüş yol)
	var off := _feature_offset(rng, feature, L, W)
	var mesh := ArrayMesh.new()
	var top_y := T * 0.5
	var bot_y := -T * 0.5
	# Üst ve alt yüz: biçim düzgün kıvrılsın diye boyuna ince şeritlere bölünür
	var top_st := SurfaceTool.new()
	top_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bot_st := SurfaceTool.new()
	bot_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for piece: PackedVector2Array in _strips(poly, hl):
		var tri := Geometry2D.triangulate_polygon(piece)
		for k in range(0, tri.size(), 3):
			var q := [piece[tri[k]], piece[tri[k + 1]], piece[tri[k + 2]]]
			_tri(top_st, q, top_y, off, 1.0)
			_tri(bot_st, q, bot_y, off, -1.0)
	top_st.set_material(_mat("top"))
	top_st.commit(mesh)
	bot_st.set_material(_mat("broken"))
	bot_st.commit(mesh)
	# Yan yüzler: dikdörtgenin uzun kenarında kalan (sağlam) kenar pembe yan duvar, kesikler koyu;
	# kenarlar biçimi izlesin diye kısa parçalara bölünür
	var side_st := SurfaceTool.new()
	side_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var broken_st := SurfaceTool.new()
	broken_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := poly.size()
	# Çokgen saat yönünün tersindeyse (alan > 0) dış normal kenarın orthogonal()'ı
	var ccw := _area(poly) > 0.0
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var intact := absf(absf(a.x) - hw) < 0.01 and absf(absf(b.x) - hw) < 0.01 and signf(a.x) == signf(b.x)
		var tgt := side_st if intact else broken_st
		var out2 := (b - a).orthogonal().normalized() * (1.0 if ccw else -1.0)
		var parts := maxi(1, ceili(a.distance_to(b) / 0.5))
		for j in parts:
			var p0 := a.lerp(b, float(j) / parts)
			var p1 := a.lerp(b, float(j + 1) / parts)
			var y0: float = off.call(p0.x, p0.y)
			var y1: float = off.call(p1.x, p1.y)
			var v0 := Vector3(p0.x, top_y + y0, p0.y)
			var v1 := Vector3(p1.x, top_y + y1, p1.y)
			var v2 := Vector3(p1.x, bot_y + y1, p1.y)
			var v3 := Vector3(p0.x, bot_y + y0, p0.y)
			for v in [v0, v2, v1, v0, v3, v2]:
				tgt.set_normal(Vector3(out2.x, 0.0, out2.y))
				tgt.add_vertex(v)
	for pair in [[side_st, "side"], [broken_st, "broken"]]:
		var st2: SurfaceTool = pair[0]
		st2.set_material(_mat(pair[1]))
		st2.commit(mesh)
	if style >= 0:
		_lines(mesh, poly, W, hl, top_y, style, z_off, off)
	if feature == Feature.RAMP:
		_ramp(mesh, rng, poly, L, W, top_y)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi


## Oyundaki şerit düzeni (RoadGenerator.LINE_STYLES[style]): kenardan uzaklık, genişlik, kesik
## boyu ve payı aynı; parça sınırında kırpılır
static func _lines(mesh: ArrayMesh, poly: PackedVector2Array, W: float, hl: float, y: float, style: int, z_off: float, off: Callable) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for ln: Dictionary in RoadGenerator.LINE_STYLES[style].lines:
		var xs: Array = [0.0] if str(ln.x) == "c" else [-(W * 0.5 - float(ln.x)), W * 0.5 - float(ln.x)]
		var w: float = ln.w
		var p: float = ln.p
		var dd: float = ln.d
		var o: float = ln.get("o", 0.0)
		for cx: float in xs:
			var rects: Array = []
			if dd >= 1.0:
				rects.append(_rect(cx - w * 0.5, -hl - 1.0, cx + w * 0.5, hl + 1.0))
			else:
				var z := -hl - fposmod(z_off - o * p, p)
				while z < hl:
					rects.append(_rect(cx - w * 0.5, z, cx + w * 0.5, z + p * dd))
					z += p
			for r: PackedVector2Array in rects:
				for clipped: PackedVector2Array in Geometry2D.intersect_polygons(r, poly):
					for piece: PackedVector2Array in _strips(clipped, hl):
						var t2 := Geometry2D.triangulate_polygon(piece)
						for k in range(0, t2.size(), 3):
							_tri(st, [piece[t2[k]], piece[t2[k + 1]], piece[t2[k + 2]]], y + 0.02, off, 1.0)
							any = true
	if any:
		st.set_material(_mat("line"))
		st.commit(mesh)


## Yüzey biçiminin kaydırması: (x, z) -> yukarı (m)
static func _feature_offset(rng: RandomNumberGenerator, feature: int, L: float, W: float) -> Callable:
	match feature:
		Feature.BUMP:
			# Ortada yumuşak kabarık: yolun yarısı boyunca yükselip iner
			var zc := rng.randf_range(-0.12, 0.12) * L
			var lb := maxf(L * 0.55, 6.0)
			var h := rng.randf_range(1.1, 1.6)
			return func(_x: float, z: float) -> float:
				var u := (z - zc) / lb + 0.5
				return 0.0 if u <= 0.0 or u >= 1.0 else h * (0.5 - 0.5 * cos(TAU * u))
		Feature.CLIMB:
			# Düz gider, yumuşak bir dirsekle kırılıp tırmanır (yokuş başlangıcı)
			var zk := rng.randf_range(-0.12, 0.05) * L
			var slope := tan(deg_to_rad(rng.randf_range(16.0, 22.0)))
			var r := 1.6
			return func(_x: float, z: float) -> float:
				var t := z - zk
				if t <= -r:
					return 0.0
				if t >= r:
					return slope * t
				return slope * (t + r) * (t + r) / (4.0 * r)
		Feature.BANK:
			# Bir uçta düz, öbür uçta yana yatık (yatık yola geçiş)
			var ang := deg_to_rad(rng.randf_range(13.0, 19.0)) * (1.0 if rng.randf() < 0.5 else -1.0)
			var t2 := tan(ang)
			return func(x: float, z: float) -> float:
				return x * t2 * smoothstep(-0.35 * L, 0.35 * L, z)
	return func(_x: float, _z: float) -> float:
		return 0.0


## Çokgeni boyuna (z) ince şeritlere böl: biçim kıvrımı şerit sınırlarında izlenir
static func _strips(poly: PackedVector2Array, hl: float, dz := 0.5) -> Array:
	var out: Array = []
	var z := -hl - 1.0
	while z < hl + 1.0:
		for piece: PackedVector2Array in Geometry2D.intersect_polygons(_rect(-500.0, z, 500.0, z + dz), poly):
			out.append(piece)
		z += dz
	return out


## Üçgen ekle: y + biçim kaydırması; normal üçgenden hesaplanır, up yönüne (üst +1, alt -1) çevrilir
static func _tri(st: SurfaceTool, q: Array, y: float, off: Callable, up: float) -> void:
	var v: Array[Vector3] = []
	for p: Vector2 in q:
		v.append(Vector3(p.x, y + float(off.call(p.x, p.y)), p.y))
	var nrm := (v[1] - v[0]).cross(v[2] - v[0]).normalized()
	if nrm.y * up < 0.0:
		nrm = -nrm
		v = [v[0], v[2], v[1]]
	for vv in v:
		st.set_normal(nrm)
		st.add_vertex(vv)


## Oyundaki zıplama rampası (ramp_style 9) parçanın üstünde: yüzey şerit renginde (ışıksız), yol
## renginde ileri bakan üç sivri ok ve iki yanda kenar çizgisi; yan duvarlar yol duvarı renginde
static func _ramp(mesh: ArrayMesh, rng: RandomNumberGenerator, poly: PackedVector2Array, L: float, W: float, top_y: float) -> void:
	var rw := W * rng.randf_range(0.55, 0.7)
	var rl := minf(L * 0.38, 8.0)
	var rise := rng.randf_range(1.5, 1.9)
	var z0 := -rl * 0.5 + rng.randf_range(-0.1, 0.1) * L
	var hw := rw * 0.5
	# Rampa parçanın içinde kalmalı (kırık köşelerden taşmasın)
	for c in [Vector2(-hw, z0), Vector2(hw, z0), Vector2(hw, z0 + rl), Vector2(-hw, z0 + rl)]:
		if not Geometry2D.is_point_in_polygon(c, poly):
			hw *= 0.7
			break
	var y := top_y + 0.01
	var at := func(x: float, f: float, lift := 0.0) -> Vector3:
		return Vector3(x, y + rise * f + lift, z0 + rl * f)
	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall := SurfaceTool.new()
	wall.begin(Mesh.PRIMITIVE_TRIANGLES)
	var deco := SurfaceTool.new()
	deco.begin(Mesh.PRIMITIVE_TRIANGLES)
	var slope_n := Vector3(0, rl, -rise).normalized()
	_quad3(top, at.call(-hw, 0.0), at.call(hw, 0.0), at.call(hw, 1.0), at.call(-hw, 1.0), slope_n)
	for sx: float in [-1.0, 1.0]:
		var a0: Vector3 = at.call(sx * hw, 0.0)
		var a1: Vector3 = at.call(sx * hw, 1.0)
		var b1 := Vector3(sx * hw, y, z0 + rl)
		for v in [a0, a1, b1]:
			wall.set_normal(Vector3(sx, 0, 0))
			wall.add_vertex(v)
	_quad3(wall, at.call(-hw, 1.0), at.call(hw, 1.0), Vector3(hw, y, z0 + rl), Vector3(-hw, y, z0 + rl), Vector3(0, 0, 1))
	# Oklar: rampa boyunca ileri (yükselen uca) bakan üç sivri ^
	var arm := minf(rw * 0.32, 1.6)
	var thick := 0.26
	var dir := Vector2(0.0, 1.0)
	for k in 3:
		var fc := (k + 0.7) / 3.4
		var p0 := Vector2(0.0, fc * rl)
		var notch := dir * (thick * 2.0 / sin(deg_to_rad(50.0)))
		for sgn: float in [-1.0, 1.0]:
			var back := dir.rotated(sgn * deg_to_rad(130.0))
			var p1 := p0 + back * arm
			var q := [p0, p1, p1 - notch, p0 - notch]
			var pts: Array[Vector3] = []
			for v2: Vector2 in q:
				pts.append(at.call(v2.x, clampf(v2.y / rl, 0.0, 1.0), 0.03))
			_quad3(deco, pts[0], pts[1], pts[2], pts[3], slope_n)
	# Kenar çizgileri (okların renginde)
	for sx: float in [-1.0, 1.0]:
		var xo := sx * (hw - 0.3)
		_quad3(deco, at.call(xo - 0.07, 0.0, 0.03), at.call(xo + 0.07, 0.0, 0.03), at.call(xo + 0.07, 1.0, 0.03), at.call(xo - 0.07, 1.0, 0.03), slope_n)
	var sky: Dictionary = Palette.SKIES[0]
	var top_m := StandardMaterial3D.new()
	top_m.albedo_color = Palette.line_for(sky.road_top)
	top_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	top_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var deco_m := StandardMaterial3D.new()
	deco_m.albedo_color = sky.road_top
	deco_m.roughness = 0.95
	deco_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	for pair in [[top, top_m], [wall, _mat("side")], [deco, deco_m]]:
		var st3: SurfaceTool = pair[0]
		st3.set_material(pair[1])
		st3.commit(mesh)


static func _quad3(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3) -> void:
	for v in [a, b, c, a, c, d]:
		st.set_normal(nrm)
		st.add_vertex(v)


## Çokgeni a-b çizgisinden kes: away yönündeki taraf atılır (düz kırık yüz)
static func _cut(poly: PackedVector2Array, a: Vector2, b: Vector2, away: Vector2) -> PackedVector2Array:
	var dir := (b - a).normalized()
	var nrm := dir.orthogonal()
	if nrm.dot(away) < 0.0:
		nrm = -nrm
	var big := 200.0
	var cutter := PackedVector2Array([a - dir * big, b + dir * big, b + dir * big + nrm * big, a - dir * big + nrm * big])
	var res := Geometry2D.clip_polygons(poly, cutter)
	if res.is_empty():
		return poly
	var best: PackedVector2Array = res[0]
	for r: PackedVector2Array in res:
		if absf(_area(r)) > absf(_area(best)):
			best = r
	# Çok küçülttüyse kesme (parça anlamsızlaşmasın)
	if absf(_area(best)) < absf(_area(poly)) * 0.45:
		return poly
	return best


static func _area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		s += p[i].cross(p[(i + 1) % p.size()])
	return s * 0.5


static func _rect(x0: float, z0: float, x1: float, z1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])


## Çokgen yüzü (üst / alt) ayrı bir yüzey olarak
static func _surface_from(mesh: ArrayMesh, poly: PackedVector2Array, tri: PackedInt32Array, y: float, normal: Vector3, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(0, tri.size(), 3):
		var idx := [tri[k], tri[k + 2], tri[k + 1]] if normal.y > 0.0 else [tri[k], tri[k + 1], tri[k + 2]]
		for q in idx:
			st.set_normal(normal)
			st.add_vertex(Vector3(poly[q].x, y, poly[q].y))
	st.set_material(mat)
	st.commit(mesh)
