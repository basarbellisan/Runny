class_name RoadDebris
## Üst kattaki yolların kırılmış, harabeye dönmüş parçaları (uçuşta kayaların yerine): tohumla
## (seed) üretilir, her parça farklı. 4 boyut sınıfı: küçük köşe/kenar parçası, orta dilim, büyük
## tam genişlik parça, uzun (ortadan bükülmüş) şerit. Yolun malzemeleriyle: koyu mor yüzey, pembe
## yan duvar, şerit çizgileri; kırık yüzler koyu ve pürüzlü, çevresinde yüzen moloz parçaları.
## Parça orijini kütle merkezine yakın (kendi ekseninde döner).

enum Size { SMALL, MEDIUM, LARGE, LONG }

const NAMES := ["Küçük", "Orta", "Büyük", "Uzun"]
## [uzunluk min-max, genişlik min-max, kalınlık min-max] (m)
const DIMS := [
	[Vector2(3.0, 5.0), Vector2(2.5, 4.0), Vector2(1.0, 1.5)],
	[Vector2(7.0, 11.0), Vector2(4.5, 7.0), Vector2(1.2, 2.0)],
	[Vector2(14.0, 20.0), Vector2(8.0, 10.0), Vector2(1.5, 2.5)],
	[Vector2(28.0, 40.0), Vector2(5.0, 7.5), Vector2(1.2, 2.0)],
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
		"rebar":
			m.albedo_color = Color("2e2430")
		"crack":
			m.albedo_color = (sky.road_top as Color).darkened(0.55)
	_mats[key] = m
	return m


## Parça üret: size sınıfı, seed tohumu. Dönen düğüm: parça + çevresindeki moloz
static func build(size: int, seed_value: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + size * 104729 + 1
	var d: Array = DIMS[size]
	var L := rng.randf_range(d[0].x, d[0].y)
	var W := rng.randf_range(d[1].x, d[1].y)
	var T := rng.randf_range(d[2].x, d[2].y)
	var root := Node3D.new()
	root.name = "Debris"
	if size == Size.LONG:
		# Uzun şerit: ortadan kırılıp hafifçe bükülmüş iki parça (kopmuş köprü gibi)
		var split := rng.randf_range(0.4, 0.6)
		var la := L * split
		var lb := L * (1.0 - split)
		var a := _slab(rng, la, W, T, size, [true, true])
		var b := _slab(rng, lb, W, T, size, [true, true])
		var bend := deg_to_rad(rng.randf_range(8.0, 18.0)) * (1.0 if rng.randf() < 0.5 else -1.0)
		var twist := deg_to_rad(rng.randf_range(-6.0, 6.0))
		# a: menteşenin arkasında (ön ucu menteşede); b: menteşeden öne, bükülmüş ve hafif burulmuş
		a.position = Vector3(0, 0, -la * 0.5)
		b.basis = Basis(Vector3.RIGHT, bend) * Basis(Vector3.FORWARD, twist)
		b.position = b.basis * Vector3(0, 0, lb * 0.5) + Vector3(0, 0, 0.25)
		root.add_child(a)
		root.add_child(b)
		# Kütle merkezi orijine yakın
		var c := (a.position * la + b.position * lb) / L
		a.position -= c
		b.position -= c
	else:
		root.add_child(_slab(rng, L, W, T, size, [true, true]))
	_rubble(rng, root, L, W, T, size)
	return root


## Tek yol dilimi: üstten bakınca çokgen (uçları kırık, küçükte köşe/kenar kopuk), kalınlıkta
## yükseltilir. ends: [arka uç kırık, ön uç kırık]
static func _slab(rng: RandomNumberGenerator, L: float, W: float, T: float, size: int, ends: Array) -> MeshInstance3D:
	var hl := L * 0.5
	var hw := W * 0.5
	# Kenarlar: her nokta [Vector2(x, z), kırık mı (bu noktadan sonraki kenar)]. Kırık kenarlar
	# içe doğru zikzak; derinlik karşı kenara varamaz, köşelerde söner (çokgen kendini kesmez)
	var pts: Array = []
	var right_broken := size == Size.SMALL and rng.randf() < 0.7
	var left_broken := size == Size.SMALL or (size == Size.MEDIUM and rng.randf() < 0.5)
	var flags := [ends[0], right_broken, ends[1], left_broken]  # arka, sağ, ön, sol
	var corners := [Vector2(-hw, -hl), Vector2(hw, -hl), Vector2(hw, hl), Vector2(-hw, hl)]
	var inward := [Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0)]
	# En çok derinlik: uçlarda boyun %30'u, yanlarda enin %22'si (küçükte biraz daha)
	var deep := 1.25 if size == Size.SMALL else 1.0
	var max_d := [L * 0.3 * deep, W * 0.22 * deep, L * 0.3 * deep, W * 0.22 * deep]
	for e in 4:
		var c0: Vector2 = corners[e]
		var c1: Vector2 = corners[(e + 1) % 4]
		var prev_broken: bool = flags[(e + 3) % 4]
		# İki kırık kenarın köşesi pahlanır (kopmuş köşe)
		var start := c0
		if flags[e] and prev_broken:
			var cut := minf(W, L) * rng.randf_range(0.1, 0.25)
			start = c0 + (c1 - c0).normalized() * cut
			pts.append([c0 + (corners[(e + 3) % 4] - c0).normalized() * cut, true])
		if not flags[e]:
			pts.append([start, false])
			continue
		pts.append([start, true])
		var k := 4 + rng.randi() % 4
		for i in range(1, k):
			var t := (float(i) + rng.randf_range(-0.3, 0.3)) / k
			var env := pow(sin(PI * t), 0.6)
			var p := c0.lerp(c1, t) + (inward[e] as Vector2) * rng.randf_range(0.15, 1.0) * float(max_d[e]) * env
			pts.append([p, true])
	# Orta ve büyükte bir yandan ısırık (kopmuş parça)
	if size != Size.SMALL and size != Size.LONG and rng.randf() < 0.7:
		pts = _bite(rng, pts, hl, hw)
	var poly := PackedVector2Array()
	for p in pts:
		poly.append(p[0])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mesh := ArrayMesh.new()
	# Üst yüz
	var tri := Geometry2D.triangulate_polygon(poly)
	var top_y := T * 0.5
	var bot_y := -T * 0.5
	_surface_from(mesh, poly, tri, top_y, Vector3.UP, _mat("top"))
	_surface_from(mesh, poly, tri, bot_y, Vector3.DOWN, _mat("broken"))
	# Yan yüzler: sağlam kenar yan duvar rengi, kırık kenar koyu ve pürüzlü (alt kenarı düzensiz)
	var side := SurfaceTool.new()
	side.begin(Mesh.PRIMITIVE_TRIANGLES)
	var broken := SurfaceTool.new()
	broken.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := pts.size()
	for i in n:
		var a: Vector2 = pts[i][0]
		var b: Vector2 = pts[(i + 1) % n][0]
		var is_broken: bool = pts[i][1]
		var tgt := broken if is_broken else side
		var v0 := Vector3(a.x, top_y, a.y)
		var v1 := Vector3(b.x, top_y, b.y)
		var v2 := Vector3(b.x, bot_y, b.y)
		var v3 := Vector3(a.x, bot_y, a.y)
		for v in [v0, v2, v1, v0, v3, v2]:
			tgt.add_vertex(v)
		# İnşaat demiri: orta ve büyük parçaların kırık yüzlerinden dışarı taşan ince çubuklar
		if is_broken and size != Size.SMALL and rng.randf() < 0.35:
			var mid := a.lerp(b, rng.randf_range(0.2, 0.8))
			var out := (b - a).orthogonal().normalized()
			if out.dot(mid) < 0.0:
				out = -out
			_rebars.append([Vector3(mid.x, rng.randf_range(-0.25, 0.25) * T, mid.y), Vector3(out.x, rng.randf_range(-0.3, 0.3), out.y).normalized(), rng.randf_range(0.4, 1.1)])
	for pair in [[side, "side"], [broken, "broken"]]:
		var s: SurfaceTool = pair[0]
		s.generate_normals()
		s.set_material(_mat(pair[1]))
		s.commit(mesh)
	# Şerit çizgileri: sağlam kenarların biraz içinde ve ortada kesikli; parça sınırında kırpılır
	var lines := PackedVector2Array()
	var line_polys: Array = []
	var lw := 0.18
	var inset := 0.45
	if not right_broken or size == Size.LARGE:
		line_polys.append(_rect(hw - inset - lw, -hl - 1.0, hw - inset, hl + 1.0))
	if not left_broken or size == Size.LARGE:
		line_polys.append(_rect(-hw + inset, -hl - 1.0, -hw + inset + lw, hl + 1.0))
	if size == Size.LARGE or size == Size.LONG:
		var z := -hl + rng.randf_range(0.0, 3.0)
		while z < hl:
			line_polys.append(_rect(-lw * 0.5, z, lw * 0.5, z + 2.0))
			z += 4.0
	var ls := SurfaceTool.new()
	ls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any_line := false
	for lp: PackedVector2Array in line_polys:
		for clipped: PackedVector2Array in Geometry2D.intersect_polygons(lp, poly):
			var t2 := Geometry2D.triangulate_polygon(clipped)
			for k in range(0, t2.size(), 3):
				for q in [t2[k], t2[k + 2], t2[k + 1]]:
					ls.set_normal(Vector3.UP)
					ls.add_vertex(Vector3(clipped[q].x, top_y + 0.02, clipped[q].y))
				any_line = true
	if any_line:
		ls.set_material(_mat("line"))
		ls.commit(mesh)
	# Çatlaklar: yüzeyde birkaç koyu kırık çizgi (kırık kenardan içe doğru)
	var cs := SurfaceTool.new()
	cs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cracks := 1 + rng.randi() % (2 if size == Size.SMALL else 4)
	var any_crack := false
	for c in cracks:
		var p := Vector2(rng.randf_range(-hw, hw) * 0.8, (-hl if rng.randf() < 0.5 else hl) * 0.9)
		var dir := Vector2(rng.randf_range(-0.6, 0.6), -signf(p.y)).normalized()
		var steps := 3 + rng.randi() % 4
		var seg_len := minf(L, W) * rng.randf_range(0.08, 0.16)
		for k in steps:
			var q := p + dir.rotated(rng.randf_range(-0.7, 0.7)) * seg_len
			if not Geometry2D.is_point_in_polygon(q, poly) or not Geometry2D.is_point_in_polygon(p, poly):
				break
			var nrm := (q - p).orthogonal().normalized() * 0.06 * (1.0 - float(k) / steps)
			for v2 in [p - nrm, q, p + nrm]:
				cs.set_normal(Vector3.UP)
				cs.add_vertex(Vector3(v2.x, top_y + 0.015, v2.y))
			any_crack = true
			p = q
	if any_crack:
		cs.set_material(_mat("crack"))
		cs.commit(mesh)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	for rb: Array in _rebars:
		var rod := MeshInstance3D.new()
		var cm := BoxMesh.new()
		var len: float = rb[2]
		cm.size = Vector3(0.07, 0.07, len)
		rod.mesh = cm
		rod.material_override = _mat("rebar")
		var dir: Vector3 = rb[1]
		rod.basis = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT)
		rod.position = (rb[0] as Vector3) + dir * len * 0.5
		mi.add_child(rod)
	_rebars.clear()
	return mi


