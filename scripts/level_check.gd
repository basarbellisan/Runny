class_name LevelCheck
extends RefCounted
## El yapımı kalıpların fizik kontrolü ve gerçek zamanlı türetilmesi.
## editor/physics.js'deki analyze() ve vary() ile aynı kurallar (değişirse ikisi birlikte).
## Kalıp: { at, pieces: [{id,x,w,z0,len,h0,h1,bank}], obstacles: [{id,kind,x,w,z0,len,rise,dir,dx}] }

const START_SPEED := 40.0
const MAX_SPEED := 80.0
const ACCELERATION := 1.5
const LATE_ACCELERATION := 0.15
const TOP_SPEED := 80.0
const GRAVITY := 28.0
const LAUNCH_VELOCITY := 8.0
const BOOST_BONUS := 1.35
const BOOST_MAX_EXTRA := 45.0
const CAR_LEN := 3.9
const HALF_WIDTH := 1.1
const STEER_SPEED := 11.0
const AIR_CONTROL := 0.8
const BUMP_LAUNCH := 1.4
const LIGHTS_TIME := 1.1
const MAX_SLOPE_DEG := 21.0
const MAX_BANK_DEG := 17.0
## Garajın en yavaş ve en hızlı arabasının hız katı (CarModel.STATS); en yavaş araba en uzun
## boşluklara tam gazla en az SLOW_MARGIN payla konmalı (kıl payı)
const SLOW_MUL := 0.96
const FAST_MUL := 1.08
const SLOW_MARGIN := 1.0
## Garajın en geniş arabasının (Gezgin, tekerleriyle) yarı genişliği: blok geçitleri buna göre
const WIDE_HALF := 1.27

const VARY_OPS := ["gap", "len", "width", "rows", "swap", "rise"]


static func speed_at(d: float) -> float:
	var v := sqrt(START_SPEED * START_SPEED + 2.0 * ACCELERATION * maxf(d, 0.0))
	if v > MAX_SPEED:
		var d_max := (MAX_SPEED * MAX_SPEED - START_SPEED * START_SPEED) / (2.0 * ACCELERATION)
		v = sqrt(MAX_SPEED * MAX_SPEED + 2.0 * LATE_ACCELERATION * (d - d_max))
	return minf(v, TOP_SPEED)


## speed_at'in tersi: bu hıza kaçıncı metrede varılır
static func distance_for_speed(v: float) -> float:
	if v <= MAX_SPEED:
		return maxf((v * v - START_SPEED * START_SPEED) / (2.0 * ACCELERATION), 0.0)
	var d_max := (MAX_SPEED * MAX_SPEED - START_SPEED * START_SPEED) / (2.0 * ACCELERATION)
	return d_max + (v * v - MAX_SPEED * MAX_SPEED) / (2.0 * LATE_ACCELERATION)


static func v_boost(v: float) -> float:
	return v + 0.9 * minf(v * BOOST_BONUS, BOOST_MAX_EXTRA)


## Tam roket, garajın en hızlı arabasıyla (iniş en uzak: yol bunu taşımalı)
static func v_full(v: float) -> float:
	var fv := v * FAST_MUL
	return fv + minf(fv * BOOST_BONUS, BOOST_MAX_EXTRA)


## Kalkıştan (dikey hız vy) dh yüksekliğine inene kadar süre; çıkılamıyorsa NAN
static func flight_time(dh: float, vy: float) -> float:
	var d := vy * vy - 2.0 * GRAVITY * dh
	if d < 0.0:
		return NAN
	return (vy + sqrt(d)) / GRAVITY


static func clear_end(v: float) -> float:
	return clampf(v * LIGHTS_TIME * 0.6, 14.0, 45.0) + v * 0.45


static func clear_start(v: float, land_far: float) -> float:
	return maxf(v_boost(v) * 0.6 + 10.0, land_far + v_boost(v) * 0.55 + 6.0)


static func f(d: Dictionary, key: String, default := 0.0) -> float:
	var v = d.get(key, default)
	return float(v) if (v is float or v is int) else default


static func p_end(p: Dictionary) -> float:
	return f(p, "z0") + f(p, "len")


static func h0(p: Dictionary) -> float:
	return f(p, "h0")


static func h1(p: Dictionary) -> float:
	return f(p, "h1", h0(p))


