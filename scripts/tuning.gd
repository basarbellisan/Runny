extends CanvasLayer
## Gizli ayar paneli (autoload: Tuning).
## Sol üst köşeye arka arkaya üç kez dokununca (PC'de F1) açılır, oyun durur.
## Değişiklikler hemen uygulanır ve user://tuning.cfg'de saklanır.
## "Kopyala" yalnızca varsayılandan farklı değerleri metin olarak verir.

const SAVE_PATH := "user://tuning.cfg"
const CORNER := 120.0
## [grup, hedef, özellik (Vector2 için :x / :y), etiket, en az, en çok, adım]
const PARAMS := [
	["HIZ", "car", "start_speed", "Başlangıç hızı", 10, 40, 1],
	["HIZ", "car", "max_speed", "En yüksek hız", 30, 90, 1],
	["HIZ", "car", "late_acceleration", "Sonra hızlanma (m/s/sn)", 0, 0.5, 0.01],
	["HIZ", "car", "top_speed", "Tavan hız", 40, 120, 1],
	["HIZ", "car", "acceleration", "Zamanla hızlanma", 0, 1.5, 0.05],
	["DİREKSİYON", "car", "steer_speed", "Yana kayma hızı", 4, 25, 0.5],
	["DİREKSİYON", "car", "steer_accel", "Direksiyon tepkisi", 10, 200, 5],
	["DİREKSİYON", "car", "air_control", "Havada kontrol", 0, 1, 0.05],
	["DİREKSİYON", "car", "landing_assist", "İniş yardımı", 0, 20, 0.5],
	["DİREKSİYON", "car", "tip_pull", "Boşluğa yatma çekişi", 0, 40, 1],
	["DİREKSİYON", "car", "grip_loss", "Boştaki teker başına tutuş kaybı", 0, 0.5, 0.05],
	["GAZ", "car", "boost_rise_time", "Dolma süresi (sn)", 0.1, 2, 0.05],
	["GAZ", "car", "boost_fall_time", "Sönme süresi (sn)", 0.1, 3, 0.05],
	["GAZ", "car", "boost_bonus", "Hız artışı (oran)", 0.2, 2.5, 0.05],
	["GAZ", "car", "boost_max_extra", "En fazla ek hız", 5, 80, 1],
	["GAZ", "car", "boost_burn_time", "Bir basışta roket (sn)", 0.2, 3, 0.05],
	["GAZ", "car", "boost_squat_deg", "Gazda burun kalkması (°)", 0, 25, 0.5],
	["GAZ", "car", "boost_kick", "Ateşlemede burun vuruşu", 0, 8, 0.1],
	["GAZ", "car", "boost_recharge_time", "Basış arası dolma (sn)", 0.2, 5, 0.1],
	["ENERJİ", "car", "boost_energy_rate", "Roket enerji/sn", 5, 150, 1],
	["ENERJİ", "car", "max_energy", "Depo", 20, 300, 5],
	["ENERJİ", "roads", "crystal_value", "Kristal başına enerji", 1, 40, 0.5],
	["ENERJİ", "roads", "crystal_supply:x", "Kristal bolluğu (baş)", 0.5, 6, 0.1],
	["ENERJİ", "roads", "crystal_supply:y", "Kristal bolluğu (son)", 0.5, 6, 0.1],
	["ENERJİ", "roads", "crystal_easy_share:x", "Kolay yerde payı (baş)", 0, 1, 0.05],
	["ENERJİ", "roads", "crystal_easy_share:y", "Kolay yerde payı (son)", 0, 1, 0.05],
	["ENERJİ", "roads", "crystal_hard_at", "Kristal zorlaşma mesafesi (m)", 500, 20000, 250],
	["ENERJİ", "roads", "crystal_need_range:x", "Depo doluyken kristal katı", 0, 2, 0.05],
	["ENERJİ", "roads", "crystal_need_range:y", "Depo boşken kristal katı", 0, 4, 0.05],
	["ENERJİ", "roads", "crystal_spacing", "Kristal aralığı (m)", 3, 15, 0.5],
	["YOLLAR", "roads", "max_empty_time", "En uzun boş düzlük (sn)", 0.6, 4, 0.1],
	["YOLLAR", "roads", "fill_after_landing", "İnişten sonra ilk engel (sn)", 0.4, 3, 0.1],
	["ENERJİ", "game", "wing_reserve_time", "Kanat yedeği (sn)", 0, 30, 0.5],
	["GAZ", "car", "gravel_speed", "Çakılda hız oranı", 0.3, 1, 0.02],
	["GAZ", "car", "gravel_grip", "Çakılda tutuş", 0.05, 1, 0.05],
	["GAZ", "car", "gravel_shove", "Çakıl savurması", 0, 100, 1],
	["GAZ", "car", "gravel_speed_gain", "Çakıl etkisi hızla (kat)", 1, 3, 0.05],
	["GAZ", "car", "bump_launch", "Tümsek fırlatması", 0.5, 3, 0.05],
	["GAZ", "car", "bump_shake", "Tümsek sarsıntısı", 0, 8, 0.1],
	["GAZ", "car", "gravel_shove", "Çakılda savrulma", 0, 80, 1],
	["GAZ", "car", "gravel_after", "Çakıldan sonra sendeleme (sn)", 0, 2, 0.05],
	["HAVA & İNİŞ", "car", "air_lean_deg", "Havada direksiyonla yatma (°)", 0, 60, 1],
	["HAVA & İNİŞ", "car", "air_lean_time", "Yatmanın sönme süresi (sn)", 0.05, 1.5, 0.05],
	["HAVA & İNİŞ", "car", "air_self_level", "Havada kendiliğinden düzelme", 0, 3, 0.05],
	["HAVA & İNİŞ", "car", "clean_landing_deg", "Temiz iniş toleransı (°)", 2, 40, 1],
	["HAVA & İNİŞ", "car", "crash_landing_deg", "Patlatan iniş açısı (°)", 30, 180, 5],
	["HAVA & İNİŞ", "car", "hard_impact", "Sert iniş hızı (m/s)", 5, 50, 1],
	["HAVA & İNİŞ", "car", "tip_roll_accel", "Kenardan devrilme", 0, 30, 0.5],
	["HAVA & İNİŞ", "car", "nose_drop_accel", "Yol sonunda burun düşmesi", 0, 20, 0.5],
	["HAVA & İNİŞ", "car", "suspension_stiffness", "Süspansiyon sertliği", 30, 300, 5],
	["HAVA & İNİŞ", "car", "suspension_damping", "Süspansiyon sönümü", 1, 30, 0.5],
	["HAVA & İNİŞ", "car", "suspension_travel", "Teker sarkması (m)", 0.1, 0.8, 0.02],
	["ATLAMA", "car", "launch_velocity", "Kalkış zıplaması", 2, 16, 0.5],
	["ATLAMA", "car", "gravity", "Yerçekimi", 10, 60, 1],
	["ATLAMA", "roads", "gap_difficulty:x", "Boşluk: en kolay (0-1)", 0, 1, 0.05],
	["ATLAMA", "roads", "gap_difficulty:y", "Boşluk: en zor (0-1)", 0, 1, 0.05],
	["YOLLAR", "roads", "min_width:y", "Başta en dar", 2, 15, 0.5],
	["YOLLAR", "roads", "max_width:y", "Başta en geniş", 2, 20, 0.5],
	["YOLLAR", "roads", "min_width:x", "Sonda en dar", 1, 15, 0.5],
	["YOLLAR", "roads", "max_width:x", "Sonda en geniş", 2, 20, 0.5],
	["YOLLAR", "roads", "difficulty_distance", "Zorlaşma mesafesi (m)", 500, 10000, 100],
	["YOLLAR", "roads", "side_road_chance", "Yan yol şansı", 0, 1, 0.05],
	["YOLLAR", "roads", "action", "Aksiyon çarpanı (olay sıklığı)", 0.5, 4, 0.1],
	["YOLLAR", "roads", "slopes_from", "Eğim ve vadiler başlar (m)", 0, 5000, 100],
	["YOLLAR", "roads", "ramps_from", "Rampa ve merdiven başlar (m)", 0, 8000, 50],
	["YOLLAR", "roads", "advanced_from", "Çıkmaz ve çatal başlar (m)", 0, 8000, 50],
	["YOLLAR", "roads", "ease_distance", "Kalıplar tam zorluğa çıkar (m)", 100, 8000, 100],
	["YOLLAR", "roads", "dead_end_weight", "Çıkmaz sıklığı", 0, 2, 0.1],
	["YOLLAR", "roads", "max_slope_deg", "En dik eğim (°)", 2, 25, 1],
	["YOLLAR", "roads", "obstacles_from", "Engel ve çakıl başlar (m)", 0, 5000, 50],
	["YOLLAR", "roads", "banks_from", "Yatık yollar başlar (m)", 0, 5000, 50],
	["YOLLAR", "roads", "bank_weight", "Yatık yol sıklığı", 0, 3, 0.1],
	["YOLLAR", "roads", "max_bank_deg", "En fazla yatma (°)", 2, 20, 0.5],
	["YOLLAR", "car", "bank_slide", "Yatık yolda kayma", 0, 120, 1],
	["KAMERA", "camera", "bank_follow", "Yatık yolda kamera yatması", 0, 1, 0.05],
	["YOLLAR", "roads", "obstacle_chance", "Engelli yol olasılığı", 0, 1, 0.05],
	["YOLLAR", "roads", "fork_weight", "Çatal sıklığı", 0, 2, 0.1],
	["YOLLAR", "roads", "lights_time", "Pist ışıkları süresi (sn)", 0.3, 2, 0.05],
	["YOLLAR", "roads", "zone_length", "Renk bölgesi uzunluğu (m)", 200, 3000, 100],
	["UÇUŞ", "game", "energy_drain", "Enerji harcama (sn)", 1, 20, 0.5],
	["UÇUŞ", "game", "boost_drain_factor", "Yükselirken harcama katı", 1, 5, 0.1],
	["UÇUŞ", "car", "climb_height", "En fazla yükselme (m)", 2, 14, 0.5],
	["UÇUŞ", "car", "climb_speed", "Yükselme hızı", 2, 20, 0.5],
	["UÇUŞ", "lower", "high_rock_chance", "Yukarıdaki kaya şansı", 0, 1, 0.05],
	["UÇUŞ", "lower", "portal_interval:x", "Portal aralığı en az (sn)", 3, 30, 0.5],
	["UÇUŞ", "lower", "portal_interval:y", "Portal aralığı en çok (sn)", 3, 30, 0.5],
	["UÇUŞ", "lower", "rock_density:x", "Kaya sayısı / 100 m (başta)", 0, 40, 0.5],
	["UÇUŞ", "lower", "rock_density:y", "Kaya sayısı / 100 m (uzun kalınca)", 0, 40, 0.5],
	["UÇUŞ", "lower", "density_time", "Kaya yoğunluğu tavan süresi (sn)", 1, 120, 1],
	["UÇUŞ", "lower", "mid_rock_chance", "Ortadaki kaya şansı", 0, 1, 0.05],
	["UÇUŞ", "lower", "comet_interval:x", "Kuyruklu kaya en az (sn)", 0.5, 30, 0.5],
	["UÇUŞ", "lower", "comet_interval:y", "Kuyruklu kaya en çok (sn)", 0.5, 30, 0.5],
	["UÇUŞ", "lower", "comet_speed:x", "Kuyruklu kaya hızı en az", 0, 120, 1],
	["UÇUŞ", "lower", "comet_speed:y", "Kuyruklu kaya hızı en çok", 0, 120, 1],
	["UÇUŞ", "car", "flight_steer_accel", "Uçuş direksiyon tepkisi", 10, 150, 5],
	["PUAN", "game", "multiplier_step_time", "Çarpan artış süresi (sn)", 2, 30, 1],
	["PUAN", "game", "max_multiplier", "En yüksek çarpan", 1, 10, 1],
	["KAMERA", "camera", "offset:y", "Yükseklik", 2, 15, 0.5],
	["KAMERA", "camera", "offset:z", "Uzaklık", 4, 20, 0.5],
	["KAMERA", "camera", "base_fov", "Görüş açısı", 40, 90, 1],
	["KAMERA", "camera", "fov_per_speed", "Hızla açı artışı", 0, 1, 0.05],
	["KAMERA", "camera", "look_ahead", "İleri bakış", 5, 40, 1],
	["GÖRSEL", "trail", "style", "İz stili (1 ışık, 2 küp, 3 rüzgâr)", 1, 3, 1],
	["GÖRSEL", "speedo", "style", "Kadran stili (1-10)", 1, 10, 1],
	["GÖRSEL", "trail", "min_life", "İz boyu: gazsız (sn)", 0, 1, 0.02],
	["GÖRSEL", "trail", "max_life", "İz boyu: tam gaz (sn)", 0.1, 2, 0.05],
	["GÖRSEL", "trail", "boost_width", "İz genişliği: tam gaz (kat)", 1, 8, 0.1],
	["SES", "audio", "music_volume_db", "Müzik (dB)", -40, 0, 1],
	["SES", "audio", "engine_volume_db", "Motor (dB)", -40, 0, 1],
	["SES", "audio", "road_volume_db", "Yol (dB)", -40, 0, 1],
	["SES", "audio", "tire_volume_db", "Lastik (dB)", -40, 0, 1],
	["SES", "audio", "wind_volume_db", "Rüzgâr (dB)", -40, 0, 1],
	["SES", "audio", "plane_volume_db", "Uçak (dB)", -40, 0, 1],
	["SES", "audio", "climb_volume_db", "Yükselme (dB)", -40, 0, 1],
	["SES", "audio", "sfx_volume_db", "Efektler (dB)", -40, 6, 1],
]

