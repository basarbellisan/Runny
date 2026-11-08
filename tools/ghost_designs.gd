extends SceneTree
## Alt katmanda kayaların yerine hayaletler: tasarım çalışması (10 farklı hayalet).
## Her tasarım alt katmanın mercan ortamında, karşıdan (bize doğru gelirken) görülür; etekleri
## dalgalanır. Kareler --out klasörüne g<no>_<kare>.png olarak yazılır.
## Kullanım: godot --path . --resolution 360x420 --script res://tools/ghost_designs.gd -- --out=/tmp --frames=48

const NAMES := ["Klasik örtü", "Kuyruklu ruh", "Kollu (böö!)", "Kukuletalı", "Denizanası",
	"Kat kat tül", "Neon hologram", "Sürü", "Yırtık uçlu", "Fener kalpli"]

var _out := "user://"
var _frames := 48
var _only := -1
var _mats: Array[ShaderMaterial] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a.begins_with("--frames="):
			_frames = int(a.trim_prefix("--frames="))
		elif a.begins_with("--only="):
			_only = int(a.trim_prefix("--only="))
	_shoot.call_deferred()


func _shoot() -> void:
	var world := Node3D.new()
	root.add_child(world)
	_environment(world)
	var cam := Camera3D.new()
	cam.fov = 40
	world.add_child(cam)
	cam.look_at_from_position(Vector3(4.2, 3.9, 11.0), Vector3(0, 2.2, -0.6))
	for i in NAMES.size():
		if _only >= 0 and i != _only:
			continue
		_mats.clear()
		var g := _build(i)
		world.add_child(g)
		for f in _frames:
			var tt := float(f) / 24.0
			for m in _mats:
				m.set_shader_parameter("t", tt)
			# Yavaşça süzülür (yukarı-aşağı)
			g.position.y = 0.15 * sin(tt * 2.0)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_viewport().get_texture().get_image().save_png("%s/g%02d_%03d.png" % [_out, i + 1, f])
		print("hayalet %d %s" % [i + 1, NAMES[i]])
		g.queue_free()
		await process_frame
	quit()


func _environment(world: Node3D) -> void:
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


## Dönel örtü ağı. prof: [[h, yarıçap, y, z], ...] (h 0 etek ucu .. 1 tepe; artan sırada)
func _sheet(prof: Array, mat: ShaderMaterial, seg := 48) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := prof.size()
	for j in rows:
		var p: Array = prof[j]
		for i in seg + 1:
			var u := float(i) / seg
			# Ağın birleşim yeri (dikiş) arkada: u = 0.5 ön (kameraya bakan)
			var a := u * TAU + PI
			st.set_uv(Vector2(u, p[0]))
			st.add_vertex(Vector3(sin(a) * p[1], p[2], cos(a) * p[1] + p[3]))
	for j in rows - 1:
		for i in seg:
			var a0 := j * (seg + 1) + i
			var b0 := a0 + seg + 1
			st.add_index(a0)
			st.add_index(b0)
			st.add_index(a0 + 1)
			st.add_index(a0 + 1)
			st.add_index(b0)
			st.add_index(b0 + 1)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Klasik hayalet profili: yuvarlak baş, aşağı doğru genişleyen örtü
func _classic(height := 4.2, head := 1.25, flare := 0.35, body_to := 0.55, rows := 34) -> Array:
	var out: Array = []
	for j in rows + 1:
		var h := float(j) / rows
		var r: float
		if h >= body_to:
			var q := (h - body_to) / (1.0 - body_to)
			r = head * sqrt(maxf(1.0 - q * q, 0.0))
		else:
			r = head * (1.0 + flare * pow((body_to - h) / body_to, 1.3))
		out.append([h, r, h * height, 0.0])
	return out


## Örtü malzemesi: önce iç yüz (ghost_back), sonra dış yüz (ghost; next_pass). Ortak varsayılanlar:
## beyaza yakın, hafif kendinden ışıklı (mercan zeminde seçilsin)
const BASE := {"glow": 1.0, "alpha_center": 0.72, "alpha_edge": 0.97}