static func h_at(p: Dictionary, z: float) -> float:
	var t := clampf((z - f(p, "z0")) / maxf(f(p, "len"), 0.01), 0.0, 1.0)
	return h0(p) + (h1(p) - h0(p)) * t


static func is_on(o: Dictionary, p: Dictionary) -> bool:
	return f(o, "z0") >= f(p, "z0") - 0.5 and f(o, "z0") <= p_end(p) + 0.5 \
		and absf(f(o, "x") - f(p, "x")) <= f(p, "w") * 0.5 + 0.5


static func host_of(level: Dictionary, o: Dictionary) -> Variant:
	var best = null
	for p in level.pieces:
		if is_on(o, p) and best == null:
			best = p
	return best


static func successor(level: Dictionary, p: Dictionary) -> Variant:
	for q in level.pieces:
		if is_same(q, p):
			continue
		if absf(f(q, "z0") - p_end(p)) < 0.6 and absf(h0(q) - h1(p)) < 0.3 \
				and absf(f(q, "x") - f(p, "x")) < (f(q, "w") + f(p, "w")) * 0.5 - 1.0:
			return q
	return null


## Yollar başlangıç sırasıyla (girişten çıkışa). "Yan yol" ayrımı yok: hepsi yol
static func main_path(level: Dictionary) -> Array:
	var path: Array = level.pieces.duplicate()
	path.sort_custom(func(a, b): return f(a, "z0") < f(b, "z0") or (f(a, "z0") == f(b, "z0") and f(a, "id") < f(b, "id")))
	return path


## Çıkış: en ileride biten yol (oyun sonraki yolları buradan bağlar)
static func exit_of(level: Dictionary) -> Variant:
	var best = null
	for p in main_path(level):
		if best == null or p_end(p) > p_end(best):
			best = p
	return best


## Yolun ucundan gidilebilen yollar: [{ q, free }]. Atlanabilir boşluk ya da boşluksuz aşağı
## basamak; free: garajın en yavaş arabası gazsız yetişir (en az SLOW_MARGIN payla)
static func onward(level: Dictionary, a: Dictionary) -> Array:
	var out: Array = []
	var v := speed_at(f(level, "at") + p_end(a))
	var vs := v * SLOW_MUL
	var slope := (h1(a) - h0(a)) / maxf(f(a, "len"), 0.01)
	for q in level.pieces:
		if is_same(q, a):
			continue
		var gap := f(q, "z0") - p_end(a)
		if gap < -0.6 or gap > 150.0:
			continue
		var lat := maxf(0.0, absf(f(q, "x") - f(a, "x")) - (f(q, "w") + f(a, "w")) * 0.5)
		if lat > 8.0:
			continue
		var jd := jump(f(level, "at"), a, q)
		var t0 := flight_time(jd.dh, LAUNCH_VELOCITY + vs * slope)
		var lat0 := STEER_SPEED * AIR_CONTROL * (0.0 if is_nan(t0) else t0)
		if gap < 0.6:
			if h0(q) <= h1(a) + 0.3:
				out.append({"q": q, "free": jd.need <= lat0})
			continue
		if is_nan(jd.reach_b) or gap > jd.reach_b - 2.5:
			continue
		out.append({"q": q, "free": not is_nan(t0) and gap <= CAR_LEN + vs * t0 - SLOW_MARGIN and jd.need <= lat0})
	return out


## Pist ışıkları (gaz bölgesi): yolun ucundan gaz isteyen bir atlama varsa, yanında gazsız
## yetişilen yol olsa da. Bitişik devamı ya da çıkmazı olan yolda yok; çıkış yolunda hep var
## (oyun sonraki yolu ardına atlamayla bağlar); gidilecek yol yoksa da var
static func needs_lights(level: Dictionary, a: Dictionary) -> bool:
	if successor(level, a) != null or has_deadend(level, a):
		return false
	if is_same(a, exit_of(level)):
		return true
	var on := onward(level, a)
	return on.is_empty() or on.any(func(o): return not o.free)


static func has_deadend(level: Dictionary, p: Dictionary) -> bool:
	return level.get("obstacles", []).any(func(o): return o.get("kind", "") == "deadend" and is_same(host_of(level, o), p))


