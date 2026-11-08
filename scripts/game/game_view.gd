extends Control
## Game page: builds the HUD, board, tray and boosters, turns taps into rule
## calls on GameState and animates the result. Rules never live here.

const GameState = preload("res://scripts/core/game_state.gd")
const TileView = preload("res://scripts/game/tile_view.gd")
const Kit = preload("res://scripts/ui/kit.gd")
const Art = preload("res://scripts/game/art.gd")
const PulseRing = preload("res://scripts/game/pulse_ring.gd")
const Sound = preload("res://scripts/game/sound.gd")

const FLY_TIME := 0.28
const REFLOW_TIME := 0.15
const MERGE_GATHER := 0.12
const MERGE_VANISH := 0.2
const DIM_TIME := 0.15
const COMBO_WINDOW := 3.0

var layout: Dictionary
var levels: Array
var level_index := 0
var state: GameState
var views: Dictionary = {}          # tile id -> TileView
var display_tray: Array = []        # ids shown in the tray, incl. tiles mid-merge
var tile_px := 120.0
var board_origin := Vector2.ZERO
var board_layer: Control
var fly_layer: Control
var hud: Dictionary = {}
var booster_buttons: Dictionary = {}
var popup: Control
var hand: Control
var app = null                  # set by the app shell; null when run on its own
var start_boosters := {}
var revived := false
var sound: Node
var box_nodes: Array = []
var box_badges: Array = []
var combo := 0
var last_match_time := -100.0
var tutorial_picks := 0
var busy_until := 0.0
var magnet_armed := false     # magnet chosen: the next dessert tapped is pulled
var debug_demo := ""

# Debug capture: --autoplay plays the known solution, --capture=<dir> saves frames.
var autoplay := false
var debug_open := ""
var debug_press_first := false  # debug: auto-press a popup's first button
var level_from_args := false
var autoplay_random := false
var capture_dir := ""
var capture_every := 0.1
var capture_clock := 0.0
var capture_index := 0
var autoplay_clock := 0.0

func _ready() -> void:
	layout = JSON.parse_string(FileAccess.get_file_as_string("res://data/layout.json"))
	levels = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels.json")).levels
	var app_theme := Theme.new()
	app_theme.default_font = Art.font
	app_theme.default_font_size = 40
	theme = app_theme
	size = Vector2(1080, 1920)
	for arg in OS.get_cmdline_user_args():
		if arg == "--autoplay":
			autoplay = true
		elif arg == "--autoplay=random":
			autoplay = true
			autoplay_random = true
		elif arg.begins_with("--capture="):
			capture_dir = arg.substr(10)
			DirAccess.make_dir_recursive_absolute(capture_dir)
		elif arg == "--press-first":
			debug_press_first = true
		elif arg.begins_with("--demo="):
			debug_demo = arg.substr(7)
		elif arg.begins_with("--open="):
			debug_open = arg.substr(7)
		elif arg.begins_with("--level="):
			level_index = clampi(int(arg.substr(8)) - 1, 0, levels.size() - 1)
			level_from_args = true
	if layout.has("tile_face_box"):
		var fb: Array = layout.tile_face_box
		var vb: Array = layout.tile_visible_box
		TileView.face_box = Rect2(fb[0], fb[1], fb[2], fb[3])
		TileView.visible_box = Rect2(vb[0], vb[1], vb[2], vb[3])
		TileView.face_fill = layout.get("tile_face_fill", 0.97)
	if layout.has("cover_multiply"):
		var m: Array = layout.cover_multiply
		TileView.cover_multiply = Color(m[0], m[1], m[2])
	if app:
		sound = app.sound
		capture_dir = ""
	else:
		sound = Sound.new()
		add_child(sound)
		sound.set_enabled(bool(_load_progress().get("sound", true)))
		sound.start_music()
	_build_static()
	if not level_from_args and app == null:
		level_index = clampi(int(_load_progress().get("unlocked", 1)) - 1, 0, levels.size() - 1)
	if app:
		app.wallet_changed.connect(_refresh_hud)
	start_level(level_index)
	if debug_open != "":
		get_tree().create_timer(1.4).timeout.connect(_debug_open_popup)

func _debug_open_popup() -> void:
	_close_popup()
	if debug_open == "pause":
		_on_pause()
	elif debug_open == "levels":
		_open_level_select()
	elif debug_open == "win":
		_show_win()
	elif debug_open == "lose":
		_show_lose()

func _blocked() -> bool:
	return popup != null or (app != null and app.popups.is_open())

func _rect(key: String) -> Rect2:
	var r: Array = layout[key]
	return Rect2(r[0], r[1] + _band(key), r[2], r[3])

## Tall screens: the HUD goes up to the screen top and the boosters down to the
## bottom; the board and the tray move by a share, so the gaps grow evenly and
## the playing area stays in the middle.
const BANDS := {"pause_button": 0.0, "level_plaque": 0.0, "coin_pill": 0.0, "progress_bar": 0.0,
	"board": 0.4, "hold_row": 0.6, "tray": 0.6, "boosters": 1.0}

func _band(key: String) -> float:
	return Kit.band_shift(BANDS[key]) if BANDS.has(key) else 0.0

# ---------------------------------------------------------------- building

func _build_static() -> void:
	var bg_tex := Art.ui("background")
	if bg_tex:
		var bg := TextureRect.new()
		bg.texture = bg_tex
		bg.position = Vector2(0, -Kit.extra)
		bg.size = Vector2(size.x, size.y + 2 * Kit.extra)
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
	else:
		var bg := ColorRect.new()
		bg.color = Color("#FCEFF3")
		bg.size = size
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)

	if Art.ui("button_pause"):
		hud.pause = _texture_button(_rect("pause_button"), Art.ui("button_pause"), null)
	else:
		hud.pause = _round_button(_rect("pause_button"), "Ⅱ", Color("#F48FB1"))
	hud.pause.pressed.connect(_on_pause)
	if Art.ui("ribbon_level"):
		hud.level = _textured_label(_rect("level_plaque"), Art.ui("ribbon_level"), _text_style("level_text"), layout.get("ribbon_text_box", []))
	else:
		hud.level = _plaque(_rect("level_plaque"), Color("#F48FB1"), Color.WHITE, 52)
	if Art.ui("coin_pill"):
		hud.coins = _textured_label(_rect("coin_pill"), Art.ui("coin_pill"), _text_style("coin_text"), layout.get("coin_text_box", []))
		hud.coins.get_child(0).text = "1280"
	else:
		hud.coins = _plaque(_rect("coin_pill"), Color("#FFF6E6"), Color("#7A4A32"), 40)
		hud.coins.get_child(0).text = "● 1280"
	var bar_rect := _rect("progress_bar")
	if Art.ui("progress_bg") and Art.ui("progress_fill"):
		var bg_rect := _fit_rect(bar_rect, Art.ui("progress_bg"))
		_texture_rect(bg_rect, Art.ui("progress_bg"))
		hud.bar_inner = _progress_inner(bg_rect)
		var fill := NinePatchRect.new()
		fill.texture = Art.ui("progress_fill")
		var vis: Array = layout.progress_fill_visible
		var cap := float(vis[3]) / 2.0
		fill.patch_margin_left = int(vis[0] + cap)
		fill.patch_margin_right = int(Art.ui("progress_fill").get_width() - vis[0] - vis[2] + cap)
		# Scale the whole strip uniformly so the round caps stay round.
		var k: float = (hud.bar_inner.size.y - 2.0) / float(vis[3])
		fill.scale = Vector2(k, k)
		fill.position = Vector2(hud.bar_inner.position.x - float(vis[0]) * k, hud.bar_inner.position.y + 1.0 - float(vis[1]) * k)
		fill.size = Vector2(0, Art.ui("progress_fill").get_height())
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fill.visible = false
		add_child(fill)
		hud.bar_fill = fill
	else:
		hud.bar_bg = _panel(bar_rect, Color("#FFF6E6"), Color("#E9B98F"), int(bar_rect.size.y / 2))
		hud.bar_fill = _panel(Rect2(bar_rect.position + Vector2(4, 4), Vector2(0, bar_rect.size.y - 8)), Color("#F48FB1"), Color.TRANSPARENT, int(bar_rect.size.y / 2))
	hud.stars = []
	for i in 3:
		var star: Control
		var star_size: float = layout.get("star_size", 64)
		var star_x: float = layout.stars_x[i] if layout.has("stars_x") else bar_rect.position.x + bar_rect.size.x * (i + 1) / 3.0
		var at := Vector2(star_x, bar_rect.position.y + bar_rect.size.y / 2) - Vector2.ONE * star_size / 2
		if Art.ui("star"):
			star = _texture_rect(Rect2(at, Vector2.ONE * star_size), Art.ui("star_off") if Art.ui("star_off") else Art.ui("star"))
			star.pivot_offset = star.size / 2
			if not Art.ui("star_off"):
				star.material = _unlit_star_material()
		else:
			var l := Label.new()
			l.text = "★"
			l.add_theme_font_size_override("font_size", 52)
			l.position = at
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(l)
			star = l
		hud.stars.append(star)

	var hold_rect := _rect("hold_row")
	hud.hold = _build_hold_row(hold_rect)
	hud.hold.modulate.a = 0.0
	var tray_rect := _rect("tray")
	if Art.ui("tray"):
		hud.tray = _texture_rect(_tray_texture_rect(), Art.ui("tray"))
	else:
		hud.tray = _panel(tray_rect, Color("#F7E3CC"), Color("#D9A57A"), 40)
	for i in (0 if Art.ui("tray") else GameState.TRAY_SIZE):
		var slot := _panel(Rect2(_tray_slot(i) - Vector2.ONE * layout.tray_slot / 2, Vector2.ONE * layout.tray_slot), Color("#EBCDAE"), Color.TRANSPARENT, 24)
		slot.modulate.a = 0.7

	for i in 4:
		var key: String = ["undo", "move_out", "shuffle", "magnet"][i]
		var label: String = ["撤回", "移出", "洗牌", "磁铁"][i]
		var glyph: String = ["↶", "⇪", "⟲", "U"][i]
		var c := Vector2(layout.booster_x[mini(i, 2)], layout.boosters_y + _band("boosters"))
		var side: float = layout.booster_size
		var b: BaseButton
		var disc := Art.ui("button_round_green" if key == "move_out" or key == "magnet" else "button_round_pink")
		var b_rect := Rect2(c - Vector2(side, side) / 2, Vector2(side, side))
		if disc:
			b = _texture_button(b_rect, disc, Art.ui("icon_" + key))
		else:
			b = _round_button(b_rect, glyph, Color("#7CC8B4"))
		b.pressed.connect(_on_booster.bind(key))
		var badge_side: float = layout.get("badge_size", 56)
		var badge_at := c + Vector2(side * 0.22, -side * 0.55)
		var badge: Control
		if Art.ui("badge"):
			badge = _textured_label(Rect2(badge_at, Vector2.ONE * badge_side), Art.ui("badge"), _text_style("badge_text"))
		else:
			badge = _plaque(Rect2(badge_at, Vector2(56, 56)), Color("#E5484D"), Color.WHITE, 34)
		var name_label := Label.new()
		name_label.text = label
		_apply_text_style(name_label, _text_style("booster_text"))
		name_label.size = Vector2(200, 50)
		name_label.position = c + Vector2(-100, side / 2 + 4)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(name_label)
		booster_buttons[key] = {"button": b, "badge": badge, "label": name_label, "badge_at": badge_at - c, "label_at": name_label.position - c}

	board_layer = Control.new()
	board_layer.size = size
	board_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(board_layer)
	fly_layer = Control.new()
	fly_layer.size = size
	fly_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fly_layer)

