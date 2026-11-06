extends Control
## Game page: builds the HUD, board, tray and boosters, turns taps into rule
## calls on GameState and animates the result. Rules never live here.

const GameState = preload("res://scripts/core/game_state.gd")
const TileView = preload("res://scripts/game/tile_view.gd")
const Art = preload("res://scripts/game/art.gd")
const PulseRing = preload("res://scripts/game/pulse_ring.gd")

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
var combo := 0
var last_match_time := -100.0
var tutorial_picks := 0
var busy_until := 0.0

# Debug capture: --autoplay plays the known solution, --capture=<dir> saves frames.
var autoplay := false
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
		elif arg.begins_with("--capture="):
			capture_dir = arg.substr(10)
			DirAccess.make_dir_recursive_absolute(capture_dir)
		elif arg.begins_with("--level="):
			level_index = clampi(int(arg.substr(8)) - 1, 0, 2)
	_build_static()
	start_level(level_index)

func _rect(key: String) -> Rect2:
	var r: Array = layout[key]
	return Rect2(r[0], r[1], r[2], r[3])

# ---------------------------------------------------------------- building

func _build_static() -> void:
	var bg_tex := Art.ui("background")
	if bg_tex:
		var bg := TextureRect.new()
		bg.texture = bg_tex
		bg.size = size
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
	else:
		var bg := ColorRect.new()
		bg.color = Color("#FCEFF3")
		bg.size = size
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)

	hud.pause = _round_button(_rect("pause_button"), "Ⅱ", Color("#F48FB1"))
	hud.pause.pressed.connect(_on_pause)
	hud.level = _plaque(_rect("level_plaque"), Color("#F48FB1"), Color.WHITE, 52)
	hud.coins = _plaque(_rect("coin_pill"), Color("#FFF6E6"), Color("#7A4A32"), 40)
	hud.coins.get_child(0).text = "● 1280"
	var bar_rect := _rect("progress_bar")
	hud.bar_bg = _panel(bar_rect, Color("#FFF6E6"), Color("#E9B98F"), int(bar_rect.size.y / 2))
	hud.bar_fill = _panel(Rect2(bar_rect.position + Vector2(4, 4), Vector2(0, bar_rect.size.y - 8)), Color("#F48FB1"), Color.TRANSPARENT, int(bar_rect.size.y / 2))
	hud.stars = []
	for i in 3:
		var star := Label.new()
		star.text = "★"
		star.add_theme_font_size_override("font_size", 52)
		star.add_theme_color_override("font_color", Color("#D9C7B8"))
		star.position = bar_rect.position + Vector2(bar_rect.size.x * (i + 1) / 3.0 - 26, -16)
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(star)
		hud.stars.append(star)

	var hold_rect := _rect("hold_row")
	hud.hold = _panel(hold_rect, Color(1, 1, 1, 0.55), Color("#E9B98F"), 30)
	hud.hold.modulate.a = 0.0
	var tray_rect := _rect("tray")
	hud.tray = _panel(tray_rect, Color("#F7E3CC"), Color("#D9A57A"), 40)
	for i in GameState.TRAY_SIZE:
		var slot := _panel(Rect2(_tray_slot(i) - Vector2.ONE * layout.tray_slot / 2, Vector2.ONE * layout.tray_slot), Color("#EBCDAE"), Color.TRANSPARENT, 24)
		slot.modulate.a = 0.7

	for i in 3:
		var key: String = ["undo", "move_out", "shuffle"][i]
		var label: String = ["撤回", "移出", "洗牌"][i]
		var glyph: String = ["↶", "⇪", "⟲"][i]
		var c := Vector2(layout.booster_x[i], layout.boosters_y)
		var side: float = layout.booster_size
		var b := _round_button(Rect2(c - Vector2(side, side) / 2, Vector2(side, side)), glyph, Color("#7CC8B4"))
		b.pressed.connect(_on_booster.bind(key))
		var badge := _plaque(Rect2(c + Vector2(side * 0.22, -side * 0.55), Vector2(56, 56)), Color("#E5484D"), Color.WHITE, 34)
		var name_label := Label.new()
		name_label.text = label
		name_label.add_theme_font_size_override("font_size", 38)
		name_label.add_theme_color_override("font_color", Color("#7A4A32"))
		name_label.size = Vector2(200, 50)
		name_label.position = c + Vector2(-100, side / 2 + 4)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(name_label)
		booster_buttons[key] = {"button": b, "badge": badge}

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

