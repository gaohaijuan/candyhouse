extends Control
## Candy house (mockups H1_A decorating, H2_A item drawer, H3_A room done).
## The room is layers on one canvas: the empty room art, wallpaper and floor
## patterns multiplied onto its plain walls and floor, the windows and
## fireplace put back on top, curtains, furniture sorted by depth, and the
## front wall. Empty slots show a "+"; tapping a placed thing selects it and
## offers colour / swap. Room data and slot positions: data/house.json.

const Kit = preload("res://scripts/ui/kit.gd")
const Common = preload("res://scripts/ui/pages/_common.gd")
const Art = preload("res://scripts/game/art.gd")
const TINT = preload("res://scripts/house/tint.gdshader")
const TINT_MUL = preload("res://scripts/house/tint_mul.gdshader")
const PANEL_Y := 1270.0
const WALL_TILE := 190.0     # on-screen size of one wallpaper repeat
const FLOOR_TILE := 230.0
const DEFAULT_MAIN := "#F06A9E"

var app
var house: Dictionary
var room: Dictionary
var layout: Dictionary
var scene: Control
var layer := {}              # name -> Control, bottom to top
var drawn := {}              # slot id -> Array of nodes drawn for it
var hit := {}                # slot id -> Array of Rect2 / PackedVector2Array
var markers: Control
var tools: Control
var panel: Control
var selected := ""
var preview := {}            # {"slot", "item", "color"} shown but not bought
var balance: Label
var progress: Label

func setup(owner_app, _args: Dictionary) -> void:
	app = owner_app
	house = JSON.parse_string(FileAccess.get_file_as_string("res://data/house.json"))
	room = house.rooms[0]
	layout = room.layout
	_build_scene()
	var top := Kit.band(self, 0.0)
	var back := Kit.art_button(top, "button_back", Rect2(18, 14, 131, 132), "返")
	back.pressed.connect(func(): app.goto("home"))
	Kit.art(top, "popup_ribbon", Rect2(213, 13, 590, 170))
	Kit.text_at(top, "我的糖果屋", Rect2(330, 32, 356, 90), 68, Kit.CREAM, Kit.OUTLINE, 12)
	Kit.art(top, "coin_pill", Rect2(792, 36, 272, 92))
	balance = Kit.text_at(top, "", Rect2(868, 57, 135, 50), 42, Kit.BROWN)
	if Kit.tex("plaque_progress"):
		# Plaque 648 x 184, text area (150, 53, 345, 90), shown at 0.57.
		Kit.art(top, "plaque_progress", Rect2(700, 150, 370, 105))
		progress = Kit.text_at(top, "", Rect2(786, 180, 197, 51), 40, Kit.BROWN)
	else:
		Kit.nine(top, "tag_plate", Rect2(740, 150, 320, 80), [42, 14, 43, 14])
		progress = Kit.text_at(top, "", Rect2(760, 163, 280, 56), 42, Kit.BROWN)
	app.wallet_changed.connect(_refresh_header)
	_refresh_header()
	if app.profile.house_reward_ready(room):
		_room_done.call_deferred()

# ---------------------------------------------------------------- the room

func _build_scene() -> void:
	var sky := ColorRect.new()
	sky.color = Color("#BFE6F5")
	sky.position = Kit.screen_rect().position
	sky.size = Kit.screen_rect().size
	add_child(sky)
	scene = Control.new()
	scene.size = Vector2(1080, 1920)
	scene.mouse_filter = Control.MOUSE_FILTER_STOP
	scene.gui_input.connect(_on_scene_input)
	add_child(scene)
	var base := _house_tex("room_base")
	if base:
		_sprite(scene, "room_base", Vector2.ZERO)
	else:
		Common.background(scene, "home_bg")
	for name in ["floor", "wall", "fixtures", "curtain", "items", "front", "fx"]:
		var c := Control.new()
		c.size = Vector2(1080, 1920)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scene.add_child(c)
		layer[name] = c
	# Room parts cut from room_base at its own scale, placed at their corners.
	for f in layout.get("fixtures", {}):
		_sprite(layer.fixtures, f, Vector2(layout.fixtures[f][0], layout.fixtures[f][1]))
	var front: Array = layout.get("front", [0, 0])
	_sprite(layer.front, "room_front", Vector2(front[0], front[1]))
	markers = Control.new()
	markers.size = Vector2(1080, 1920)
	markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.add_child(markers)
	tools = Control.new()
	tools.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.add_child(tools)
	for s in room.slots:
		_draw_slot(s.id)
	_refresh_markers()