func _panel(rect: Rect2, fill: Color, border: Color, radius: int) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(4 if border.a > 0 else 0)
	sb.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel", sb)
	p.position = rect.position
	p.size = rect.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)
	return p

func _plaque(rect: Rect2, fill: Color, text_color: Color, font_size: int) -> Panel:
	var p := _panel(rect, fill, Color("#E9B98F") if fill.v > 0.9 else Color.TRANSPARENT, int(rect.size.y / 2))
	var l := Label.new()
	l.size = rect.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", text_color)
	p.add_child(l)
	return p

func _round_button(rect: Rect2, glyph: String, ring: Color) -> Button:
	var b := Button.new()
	b.position = rect.position
	b.size = rect.size
	b.text = glyph
	b.add_theme_font_size_override("font_size", int(rect.size.y * 0.42))
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#FFF9F0") if state_name != "pressed" else Color("#F3E4D2")
		sb.border_color = ring
		sb.set_border_width_all(8)
		sb.set_corner_radius_all(int(rect.size.x / 2))
		sb.shadow_color = Color(0.5, 0.3, 0.2, 0.3)
		sb.shadow_size = 6
		sb.shadow_offset = Vector2(0, 6)
		if state_name == "focus":
			sb.draw_center = false
			sb.set_border_width_all(0)
			sb.shadow_size = 0
		b.add_theme_stylebox_override(state_name, sb)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, Color("#7A4A32"))
	b.add_theme_color_override("font_disabled_color", Color("#7A4A32", 0.4))
	b.focus_mode = Control.FOCUS_NONE
	add_child(b)
	return b

func _texture_rect(rect: Rect2, tex: Texture2D) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.position = rect.position
	t.size = rect.size
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(t)
	return t

## Largest rect with the texture's aspect that fits inside `rect`, centred.
func _fit_rect(rect: Rect2, tex: Texture2D) -> Rect2:
	var aspect := float(tex.get_width()) / tex.get_height()
	var sz := rect.size
	if sz.x / sz.y > aspect:
		sz.x = sz.y * aspect
	else:
		sz.y = sz.x / aspect
	return Rect2(rect.position + (rect.size - sz) / 2, sz)

## `text_box` is [x, y, w, h] in the texture's own pixels (measured from the art);
## the label is centred inside it so the words sit on the art, not on the canvas.
func _textured_label(rect: Rect2, tex: Texture2D, style: Dictionary, text_box: Array = []) -> TextureRect:
	var fitted := _fit_rect(rect, tex)
	var t := _texture_rect(fitted, tex)
	var l := Label.new()
	var k := fitted.size.x / tex.get_width()
	if text_box.size() == 4:
		l.position = Vector2(text_box[0], text_box[1]) * k
		l.size = Vector2(text_box[2], text_box[3]) * k
	else:
		l.size = fitted.size
	l.position += Vector2(style.get("offset_x", 0.0), style.get("offset_y", 0.0))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_text_style(l, style)
	t.add_child(l)
	return t

func _texture_button(rect: Rect2, base: Texture2D, icon: Texture2D) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = base
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.position = rect.position
	b.size = rect.size
	b.pivot_offset = rect.size / 2
	b.focus_mode = Control.FOCUS_NONE
	b.button_down.connect(func(): create_tween().tween_property(b, "scale", Vector2(0.92, 0.92), 0.06))
	b.button_up.connect(func(): create_tween().tween_property(b, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_BACK))
	if icon:
		var ic := TextureRect.new()
		ic.texture = icon
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var pad := rect.size * 0.2
		ic.position = pad
		ic.size = rect.size - pad * 2
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(ic)
	add_child(b)
	return b

## Text styles come from layout.json ("text_styles"), measured from the approved mockup.
func _text_style(key: String) -> Dictionary:
	var defaults := {
		"level_text": {"size": 56, "color": "#FFFFFF", "outline": "#E05A87", "outline_size": 10},
		"coin_text": {"size": 44, "color": "#7A4A32", "outline": "#FFFFFF", "outline_size": 0},
		"badge_text": {"size": 36, "color": "#FFFFFF", "outline": "#B8323A", "outline_size": 0},
		"booster_text": {"size": 44, "color": "#6B3A26", "outline": "#FFFFFF", "outline_size": 10},
		"box_count_text": {"size": 40, "color": "#FFFFFF", "outline": "#9C1F1F", "outline_size": 8},
	}
	var styles: Dictionary = layout.get("text_styles", {})
	var out: Dictionary = defaults.get(key, {}).duplicate()
	out.merge(styles.get(key, {}), true)
	return out

func _apply_text_style(l: Label, style: Dictionary) -> void:
	l.add_theme_font_size_override("font_size", int(style.get("size", 40)))
	l.add_theme_color_override("font_color", Color(style.get("color", "#7A4A32")))
	if int(style.get("outline_size", 0)) > 0:
		l.add_theme_color_override("font_outline_color", Color(style.get("outline", "#FFFFFF")))
		l.add_theme_constant_override("outline_size", int(style.outline_size))
	if style.has("shadow"):
		l.add_theme_color_override("font_shadow_color", Color(style.shadow))
		l.add_theme_constant_override("shadow_offset_x", int(style.get("shadow_x", 0)))
		l.add_theme_constant_override("shadow_offset_y", int(style.get("shadow_y", 4)))
		l.add_theme_constant_override("shadow_outline_size", int(style.get("shadow_outline", style.get("outline_size", 0))))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE

# ---------------------------------------------------------------- level