## Bir yolun ardına önerilen boşluk (oyunun seçtiği gibi: pencerenin ~%35'i; physics.js suggestGap)
static func suggest_gap(at: float, a: Dictionary, dh: float) -> float:
	var v := speed_at(at + p_end(a))
	var slope := (h1(a) - h0(a)) / maxf(f(a, "len"), 0.01)
	var lo := CAR_LEN + v * flight_time(dh, LAUNCH_VELOCITY + v * slope) + 1.5
	var hi := CAR_LEN + v_boost(v) * flight_time(dh, LAUNCH_VELOCITY + v_boost(v) * slope) - 2.5
	if is_nan(lo) or is_nan(hi):
		return 25.0
	return roundf(lo + (maxf(hi, lo) - lo) * 0.35)


## A'nın sonundan B'ye atlama
static func jump(at: float, a: Dictionary, b: Dictionary) -> Dictionary:
	var v := speed_at(at + p_end(a))
	var slope := (h1(a) - h0(a)) / maxf(f(a, "len"), 0.01)
	var dh := h0(b) - h1(a)
	var gap := f(b, "z0") - p_end(a)
	var vb := v_boost(v)
	var vf := v_full(v)
	var t0 := flight_time(dh, LAUNCH_VELOCITY + v * slope)
	var tb := flight_time(dh, LAUNCH_VELOCITY + vb * slope)
	var tf := flight_time(dh, LAUNCH_VELOCITY + vf * slope)
	var reach0 := CAR_LEN + v * t0
	var reach_b := CAR_LEN + vb * tb
	var reach_f := CAR_LEN + vf * tf
	# En yavaş araba: aynı gazla, hızı katı kadar düşük (gazın ek hızı aynı)
	var dv_s := v * (1.0 - SLOW_MUL)
	var reach_s := CAR_LEN + (vb - dv_s) * flight_time(dh, LAUNCH_VELOCITY + vb * slope - dv_s * slope)
	var lateral := STEER_SPEED * AIR_CONTROL * (0.0 if is_nan(tb) else tb)
	var need := maxf(0.0, absf(f(b, "x") - f(a, "x")) - (f(a, "w") + f(b, "w")) * 0.5 + 2.0 * HALF_WIDTH + 0.5)
	return {"a": a, "b": b, "v": v, "vb": vb, "gap": gap, "dh": dh, "reach0": reach0, "reach_b": reach_b, "reach_s": reach_s,
		"lateral": lateral, "need": need,
		"land_far": p_end(a) + (reach_b if is_nan(reach_f) else reach_f)}


## Rampa/tümsek uçuşu
static func ramp_flight(at: float, o: Dictionary, host: Dictionary) -> Dictionary:
	var v := speed_at(at + f(o, "z0"))
	var rise := f(o, "rise", 1.6)
	var plen := maxf(f(o, "len", 8.0), 0.5)
	if o.get("kind", "") == "bump":
		var half := plen * 0.5
		var vy := v * rise / half * BUMP_LAUNCH + 1.0
		var t := 2.0 * vy / GRAVITY
		return {"v": v, "t": t, "vy0": vy, "from": f(o, "z0") + half, "land": f(o, "z0") + half + v * t,
			"x": f(o, "x"), "top": h_at(host, f(o, "z0")) + rise}
	var vy2 := LAUNCH_VELOCITY + v * rise / plen
	var t2 := flight_time(-rise, vy2)
	var x := f(o, "x")
	if o.get("kind", "") == "kick":
		x += signf(f(o, "dir", 1.0)) * f(o, "dx", 8.0)
	return {"v": v, "t": t2, "vy0": vy2, "from": f(o, "z0") + plen, "land": f(o, "z0") + plen + CAR_LEN + v * t2,
		"x": x, "top": h_at(host, f(o, "z0")) + rise}


