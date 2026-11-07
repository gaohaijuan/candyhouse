extends Control
## The whole game: owns the save, wallet, sound, ads and purchases, and swaps
## pages (splash, home, map, shop, game). Pages and popups only ask the app.

signal wallet_changed

const Profile = preload("res://scripts/meta/profile.gd")
const Sound = preload("res://scripts/game/sound.gd")
const AdService = preload("res://scripts/services/ad_service.gd")
const PurchaseService = preload("res://scripts/services/purchase_service.gd")
const Popups = preload("res://scripts/ui/popups.gd")
const Art = preload("res://scripts/game/art.gd")
const PAGES := {
	"splash": preload("res://scripts/ui/pages/splash.gd"),
	"home": preload("res://scripts/ui/pages/home.gd"),
	"map": preload("res://scripts/ui/pages/map.gd"),
	"shop": preload("res://scripts/ui/pages/shop.gd"),
	"game": preload("res://scripts/ui/pages/game_page.gd"),
}

var economy: Dictionary
var levels: Array
var profile: Profile
var sound: Node
var ads: Node
var iap: Node
var popups: Popups
var page: Control
var page_name := ""
var popup_layer: Control
var clock_offset := 0          # debug: shift time to test lives and check-in
var debug_args := {}
var capture_dir := ""
var capture_clock := 0.0
var capture_index := 0
var last_lives := -1
var unlock_all := false

func _ready() -> void:
	size = Vector2(1080, 1920)
	var app_theme := Theme.new()
	app_theme.default_font = Art.font
	app_theme.default_font_size = 40
	theme = app_theme
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.trim_prefix("--").split("=", true, 1)
		debug_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	capture_dir = debug_args.get("capture", "")
	if capture_dir != "":
		DirAccess.make_dir_recursive_absolute(capture_dir)
	economy = JSON.parse_string(FileAccess.get_file_as_string("res://data/economy.json"))
	levels = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels.json")).levels
	var save_path: String = debug_args.get("profile", Profile.SAVE_PATH)
	profile = Profile.new(economy, save_path)
	if debug_args.has("fresh") and FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	profile.load_or_create(now())
	# Test builds may open every level on the map without touching progress.
	unlock_all = debug_args.has("unlock_all") or _build_flag("unlock_all")
	sound = Sound.new()
	add_child(sound)
	apply_settings()
	ads = AdService.new()
	add_child(ads)
	iap = PurchaseService.new()
	add_child(iap)
	popups = Popups.new(self)
	popup_layer = Control.new()
	popup_layer.size = size
	popup_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(popup_layer)
	ads.overlay_parent = self
	if debug_args.has("level"):
		goto("game", {"level": int(debug_args.level) - 1})
	elif debug_args.has("page"):
		goto(debug_args.page)
	else:
		goto("splash")
	if debug_args.has("open"):
		get_tree().create_timer(1.2).timeout.connect(func(): popups.debug_open(debug_args.open))

func _build_flag(name: String) -> bool:
	if not FileAccess.file_exists("res://data/build.json"):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/build.json"))
	return d is Dictionary and bool(d.get(name, false))

func now() -> int:
	return int(Time.get_unix_time_from_system()) + clock_offset

func apply_settings() -> void:
	var st: Dictionary = profile.data.settings
	sound.set_music(bool(st.music))
	sound.set_effects(bool(st.sfx))
	sound.vibrate_on = bool(st.vibrate)
	sound.start_music()

## Persist and tell every widget the wallet may have changed.
func save() -> void:
	profile.save()
	wallet_changed.emit()

func goto(name: String, args := {}) -> void:
	popups.close_all()
	if page:
		page.queue_free()
	page_name = name
	page = Control.new()
	page.set_script(PAGES[name])
	page.size = size
	add_child(page)
	move_child(page, popup_layer.get_index())
	page.call("setup", self, args)

func level_def(index: int) -> Dictionary:
	return levels[clampi(index, 0, levels.size() - 1)]

func current_level_index() -> int:
	return clampi(int(profile.data.unlocked) - 1, 0, levels.size() - 1)

## "normal", "hard" or "super" from the authored difficulty.
func difficulty(index: int) -> String:
	var r: float = float(level_def(index).get("target_rating", 5.0))
	return "super" if r >= 7.75 else ("hard" if r >= 6.75 else "normal")

## Short message that floats up and fades.
func toast(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 48)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color("#9C3219"))
	l.add_theme_constant_override("outline_size", 12)
	l.size = Vector2(1080, 100)
	l.position = Vector2(0, 1500)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", 1380.0, 0.9).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.6)
	tw.tween_callback(l.queue_free)

func _process(delta: float) -> void:
	var lives := profile.lives(now())
	if lives != last_lives:
		last_lives = lives
		wallet_changed.emit()
	if capture_dir != "":
		capture_clock += delta
		if capture_clock >= 0.1:
			capture_clock = 0.0
			get_viewport().get_texture().get_image().save_png("%s/frame_%04d.png" % [capture_dir, capture_index])
			capture_index += 1