func start_level(index: int) -> void:
	level_index = index
	state = GameState.new(levels[index])
	revived = false
	if app:
		# In the full game boosters come from the player's inventory.
		state.boosters = {"undo": 9999, "move_out": 9999, "shuffle": 9999, "magnet": 1 if start_boosters.get("magnet", false) else 0}
		if start_boosters.get("extra_slot", false):
			state.tray_size = GameState.TRAY_SIZE + 1
	_apply_tray_art()
	_place_boosters()
	_arm_magnet(false)
	for v in views.values():
		v.queue_free()
	views.clear()
	display_tray.clear()
	combo = 0
	tutorial_picks = 0
	if popup:
		popup.queue_free()
		popup = null
	hud.level.get_child(0).text = "第 %d 关" % levels[index].id
	_fit_board()
	var by_layer := state.tiles.values()
	by_layer.sort_custom(func(a, b): return a.layer < b.layer or (a.layer == b.layer and (a.y < b.y or (a.y == b.y and a.x < b.x))))
	var order := 0
	for t in by_layer:
		var v := TileView.new(t.id, t.type, _tile_side(t))
		v.face_down = t.get("mystery", false) and not t.get("revealed", false)
		v.blank = t.has("stack") and not state.is_free(t.id)
		v.ice = int(t.get("ice", 0))
		v.key_id = int(t.get("key", -1))
		v.lock_id = int(t.get("lock", -1))
		v.fuse = int(t.get("fuse", -1))
		board_layer.add_child(v)
		views[t.id] = v
		var target := _board_pos(t)
		v.position = target - Vector2(0, 90)
		v.modulate.a = 0.0
		var tw := create_tween().set_parallel()
		var delay: float = mini(int(t.layer), 4) * 0.22 + order * 0.006
		tw.tween_property(v, "position", target, 0.25).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(v, "modulate:a", 1.0, 0.18).set_delay(delay)
		order += 1
	_build_boxes()
	_refresh_cover(false)
	_refresh_hud()
	busy_until = Time.get_ticks_msec() / 1000.0 + 1.2
	if debug_demo != "":
		get_tree().create_timer(1.6).timeout.connect(_run_demo)
	if levels[index].get("tutorial", false):
		_show_hand()
	if levels[index].has("intro") and not autoplay:
		var intro: Dictionary = levels[index].intro
		get_tree().create_timer(1.25).timeout.connect(func():
			if state.tiles.size() > 0 and not _blocked():
				_open_popup(intro.title, intro.text, [["知道了", _close_popup]]))

func _fit_board() -> void:
	var minx := 999; var maxx := -999; var miny := 999; var maxy := -999
	for t in state.tiles.values():
		if t.has("stack"):
			continue
		minx = mini(minx, t.x); maxx = maxi(maxx, t.x + 2)
		miny = mini(miny, t.y); maxy = maxi(maxy, t.y + 2)
	var area := _rect("board")
	var cols := (maxx - minx) / 2.0
	var rows := (maxy - miny) / 2.0
	tile_px = minf(layout.board_tile_max, minf(area.size.x / cols, area.size.y / rows))
	var used := Vector2(cols, rows) * tile_px
	board_origin = area.position + (area.size - used) / 2 - Vector2(minx, miny) * tile_px / 2

func _board_pos(t: Dictionary) -> Vector2:
	if t.has("stack"):
		var side := _tile_side(t)
		var step: Array = layout.stack_step
		var anchor := _stack_anchor(int(t.stack))
		var dir := 1.0 if int(t.stack) == 0 else -1.0
		var x: float = anchor.x + dir * float(step[0]) * int(t.depth)
		if dir < 0:
			x -= side
		return Vector2(x, anchor.y + float(step[1]) * int(t.depth))
	return board_origin + Vector2(t.x, t.y) * tile_px / 2 - Vector2(0, t.layer * layout.layer_lift)

## Side piles sit beside the hold row and move with it on tall screens.
func _stack_anchor(i: int) -> Vector2:
	var a: Array = layout.stacks[i]
	return Vector2(float(a[0]), float(a[1]) + _band("hold_row"))

## Wooden box under each side pile. The box is drawn behind the tiles and its
## front wall (a crop of the same art) in front, so tiles stand inside the box.
func _build_boxes() -> void:
	for n in box_nodes:
		n.queue_free()
	box_nodes.clear()
	box_badges.clear()
	var stacks: Array = levels[level_index].get("stacks", [])
	var bm: Dictionary = layout.box
	var side := float(layout.stack_tile)
	for i in stacks.size():
		var tex := Art.ui("box_base_left" if i == 0 else "box_base_right")
		var anchor := _stack_anchor(i)
		var pile_w := side + float(layout.stack_step[0]) * (int(stacks[i].count) - 1)
		var w: float = pile_w + float(bm.side_pad) * 2
		var k: float = w / float(bm.visible[2])
		var pile_left := anchor.x if i == 0 else anchor.x - pile_w
		var visible_left := pile_left - float(bm.side_pad)
		# Tile bottoms rest on the box's inner floor line, behind the front wall.
		var tile_bottom := anchor.y + _tile_visible_bottom(side)
		var top := tile_bottom - float(bm.rest_y) * k
		var origin := Vector2(visible_left, top) - Vector2(bm.visible[0], 0) * k
		if tex:
			var back := TextureRect.new()
			back.texture = tex
			back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			back.stretch_mode = TextureRect.STRETCH_SCALE
			back.size = Vector2(tex.get_width(), tex.get_height()) * k
			back.position = origin
			back.mouse_filter = Control.MOUSE_FILTER_IGNORE
			board_layer.add_child(back)
			board_layer.move_child(back, 0)
			box_nodes.append(back)
			var lip_tex := AtlasTexture.new()
			lip_tex.atlas = tex
			var lip_y: float = bm.lip_y
			lip_tex.region = Rect2(0, lip_y, tex.get_width(), tex.get_height() - lip_y)
			var lip := TextureRect.new()
			lip.texture = lip_tex
			lip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			lip.stretch_mode = TextureRect.STRETCH_SCALE
			lip.size = lip_tex.region.size * k
			lip.position = origin + Vector2(0, lip_y * k)
			lip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			fly_layer.add_child(lip)
			fly_layer.move_child(lip, 0)
			box_nodes.append(lip)
		var bsz: float = bm.badge_size
		var bc := origin + Vector2(bm.badge_center[0], bm.badge_center[1]) * k
		var badge_tex := Art.ui("box_count_badge")
		var badge: Control = _textured_label(Rect2(bc - Vector2(bsz, bsz) / 2, Vector2(bsz, bsz)), badge_tex, _text_style("box_count_text")) if badge_tex else _plaque(Rect2(bc - Vector2(bsz, bsz) / 2, Vector2(bsz, bsz)), Color("#E5484D"), Color.WHITE, 36)
		badge.reparent(fly_layer)
		box_nodes.append(badge)
		box_badges.append(badge)
	_refresh_box_counts()

## Distance from a tile view's top to the bottom of its drawn biscuit.
func _tile_visible_bottom(side: float) -> float:
	var k := side * TileView.face_fill / TileView.face_box.size.x
	return (side + TileView.visible_box.size.y * k) / 2

func _refresh_box_counts() -> void:
	for i in box_badges.size():
		var left := state.board_tiles().filter(func(t): return t.has("stack") and int(t.stack) == i).size()
		box_badges[i].get_child(0).text = str(left)
		box_badges[i].visible = left > 0

func _tile_side(t: Dictionary) -> float:
	return float(layout.stack_tile) if t.has("stack") else tile_px

## Screen rect for the tray texture so that its visible wooden frame (measured
## inside the PNG) lands exactly on the layout's tray rect.
func _tray_texture_rect() -> Rect2:
	var tex := Art.ui("tray")
	var target := _rect("tray")
	if not tex or not layout.has("tray_texture_frame"):
		return target
	var f: Array = layout.tray_texture_frame
	var k := Vector2(target.size.x / f[2], target.size.y / f[3])
	return Rect2(target.position - Vector2(f[0], f[1]) * k, Vector2(tex.get_width(), tex.get_height()) * k)

## True when this level uses the eight-slot tray art ("多一格").
func _tray8_art() -> bool:
	return state != null and state.tray_size > GameState.TRAY_SIZE and Art.ui("tray_8") != null and layout.has("tray_texture_slots_8")

## Shows the seven- or eight-slot tray picture for the current level. Both
## pictures share one canvas, so the frame rect is the same.
func _apply_tray_art() -> void:
	if hud.get("tray") is TextureRect and Art.ui("tray"):
		(hud.tray as TextureRect).texture = Art.ui("tray_8") if _tray8_art() else Art.ui("tray")

## Tile size in the tray; smaller when the tray holds eight.
func _tray_tile() -> float:
	var side: float = layout.tray_slot
	if _tray8_art():
		return side * float(layout.tray_texture_slots_8.w) / float(layout.tray_texture_slots.w)
	return side * 0.86 if state and state.tray_size > GameState.TRAY_SIZE else side

func _tray_slot(i: int) -> Vector2:
	if _tray8_art():
		var r := _tray_texture_rect()
		var tex := Art.ui("tray")
		var k := r.size / Vector2(tex.get_width(), tex.get_height())
		var s8: Dictionary = layout.tray_texture_slots_8
		return r.position + Vector2(float(s8.cx[i]), float(s8.cy)) * k
	if state and state.tray_size > GameState.TRAY_SIZE:
		var a := _tray_slot7(0)
		var b := _tray_slot7(GameState.TRAY_SIZE - 1)
		return a.lerp(b, float(i) / (state.tray_size - 1))
	return _tray_slot7(i)

func _tray_slot7(i: int) -> Vector2:
	if Art.ui("tray") and layout.has("tray_texture_slots"):
		var r := _tray_texture_rect()
		var tex := Art.ui("tray")
		var k := r.size / Vector2(tex.get_width(), tex.get_height())
		var s: Dictionary = layout.tray_texture_slots
		return r.position + Vector2(float(s.cx[i]), float(s.cy)) * k
	var r := _rect("tray")
	var slot: float = layout.tray_slot
	var gap := (r.size.x - slot * GameState.TRAY_SIZE) / (GameState.TRAY_SIZE + 1)
	return Vector2(r.position.x + gap + i * (slot + gap) + slot / 2, r.position.y + r.size.y / 2)