func _slot_def(id: String) -> Dictionary:
	for s in room.slots:
		if s.id == id:
			return s
	return {}

func _item_def(slot: Dictionary, id: String) -> Dictionary:
	for it in slot.items:
		if it.id == id:
			return it
	return {}

## What a slot shows now: the preview if there is one, else the saved choice.
func _shown(slot_id: String) -> Dictionary:
	if preview.get("slot", "") == slot_id:
		return preview
	return app.profile.house_slot(room.id, slot_id)

func _house_tex(name: String) -> Texture2D:
	return Art.texture("res://assets/house/%s.png" % name)

## Room art drawn 1:1 on the 1080-wide canvas (room_base is exported at that width).
func _sprite(parent: Control, art: String, at: Vector2) -> void:
	var t := _house_tex(art)
	if t == null:
		return
	var r := TextureRect.new()
	r.texture = t
	r.position = at
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)

func _tint(mat_shader: Shader, item: Dictionary, color: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = mat_shader
	m.set_shader_parameter("ref", Color(item.get("main", DEFAULT_MAIN)))
	m.set_shader_parameter("enabled", color >= 0)
	if color >= 0:
		m.set_shader_parameter("target", Color(house.colors[color].hex))
	return m

## Redraws one slot from what it shows now.
func _draw_slot(slot_id: String) -> void:
	for n in drawn.get(slot_id, []):
		if is_instance_valid(n):
			n.queue_free()
	drawn[slot_id] = []
	hit[slot_id] = []
	var e := _shown(slot_id)
	if e.is_empty():
		return
	var slot := _slot_def(slot_id)
	var item := _item_def(slot, e.item)
	var color := int(e.get("color", -1))
	match String(slot.kind):
		"wall":
			for w in layout.walls:
				_pattern(slot_id, layer.wall, w, item, color, WALL_TILE)
		"floor":
			_pattern(slot_id, layer.floor, layout.floor, item, color, FLOOR_TILE)
		"window":
			for side in layout.windows:
				var p: Array = layout.windows[side]
				var art := item.duplicate()
				if item.has("anchor_" + side):
					art.anchor = item["anchor_" + side]
				var n := _item_sprite(slot_id, layer.curtain, "%s_%s" % [item.id, side], art, color, Vector2(p[0], p[1]), float(item.get("width_" + side, 175)), true)
				hit[slot_id].append(Rect2(n.position, n.size))
		_:
			var cfg: Dictionary = layout.slots[slot_id]
			var n := _item_sprite(slot_id, layer.items, item.id, item, color, Vector2(cfg.pos[0], cfg.pos[1]), float(item.get("width", cfg.width)), false)
			# Furniture is drawn back to front; the rug always lies under it.
			n.set_meta("depth", -1.0 if slot_id == "rug" else float(cfg.pos[1]))
			var kids: Array = layer.items.get_children()
			kids.sort_custom(func(a, b): return float(a.get_meta("depth", 0.0)) < float(b.get_meta("depth", 0.0)))
			for i in kids.size():
				layer.items.move_child(kids[i], i)
			hit[slot_id].append(Rect2(n.position + n.size * 0.12, n.size * 0.76))

func _item_sprite(slot_id: String, parent: Control, art: String, item: Dictionary, color: int, at: Vector2, width: float, centred: bool) -> Control:
	var t := _house_tex(art)
	var n: Control
	if t:
		var r := TextureRect.new()
		r.texture = t
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.size = Vector2(width, width * t.get_height() / t.get_width())
		r.material = _tint(TINT, item, color)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		n = r
		var a: Array = item.get("anchor", [t.get_width() / 2.0, t.get_height() * (0.5 if centred else 0.92)])
		n.position = at - Vector2(a[0], a[1]) * (width / t.get_width())
	else:
		var tint: Color = Color(house.colors[color].hex) if color >= 0 else Color(item.get("main", DEFAULT_MAIN))
		n = Kit.picture("", Vector2(width, width * 0.8), String(item.name), tint.lerp(Color.WHITE, 0.35))
		n.position = at - Vector2(width / 2, width * (0.4 if centred else 0.75))
	parent.add_child(n)
	drawn[slot_id].append(n)
	return n

## A wallpaper or floor pattern laid on one surface of the room, multiplied
## with the plain surface so the room's own light and shadow stay.
func _pattern(slot_id: String, parent: Control, face: Dictionary, item: Dictionary, color: int, tile: float) -> void:
	var pts := PackedVector2Array()
	for p in face.points:
		pts.append(Vector2(p[0], p[1]))
	hit[slot_id].append(pts)
	var poly := Polygon2D.new()
	poly.polygon = pts
	var t := _house_tex(item.id)
	if t:
		var ax := Vector2(face.ax[0], face.ax[1])
		var ay := Vector2(face.ay[0], face.ay[1])
		var base := Vector2(face.base[0], face.base[1])
		var k := Vector2(t.get_width(), t.get_height()) / tile
		var uv := PackedVector2Array()
		var det := ax.x * ay.y - ax.y * ay.x
		for p in pts:
			var d := p - base
			uv.append(Vector2((d.x * ay.y - d.y * ay.x) / det, (ax.x * d.y - ax.y * d.x) / det) * k)
		poly.texture = t
		poly.uv = uv
		poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		poly.material = _tint(TINT_MUL, item, color)
		poly.material.set_shader_parameter("min_sat", 0.03)
	else:
		var c: Color = Color(house.colors[color].hex) if color >= 0 else Color(item.get("main", DEFAULT_MAIN))
		poly.color = c.lerp(Color.WHITE, 0.55)
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
		poly.material = m
	parent.add_child(poly)
	drawn[slot_id].append(poly)

func _refresh_markers() -> void:
	for c in markers.get_children():
		c.queue_free()
	for s in room.slots:
		if not _shown(s.id).is_empty():
			continue
		var at := _marker_at(s.id)
		var size := Vector2(200, 100) if s.kind == "item" or s.kind == "floor" else Vector2(150, 75)
		var b := TextureButton.new()
		b.position = at - size / 2
		b.size = size
		b.pivot_offset = size / 2
		var t := Kit.tex("slot_plus")
		if t:
			b.texture_normal = t
			b.ignore_texture_size = true
			b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		else:
			var p := Kit.picture("", size, "+", Color(1, 1, 1, 0.55))
			p.modulate.a = 0.9
			b.add_child(p)
		var id: String = s.id
		b.pressed.connect(func(): _open_drawer(id))
		markers.add_child(b)
		var tw := b.create_tween().set_loops()
		tw.tween_property(b, "scale", Vector2(1.08, 1.08), 0.6).set_trans(Tween.TRANS_SINE)
		tw.tween_property(b, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE)

func _marker_at(slot_id: String) -> Vector2:
	var m: Dictionary = layout.get("markers", {})
	if m.has(slot_id):
		return Vector2(m[slot_id][0], m[slot_id][1])
	var p: Array = layout.slots[slot_id].pos
	return Vector2(p[0], p[1]) - Vector2(0, 30)

func _refresh_header() -> void:
	if not is_instance_valid(balance):
		return
	balance.text = str(app.profile.data.coins)
	var p: Vector2i = app.profile.house_progress(room)
	progress.text = "装修度 %d/%d" % [p.x, p.y]

# ---------------------------------------------------------------- picking

func _on_scene_input(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
		return
	var at: Vector2 = ev.position
	if panel:
		_close_panel()
		return
	var id := _slot_at(at)
	if id == "" or id == selected:
		_select("")
	else:
		app.sound.play("tap")
		_select(id)

## The placed thing under a point: furniture front to back, then curtains,
## walls and floor.
func _slot_at(at: Vector2) -> String:
	var kids: Array = layer.items.get_children()
	kids.reverse()
	for n in kids:
		for id in drawn:
			if drawn[id].has(n) and (hit[id][0] as Rect2).has_point(at):
				return id
	for id in ["curtain", "wallpaper", "floor"]:
		for h in hit.get(id, []):
			if (h is Rect2 and h.has_point(at)) or (h is PackedVector2Array and Geometry2D.is_point_in_polygon(at, h)):
				return id
	return ""

func _select(id: String) -> void:
	selected = id
	for c in tools.get_children():
		c.queue_free()
	for id2 in drawn:
		for n in drawn[id2]:
			if n is CanvasItem:
				(n as CanvasItem).self_modulate = Color(1.12, 1.12, 1.12) if id2 == id and n is Control else Color.WHITE
	if id == "":
		return
	var box := _bounds(id)
	var x := minf(box.end.x + 20, 1080 - 150)
	var y := clampf(box.get_center().y - 200, 260, PANEL_Y - 420)
	var buttons := [["tool_color", "色", func(): _open_colors(id)], ["tool_swap", "换", func(): _open_drawer(id)], ["tool_back", "返", func(): _select("")]]
	for i in buttons.size():
		var b := Kit.round_button(buttons[i][0], 130, buttons[i][1])
		b.position = Vector2(x, y + i * 140)
		b.pressed.connect(buttons[i][2])
		tools.add_child(b)
		b.scale = Vector2.ZERO
		b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.2).set_delay(i * 0.05).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _bounds(id: String) -> Rect2:
	var box := Rect2()
	var first := true
	for h in hit.get(id, []):
		var r: Rect2
		if h is Rect2:
			r = h
		else:
			r = Rect2(h[0], Vector2.ZERO)
			for p in h:
				r = r.expand(p)
		box = r if first else box.merge(r)
		first = false
	return box

# ---------------------------------------------------------------- bottom panel

func _new_panel(title: String) -> Control:
	# A preview left from the previous drawer goes back first.
	_close_panel()
	panel = Control.new()
	panel.position = Vector2(0, PANEL_Y + Kit.band_shift(1.0))
	panel.size = Vector2(1080, 1920 - PANEL_Y)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	Kit.nine(panel, "card_wide", Rect2(14, 40, 1052, 1920 - PANEL_Y + Kit.extra), [90, 90, 90, 90], Color("#FFF4DE"), 0.72)
	Kit.art(panel, "popup_ribbon", Rect2(250, -40, 580, 168))
	Kit.text_at(panel, title, Rect2(360, -22, 360, 84), 60, Kit.CREAM, Kit.OUTLINE, 10)
	var close := Kit.art_button(panel, "button_close", Rect2(944, 34, 110, 110), "×")
	close.pressed.connect(func(): _close_panel())
	panel.position.y += 300
	panel.create_tween().tween_property(panel, "position:y", panel.position.y - 300, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return panel

## Closes the panel; an unbought preview goes back to what was there.
func _close_panel(restore := true) -> void:
	if panel:
		panel.queue_free()
		panel = null
	if restore and not preview.is_empty():
		var id: String = preview.slot
		preview = {}
		_draw_slot(id)
		_refresh_markers()
		if selected == id:
			_select(id)

func _show_preview(slot_id: String, item_id: String, color: int) -> void:
	var old: String = preview.get("slot", "")
	preview = {"slot": slot_id, "item": item_id, "color": color}
	if old != "" and old != slot_id:
		_draw_slot(old)
	_draw_slot(slot_id)
	_refresh_markers()

## Item drawer for one slot: its three styles with price or "owned".
func _open_drawer(slot_id: String) -> void:
	_select("")
	var slot := _slot_def(slot_id)
	var p := _new_panel(String(slot.name))
	var current: Dictionary = app.profile.house_slot(room.id, slot_id)
	var confirm := Kit.pill("", "pink", Vector2(620, 150))
	confirm.position = Vector2(230, 470)
	confirm.visible = false
	p.add_child(confirm)
	var cards: Array = []
	for i in slot.items.size():
		var it: Dictionary = slot.items[i]
		var card := Control.new()
		card.position = Vector2(52 + i * 330, 120)
		card.size = Vector2(316, 330)
		p.add_child(card)
		cards.append(card)
		Kit.nine(card, "card_square", Rect2(Vector2.ZERO, card.size), [90, 90, 90, 90], Color("#FFF4DE"), 0.6)
		var icon := _icon(it)
		icon.position = Vector2(28, 14)
		card.add_child(icon)
		Kit.text_at(card, String(it.name), Rect2(10, 196, 296, 50), 36, Kit.BROWN)
		var owned: bool = app.profile.house_owns(it.id)
		if current.get("item", "") == it.id:
			Kit.nine(card, "button_pill_cream", Rect2(48, 252, 220, 64), [60, 30, 60, 30], Color("#FFF1DC"), 0.5)
			Kit.text_at(card, "使用中", Rect2(48, 254, 220, 58), 36, Kit.BROWN)
		elif owned:
			Kit.nine(card, "button_pill_green", Rect2(48, 252, 220, 64), [60, 30, 60, 30], Color("#7CC84A"), 0.5)
			Kit.text_at(card, "已拥有", Rect2(48, 254, 220, 58), 36, Kit.CREAM, Color("#3D7415"), 6)
		else:
			Kit.nine(card, "price_chip", Rect2(48, 252, 220, 64), [40, 20, 40, 20], Color("#FFF1DC"))
			Kit.art(card, "coin_small", Rect2(60, 258, 52, 52))
			Kit.text_at(card, str(int(it.price)), Rect2(110, 254, 150, 58), 40, Kit.BROWN)
		var tap := Kit.hit_area(card, Rect2(Vector2.ZERO, card.size))
		tap.pressed.connect(func():
			app.sound.play("tap")
			for k in cards.size():
				(cards[k] as Control).modulate = Color(1.15, 1.15, 1.15) if k == i else Color(0.92, 0.92, 0.92)
			_show_preview(slot_id, it.id, int(current.get("color", -1)))
			_set_pill(confirm, "使用" if owned else "购买", "" if owned else str(int(it.price)))
			confirm.visible = current.get("item", "") != it.id)
	confirm.pressed.connect(func(): _buy(slot_id))

func _set_pill(b: TextureButton, text: String, price: String) -> void:
	for c in b.get_children():
		if c is Label:
			c.text = text + ("  " + price if price != "" else "")
			c.add_theme_font_size_override("font_size", 68)

func _icon(it: Dictionary) -> Control:
	var t := _house_tex(it.id)
	if t == null:
		t = _house_tex(it.id + "_B")
	if t:
		var r := TextureRect.new()
		r.texture = t
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.size = Vector2(260, 180)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return r
	return Kit.picture("", Vector2(260, 180), String(it.name), Color(it.get("main", DEFAULT_MAIN)).lerp(Color.WHITE, 0.35))

func _buy(slot_id: String) -> void:
	if preview.is_empty():
		return
	var slot := _slot_def(slot_id)
	var it := _item_def(slot, preview.item)
	var was_empty: bool = app.profile.house_slot(room.id, slot_id).is_empty()
	if not app.profile.house_place(room.id, slot_id, it):
		app.sound.play("nope")
		app.toast("金币不足")
		return
	preview = {}
	app.save()
	_close_panel(false)
	_draw_slot(slot_id)
	_refresh_markers()
	_drop_in(slot_id)
	if was_empty:
		var p: Vector2i = app.profile.house_progress(room)
		if p.x == p.y:
			get_tree().create_timer(0.9).timeout.connect(_room_done)
		elif p.x * 4 / p.y != (p.x - 1) * 4 / p.y:
			app.toast("装修度 %d%%!" % (p.x * 4 / p.y * 25))

## Colour panel: eight sweets colours; the item's own colour is the ball
## closest to it, so picking that ball keeps the art untouched.
func _open_colors(slot_id: String) -> void:
	var e: Dictionary = app.profile.house_slot(room.id, slot_id)
	if e.is_empty():
		return
	var slot := _slot_def(slot_id)
	var item := _item_def(slot, e.item)
	var own := _nearest_color(Color(item.get("main", DEFAULT_MAIN)))
	var p := _new_panel("换颜色")
	var balls: Array = []
	var pick := int(e.color) if int(e.color) >= 0 else own
	for i in house.colors.size():
		var c: Dictionary = house.colors[i]
		var b := Kit.round_button("ball_" + c.id, 116, "", Color(c.hex))
		if Kit.tex("ball_" + c.id) == null:
			var dot := Kit.picture("", Vector2(76, 76), "", Color(c.hex))
			dot.position = Vector2(20, 20)
			b.add_child(dot)
		b.position = Vector2(42 + i * 126, 190)
		p.add_child(b)
		balls.append(b)
		b.pressed.connect(func():
			app.sound.play("tap")
			_mark_ball(balls, i)
			_show_preview(slot_id, e.item, -1 if i == own else i))
	_mark_ball(balls, pick)
	var ok := Kit.pill("确定", "pink", Vector2(620, 150))
	ok.position = Vector2(230, 420)
	p.add_child(ok)
	ok.pressed.connect(func():
		app.sound.play("tap")
		if not preview.is_empty():
			app.profile.house_set_color(room.id, slot_id, int(preview.color))
			app.save()
			preview = {}
		_close_panel(false)
		_draw_slot(slot_id)
		_select(slot_id))

## The chosen ball wears the gold ring and the tick (mockup H1_A).
func _mark_ball(balls: Array, i: int) -> void:
	for k in balls.size():
		var b: Control = balls[k]
		for c in b.get_children():
			if c.has_meta("mark"):
				c.queue_free()
		b.pivot_offset = b.size / 2
		b.scale = Vector2(1.1, 1.1) if k == i else Vector2.ONE
		if k != i:
			continue
		var ring := Kit.picture("ball_selected_ring", b.size * 1.1)
		ring.position = -b.size * 0.05
		ring.set_meta("mark", true)
		b.add_child(ring)
		if Kit.tex("ball_check"):
			var tick := Kit.picture("ball_check", Vector2(54, 41))
			tick.position = (b.size - tick.size) / 2
			tick.set_meta("mark", true)
			b.add_child(tick)

func _nearest_color(c: Color) -> int:
	var best := 0
	var bd := INF
	for i in house.colors.size():
		var h: Color = Color(house.colors[i].hex)
		var d := Vector3(c.r - h.r, c.g - h.g, c.b - h.b).length_squared()
		if d < bd:
			bd = d
			best = i
	return best

# ---------------------------------------------------------------- moments

## New furniture drops in with a little bounce and sparkles.
func _drop_in(slot_id: String) -> void:
	app.sound.play("unlock")
	for n in drawn.get(slot_id, []):
		if n is Control:
			var c: Control = n
			var to := c.position
			c.position = to - Vector2(0, 120)
			c.modulate.a = 0.0
			var tw := c.create_tween().set_parallel()
			tw.tween_property(c, "position", to, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			tw.tween_property(c, "modulate:a", 1.0, 0.15)
		elif n is Polygon2D:
			var poly: Polygon2D = n
			poly.modulate.a = 0.0
			poly.create_tween().tween_property(poly, "modulate:a", 1.0, 0.5)
	_sparkles(_bounds(slot_id).get_center())

func _sparkles(at: Vector2) -> void:
	for i in 12:
		var s := Kit.picture("fx_sparkle", Vector2(60, 60), "", Color("#FFE58A"))
		s.position = at - Vector2(30, 30)
		s.pivot_offset = Vector2(30, 30)
		layer.fx.add_child(s)
		var a := TAU * i / 12.0 + randf() * 0.3
		var tw := s.create_tween().set_parallel()
		tw.tween_property(s, "position", s.position + Vector2(cos(a), sin(a)) * randf_range(90, 170), 0.6).set_delay(0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(s, "rotation", randf_range(-2, 2), 0.6).set_delay(0.3)
		tw.tween_property(s, "modulate:a", 0.0, 0.3).set_delay(0.6)
		tw.chain().tween_callback(s.queue_free)

## Room finished: the empty room wipes away to show the decorated one, then
## the reward (mockup H3_A).
func _room_done() -> void:
	if not app.profile.house_reward_ready(room):
		return
	_select("")
	var base := _house_tex("room_base")
	var clip := Control.new()
	clip.clip_contents = true
	clip.size = Vector2(1080, PANEL_Y)
	clip.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(clip)
	if base:
		_sprite(clip, "room_base", Vector2.ZERO)
	else:
		var c := ColorRect.new()
		c.color = Color("#FCE4EC")
		c.size = clip.size
		clip.add_child(c)
	var tw := clip.create_tween()
	tw.tween_interval(0.5)
	tw.tween_property(clip, "size:x", 0.0, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func():
		clip.queue_free()
		for i in 4:
			_sparkles(Vector2(randf_range(200, 880), randf_range(400, 1000)))
		var r: Dictionary = app.profile.claim_house_reward(room)
		app.save()
		app.popups.reward(r, Callable(), "装修完成!"))