static var _rebars: Array = []


static func _rect(x0: float, z0: float, x1: float, z1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])


## Kenar ekle: düz (sağlam) ya da içe-dışa zikzak kırık çizgi. inward: parçanın içine doğru yön
static func _edge(rng: RandomNumberGenerator, pts: Array, a: Vector2, b: Vector2, is_broken: bool, jag: float, inward: Vector2) -> void:
	if not is_broken:
		pts.append([a, false])
		return
	var k := 4 + rng.randi() % 5
	for i in k:
		var t := float(i) / k
		var p := a.lerp(b, t)
		if i > 0:
			p += inward * rng.randf_range(0.0, jag) + (b - a).normalized() * rng.randf_range(-0.3, 0.3) * (b - a).length() / k
		pts.append([p, true])


## Bir uzun kenardan içe doğru kopmuş parça (çentik)
static func _bite(rng: RandomNumberGenerator, pts: Array, hl: float, hw: float) -> Array:
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var zc := rng.randf_range(-hl * 0.5, hl * 0.5)
	var bl := rng.randf_range(0.18, 0.35) * hl * 2.0
	var depth := rng.randf_range(0.2, 0.4) * hw * 2.0
	var notch := PackedVector2Array([
		Vector2(side * (hw + 1.0), zc - bl * 0.5), Vector2(side * (hw - depth * 0.6), zc - bl * 0.35),
		Vector2(side * (hw - depth), zc + rng.randf_range(-0.1, 0.1) * bl), Vector2(side * (hw - depth * 0.5), zc + bl * 0.4),
		Vector2(side * (hw + 1.0), zc + bl * 0.5)])
	var poly := PackedVector2Array()
	for p in pts:
		poly.append(p[0])
	var res := Geometry2D.clip_polygons(poly, notch)
	if res.is_empty() or Geometry2D.is_polygon_clockwise(res[0]) != Geometry2D.is_polygon_clockwise(poly):
		return pts
	# Kırık bilgisi: eski noktalar korunur, çentiğin yeni kenarları kırık
	var out: Array = []
	var cut: PackedVector2Array = res[0]
	for i in cut.size():
		var p := cut[i]
		var flag := true
		for o in pts:
			if (o[0] as Vector2).distance_to(p) < 0.01:
				flag = o[1]
				break
		out.append([p, flag])
	return out


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


## Parçanın çevresinde yüzen küçük moloz parçaları (parçayla birlikte döner)
static func _rubble(rng: RandomNumberGenerator, root: Node3D, L: float, W: float, T: float, size: int) -> void:
	var count: int = [2, 4, 6, 7][size]
	for i in count:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var s := rng.randf_range(0.25, 0.7) * (1.0 + size * 0.35)
		bm.size = Vector3(s * rng.randf_range(0.8, 1.6), s * rng.randf_range(0.5, 1.0), s * rng.randf_range(0.8, 1.6))
		mi.mesh = bm
		mi.material_override = _mat("broken") if rng.randf() < 0.6 else _mat("top")
		var ang := rng.randf() * TAU
		mi.position = Vector3(cos(ang) * (W * 0.5 + rng.randf_range(0.5, 2.5)), rng.randf_range(-1.5, 1.5) * T,
			sin(ang) * (L * 0.5 + rng.randf_range(0.5, 3.0)) * 0.8)
		mi.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		root.add_child(mi)
