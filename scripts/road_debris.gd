class_name RoadDebris
## Üst kattaki yolların kırılmış, harabeye dönmüş parçaları (uçuşta kayaların yerine): tohumla
## (seed) üretilir, her parça farklı. 4 boyut sınıfı: küçük, orta, büyük (tam genişlik), uzun
## (ortadan kırılıp bükülmüş). Grafik ve sade: düz bir yol dilimi her kırık kenarda 1-3 düz
## kesikle kırpılır (temiz, açılı yüzler). Yolun malzemeleri: koyu mor yüzey, pembe yan duvar
## (sağlam uzun kenarlar), oyundaki şerit çizgisi düzenlerinden biri; kırık yüzler koyu ve mat.
## Moloz ayrı ve bağımsız (build_rubble). Parça orijini kütle merkezine yakın (kendi ekseninde döner).

enum Size { SMALL, MEDIUM, LARGE, LONG }

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
static func build(size: int, seed_value: int, line_style := -1) -> Node3D:
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
		var b := _slab(rng, lb, W, T, size, style, la)
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
		root.add_child(_slab(rng, L, W, T, size, style, 0.0))
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
static func _slab(rng: RandomNumberGenerator, L: float, W: float, T: float, size: int, style: int, z_off: float) -> MeshInstance3D:
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
	var mesh := ArrayMesh.new()
	var top_y := T * 0.5
	var bot_y := -T * 0.5
	var tri := Geometry2D.triangulate_polygon(poly)
	_surface_from(mesh, poly, tri, top_y, Vector3.UP, _mat("top"))
	_surface_from(mesh, poly, tri, bot_y, Vector3.DOWN, _mat("broken"))
	# Yan yüzler: dikdörtgenin uzun kenarında kalan (sağlam) kenar pembe yan duvar, kesikler koyu
	var side_st := SurfaceTool.new()
	side_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var broken_st := SurfaceTool.new()
	broken_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var intact := absf(absf(a.x) - hw) < 0.01 and absf(absf(b.x) - hw) < 0.01 and signf(a.x) == signf(b.x)
		var tgt := side_st if intact else broken_st
		var v0 := Vector3(a.x, top_y, a.y)
		var v1 := Vector3(b.x, top_y, b.y)
		var v2 := Vector3(b.x, bot_y, b.y)
		var v3 := Vector3(a.x, bot_y, a.y)
		for v in [v0, v2, v1, v0, v3, v2]:
			tgt.add_vertex(v)
	for pair in [[side_st, "side"], [broken_st, "broken"]]:
		var s: SurfaceTool = pair[0]
		s.generate_normals()
		s.set_material(_mat(pair[1]))
		s.commit(mesh)
	if style >= 0:
		_lines(mesh, poly, W, hl, top_y, style, z_off)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi


## Oyundaki şerit düzeni (RoadGenerator.LINE_STYLES[style]): kenardan uzaklık, genişlik, kesik
## boyu ve payı aynı; parça sınırında kırpılır
static func _lines(mesh: ArrayMesh, poly: PackedVector2Array, W: float, hl: float, y: float, style: int, z_off: float) -> void:
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
					var t2 := Geometry2D.triangulate_polygon(clipped)
					for k in range(0, t2.size(), 3):
						for q in [t2[k], t2[k + 2], t2[k + 1]]:
							st.set_normal(Vector3.UP)
							st.add_vertex(Vector3(clipped[q].x, y + 0.02, clipped[q].y))
						any = true
	if any:
		st.set_material(_mat("line"))
		st.commit(mesh)


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