var _targets := {}
var _defaults := {}    # anahtar -> koddaki varsayılan
var _overrides := {}   # anahtar -> kullanıcının değeri
var _sliders := {}     # anahtar -> HSlider
var _value_labels := {}
var _root: Control
var _taps := []
var _scroll: ScrollContainer
## Sağ kenardaki kaydırma şeridi (ayarlara yanlışlıkla dokunmadan kaydırmak için)
var _strip: Control
const STRIP_WIDTH := 84.0


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK and cfg.has_section("values"):
		for key in cfg.get_section_keys("values"):
			_overrides[key] = cfg.get_value("values", key)
	_build_ui()


## Oyun sahnesi her yüklendiğinde çağrılır: hedefleri kaydet, kayıtlı ayarları uygula
func register(targets: Dictionary) -> void:
	_targets = targets
	for p in PARAMS:
		var key := _key(p)
		if not _defaults.has(key):
			_defaults[key] = _read(p)
		if _overrides.has(key):
			_write(p, _overrides[key])


func _input(event: InputEvent) -> void:
	# Panel yalnızca oyun sırasında açılır (garajda değil)
	if not _targets.has("game") or not is_instance_valid(_targets.game):
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		_set_open(not _root.visible)
		return
	if _root.visible or not event is InputEventScreenTouch:
		return
	var pos: Vector2 = event.position
	if pos.x > CORNER or pos.y > CORNER:
		return
	# Köşe dokunuşları direksiyona gitmesin
	get_viewport().set_input_as_handled()
	if not event.pressed:
		return
	var now := Time.get_ticks_msec()
	_taps.append(now)
	_taps = _taps.filter(func(t): return now - t < 1500)
	if _taps.size() >= 3:
		_taps.clear()
		_set_open(true)