## Top-left offset that centres a tile (face plus thickness) on a slot centre.
func _tile_anchor(side: float) -> Vector2:
	return Vector2(side, side) / 2

## The "move out" row: three cells cut from the tray art, spaced like the
## tray's, on a soft panel. Parked tiles keep the seven-slot tray size, so
## tiles and cells match whatever the tray holds.
func _hold_cell() -> Dictionary:
	var tex := Art.ui("tray")
	if not tex or not layout.has("tray_texture_slots"):
		var slot: float = layout.tray_slot
		return {"tex": null, "size": Vector2(slot, slot), "pitch": slot + 16.0}
	var k: float = _tray_texture_rect().size.x / tex.get_width()
	var s: Dictionary = layout.tray_texture_slots
	var cell := AtlasTexture.new()
	cell.atlas = tex
	cell.region = Rect2(float(s.cx[0]) - float(s.w) / 2, float(s.cy) - float(s.h) / 2, float(s.w), float(s.h))
	return {"tex": cell, "size": Vector2(float(s.w), float(s.h)) * k, "pitch": (float(s.cx[1]) - float(s.cx[0])) * k}

func _build_hold_row(area: Rect2) -> Control:
	var c := _hold_cell()
	var pad := 16.0
	var w: float = c.pitch * (GameState.HOLD_SIZE - 1) + c.size.x + pad * 2
	var h: float = c.size.y + pad * 2
	var panel := _panel(Rect2(area.get_center() - Vector2(w, h) / 2, Vector2(w, h)), Color(1, 0.97, 0.92, 0.7), Color("#E9B98F"), 30)
	for i in GameState.HOLD_SIZE:
		var at: Vector2 = _hold_slot(i) - panel.position - c.size / 2
		if c.tex:
			var cell := TextureRect.new()
			cell.texture = c.tex
			cell.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			cell.stretch_mode = TextureRect.STRETCH_SCALE
			cell.position = at
			cell.size = c.size
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			panel.add_child(cell)
	return panel

func _hold_tile() -> float:
	return layout.tray_slot

func _hold_slot(i: int) -> Vector2:
	var r := _rect("hold_row")
	var pitch: float = _hold_cell().pitch
	return r.get_center() + Vector2((i - (GameState.HOLD_SIZE - 1) / 2.0) * pitch, 0)

# ---------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
	# Touches also arrive as emulated mouse clicks; handle only the mouse
	# event, otherwise one tap picks two tiles (top tile, then the one it uncovered).
	var press: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if not press or _blocked() or Time.get_ticks_msec() / 1000.0 < busy_until:
		return
	if magnet_armed:
		var target := _any_tile_at(event.position)
		if target >= 0:
			_use_magnet(target)
		return
	var id := _tile_at(event.position)
	if id >= 0:
		_pick(id)

## Any dessert under the point, covered or not (for the magnet).
func _any_tile_at(point: Vector2) -> int:
	var side := _tray_tile()
	for i in display_tray.size():
		if state.tiles[display_tray[i]].place == "tray" and Rect2(_tray_slot(i) - Vector2.ONE * side / 2, Vector2.ONE * side).has_point(point):
			return display_tray[i]
	for id in state.hold:
		if Rect2(_hold_slot(state.hold.find(id)) - Vector2.ONE * _hold_tile() / 2, Vector2.ONE * _hold_tile()).has_point(point):
			return id
	var best := -1
	var best_layer := -1
	for t in state.board_tiles():
		var ts := _tile_side(t)
		if Rect2(_board_pos(t), Vector2(ts, ts)).has_point(point) and int(t.layer) > best_layer:
			best = t.id
			best_layer = int(t.layer)
	return best

func _tile_at(point: Vector2) -> int:
	for id in state.hold:
		if Rect2(_hold_slot(state.hold.find(id)) - Vector2.ONE * _hold_tile() / 2, Vector2.ONE * _hold_tile()).has_point(point):
			return id
	var best := -1
	var best_layer := -1
	for t in state.board_tiles():
		var side := _tile_side(t)
		if Rect2(_board_pos(t), Vector2(side, side)).has_point(point) and t.layer > best_layer:
			best = t.id
			best_layer = t.layer
	if best >= 0 and not state.is_free(best):
		_nudge(best)
		return -1
	if best >= 0 and state.is_locked(best):
		_nudge(best)
		_float_text(_board_pos(state.tiles[best]) + Vector2(tile_px / 2, -10), "需要钥匙", Color("#B07A20"), 40)
		return -1
	if best >= 0 and state.is_frozen(best):
		_nudge(best)
		_float_text(_board_pos(state.tiles[best]) + Vector2(tile_px / 2, -10), "还冻着", Color("#2A7CC7"), 40)
		return -1
	return best

func _nudge(id: int) -> void:
	sound.play("nope")
	var v: Control = views[id]
	var tw := create_tween()
	tw.tween_property(v, "rotation", 0.06, 0.05)
	tw.tween_property(v, "rotation", -0.06, 0.08)
	tw.tween_property(v, "rotation", 0.0, 0.05)

# ---------------------------------------------------------------- actions

func _pick(id: int) -> void:
	var r := state.pick(id)
	if not r.ok:
		return
	_hide_hand()
	tutorial_picks += 1
	var v: Control = views[id]
	sound.play("tap", randf_range(0.95, 1.08))
	v.fuse = -1
	if v.face_down:
		_reveal(v, true)
	var start := v.global_position
	v.reparent(fly_layer)
	v.global_position = start
	display_tray = state.tray.duplicate()
	if not r.matched.is_empty():
		var at: int = r.index - 2
		for i in r.matched.size():
			display_tray.insert(at + i, r.matched[i])
	_reflow(display_tray, [id])
	var slot: Vector2 = _tray_slot(display_tray.find(id)) - _tile_anchor(_tray_tile())
	var press := create_tween()
	press.tween_property(v, "scale", Vector2(0.93, 0.93), 0.06)
	press.tween_property(v, "scale", Vector2.ONE, 0.06)
	_fly(v, start, slot, FLY_TIME, _tray_tile())
	if r.from == "hold":
		_layout_hold()
	_refresh_cover(true)
	_refresh_hud()
	if not r.matched.is_empty():
		get_tree().create_timer(FLY_TIME).timeout.connect(_merge.bind(r.matched))
	if not r.thawed.is_empty():
		get_tree().create_timer(FLY_TIME + MERGE_GATHER).timeout.connect(_thaw.bind(r.thawed))
	if not r.unlocked.is_empty():
		get_tree().create_timer(FLY_TIME + MERGE_GATHER).timeout.connect(_unlock.bind(r.unlocked))
	_burn(r.burning)
	if r.won:
		get_tree().create_timer(FLY_TIME + MERGE_GATHER + MERGE_VANISH + 0.3).timeout.connect(_show_win)
	elif r.lost:
		get_tree().create_timer(FLY_TIME + 0.05).timeout.connect(_show_lose)
	elif levels[level_index].get("tutorial", false) and tutorial_picks < 3:
		get_tree().create_timer(FLY_TIME + 0.4).timeout.connect(_show_hand)

func _fly(v: Control, from: Vector2, to: Vector2, duration: float, side: float) -> void:
	var lift := Vector2(0, -minf(220.0, from.distance_to(to) * 0.35))
	var mid := (from + to) / 2 + lift
	var start_side := v.size.x
	var tw := create_tween()
	tw.tween_method(func(t: float):
		var a := from.lerp(mid, t)
		var b := mid.lerp(to, t)
		v.global_position = a.lerp(b, t)
		v.set_side(lerpf(start_side, side, t)), 0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _reflow(order: Array, skip: Array) -> void:
	for i in order.size():
		var id: int = order[i]
		if skip.has(id):
			continue
		var v: Control = views[id]
		var target: Vector2 = _tray_slot(i) - _tile_anchor(_tray_tile())
		create_tween().tween_property(v, "global_position", target, REFLOW_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _merge(ids: Array) -> void:
	var center_id: int = ids[1]
	var center: Vector2 = views[center_id].global_position
	var color: Color = Art.DESSERTS[state.tiles[center_id].type].color
	for id in ids:
		var v: Control = views[id]
		var tw := create_tween()
		tw.tween_property(v, "global_position", center, MERGE_GATHER).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(v, "scale", Vector2(1.15, 1.15), MERGE_GATHER)
		tw.tween_property(v, "scale", Vector2(0.2, 0.2), MERGE_VANISH).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(v, "modulate:a", 0.0, MERGE_VANISH)
		tw.tween_callback(v.queue_free)
		views.erase(id)
	var burst_at: Vector2 = center + _tile_anchor(_tray_tile())
	get_tree().create_timer(MERGE_GATHER).timeout.connect(func():
		_burst(burst_at, color)
		_float_text(burst_at + Vector2(0, -90), "+30", Color("#E5484D"), 46)
		_combo_feedback(burst_at))
	get_tree().create_timer(MERGE_GATHER + MERGE_VANISH).timeout.connect(func():
		display_tray = state.tray.duplicate()
		_reflow(display_tray, []))

func _combo_feedback(at: Vector2) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	combo = combo + 1 if now - last_match_time <= COMBO_WINDOW else 1
	last_match_time = now
	# Each combo step plays the chime a little higher.
	sound.play("match", pow(2.0, mini(combo - 1, 6) / 12.0 * 2.0))
	if combo >= 2:
		var words := ["棒!", "太棒了!", "完美!"]
		_float_text(Vector2(540, at.y - 200), words[mini(combo - 2, 2)], Color("#F06292"), 72)

func _burst(at: Vector2, color: Color) -> void:
	var p := CPUParticles2D.new()
	p.position = at
	p.one_shot = true
	p.amount = 26
	p.lifetime = 0.6
	p.explosiveness = 0.95
	p.spread = 180.0
	p.initial_velocity_min = 260.0
	p.initial_velocity_max = 520.0
	p.gravity = Vector2(0, 700)
	p.scale_amount_min = 6.0
	p.scale_amount_max = 12.0
	var tex := Art.ui("fx_sparkle")
	if tex:
		p.texture = tex
		p.scale_amount_min = 0.3
		p.scale_amount_max = 0.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.98, 0.9))
	ramp.add_point(0.45, color.lightened(0.35))
	ramp.set_color(1, Color(color.lightened(0.2), 0.0))
	p.color_ramp = ramp
	fly_layer.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)