## Kontrol: { errors, warns, issues: ["hata: ...", ...] }
static func analyze(level: Dictionary) -> Dictionary:
	var res := {"errors": 0, "warns": 0, "issues": []}
	var add := func(error: bool, text: String) -> void:
		res[("errors" if error else "warns")] += 1
		res.issues.append(("hata: " if error else "uyarı: ") + text)
	var pieces: Array = level.get("pieces", [])
	var obstacles: Array = level.get("obstacles", [])
	var at := f(level, "at")
	if pieces.is_empty():
		add.call(true, "yol yok")
		return res
	var path := main_path(level)
	var tan_max := tan(deg_to_rad(MAX_SLOPE_DEG))
	for p in pieces:
		if absf(h1(p) - h0(p)) / maxf(f(p, "len"), 0.01) > tan_max + 1e-6:
			add.call(true, "dik yokuş #%s" % p.id)
		if f(p, "w") < 3.0:
			add.call(false, "dar yol #%s" % p.id)
		if absf(f(p, "bank")) > MAX_BANK_DEG:
			add.call(false, "yatıklık #%s" % p.id)
	for i in pieces.size():
		for j in range(i + 1, pieces.size()):
			var a: Dictionary = pieces[i]
			var b: Dictionary = pieces[j]
			var oz := minf(p_end(a), p_end(b)) - maxf(f(a, "z0"), f(b, "z0"))
			var ox := minf(f(a, "x") + f(a, "w") * 0.5, f(b, "x") + f(b, "w") * 0.5) \
				- maxf(f(a, "x") - f(a, "w") * 0.5, f(b, "x") - f(b, "w") * 0.5)
			if oz > 1.0 and ox > 0.5:
				var dz := maxf(f(a, "z0"), f(b, "z0"))
				if absf(h_at(a, dz) - h_at(b, dz)) < 4.0:
					add.call(true, "üst üste yollar #%s #%s" % [a.id, b.id])
	# Atlamanın inişi: tam roketle yolu aşmasın, iniş bölgesinde engel olmasın
	var landing := func(jd: Dictionary, b: Dictionary) -> void:
		var land_far: float = jd.land_far - f(b, "z0")
		if jd.land_far > p_end(b) - 2.0:
			add.call(true, "tam roketle yol aşılıyor #%s" % b.id)
		elif p_end(b) - jd.land_far < jd.v * 1.2 and successor(level, b) == null:
			var left: float = p_end(b) - jd.land_far
			add.call(left < jd.v * 0.6, "inişten sonra az yol #%s" % b.id)
		if jd.need > jd.lateral * 0.8:
			jd["bad"] = true
			add.call(true, "yana çok uzak #%s" % b.id)
		var calm := f(b, "z0") + clear_start(speed_at(at + f(b, "z0")), land_far)
		var hot: float = jd.land_far + jd.vb * 0.3
		for o in obstacles:
			if o.get("kind", "") != "deadend" and is_same(host_of(level, o), b) and f(o, "z0") < calm:
				var strong: bool = o.get("kind", "") in ["bump", "ramp", "kick", "block"] and f(o, "z0") < hot
				add.call(strong, "engel inişe yakın #%s" % o.id)
	# Giriş: oyun kalıba önceki yoldan atlayarak girer; ilk yolun başı da iniş bölgesi
	if not path.is_empty():
		var e: Dictionary = path[0]
		var pre := {"id": 0, "x": f(e, "x"), "w": f(e, "w"), "z0": f(e, "z0") - 100.0, "len": 100.0, "h0": h0(e), "h1": h0(e)}
		pre["z0"] = f(pre, "z0") - suggest_gap(at, pre, 0.0)
		var je := jump(at, pre, e)
		if not is_nan(je.reach_b):
			var calm_e := f(e, "z0") + clear_start(speed_at(at + f(e, "z0")), je.land_far - f(e, "z0"))
			for o in obstacles:
				if o.get("kind", "") != "deadend" and is_same(host_of(level, o), e) and f(o, "z0") < calm_e:
					add.call(o.get("kind", "") != "gravel", "engel girişin iniş bölgesinde #%s" % o.id)
	# Ana yol boyunca atlamalar
	var path_end := 0.0
	for q in path:
		path_end = maxf(path_end, p_end(q))
	for i in range(path.size() - 1):
		var a: Dictionary = path[i]
		if successor(level, a) != null:
			continue
		var b = null
		var best := INF
		for q in path:
			if is_same(q, a) or f(q, "z0") < p_end(a) - 0.6 or f(q, "z0") > p_end(a) + 150.0:
				continue
			var lat := maxf(0.0, absf(f(q, "x") - f(a, "x")) - (f(q, "w") + f(a, "w")) * 0.5)
			if lat > 8.0:
				continue
			var cost := (f(q, "z0") - p_end(a)) + lat * 12.0
			if cost < best:
				best = cost
				b = q
		if b == null:
			if p_end(a) < path_end - 1.0 and not has_deadend(level, a):
				add.call(false, "yolun sonundan inilecek yol yok #%s" % a.id)
			continue
		if f(b, "z0") - p_end(a) < 0.6:
			continue
		var jd := jump(at, a, b)
		if is_nan(jd.reach_b):
			add.call(true, "çok yüksek basamak #%s" % b.id)
			continue
		if jd.gap > jd.reach_b - 2.5:
			add.call(true, "atlanamaz boşluk #%s" % b.id)
			continue
		if not (jd.gap <= jd.reach_s - SLOW_MARGIN):
			add.call(false, "en yavaş araba yetişemez #%s" % b.id)
		landing.call(jd, b)
	# Her ana yolun sonunda pist bölgesi
	for p in path:
		if not needs_lights(level, p):
			continue
		var runway := p_end(p) - clear_end(speed_at(at + p_end(p)))
		for o in obstacles:
			if o.get("kind", "") != "deadend" and is_same(host_of(level, o), p) and f(o, "z0") + f(o, "len") > runway:
				add.call(false, "engel pistte #%s" % o.id)
	# Rampa ve tümsek uçuşları (akış için: [kalkılan yol, inilen yol])
	var fl_edges: Array = []
	for o in obstacles:
		if not o.get("kind", "") in ["ramp", "kick", "bump"]:
			continue
		var host = host_of(level, o)
		if host == null:
			add.call(true, "rampa yolda değil #%s" % o.id)
			continue
		var fl := ramp_flight(at, o, host)
		if is_nan(fl.t):
			continue
		var cands: Array = pieces.filter(func(p): return absf(fl.x - f(p, "x")) <= f(p, "w") * 0.5 + 0.3)
		# En yüksek önce; eşitse tasarımdaki sıra (editördeki kararlı sıralama gibi)
		cands.sort_custom(func(p, q):
			var hp := h_at(p, fl.from)
			var hq := h_at(q, fl.from)
			return hp > hq if hp != hq else pieces.find(p) < pieces.find(q))
		var land_on = null
		for p in cands:
			var t := flight_time(h_at(p, fl.from + 10.0) - fl.top, fl.vy0)
			if is_nan(t):
				continue
			var z: float = fl.from + (0.0 if o.kind == "bump" else CAR_LEN) + fl.v * t
			if z >= f(p, "z0") - 1.0 and z <= p_end(p):
				land_on = p
				fl.land = z
				break
		if land_on != null:
			fl_edges.append([host, land_on])
		if land_on == null:
			add.call(true, "rampa boşluğa atıyor #%s" % o.id)
		elif successor(level, land_on) == null and p_end(land_on) - fl.land < clear_end(fl.v):
			add.call(maxf(0.0, p_end(land_on) - fl.land) < fl.v * 0.6, "rampa sonrası az yol #%s" % o.id)
	# Akış: girişten çıkışa giden bir yol var mı (bitişik devam, atlanabilen boşluk, rampa uçuşu)
	var exit_p = exit_of(level)
	if path.size() > 1 and exit_p != null:
		var seen: Array = [path[0]]
		var todo: Array = [path[0]]
		while not todo.is_empty():
			var a: Dictionary = todo.pop_back()
			var nxt: Array = []
			var s = successor(level, a)
			if s != null:
				nxt.append(s)
			else:
				for o in onward(level, a):
					nxt.append(o.q)
			for e in fl_edges:
				if is_same(e[0], a):
					nxt.append(e[1])
			for q in nxt:
				if not seen.any(func(x): return is_same(x, q)):
					seen.append(q)
					todo.append(q)
		if not seen.any(func(x): return is_same(x, exit_p)):
			add.call(false, "akış kopuk")
	# Bloklar yolu kapatmasın
	var need_lane := 2.0 * WIDE_HALF + 1.0
	for p in pieces:
		var blocks: Array = obstacles.filter(func(o): return o.get("kind", "") == "block" and is_same(host_of(level, o), p))
		blocks.sort_custom(func(a, b): return f(a, "z0") < f(b, "z0"))
		var seen: Array = []
		for o in blocks:
			if seen.any(func(s): return is_same(s, o)):
				continue
			var row: Array = blocks.filter(func(b): return absf(f(b, "z0") - f(o, "z0")) < CAR_LEN + 2.0)
			seen.append_array(row)
			var ivs: Array = row.map(func(b): return Vector2(f(b, "x") - f(b, "w") * 0.5, f(b, "x") + f(b, "w") * 0.5))
			ivs.sort_custom(func(a, b): return a.x < b.x)
			var left := f(p, "x") - f(p, "w") * 0.5
			var widest := 0.0
			for iv in ivs:
				widest = maxf(widest, iv.x - left)
				left = maxf(left, iv.y)
			widest = maxf(widest, f(p, "x") + f(p, "w") * 0.5 - left)
			if widest < need_lane - 1e-6:
				add.call(true, "bloklar yolu kapatıyor #%s" % o.id)
	# Çıkış yolunun sonu boş
	if not path.is_empty():
		var exit: Dictionary = exit_of(level)
		var lim := p_end(exit) - clear_end(speed_at(at + p_end(exit)))
		if obstacles.any(func(o): return is_same(host_of(level, o), exit) and o.get("kind", "") != "deadend" and f(o, "z0") > lim):
			add.call(false, "çıkış yolunun sonu dolu")
	return res