func _set_open(open: bool) -> void:
	_root.visible = open
	get_tree().paused = open
	if open:
		for p in PARAMS:
			var key := _key(p)
			_sliders[key].set_value_no_signal(_current(p))
			_update_label(p)
	elif _targets.has("car") and is_instance_valid(_targets.car):
		_targets.car.clear_touches()


func _on_slider(value: float, p: Array) -> void:
	var key := _key(p)
	if is_equal_approx(value, float(_defaults.get(key, value))):
		_overrides.erase(key)
	else:
		_overrides[key] = value
	_write(p, value)
	_update_label(p)
	_save()


func _reset_all() -> void:
	_overrides.clear()
	for p in PARAMS:
		var key := _key(p)
		if _defaults.has(key):
			_write(p, _defaults[key])
			_sliders[key].set_value_no_signal(float(_defaults[key]))
		_update_label(p)
	_save()


func _restart() -> void:
	_set_open(false)
	get_tree().reload_current_scene()


func _copy() -> void:
	var parts: Array[String] = []
	for p in PARAMS:
		var key := _key(p)
		if _overrides.has(key):
			parts.append("%s=%s" % [key, _fmt(_overrides[key], p[6])])
	var text := "AYARLAR " + ("; ".join(parts) if parts else "(değişiklik yok)")
	DisplayServer.clipboard_set(text)
	if OS.has_feature("web"):
		# iOS Safari panoya yazmayı engelleyebilir; seçilip kopyalanabilen bir kutu da göster
		JavaScriptBridge.eval("window.prompt('Bu metni kopyalayıp gönder:', %s)" % JSON.stringify(text))


