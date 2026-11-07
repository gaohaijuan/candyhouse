extends Control
## Coin and life pills shown at the top of the home, map and shop pages.
## Tapping "+" on coins opens the shop; on lives, the lives popup.

const Kit = preload("res://scripts/ui/kit.gd")

var app
var coin_label: Label
var life_label: Label
var timer_label: Label
var show_lives := true

func setup(owner_app, with_lives := true) -> void:
	app = owner_app
	show_lives = with_lives
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Rects measured from the home mockup (M3_B).
	coin_label = _pill(Rect2(46, 54, 393, 117), Rect2(170, 80, 186, 66), "coin_pill", "金", Color("#F5B82E"), func(): app.goto("shop"))
	if show_lives:
		life_label = _pill(Rect2(473, 54, 364, 117), Rect2(600, 80, 120, 66), "life_pill", "♥", Color("#F06292"), func(): app.popups.lives())
		timer_label = Kit.label("", 32, Color.WHITE, Color("#9C3219"), 8)
		timer_label.position = Vector2(473, 166)
		timer_label.size = Vector2(364, 42)
		add_child(timer_label)
	app.wallet_changed.connect(refresh)
	refresh()

func _pill(rect: Rect2, text_rect: Rect2, art: String, glyph: String, color: Color, on_plus: Callable) -> Label:
	var at := rect.position
	var w := rect.size.x
	var h := rect.size.y
	var bg := Kit.picture(art, rect.size)
	if not Kit.tex(art):
		bg.queue_free()
		bg = Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#FFF4DE"); sb.border_color = Color("#E9B98F")
		sb.set_border_width_all(4); sb.set_corner_radius_all(int(h / 2))
		bg.add_theme_stylebox_override("panel", sb)
		bg.size = Vector2(w, h)
		var icon := Kit.label(glyph, 48, color, Color.WHITE, 6)
		icon.size = Vector2(h, h)
		bg.add_child(icon)
		var plus := Kit.label("+", 52, Color("#4CAF50"), Color.WHITE, 6)
		plus.position = Vector2(w - h, 0)
		plus.size = Vector2(h, h)
		bg.add_child(plus)
	bg.position = at
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var value := Kit.label("", 54, Kit.BROWN)
	value.position = text_rect.position
	value.size = text_rect.size
	add_child(value)
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.position = at
	hit.size = Vector2(w, h)
	hit.pressed.connect(on_plus)
	add_child(hit)
	return value

func refresh() -> void:
	if not is_instance_valid(coin_label):
		return
	coin_label.text = str(app.profile.data.coins)
	if show_lives:
		var t: int = app.now()
		life_label.text = str(app.profile.lives(t))
		var wait: int = app.profile.next_life_in(t)
		timer_label.text = "" if wait <= 0 else "%02d:%02d" % [wait / 60, wait % 60]

func _process(_delta: float) -> void:
	if show_lives and Engine.get_process_frames() % 30 == 0:
		refresh()