# ------------------------------------------------------------------ türevler

static func _tag(tags: Array[String], t: String) -> void:
	if not t in tags:
		tags.append(t)


static func _r1(v: float) -> float:
	return roundf(v * 10.0) / 10.0


## Kalıbın imzası: aynı türev iki kez gelmesin
static func signature(level: Dictionary) -> String:
	var parts: Array = []
	for p in level.pieces:
		parts.append("%.1f,%.1f,%.1f,%.1f,%.1f,%.1f" % [f(p, "x"), f(p, "w"), f(p, "z0"), f(p, "len"), h0(p), h1(p)])
	for o in level.obstacles:
		parts.append("%s,%.1f,%.1f,%.1f,%.1f,%.2f" % [o.get("kind", ""), f(o, "x"), f(o, "w"), f(o, "z0"), f(o, "len"), f(o, "rise")])
	return "|".join(parts)


## Bir kez çeşitle (physics.js varyOnce ile aynı işlemler)
static func vary_once(level: Dictionary, rng: RandomNumberGenerator, ops: Array) -> Dictionary:
	var lv: Dictionary = level.duplicate(true)
	lv.erase("variants")
	var tags: Array[String] = []
	var shift_from := func(z: float, d: float) -> void:
		var hosts := {}
		for o in lv.obstacles:
			hosts[o.id] = host_of(lv, o)
		var moved: Array = lv.pieces.filter(func(p): return f(p, "z0") >= z - 0.01)
		for p in moved:
			p["z0"] = _r1(f(p, "z0") + d)
		for o in lv.obstacles:
			var h = hosts[o.id]
			if (h != null and moved.any(func(m): return is_same(m, h))) or (h == null and f(o, "z0") >= z - 0.01):
				o["z0"] = _r1(f(o, "z0") + d)
	if "rise" in ops:
		for o in lv.obstacles:
			if o.get("kind", "") in ["ramp", "kick", "bump"]:
				o["rise"] = roundf(clampf(f(o, "rise", 1.6) * rng.randf_range(0.85, 1.15), 0.3, 4.0) * 20.0) / 20.0
				_tag(tags, "rampa yüksekliği")
	if "swap" in ops:
		for o in lv.obstacles:
			if o.get("kind", "") == "block" and f(o, "w") <= 3.0 and rng.randf() < 0.4:
				o.merge({"kind": "gravel", "w": 3.0, "z0": _r1(f(o, "z0") - 4.0), "len": 10.0}, true)
				_tag(tags, "çakıl ↔ blok")
			elif o.get("kind", "") == "gravel" and f(o, "w") <= 3.5 and rng.randf() < 0.4:
				o.merge({"kind": "block", "w": 2.0, "z0": _r1(f(o, "z0") + f(o, "len", 10.0) * 0.5), "len": 1.2}, true)
				_tag(tags, "çakıl ↔ blok")
	if "rows" in ops:
		for p in lv.pieces:
			var on: Array = lv.obstacles.filter(func(o): return not o.get("kind", "") in ["kick", "deadend"] and is_same(host_of(lv, o), p))
			on.sort_custom(func(a, b): return f(a, "z0") < f(b, "z0"))
			var kicks: Array = lv.obstacles.filter(func(k): return k.get("kind", "") == "kick" and is_same(host_of(lv, k), p))
			var seen: Array = []
			for o in on:
				if seen.any(func(s): return is_same(s, o)):
					continue
				var row: Array = on.filter(func(b): return absf(f(b, "z0") - f(o, "z0")) < 10.0)
				seen.append_array(row)
				# Eğik rampanın sırası taşınmaz (yan yola atar)
				if kicks.any(func(k): return absf(f(k, "z0") - f(o, "z0")) < 12.0):
					continue
				if rng.randf() < 0.5:
					for b in row:
						b["x"] = _r1(2.0 * f(p, "x") - f(b, "x"))
					_tag(tags, "engel düzeni")
				if rng.randf() < 0.5:
					var lo := -INF
					var hi := INF
					for b in row:
						lo = maxf(lo, f(p, "z0") + 1.0 - f(b, "z0"))
						hi = minf(hi, p_end(p) - 1.0 - f(b, "len", 1.0) - f(b, "z0"))
					var dz := roundf(minf(maxf(rng.randf_range(-8.0, 8.0), lo), hi))
					if dz != 0.0:
						for b in row:
							b["z0"] = _r1(f(b, "z0") + dz)
						_tag(tags, "engel düzeni")
	if "width" in ops:
		for p in lv.pieces:
			var nw := maxf(4.5, roundf(f(p, "w") * rng.randf_range(0.86, 1.14) * 2.0) / 2.0)
			if nw == f(p, "w"):
				continue
			for o in lv.obstacles.filter(func(q): return is_same(host_of(lv, q), p)):
				o["x"] = _r1(f(p, "x") + (f(o, "x") - f(p, "x")) * nw / f(p, "w"))
				if o.get("kind", "") in ["bump", "deadend"]:
					o["w"] = nw
			p["w"] = nw
			_tag(tags, "genişlik")
	if "len" in ops:
		var pp := main_path(lv)
		for i in range(pp.size() - 2, -1, -1):
			var p: Dictionary = pp[i]
			if successor(lv, p) != null:
				continue
			var ext := roundf(f(p, "len") * rng.randf_range(0.0, 0.15))
			if ext < 2.0:
				continue
			shift_from.call(p_end(p) + 0.01, ext)
			p["len"] = f(p, "len") + ext
			_tag(tags, "yollar uzun")
	if "gap" in ops:
		var pp := main_path(lv)
		for i in range(pp.size() - 2, -1, -1):
			var a: Dictionary = pp[i]
			var b: Dictionary = pp[i + 1]
			var g := f(b, "z0") - p_end(a)
			if g < 0.6 or successor(lv, a) != null:
				continue
			var d := roundf(g * (rng.randf_range(0.85, 1.15) - 1.0))
			if d != 0.0:
				shift_from.call(f(b, "z0"), d)
				_tag(tags, "boşluklar")
	return {"level": lv, "tags": tags}