func _save() -> void:
	var cfg := ConfigFile.new()
	for key in _overrides:
		cfg.set_value("values", key, _overrides[key])
	cfg.save(SAVE_PATH)


# --- Hedef özellikleri okuma / yazma ---

func _key(p: Array) -> String:
	return "%s.%s" % [p[1], p[2]]


func _read(p: Array) -> float:
	var target: Object = _targets.get(p[1])
	if target == null:
		return float(p[4])
	var parts: PackedStringArray = p[2].split(":")
	var v = target.get(parts[0])
	if parts.size() > 1:
		v = v[parts[1]]
	return float(v)


func _write(p: Array, value: float) -> void:
	var target: Object = _targets.get(p[1])
	if target == null or not is_instance_valid(target):
		return
	var parts: PackedStringArray = p[2].split(":")
	if parts.size() > 1:
		var vec = target.get(parts[0])
		vec[parts[1]] = value
		target.set(parts[0], vec)
	elif typeof(target.get(parts[0])) == TYPE_INT:
		target.set(parts[0], int(round(value)))
	else:
		target.set(parts[0], value)


func _current(p: Array) -> float:
	var key := _key(p)
	return float(_overrides.get(key, _defaults.get(key, p[4])))


func _fmt(v: float, step: float) -> String:
	return str(int(round(v))) if step >= 1 else ("%.2f" % v).rstrip("0").rstrip(".")