# ---------------------------------------------------------------- level

func start_level(index: int) -> void:
	level_index = index
	state = GameState.new(levels[index])
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
		var v := TileView.new(t.id, t.type, tile_px)
		board_layer.add_child(v)
		views[t.id] = v
		var target := _board_pos(t)
		v.position = target - Vector2(0, 90)
		v.modulate.a = 0.0
		var tw := create_tween().set_parallel()
		var delay: float = t.layer * 0.22 + order * 0.006
		tw.tween_property(v, "position", target, 0.25).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(v, "modulate:a", 1.0, 0.18).set_delay(delay)
		order += 1
	_refresh_cover(false)
	_refresh_hud()
	busy_until = Time.get_ticks_msec() / 1000.0 + 1.2
	if levels[index].get("tutorial", false):
		_show_hand()

func _fit_board() -> void:
	var minx := 999; var maxx := -999; var miny := 999; var maxy := -999
	for t in state.tiles.values():
		minx = mini(minx, t.x); maxx = maxi(maxx, t.x + 2)
		miny = mini(miny, t.y); maxy = maxi(maxy, t.y + 2)
	var area := _rect("board")
	var cols := (maxx - minx) / 2.0
	var rows := (maxy - miny) / 2.0
	tile_px = minf(layout.board_tile_max, minf(area.size.x / cols, area.size.y / rows))
	var used := Vector2(cols, rows) * tile_px
	board_origin = area.position + (area.size - used) / 2 - Vector2(minx, miny) * tile_px / 2

func _board_pos(t: Dictionary) -> Vector2:
	return board_origin + Vector2(t.x, t.y) * tile_px / 2 - Vector2(0, t.layer * layout.layer_lift)

func _tray_slot(i: int) -> Vector2:
	var r := _rect("tray")
	var slot: float = layout.tray_slot
	var gap := (r.size.x - slot * GameState.TRAY_SIZE) / (GameState.TRAY_SIZE + 1)
	return Vector2(r.position.x + gap + i * (slot + gap) + slot / 2, r.position.y + r.size.y / 2)

func _hold_slot(i: int) -> Vector2:
	var r := _rect("hold_row")
	var slot: float = layout.tray_slot
	var gap := (r.size.x - slot * GameState.HOLD_SIZE) / (GameState.HOLD_SIZE + 1)
	return Vector2(r.position.x + gap + i * (slot + gap) + slot / 2, r.position.y + r.size.y / 2)

# ---------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
	var press: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	press = press or (event is InputEventScreenTouch and event.pressed)
	if not press or popup != null or Time.get_ticks_msec() / 1000.0 < busy_until:
		return
	var id := _tile_at(event.position)
	if id >= 0:
		_pick(id)

func _tile_at(point: Vector2) -> int:
	for id in state.hold:
		if Rect2(_hold_slot(state.hold.find(id)) - Vector2.ONE * layout.tray_slot / 2, Vector2.ONE * layout.tray_slot).has_point(point):
			return id
	var best := -1
	var best_layer := -1
	for t in state.board_tiles():
		if Rect2(_board_pos(t), Vector2(tile_px, tile_px)).has_point(point) and t.layer > best_layer:
			best = t.id
			best_layer = t.layer
	if best >= 0 and not state.is_free(best):
		_nudge(best)
		return -1
	return best

func _nudge(id: int) -> void:
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
	var start := v.global_position
	v.reparent(fly_layer)
	v.global_position = start
	display_tray = state.tray.duplicate()
	if not r.matched.is_empty():
		var at: int = r.index - 2
		for i in r.matched.size():
			display_tray.insert(at + i, r.matched[i])
	_reflow(display_tray, [id])
	var slot: Vector2 = _tray_slot(display_tray.find(id)) - Vector2.ONE * layout.tray_slot / 2
	var press := create_tween()
	press.tween_property(v, "scale", Vector2(0.93, 0.93), 0.06)
	press.tween_property(v, "scale", Vector2.ONE, 0.06)
	_fly(v, start, slot, FLY_TIME, layout.tray_slot)
	if r.from == "hold":
		_layout_hold()
	_refresh_cover(true)
	_refresh_hud()
	if not r.matched.is_empty():
		get_tree().create_timer(FLY_TIME).timeout.connect(_merge.bind(r.matched))
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
		var target: Vector2 = _tray_slot(i) - Vector2.ONE * layout.tray_slot / 2
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
	var burst_at: Vector2 = center + Vector2.ONE * layout.tray_slot / 2
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
	ramp.set_color(0, color.lightened(0.3))
	ramp.set_color(1, Color(color, 0.0))
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
	if popup != null:
		return
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
	_refresh_hud()