func _float_text(at: Vector2, text: String, color: Color, font_size: int) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.WHITE)
	l.add_theme_constant_override("outline_size", 12)
	l.size = Vector2(500, 100)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = at - Vector2(250, 50)
	l.pivot_offset = l.size / 2
	l.scale = Vector2(0.6, 0.6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fly_layer.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y - 60, 0.5)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.2)
	tw.tween_callback(l.queue_free)

func _on_booster(kind: String) -> void:
	if _blocked():
		return
	if kind == "magnet":
		_arm_magnet(not magnet_armed and int(state.boosters.get("magnet", 0)) > 0)
		return
	_arm_magnet(false)
	if app and app.profile.booster_count(kind) <= 0:
		app.popups.booster_shortage(kind, func():
			app.save()
			_refresh_hud())
		return
	var used_before: int = state.boosters_used
	match kind:
		"undo":
			var r := state.undo()
			if r.ok:
				_animate_back(r.id, r.to)
		"move_out":
			var r := state.move_out()
			if r.ok:
				display_tray = state.tray.duplicate()
				_layout_hold()
				_reflow(display_tray, [])
		"shuffle":
			var r := state.shuffle()
			if r.ok:
				for id in r.ids:
					var v: Control = views[id]
					var tw := create_tween()
					tw.tween_property(v, "scale", Vector2(0.0, 1.0), 0.12)
					tw.tween_callback(func(): v.type = state.tiles[id].type)
					tw.tween_property(v, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if state.boosters_used > used_before:
		sound.play("booster")
		if app:
			app.profile.use_booster(kind)
			app.save()
	_refresh_hud()

func _animate_back(id: int, to: String) -> void:
	var v: Control = views[id]
	for t in state.tiles.values():
		if t.has("fuse") and views.has(t.id):
			views[t.id].fuse = int(t.fuse) if t.place == "board" else -1
	display_tray = state.tray.duplicate()
	_reflow(display_tray, [])
	if to == "hold":
		_layout_hold()
		return
	var t: Dictionary = state.tiles[id]
	var start := v.global_position
	v.reparent(board_layer)
	v.global_position = start
	_fly(v, start, _board_pos(t), FLY_TIME, tile_px)
	get_tree().create_timer(FLY_TIME).timeout.connect(_restack)
	_refresh_cover(true)

func _restack() -> void:
	var board := state.board_tiles()
	board.sort_custom(func(a, b): return a.layer < b.layer or (a.layer == b.layer and (a.y < b.y or (a.y == b.y and a.x < b.x))))
	for t in board:
		board_layer.move_child(views[t.id], -1)

func _layout_hold() -> void:
	var tw := create_tween()
	tw.tween_property(hud.hold, "modulate:a", 1.0 if not state.hold.is_empty() else 0.0, 0.15)
	for i in state.hold.size():
		var v: Control = views[state.hold[i]]
		var start := v.global_position
		v.reparent(fly_layer)
		v.global_position = start
		_fly(v, start, _hold_slot(i) - _tile_anchor(_hold_tile()), 0.22, _hold_tile())

func _refresh_cover(animate: bool) -> void:
	for t in state.board_tiles():
		var v: Control = views[t.id]
		var free := state.is_free(t.id)
		# Box tiles show their dessert once on top; mystery tiles stay hidden
		# until they are taken (see _pick).
		if free and v.blank:
			_reveal(v, animate)
		var target := 0.0 if free else 1.0
		if animate and not is_equal_approx(v.dim, target):
			create_tween().tween_property(v, "dim", target, DIM_TIME)
		else:
			v.dim = target

## Flip a face-down tile (mystery or buried box tile) to show its dessert.
func _reveal(v: Control, animate: bool) -> void:
	if not animate:
		v.face_down = false
		v.blank = false
		return
	var tw := v.create_tween()
	tw.tween_property(v, "scale:x", 0.0, 0.12).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		v.face_down = false
		v.blank = false)
	tw.tween_property(v, "scale:x", 1.0, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Three booster buttons, or four when the magnet was chosen for this level.
func _place_boosters() -> void:
	var with_magnet := state != null and int(state.boosters.get("magnet", 0)) > 0
	var keys := ["undo", "move_out", "shuffle", "magnet"] if with_magnet else ["undo", "move_out", "shuffle"]
	var side: float = layout.booster_size * (0.86 if with_magnet else 1.0)
	var y: float = layout.boosters_y + _band("boosters")
	booster_buttons.magnet.button.visible = with_magnet
	booster_buttons.magnet.badge.visible = with_magnet
	booster_buttons.magnet.label.visible = with_magnet
	for i in keys.size():
		var e: Dictionary = booster_buttons[keys[i]]
		var x: float = layout.booster_x[i] if not with_magnet else 1080.0 * (2 * i + 1) / 8.0
		var c := Vector2(x, y)
		var k: float = side / float(layout.booster_size)
		var b: Control = e.button
		b.scale = Vector2.ONE
		b.size = Vector2(side, side)
		b.position = c - b.size / 2
		b.pivot_offset = b.size / 2
		for ic in b.get_children():
			if ic is TextureRect:
				ic.position = b.size * 0.2
				ic.size = b.size * 0.6
		e.badge.position = c + e.badge_at * k
		e.label.position = c + Vector2(e.label_at.x, e.label_at.y * k)

## Magnet chosen: the button glows and the next dessert tapped is pulled.
func _arm_magnet(on: bool) -> void:
	magnet_armed = on
	if not booster_buttons.has("magnet"):
		return
	var b: Control = booster_buttons.magnet.button
	if b.has_meta("pulse"):
		(b.get_meta("pulse") as Tween).kill()
		b.remove_meta("pulse")
		b.modulate = Color.WHITE
	if on:
		var tw := b.create_tween().set_loops()
		tw.tween_property(b, "modulate", Color(1.25, 1.2, 0.8), 0.35)
		tw.tween_property(b, "modulate", Color.WHITE, 0.35)
		b.set_meta("pulse", tw)
		_float_text(Vector2(540, 1180 + _band("hold_row")), "点选一块甜点,吸走同款3块", Color("#2E8B57"), 44)

## Magnet: the tapped dessert flies out with two of its kind, wherever they are.
func _use_magnet(id: int) -> void:
	var r := state.magnet(id)
	_arm_magnet(false)
	if not r.ok:
		return
	_hide_hand()
	sound.play("booster")
	var center := Vector2(540, 1250 + _band("hold_row"))
	for tid in r.ids:
		var v: Control = views[tid]
		if v.face_down or v.blank:
			_reveal(v, true)
		v.fuse = -1
		var start := v.global_position
		v.reparent(fly_layer)
		v.global_position = start
		_fly(v, start, center - Vector2(tile_px, tile_px) / 2, 0.45, tile_px)
	display_tray = state.tray.duplicate()
	_reflow(display_tray, [])
	_layout_hold()
	get_tree().create_timer(0.5).timeout.connect(func():
		for tid in r.ids:
			var v: Control = views[tid]
			var tw := v.create_tween()
			tw.tween_property(v, "scale", Vector2(0.2, 0.2), 0.2)
			tw.parallel().tween_property(v, "modulate:a", 0.0, 0.2)
			tw.tween_callback(v.queue_free)
			views.erase(tid)
		_burst(center, Color("#F48FB1"))
		sound.play("match")
		_unlock(r.unlocked)
		_thaw(r.thawed)
		_refresh_cover(true)
		_refresh_hud()
		if state.is_won():
			get_tree().create_timer(0.5).timeout.connect(_show_win))
	_refresh_hud()

## Debug captures: --demo=moveout parks three tray tiles, --demo=magnet pulls a
## buried dessert's triple, --demo=extra shows the eight-slot tray, --demo=fill
## puts six desserts in the tray, --demo=shuffle shuffles at once.
func _run_demo() -> void:
	if debug_demo == "shuffle":
		var before := {}
		for t in state.board_tiles():
			before[t.id] = t.type
		_on_booster("shuffle")
		var changed := state.board_tiles().filter(func(t): return before[t.id] != t.type).size()
		print("RESULT level=%d shuffle changed=%d of %d" % [levels[level_index].id, changed, before.size()])
		return
	if debug_demo == "extra":
		state.tray_size = GameState.TRAY_SIZE + 1
		_apply_tray_art()
	if debug_demo in ["moveout", "magnet", "extra", "fill"]:
		for i in (7 if debug_demo == "extra" else (6 if debug_demo == "fill" else 3)):
			for t in state.solution:
				if state.can_pick(t) and not state.tray.any(func(x): return int(state.tiles[x].type) == int(state.tiles[t].type)):
					_pick(t)
					break
		if debug_demo == "moveout":
			get_tree().create_timer(0.8).timeout.connect(_on_booster.bind("move_out"))
		elif debug_demo == "magnet":
			state.boosters.magnet = 1
			_place_boosters()
			get_tree().create_timer(0.8).timeout.connect(func():
				_on_booster("magnet")
				var deep: Dictionary = state.board_tiles().reduce(func(a, t): return t if int(t.layer) < int(a.layer) else a)
				get_tree().create_timer(0.8).timeout.connect(_use_magnet.bind(int(deep.id))))

func _unlock(ids: Array) -> void:
	if not ids.is_empty():
		sound.play("unlock")
	for id in ids:
		if not views.has(id):
			continue
		var v: Control = views[id]
		var tw := v.create_tween()
		tw.tween_property(v, "scale", Vector2(1.15, 1.15), 0.1)
		tw.tween_callback(func(): v.lock_id = -1)
		tw.tween_property(v, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_burst(v.global_position + v.size / 2, Color("#F2B233"))

## Candles show their remaining steps; the last three pulse as a warning.
func _burn(ids: Array) -> void:
	for id in ids:
		if not views.has(id):
			continue
		var v: Control = views[id]
		var left := int(state.tiles[id].fuse)
		v.fuse = left
		if left <= 3:
			var tw := v.create_tween()
			tw.tween_property(v, "scale", Vector2(1.08, 1.08), 0.08)
			tw.tween_property(v, "scale", Vector2.ONE, 0.12)

## Ice loses one level per cleared triple; at zero it shatters.
func _thaw(ids: Array) -> void:
	for id in ids:
		if not views.has(id):
			continue
		var v: Control = views[id]
		var left := int(state.tiles[id].get("ice", 0))
		var tw := v.create_tween()
		tw.tween_property(v, "rotation", 0.08, 0.05)
		tw.tween_property(v, "rotation", -0.08, 0.07)
		tw.tween_property(v, "rotation", 0.0, 0.05)
		tw.tween_callback(func(): v.ice = left)
		if left == 0:
			sound.play("unlock", 1.2)
			_burst(v.global_position + v.size / 2, Color("#A8DBFF"))

func _refresh_hud() -> void:
	_refresh_box_counts()
	var total := state.tiles.size()
	var done := total - state.remaining()
	var frac := float(done) / total
	var bar_rect := _rect("progress_bar")
	if hud.bar_fill is NinePatchRect:
		var fill: NinePatchRect = hud.bar_fill
		var vis: Array = layout.progress_fill_visible
		var pad := float(fill.texture.get_width() - vis[2])
		var inner: Rect2 = hud.bar_inner
		var shown: float = inner.size.x * frac / fill.scale.x
		var min_shown := float(vis[3])
		fill.visible = frac > 0.0
		create_tween().tween_property(fill, "size:x", maxf(shown, min_shown) + pad, 0.2)
	else:
		var fill_w := maxf(0.0, (bar_rect.size.x - 8) * frac)
		create_tween().tween_property(hud.bar_fill, "size:x", fill_w, 0.2)
	for i in 3:
		var threshold: float = (i + 1) / 3.0
		if layout.has("stars_x"):
			threshold = (float(layout.stars_x[i]) - bar_rect.position.x) / bar_rect.size.x
		var lit := frac >= threshold - 0.001
		var star: Control = hud.stars[i]
		if star is Label:
			star.add_theme_color_override("font_color", Color("#FFC233") if lit else Color("#D9C7B8"))
		elif lit != bool(star.get_meta("lit", false)):
			star.set_meta("lit", lit)
			_set_star_lit(star, lit)
	var enabled := {"undo": state.can_undo(), "move_out": state.can_move_out(), "shuffle": state.can_shuffle()}
	for key in booster_buttons:
		var entry: Dictionary = booster_buttons[key]
		if key == "magnet":
			var left := int(state.boosters.get("magnet", 0))
			entry.badge.get_child(0).text = str(left)
			entry.badge.visible = left > 0
			entry.button.disabled = left <= 0 or state.is_finished()
			entry.button.modulate.a = 1.0 if left > 0 else 0.55
			continue
		entry.button.disabled = not enabled[key]
		entry.button.modulate.a = 1.0 if enabled[key] else 0.55
		if app:
			var have: int = app.profile.booster_count(key)
			entry.badge.get_child(0).text = str(have) if have > 0 else "+"
			entry.badge.visible = true
			entry.button.disabled = not enabled[key] and have > 0
			entry.button.modulate.a = 1.0 if (enabled[key] or have <= 0) else 0.55
		else:
			entry.badge.get_child(0).text = str(state.boosters[key])
			entry.badge.visible = state.boosters[key] > 0
	if app and is_instance_valid(hud.coins):
		hud.coins.get_child(0).text = str(app.profile.data.coins)

func _unlit_star_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform vec3 tint = vec3(0.86, 0.76, 0.66);
uniform float amount = 1.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(c.rgb, tint * (0.55 + 0.6 * g), amount), c.a);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m

## Inner groove of the progress bar on screen, from the groove measured in the PNG.
func _progress_inner(bg_rect: Rect2) -> Rect2:
	var tex := Art.ui("progress_bg")
	var k := bg_rect.size.x / tex.get_width()
	var r: Array = layout.get("progress_inner_slot", [0, 0, tex.get_width(), tex.get_height()])
	return Rect2(bg_rect.position + Vector2(r[0], r[1]) * k, Vector2(r[2], r[3]) * k)

## Lit stars use the gold art at 1.2x after a pop; unlit stars are solid and muted.
func _set_star_lit(star: TextureRect, lit: bool) -> void:
	if lit:
		star.texture = Art.ui("star")
		star.material = null
		var tw := create_tween()
		tw.tween_property(star, "scale", Vector2(1.5, 1.5), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(star, "scale", Vector2(1.2, 1.2), 0.18)
		_burst(star.global_position + star.size / 2, Color("#FFC233"))
	else:
		star.texture = Art.ui("star_off") if Art.ui("star_off") else Art.ui("star")
		star.material = null if Art.ui("star_off") else _unlit_star_material()
		star.scale = Vector2.ONE

# ---------------------------------------------------------------- tutorial hand

func _show_hand() -> void:
	if _blocked() or state.is_finished() or state.solution.is_empty():
		return
	_hide_hand()
	var target: int = _tutorial_target() if levels[level_index].get("tutorial", false) else state.solution[0]
	if target < 0 or not state.is_free(target):
		return
	var tile_center := _board_pos(state.tiles[target]) + Vector2(tile_px, tile_px) / 2
	var tex := Art.ui("tutorial_hand")
	if not tex:
		hand = PulseRing.new()
		hand.size = Vector2(tile_px, tile_px)
		hand.position = _board_pos(state.tiles[target])
		hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fly_layer.add_child(hand)
		return
	hand = Control.new()
	hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fly_layer.add_child(hand)
	var pic := TextureRect.new()
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_SCALE
	var side: float = layout.get("hand_size", 170)
	pic.size = Vector2(side, side)
	var tip_px: Array = layout.get("hand_tip", [48, 28])
	var tip := Vector2(tip_px[0], tip_px[1]) * side / tex.get_width()
	pic.pivot_offset = tip
	pic.position = -tip
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand.add_child(pic)
	var press_tex := Art.ui("tutorial_hand_press")
	var rest := tile_center + Vector2(46, 52)
	hand.position = rest
	var tw := hand.create_tween().set_loops()
	tw.tween_property(hand, "position", tile_center, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		if press_tex: pic.texture = press_tex
		_tap_ripple(tile_center))
	tw.tween_property(pic, "scale", Vector2(0.88, 0.88), 0.08)
	tw.tween_property(pic, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): pic.texture = tex)
	tw.tween_interval(0.25)
	tw.tween_property(hand, "position", rest, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_interval(0.2)

func _tap_ripple(at: Vector2) -> void:
	if hand == null:
		return
	var ring := PulseRing.new()
	ring.set_process(false)
	ring.size = Vector2(tile_px, tile_px) * 0.5
	ring.position = at - ring.size / 2
	ring.pivot_offset = ring.size / 2
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fly_layer.add_child(ring)
	var tw := ring.create_tween().set_parallel()
	tw.tween_property(ring, "scale", Vector2(2.2, 2.2), 0.4).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "modulate:a", 0.0, 0.4)
	tw.chain().tween_callback(ring.queue_free)

## Tutorial hint: always guide a real triple. Continue the dessert already in
## the tray; otherwise start the one with the most free tiles (ties follow the
## winning order, so the hint stays on a winning path).
func _tutorial_target() -> int:
	var free_by_type := {}
	for id in state.solution:
		if state.is_free(id):
			var ty: int = int(state.tiles[id].type)
			if not free_by_type.has(ty):
				free_by_type[ty] = []
			free_by_type[ty].append(id)
	for tid in state.tray:
		var ty: int = int(state.tiles[tid].type)
		if free_by_type.has(ty):
			return free_by_type[ty][0]
	var best := -1
	var best_n := 0
	for ty in free_by_type:
		var n: int = free_by_type[ty].size()
		if n > best_n:
			best_n = n
			best = free_by_type[ty][0]
	return best

func _hide_hand() -> void:
	if hand:
		hand.queue_free()
		hand = null

# ---------------------------------------------------------------- popups

func _on_pause() -> void:
	if _blocked():
		return
	if app:
		var spends: bool = app.profile.level_costs_life(level_index + 1) and state.started() and not state.is_won()
		app.popups.pause(spends, func(): pass, func(): _give_up("restart"), func(): _give_up("home"))
		return
	var sound_label := "声音:开" if sound.enabled else "声音:关"
	_open_popup("暂停", "", [["继续", _close_popup], ["重新开始", func(): start_level(level_index), "cream"], ["选择关卡", _open_level_select, "cream"], [sound_label, _toggle_sound, "cream"]])

func _toggle_sound() -> void:
	sound.set_enabled(not sound.enabled)
	var progress := _load_progress()
	progress["sound"] = sound.enabled
	_write_progress(progress)
	_close_popup()
	_on_pause()

func _open_level_select() -> void:
	_close_popup()
	var cols := 5
	var cell := 140.0
	var rows := ceili(levels.size() / float(cols))
	var panel: Control = _open_popup("选择关卡", "", [["返回", _close_popup, "cream"]], -1, rows * cell + 20)
	var unlocked := _unlocked()
	var top: float = panel.get_meta("body_top")
	var grid_w := cols * cell
	for i in levels.size():
		var b := Button.new()
		b.text = str(int(levels[i].id))
		b.size = Vector2(cell - 20, cell - 20)
		b.position = Vector2((panel.size.x - grid_w) / 2 + (i % cols) * cell + 10, top + (i / cols) * cell)
		b.add_theme_font_size_override("font_size", 50)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#F48FB1") if i < unlocked else Color("#E8DCCF")
		sb.border_color = Color("#E05A87") if i < unlocked else Color("#D9C7B8")
		sb.set_border_width_all(5)
		sb.set_corner_radius_all(32)
		for st_name in ["normal", "hover", "pressed", "disabled"]:
			b.add_theme_stylebox_override(st_name, sb)
		b.add_theme_color_override("font_color", Color.WHITE)
		b.add_theme_color_override("font_outline_color", Color("#9C3219"))
		b.add_theme_constant_override("outline_size", 8)
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = i >= unlocked
		b.pressed.connect(func(): start_level(i))
		panel.add_child(b)

## Highest level the player may start (all levels are open in this test build).
func _unlocked() -> int:
	if bool(_build_flags().get("unlock_all", false)):
		return levels.size()
	return clampi(int(_load_progress().get("unlocked", 1)), 1, levels.size())

func _build_flags() -> Dictionary:
	if not FileAccess.file_exists("res://data/build.json"):
		return {}
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/build.json"))

func _load_progress() -> Dictionary:
	if not FileAccess.file_exists("user://progress.json"):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string("user://progress.json"))
	return d if d is Dictionary else {}

