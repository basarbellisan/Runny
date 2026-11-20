extends Control
## Açılış introsu (OLLO, intro/ollo-intro.ogv; dikey, koyu zemin #0F0E11, ~2 sn): oyun ilk açılınca bir kez
## oynar, sonra kâğıt rengine yumuşakça geçip giriş sayfasına (garaj sahnesi) gider. Dokunmak ya da bir tuş
## introyu atlar. Video ekranı esnetmez: genişliğe sığar, üst ve alt boşluk zemin rengiyle dolar.
## Testler (otomatik pilot, ekran görüntüsü), bölüm tasarımcısından açılış (?level=) ve --nointro introyu atlar.

const NEXT_SCENE := "res://scenes/menu.tscn"
const BG := Color("0f0e11")
## Video bitince son karede bu kadar kalır, sonra kâğıt rengine geçer (sn)
const HOLD := 0.25
const FADE := 0.4

var _video: VideoStreamPlayer
var _fade: ColorRect
var _done := false


func _ready() -> void:
	if _skip_intro():
		get_tree().change_scene_to_file.call_deferred(NEXT_SCENE)
		return
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := AspectRatioContainer.new()
	box.ratio = 1080.0 / 1920.0
	box.stretch_mode = AspectRatioContainer.STRETCH_FIT
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	_video = VideoStreamPlayer.new()
	_video.stream = load("res://intro/ollo-intro.ogv")
	_video.expand = true
	box.add_child(_video)
	_fade = ColorRect.new()
	_fade.color = Palette.PAPER
	_fade.modulate.a = 0.0
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)
	_video.finished.connect(_finish)
	_video.play()


func _unhandled_input(event: InputEvent) -> void:
	if (event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch \
			or event is InputEventJoypadButton) and event.is_pressed():
		_finish(true)


## Son karede kısa bekleme, kâğıt rengine geçiş, giriş sayfası (atlanınca beklemeden)
func _finish(skipped := false) -> void:
	if _done:
		return
	_done = true
	var t := create_tween()
	if not skipped:
		t.tween_interval(HOLD)
	t.tween_property(_fade, "modulate:a", 1.0, FADE * (0.5 if skipped else 1.0))
	t.tween_callback(get_tree().change_scene_to_file.bind(NEXT_SCENE))


func _skip_intro() -> bool:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a == "--autopilot" or a == "--nointro" or a.begins_with("--shots") or a.begins_with("--car=") \
				or a.begins_with("--lesson") or a.begins_with("--level"):
			return true
	if OS.has_feature("web"):
		var r: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('level') || ''")
		if r != null and str(r) != "":
			return true
	return false