func _animate_back(id: int, to: String) -> void:
	var v: Control = views[id]
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
		_fly(v, start, _hold_slot(i) - Vector2.ONE * layout.tray_slot / 2, 0.22, layout.tray_slot)

func _refresh_cover(animate: bool) -> void:
	for t in state.board_tiles():
		var v: Control = views[t.id]
		var target := 0.0 if state.is_free(t.id) else 1.0
		if animate and not is_equal_approx(v.dim, target):
			create_tween().tween_property(v, "dim", target, DIM_TIME)
		else:
			v.dim = target

func _refresh_hud() -> void:
	var total := state.tiles.size()
	var done := total - state.remaining()
	var frac := float(done) / total
	var bar_rect := _rect("progress_bar")
	create_tween().tween_property(hud.bar_fill, "size:x", maxf(0.0, (bar_rect.size.x - 8) * frac), 0.2)
	for i in 3:
		var lit := frac >= (i + 1) / 3.0
		hud.stars[i].add_theme_color_override("font_color", Color("#FFC233") if lit else Color("#D9C7B8"))
	var enabled := {"undo": state.can_undo(), "move_out": state.can_move_out(), "shuffle": state.can_shuffle()}
	for key in booster_buttons:
		var entry: Dictionary = booster_buttons[key]
		entry.button.disabled = not enabled[key]
		entry.button.modulate.a = 1.0 if enabled[key] else 0.55
		entry.badge.get_child(0).text = str(state.boosters[key])
		entry.badge.visible = state.boosters[key] > 0

# ---------------------------------------------------------------- tutorial hand

func _show_hand() -> void:
	if popup != null or state.is_finished() or state.solution.is_empty():
		return
	_hide_hand()
	var target: int = state.solution[0]
	if not state.is_free(target):
		return
	var tex := Art.ui("tutorial_hand")
	if tex:
		hand = TextureRect.new()
		hand.texture = tex
		hand.size = Vector2(150, 150)
	else:
		hand = PulseRing.new()
		hand.size = Vector2(tile_px, tile_px)
	hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var base := _board_pos(state.tiles[target])
	if tex:
		base += Vector2(tile_px * 0.45, tile_px * 0.55)
	hand.position = base
	fly_layer.add_child(hand)
	var tw := hand.create_tween().set_loops()
	tw.tween_property(hand, "position", base + Vector2(-12, -18), 0.45).set_trans(Tween.TRANS_SINE)
	tw.tween_property(hand, "position", base, 0.45).set_trans(Tween.TRANS_SINE)

func _hide_hand() -> void:
	if hand:
		hand.queue_free()
		hand = null

# ---------------------------------------------------------------- popups

func _on_pause() -> void:
	if popup != null:
		return
	_open_popup("暂停", "", [["继续", _close_popup], ["重新开始", func(): start_level(level_index)]])

func _show_win() -> void:
	var stars := state.stars()
	var last := level_index >= levels.size() - 1
	var next_label := "再玩一次" if last else "下一关"
	var next_action := func(): start_level(0 if last else level_index + 1)
	_open_popup("过关!", "全部关卡完成!" if last else "", [[next_label, next_action]], stars)
	_confetti()

func _show_lose() -> void:
	var tw := create_tween()
	for i in 4:
		tw.tween_property(hud.tray, "position:x", _rect("tray").position.x + (14 if i % 2 == 0 else -14), 0.05)
	tw.tween_property(hud.tray, "position:x", _rect("tray").position.x, 0.05)
	var buttons := [["重新开始", func(): start_level(level_index)]]
	if state.boosters.move_out > 0 and state.hold.is_empty():
		buttons.push_front(["用“移出”继续", func():
			_close_popup()
			var r := state.move_out()
			if r.ok:
				display_tray = state.tray.duplicate()
				_layout_hold()
				_reflow(display_tray, [])
				_refresh_hud()])
	get_tree().create_timer(0.35).timeout.connect(func(): _open_popup("托盘满了", "再想想顺序吧", buttons))