func _save_progress(unlocked: int) -> void:
	var progress := _load_progress()
	progress["unlocked"] = unlocked
	_write_progress(progress)

func _write_progress(progress: Dictionary) -> void:
	var f := FileAccess.open("user://progress.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(progress))

func _show_win() -> void:
	if autoplay or debug_demo != "":
		print("RESULT level=%d won" % levels[level_index].id)
	sound.play("win")
	sound.duck(2.2)
	if app:
		var stars := state.stars()
		var coins: int = app.profile.record_win(level_index + 1, stars, app.difficulty(level_index))
		var chapter: Dictionary = app.profile.claim_chapter_chest(level_index + 1)
		app.save()
		_confetti()
		var last := level_index >= levels.size() - 1
		var idx := level_index
		var go_on := func():
			if last:
				app.goto("home")
			else:
				app.popups.level_start(idx + 1)
		app.popups.win(level_index, stars, coins, func():
			if chapter.is_empty():
				go_on.call()
			else:
				app.popups.reward(chapter, go_on, "章节宝箱"))
		return
	var progress := int(_load_progress().get("unlocked", 1))
	_save_progress(maxi(progress, mini(level_index + 2, levels.size())))
	var stars := state.stars()
	var last := level_index >= levels.size() - 1
	var next_label := "再玩一次" if last else "下一关"
	var next_action := func(): start_level(0 if last else level_index + 1)
	_open_popup("过关!", "全部关卡完成!" if last else "", [[next_label, next_action]], stars)
	_confetti()

func _show_lose() -> void:
	if autoplay or debug_demo != "":
		print("RESULT level=%d lost reason=%s" % [levels[level_index].id, state.lose_reason()])
	sound.play("lose")
	if app:
		var reason: String = state.lose_reason()
		var texts := {"tray": ["托盘满了", "再想想顺序吧"], "candle": ["蜡烛烧完了", "下次早点把蜡烛拿走"], "stuck": ["没有可以拿的了", "冰块和锁挡住了去路"]}
		var tx: Array = texts.get(reason, texts.tray)
		var can_revive := not revived and (state.can_undo() if reason == "candle" else state.can_move_out())
		get_tree().create_timer(0.35).timeout.connect(func():
			app.popups.lose(level_index, tx[0], tx[1], can_revive, _revive, _give_up))
		return
	var tw := create_tween()
	var rest_x: float = hud.tray.position.x
	for i in 4:
		tw.tween_property(hud.tray, "position:x", rest_x + (14 if i % 2 == 0 else -14), 0.05)
	tw.tween_property(hud.tray, "position:x", rest_x, 0.05)
	var buttons := [["重新开始", func(): start_level(level_index)]]
	var titles := {"tray": ["托盘满了", "再想想顺序吧"], "candle": ["蜡烛烧完了", "下次早点把蜡烛拿走"], "stuck": ["没有可以拿的了", "冰块和锁挡住了去路"]}
	var reason: String = state.lose_reason()
	if state.can_undo():
		buttons.push_front(["用“撤回”救一下", func():
			_close_popup()
			var u := state.undo()
			if u.ok:
				_animate_back(u.id, u.to)
				_refresh_cover(true)
				_refresh_hud(), "green"])
	if state.can_move_out():
		buttons.push_front(["用“移出”继续", func():
			_close_popup()
			var r := state.move_out()
			if r.ok:
				display_tray = state.tray.duplicate()
				_layout_hold()
				_reflow(display_tray, [])
				_refresh_hud(), "green"])
	var text: Array = titles.get(reason, titles.tray)
	get_tree().create_timer(0.35).timeout.connect(func(): _open_popup(text[0], text[1], buttons))

## Popup built from the approved popup art (panel, ribbon, candy buttons).
## Each button entry is [label, callable] or [label, callable, "pink"|"green"|"cream"].
## Returns the panel so callers may add content; `body_height` reserves space
## for that content above the buttons.
## Revive after a loss: undo the burned-out candle pick, or park three tray tiles.
func _revive() -> void:
	revived = true
	if state.lose_reason() == "candle" and state.can_undo():
		var u := state.undo()
		if u.ok:
			_animate_back(u.id, u.to)
	else:
		var r := state.move_out()
		if r.ok:
			display_tray = state.tray.duplicate()
			_layout_hold()
			_reflow(display_tray, [])
	_refresh_cover(true)
	_refresh_hud()

## Leaving a level without winning costs a life (outside the first levels).
func _give_up(where: String) -> void:
	_close_popup()
	if not state.is_won() and state.started() or state.is_lost():
		app.profile.lose_life(app.now(), level_index + 1)
		app.save()
	if where == "restart":
		app.popups.level_start(level_index)
	else:
		app.goto("home")

func _open_popup(title: String, subtitle: String, buttons: Array, stars := -1, body_height := 0.0) -> Control:
	_hide_hand()
	popup = Control.new()
	popup.size = size
	add_child(popup)
	var dimmer := ColorRect.new()
	var dim: Array = layout.get("popup_dim", [47, 11, 0, 0.69])
	dimmer.color = Color8(int(dim[0]), int(dim[1]), int(dim[2]), int(float(dim[3]) * 255))
	dimmer.position = Kit.screen_rect().position
	dimmer.size = Kit.screen_rect().size
	popup.add_child(dimmer)
	var pl: Dictionary = layout.popup
	var panel_w: float = pl.panel_width
	var panel := Control.new()
	panel.size = Vector2(panel_w, 400)
	popup.add_child(panel)
	var frame: Control
	if Art.ui("popup_panel"):
		var np := NinePatchRect.new()
		np.texture = Art.ui("popup_panel")
		var m: Array = pl.panel_nine_slice
		np.patch_margin_left = int(m[0]); np.patch_margin_right = int(m[1])
		np.patch_margin_top = int(m[2]); np.patch_margin_bottom = int(m[3])
		var vis: Array = pl.panel_visible
		var k: float = panel_w / float(vis[2])
		np.scale = Vector2(k, k)
		np.position = -Vector2(vis[0], vis[1]) * k
		frame = np
	else:
		var flat := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#FFF9F0"); sb.border_color = Color("#F48FB1")
		sb.set_border_width_all(10); sb.set_corner_radius_all(48)
		flat.add_theme_stylebox_override("panel", sb)
		frame = flat
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(frame)
	# Title ribbon overlaps the panel's top edge.
	var ribbon_tex := Art.ui("popup_ribbon")
	var rb: Array = pl.ribbon_rect
	if ribbon_tex:
		var rr := Rect2(rb[0], rb[1], rb[2], rb[3])
		var ribbon := TextureRect.new()
		ribbon.texture = ribbon_tex
		ribbon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ribbon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ribbon.position = rr.position
		ribbon.size = rr.size
		ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(ribbon)
		var tb: Array = pl.ribbon_text_box
		var kk: float = rr.size.x / ribbon_tex.get_width()
		var t := Label.new()
		t.text = title
		t.position = rr.position + Vector2(tb[0], tb[1]) * kk
		t.size = Vector2(tb[2], tb[3]) * kk
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_apply_text_style(t, _text_style("popup_title"))
		_shrink_to_fit(t)
		panel.add_child(t)
	else:
		var t := Label.new()
		t.text = title
		t.add_theme_font_size_override("font_size", 80)
		t.add_theme_color_override("font_color", Color("#E05A87"))
		t.size = Vector2(panel_w, 120)
		t.position = Vector2(0, 40)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(t)
	var y: float = pl.content_top
	if stars >= 0:
		var d: float = pl.star_size
		var gap: float = pl.star_gap
		for i in 3:
			var star := TextureRect.new()
			star.texture = Art.ui("star_off")
			star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			star.size = Vector2(d, d)
			star.position = Vector2(panel_w / 2 + (i - 1) * gap - d / 2, y)
			star.pivot_offset = star.size / 2
			star.mouse_filter = Control.MOUSE_FILTER_IGNORE
			panel.add_child(star)
			if i < stars:
				var tw := create_tween()
				tw.tween_interval(0.3 + i * 0.18)
				tw.tween_callback(func(): star.texture = Art.ui("star"))
				tw.tween_property(star, "scale", Vector2(1.25, 1.25), 0.1)
				tw.tween_property(star, "scale", Vector2.ONE, 0.12)
		y += d + float(pl.block_gap)
	if subtitle != "":
		var st := Label.new()
		st.text = subtitle
		_apply_text_style(st, _text_style("popup_subtitle"))
		var lines := subtitle.count("\n") + 1
		var lh: float = pl.subtitle_line
		st.size = Vector2(panel_w - 160, lh * lines)
		st.position = Vector2(80, y)
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		st.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_shrink_to_fit(st)
		panel.add_child(st)
		y += lh * lines + float(pl.block_gap)
	panel.set_meta("body_top", y)
	y += body_height
	for entry in buttons:
		var style: String = entry[2] if entry.size() > 2 else "pink"
		var b := _pill_button(entry[0], style, Vector2(pl.button_width, pl.button_height))
		b.position = Vector2((panel_w - b.size.x) / 2, y)
		b.pressed.connect(entry[1])
		panel.add_child(b)
		y += b.size.y + float(pl.button_gap)
	panel.size.y = y - float(pl.button_gap) + float(pl.bottom_pad)
	if frame is NinePatchRect:
		# Visible frame maps onto the panel; keep the PNG's transparent padding outside it.
		var tex := Art.ui("popup_panel")
		var vis: Array = pl.panel_visible
		frame.size = panel.size / frame.scale.x + Vector2(tex.get_width() - float(vis[2]), tex.get_height() - float(vis[3]))
	else:
		frame.size = panel.size
	panel.position = (size - panel.size) / 2 + Vector2(0, float(pl.get("center_offset_y", 40)))
	panel.pivot_offset = panel.size / 2
	panel.scale = Vector2(0.7, 0.7)
	panel.modulate.a = 0.0
	var tw2 := create_tween().set_parallel()
	tw2.tween_property(panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw2.tween_property(panel, "modulate:a", 1.0, 0.15)
	if debug_press_first and not buttons.is_empty():
		var first: Callable = buttons[0][1]
		get_tree().create_timer(1.0).timeout.connect(func():
			if _blocked():
				print("debug: pressing ", buttons[0][0])
				first.call())
	return panel

## Candy pill button from the approved art: stretched horizontally by nine-slice.
func _pill_button(label: String, style: String, sz: Vector2) -> BaseButton:
	var tex := Art.ui("button_pill_" + style)
	var b := TextureButton.new()
	b.size = sz
	b.pivot_offset = sz / 2
	b.focus_mode = Control.FOCUS_NONE
	b.button_down.connect(func(): create_tween().tween_property(b, "scale", Vector2(0.94, 0.94), 0.06))
	b.button_up.connect(func(): create_tween().tween_property(b, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_BACK))
	if tex:
		# Height fits the button; width stretches through the nine-slice middle,
		# so the round caps keep their drawn shape for every style.
		var pm: Dictionary = layout.popup.pill[style]
		var vis: Array = pm.visible
		var nine: Array = pm.nine
		var k: float = sz.y / float(vis[3])
		var np := NinePatchRect.new()
		np.texture = tex
		np.patch_margin_left = int(nine[0]); np.patch_margin_right = int(nine[1])
		np.patch_margin_top = int(nine[2]); np.patch_margin_bottom = int(nine[3])
		np.scale = Vector2(k, k)
		np.position = -Vector2(vis[0], vis[1]) * k
		np.size = Vector2(sz.x / k + (tex.get_width() - float(vis[2])), tex.get_height())
		np.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(np)
	var l := Label.new()
	l.text = label
	l.size = sz - Vector2(60, 12)
	l.position = Vector2(30, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_text_style(l, _text_style("pill_text_cream" if style == "cream" else "pill_text"))
	_shrink_to_fit(l)
	b.add_child(l)
	return b

## Reduce a label's font size until its text fits its box.
func _shrink_to_fit(l: Label) -> void:
	var fs := l.get_theme_font_size("font_size")
	var font := l.get_theme_font("font")
	var widest := 0.0
	for line in l.text.split("\n"):
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	if widest > l.size.x and widest > 0:
		l.add_theme_font_size_override("font_size", int(fs * l.size.x / widest))

func _close_popup() -> void:
	if popup:
		popup.queue_free()
		popup = null

func _confetti() -> void:
	# One emitter per confetti slice; falls in front of the win popup.
	var host: Node = app.popup_layer if app else self
	for i in 4:
		var p := CPUParticles2D.new()
		p.z_index = 100
		p.position = Vector2(540, -30 - Kit.extra)
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p.emission_rect_extents = Vector2(560, 10)
		p.amount = 26
		p.lifetime = 3.2
		p.direction = Vector2(0, 1)
		p.spread = 25.0
		p.initial_velocity_min = 180.0
		p.initial_velocity_max = 420.0
		p.gravity = Vector2(0, 240)
		p.angular_velocity_min = -300.0
		p.angular_velocity_max = 300.0
		p.angle_min = 0.0
		p.angle_max = 360.0
		p.one_shot = true
		p.explosiveness = 0.35
		var t: Texture2D = Art.ui("confetti_%d" % (i + 1))
		if t:
			p.texture = t
			p.scale_amount_min = 0.7
			p.scale_amount_max = 1.1
		else:
			p.scale_amount_min = 10.0
			p.scale_amount_max = 18.0
			p.color = [Color("#F48FB1"), Color("#FFC233"), Color("#7CC8B4"), Color("#B39DDB")][i]
		host.add_child(p)
		p.emitting = true
		get_tree().create_timer(3.8).timeout.connect(p.queue_free)

# ---------------------------------------------------------------- debug capture

func _process(delta: float) -> void:
	if autoplay and not _blocked() and not state.is_finished() and Time.get_ticks_msec() / 1000.0 >= busy_until:
		autoplay_clock += delta
		if autoplay_clock >= 0.45 and not state.solution.is_empty():
			autoplay_clock = 0.0
			if autoplay_random:
				var free: Array = state.board_tiles().filter(func(t): return state.can_pick(t.id))
				if not free.is_empty():
					_pick(free[state.rng.randi_range(0, free.size() - 1)].id)
			else:
				_pick(state.solution[0])
	if capture_dir != "":
		capture_clock += delta
		if capture_clock >= capture_every:
			capture_clock = 0.0
			var img := get_viewport().get_texture().get_image()
			img.save_png("%s/frame_%04d.png" % [capture_dir, capture_index])
			capture_index += 1