## Geçerli bir türev (asıl kalıpta olmayan yeni hata yok, uyarı asıl kalıptan fazla değil, daha önce
## görülmemiş); yoksa {}.
## speed > 0 ise kontrol o hızda yapılır (kalıp oyunda tasarımdakinden hızlı gelebilir).
static func vary(level: Dictionary, rng: RandomNumberGenerator, seen: Dictionary, speed := 0.0, tries := 30) -> Dictionary:
	var check := func(l: Dictionary) -> Dictionary:
		if speed > speed_at(f(l, "at")):
			var c: Dictionary = l.duplicate()
			c["at"] = distance_for_speed(speed)
			return analyze(c)
		return analyze(l)
	var base: Dictionary = check.call(level)
	var base_warns: int = base.warns
	var base_errors: Array = base.issues.filter(func(t): return t.begins_with("hata: "))
	for t in tries:
		var ops: Array = VARY_OPS.filter(func(_op): return rng.randf() < 0.45)
		if ops.is_empty():
			ops.append(VARY_OPS[rng.randi() % VARY_OPS.size()])
		var res := vary_once(level, rng, ops)
		if res.tags.is_empty():
			continue
		var sig := signature(res.level)
		if seen.has(sig):
			continue
		var a: Dictionary = check.call(res.level)
		# Tasarımcının kalıbında olmayan yeni hata olmasın (kalıbın bilerek zor yerleri kalabilir)
		var new_error: bool = a.issues.any(func(t): return t.begins_with("hata: ") and not t in base_errors)
		if not new_error and a.warns <= base_warns:
			res["sig"] = sig
			return res
	return {}