func _open_popup(title: String, subtitle: String, buttons: Array, stars := -1) -> void:
	_hide_hand()
	popup = Control.new()
	popup.size = size
	add_child(popup)
	var dimmer := ColorRect.new()
	dimmer.color = Color(0.2, 0.1, 0.15, 0.55)
	dimmer.size = size
	popup.add_child(dimmer)
	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#FFF9F0")
	sb.border_color = Color("#F48FB1")
	sb.set_border_width_all(10)
	sb.set_corner_radius_all(48)
	panel.add_theme_stylebox_override("panel", sb)
	panel.size = Vector2(780, 640 if stars >= 0 else 520)
	panel.position = (size - panel.size) / 2
	panel.pivot_offset = panel.size / 2
	popup.add_child(panel)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 80)
	t.add_theme_color_override("font_color", Color("#E05A87"))
	t.size = Vector2(panel.size.x, 120)
	t.position = Vector2(0, 40)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(t)
	var y := 170.0
	if stars >= 0:
		for i in 3:
			var s := Label.new()
			s.text = "★"
			s.add_theme_font_size_override("font_size", 130)
			s.add_theme_color_override("font_color", Color("#E8DCCF"))
			s.size = Vector2(150, 150)
			s.position = Vector2(panel.size.x / 2 - 225 + i * 150, y)
			s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			s.pivot_offset = s.size / 2
			panel.add_child(s)
			if i < stars:
				var tw := create_tween()
				tw.tween_interval(0.3 + i * 0.18)
				tw.tween_callback(func(): s.add_theme_color_override("font_color", Color("#FFC233")))
				tw.tween_property(s, "scale", Vector2(1.25, 1.25), 0.1)
				tw.tween_property(s, "scale", Vector2.ONE, 0.12)
		y += 170
	if subtitle != "":
		var st := Label.new()
		st.text = subtitle
		st.add_theme_font_size_override("font_size", 42)
		st.add_theme_color_override("font_color", Color("#7A4A32"))
		st.size = Vector2(panel.size.x, 60)
		st.position = Vector2(0, y)
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(st)
		y += 80
	for entry in buttons:
		var b := Button.new()
		b.text = entry[0]
		b.size = Vector2(520, 120)
		b.position = Vector2((panel.size.x - 520) / 2, y + 20)
		b.add_theme_font_size_override("font_size", 50)
		var bs := StyleBoxFlat.new()
		bs.bg_color = Color("#7CC8B4")
		bs.set_corner_radius_all(60)
		bs.shadow_color = Color(0.3, 0.5, 0.45, 0.4)
		bs.shadow_size = 6
		bs.shadow_offset = Vector2(0, 8)
		for st_name in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st_name, bs)
		b.add_theme_color_override("font_color", Color.WHITE)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(entry[1])
		panel.add_child(b)
		y += 150
	panel.scale = Vector2(0.7, 0.7)
	panel.modulate.a = 0.0
	var tw2 := create_tween().set_parallel()
	tw2.tween_property(panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw2.tween_property(panel, "modulate:a", 1.0, 0.15)

func _close_popup() -> void:
	if popup:
		popup.queue_free()
		popup = null

func _confetti() -> void:
	var p := CPUParticles2D.new()
	p.position = Vector2(540, -20)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(560, 10)
	p.amount = 120
	p.lifetime = 3.0
	p.direction = Vector2(0, 1)
	p.spread = 25.0
	p.initial_velocity_min = 200.0
	p.initial_velocity_max = 420.0
	p.gravity = Vector2(0, 260)
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 10.0
	p.scale_amount_max = 18.0
	p.one_shot = true
	p.explosiveness = 0.3
	var colors := Gradient.new()
	colors.set_color(0, Color("#F48FB1"))
	colors.set_color(1, Color("#7CC8B4"))
	colors.add_point(0.5, Color("#FFC233"))
	p.color_initial_ramp = colors
	add_child(p)
	p.emitting = true
	get_tree().create_timer(3.5).timeout.connect(p.queue_free)

# ---------------------------------------------------------------- debug capture

func _process(delta: float) -> void:
	if autoplay and popup == null and not state.is_finished() and Time.get_ticks_msec() / 1000.0 >= busy_until:
		autoplay_clock += delta
		if autoplay_clock >= 0.45 and not state.solution.is_empty():
			autoplay_clock = 0.0
			_pick(state.solution[0])
	if capture_dir != "":
		capture_clock += delta
		if capture_clock >= capture_every:
			capture_clock = 0.0
			var img := get_viewport().get_texture().get_image()
			img.save_png("%s/frame_%04d.png" % [capture_dir, capture_index])
			capture_index += 1