func _update_label(p: Array) -> void:
	var key := _key(p)
	var changed := _overrides.has(key)
	var l: Label = _value_labels[key]
	l.text = _fmt(_current(p), p[6])
	l.add_theme_color_override("font_color", Palette.ACCENT if changed else Palette.INK_LIGHT)


# --- Arayüz ---

## Şeridin içindeki tutamak: listenin görünen kısmı (y, yükseklik)
func _thumb() -> Vector2:
	var bar := _scroll.get_v_scroll_bar()
	var total := maxf(bar.max_value, 1.0)
	var h := _strip.size.y
	var th := clampf(h * bar.page / total, 60.0, h)
	var range_ := maxf(bar.max_value - bar.page, 1.0)
	return Vector2((h - th) * bar.value / range_, th)


func _draw_strip() -> void:
	var w := _strip.size.x
	_strip.draw_rect(Rect2(Vector2(w * 0.5 - 3, 0), Vector2(6, _strip.size.y)), Color(Palette.INK_LIGHT, 0.12))
	var t := _thumb()
	_strip.draw_rect(Rect2(Vector2(w * 0.5 - 14, t.x), Vector2(28, t.y)), Color(Palette.ACCENT, 0.85))


## Şeritte sürükle: tutamak parmağı izler (aşağı çek = listede aşağı in)
func _on_strip_input(event: InputEvent) -> void:
	var dy := 0.0
	# Dokunma, fare olayına da çevrilir (emulate_mouse_from_touch): yalnız fareyi dinle ki iki kez kaymasın
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		dy = event.relative.y
	if dy == 0.0:
		return
	var bar := _scroll.get_v_scroll_bar()
	var t := _thumb()
	var travel := maxf(_strip.size.y - t.y, 1.0)
	bar.value = clampf(bar.value + dy * (bar.max_value - bar.page) / travel, 0.0, bar.max_value - bar.page)
	_strip.accept_event()

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color(Palette.GRAPHITE, 0.96)
	_root.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	_root.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 60)
	margin.add_theme_constant_override("margin_bottom", 40)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	margin.add_child(col)

	col.add_child(_text("AYARLAR", 34, Palette.INK_LIGHT))
	# Liste solda, sağda parmak genişliğinde kaydırma şeridi
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	col.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	body.add_child(scroll)
	_scroll = scroll
	_strip = Control.new()
	_strip.custom_minimum_size.x = STRIP_WIDTH
	_strip.mouse_filter = Control.MOUSE_FILTER_STOP
	_strip.draw.connect(_draw_strip)
	_strip.gui_input.connect(_on_strip_input)
	body.add_child(_strip)
	scroll.get_v_scroll_bar().value_changed.connect(func(_v): _strip.queue_redraw())
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	var group := ""
	for p in PARAMS:
		if p[0] != group:
			group = p[0]
			var header := _text(group, 22, Palette.ACCENT)
			header.custom_minimum_size.y = 56
			header.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			list.add_child(header)
		var row := HBoxContainer.new()
		var name_label := _text(p[3], 22, Palette.INK_LIGHT)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(name_label)
		var value_label := _text("", 22, Palette.INK_LIGHT)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_label)
		list.add_child(row)
		var slider := HSlider.new()
		slider.min_value = p[4]
		slider.max_value = p[5]
		slider.step = p[6]
		slider.custom_minimum_size.y = 48
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(_on_slider.bind(p))
		list.add_child(slider)
		_sliders[_key(p)] = slider
		_value_labels[_key(p)] = value_label

	var buttons := GridContainer.new()
	buttons.columns = 2
	buttons.add_theme_constant_override("h_separation", 12)
	buttons.add_theme_constant_override("v_separation", 12)
	col.add_child(buttons)
	for b in [["KAPAT", _set_open.bind(false)], ["YENİDEN BAŞLAT", _restart],
			["VARSAYILANA DÖN", _reset_all], ["KOPYALA", _copy]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.custom_minimum_size = Vector2(0, 72)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 22)
		btn.pressed.connect(b[1])
		buttons.add_child(btn)


func _text(t: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