func _mat(params: Dictionary) -> ShaderMaterial:
	var p := BASE.duplicate()
	p.merge(params, true)
	var front := ShaderMaterial.new()
	front.shader = preload("res://shaders/ghost.gdshader")
	var back := ShaderMaterial.new()
	back.shader = preload("res://shaders/ghost_back.gdshader")
	for k: String in p:
		front.set_shader_parameter(k, p[k])
		back.set_shader_parameter(k, p[k])
	back.next_pass = front
	_mats.append(front)
	_mats.append(back)
	return back


func _build(i: int) -> Node3D:
	var g := Node3D.new()
	match i:
		0:  # Klasik örtü: yuvarlak baş, dilimli etek, iki koyu göz
			g.add_child(_sheet(_classic(), _mat({"color": Color("f7f4ff")})))
		1:  # Kuyruklu ruh: dik yuvarlak baş (yüzü bize dönük), gövde incelerek geriye kıvrılan
			# uzun bir kuyruğa döner; kuyruk dalgalanır
			var prof: Array = []
			var rows := 44
			for j in rows + 1:
				var h := float(j) / rows
				var r: float
				var y: float
				var z := 0.0
				if h >= 0.55:
					var q := (h - 0.55) / 0.45
					r = 1.3 * sqrt(maxf(1.0 - q * q, 0.0))
					y = 2.4 + (h - 0.55) / 0.45 * 1.6
				else:
					var q2 := h / 0.55
					r = 1.3 * pow(q2, 0.85)
					y = 2.4 - (1.0 - q2) * 2.0
					z = -pow(1.0 - q2, 1.5) * 3.6
				prof.append([h, r, y, z])
			g.add_child(_sheet(prof, _mat({"color": Color("eefcff"), "rim_color": Color("bff4ff"),
				"hem": 0, "wave_amp": 0.05, "ripple_amp": 0.5, "ripple_freq": 9.0, "trail": 0.0,
				"eye_pos": Vector2(0.06, 0.8), "eye_size": Vector2(0.032, 0.07)})))
		2:  # Kollu: iki yana kalkmış kollar (örtünün uçları), ağzı açık
			var m := _mat({"color": Color("fbf8ff"), "mouth": 1.0})
			g.add_child(_sheet(_classic(4.0, 1.2, 0.3), m))
			for side in [-1.0, 1.0]:
				var arm_prof: Array = []
				for j in 13:
					var h := float(j) / 12.0
					arm_prof.append([h, 0.42 * pow(h, 0.6) * (1.0 - 0.4 * h) + 0.05, h * 1.8, 0.0])
				var arm := _sheet(arm_prof, _mat({"color": Color("fbf8ff"), "eyes": 0.0, "hem": 0,
					"wave_amp": 0.15, "trail": 0.1, "phase": side}), 24)
				arm.rotation = Vector3(0, 0, side * deg_to_rad(-115))
				arm.scale = Vector3(1.0, 1.0, 0.45)
				arm.position = Vector3(side * 0.95, 2.3, 0.0)
				g.add_child(arm)
		3:  # Kukuletalı: uzun sivri kukuleta, önde koyu yüz oyuğu, içinde parlayan gözler
			var prof: Array = []
			var rows := 36
			for j in rows + 1:
				var h := float(j) / rows
				var r := 1.35 * (1.0 + 0.4 * pow(1.0 - h, 1.4)) * pow(maxf(1.0 - pow(h, 3.0), 0.0), 0.5)
				prof.append([h, r, h * 4.8, -pow(h, 3.0) * 0.8])
			g.add_child(_sheet(prof, _mat({"color": Color("e2d6fa"), "hood": 1.0, "eye_pos": Vector2(0.045, 0.7), "eye_size": Vector2(0.022, 0.03),
				"eye_color": Color("fff1a0"), "eye_glow": 2.5, "hem": 2, "hem_depth": 0.1})))
		4:  # Denizanası: kısa çan, altından sarkan dalgalı şeritler
			g.add_child(_sheet(_classic(2.2, 1.5, 0.15, 0.25, 24).map(func(p): return [p[0] * 0.55 + 0.45, p[1], p[2] + 2.6, p[3]]),
				_mat({"color": Color("fdf0fb"), "rim_color": Color("ff9ad5"),
				"hem": 1, "scallops": 8.0, "hem_depth": 0.08, "wave_amp": 0.18,
				"eye_pos": Vector2(0.05, 0.86), "eye_size": Vector2(0.025, 0.045)})))
			for k in 9:
				var a := TAU * k / 9.0
				var rib: Array = []
				for j in 17:
					var h := float(j) / 16.0
					rib.append([h, 0.12, 2.75 - (1.0 - h) * 2.6, 0.0])
				var r := _sheet(rib, _mat({"color": Color("fdf0fb"), "rim_color": Color("ff9ad5"),
					"eyes": 0.0, "hem": 0, "wave_amp": 0.0, "ripple_amp": 0.35, "ripple_freq": 8.0,
					"trail": 0.6, "phase": k * 0.7, "alpha_center": 0.5}), 8)
				r.position = Vector3(sin(a) * 1.05, 0.0, cos(a) * 1.05)
				g.add_child(r)
		5:  # Kat kat tül: üç saydam katman, her biri farklı uzunlukta ve dalgada
			g.add_child(_sheet(_classic(4.2, 1.15, 0.25), _mat({"color": Color("f6f2ff")})))
			for k in 2:
				var len := 0.62 - k * 0.14
				var prof: Array = []
				for j in 21:
					var h := float(j) / 20.0
					var y := 2.3 * len / 0.62 * h + (2.4 - 2.3 * len / 0.62)
					prof.append([h * 0.7, 1.35 + 0.35 * k + (1.0 - h) * (0.55 + 0.25 * k), y, 0.0])
				g.add_child(_sheet(prof, _mat({"color": Color("f1ecff"), "eyes": 0.0,
					"alpha_center": 0.3, "alpha_edge": 0.75, "scallops": 6.0 + k * 2.0,
					"phase": 1.3 * (k + 1), "wave_amp": 0.3, "hem_depth": 0.1})))
		6:  # Neon hologram: kenarları ve tarama çizgileri parlayan, içi boş camgöbeği hayalet
			g.add_child(_sheet(_classic(), _mat({"color": Color("38e8ff"), "holo": 1.0,
				"eye_color": Color("ffffff"), "eye_glow": 2.0})))
		7:  # Sürü: beş küçük hayalet, farklı dalga zamanlarıyla
			var spots := [Vector3(0, 1.0, 0.6), Vector3(-1.9, 2.2, -0.6), Vector3(1.9, 2.0, -0.4),
				Vector3(-1.0, 3.5, -1.2), Vector3(1.1, 3.6, -1.4)]
			for k in spots.size():
				var s := _sheet(_classic(), _mat({"color": Color("fbf9ff"), "phase": k * 1.3,
					"wave_speed": 2.6}))
				s.scale = Vector3.ONE * 0.42
				s.position = spots[k]
				g.add_child(s)
		8:  # Yırtık uçlu: etek uçları farklı uzunlukta şeritler halinde sarkar
			var prof := _classic(4.6, 1.2, 0.45, 0.5)
			g.add_child(_sheet(prof, _mat({"color": Color("efe9f7"), "hem": 2, "hem_depth": 0.22,
				"wave_amp": 0.3, "scallops": 7.0, "eye_size": Vector2(0.02, 0.09),
				"eye_pos": Vector2(0.05, 0.76)})))
		9:  # Fener kalpli: örtünün içinden görünen sıcak, parlayan bir çekirdek
			g.add_child(_sheet(_classic(), _mat({"color": Color("fffaf4"), "alpha_center": 0.45,
				"eye_color": Color("3a1a20")})))
			var core := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.5
			sm.height = 1.0
			core.mesh = sm
			var cm := StandardMaterial3D.new()
			cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			cm.albedo_color = Color("ffb05e")
			core.material_override = cm
			core.position = Vector3(0, 1.9, -0.1)
			g.add_child(core)
			var halo := MeshInstance3D.new()
			var hm := SphereMesh.new()
			hm.radius = 1.0
			hm.height = 2.0
			halo.mesh = hm
			var hmat := StandardMaterial3D.new()
			hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			hmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			hmat.albedo_color = Color(1.0, 0.6, 0.25, 0.35)
			halo.material_override = hmat
			halo.position = core.position
			g.add_child(halo)
	return g
