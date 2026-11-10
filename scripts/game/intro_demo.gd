extends Control
## Looping demo for a new mechanic's intro popup: a few real tiles, a small
## tray and the tutorial hand acting the rule out (mystery, ice, stacks,
## locks, candles). Built from the same tile art as the board.

const TileView = preload("res://scripts/game/tile_view.gd")
const Art = preload("res://scripts/game/art.gd")
const TS := 132.0                 # board tile side
const TRAY_H := 150.0
const A := 0                      # macaron
const B := 1                      # donut
const C := 2                      # cupcake

var kind := ""
var tray_slots: Array = []        # centres of the tray cells
var tray_tiles: Array = []
var hand: TextureRect
var run_id := 0
var planned := 0                  # tray cells taken once the queued actions run

func setup(mechanic: String, width: float, height: float) -> void:
	kind = mechanic
	size = Vector2(width, height)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_run.call_deferred()

func _run() -> void:
	if not is_inside_tree():
		return
	run_id += 1
	for c in get_children():
		c.queue_free()
	tray_tiles.clear()
	planned = 0
	_build_tray()
	hand = TextureRect.new()
	hand.texture = Art.ui("tutorial_hand")
	hand.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hand.size = Vector2(150, 150)
	hand.position = Vector2(size.x - 120, size.y - TRAY_H - 140)
	hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand.modulate.a = 0.0
	add_child(hand)
	var tw := create_tween()
	match kind:
		"mystery": _mystery(tw)
		"ice": _ice(tw)
		"stacks": _stacks(tw)
		"locks": _locks(tw)
		"candles": _candles(tw)
	tw.tween_interval(1.4)
	var me := run_id
	tw.tween_callback(func():
		if me == run_id:
			_run())

# ---------------------------------------------------------------- pieces

func _build_tray() -> void:
	var w := minf(size.x, 7 * TS * 0.86 + 60)
	var r := Rect2((size.x - w) / 2, size.y - TRAY_H, w, TRAY_H)
	var t := Art.ui("tray")
	if t:
		var tr := TextureRect.new()
		tr.texture = t
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.position = r.position
		tr.size = r.size
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tr)
	else:
		var p := ColorRect.new()
		p.color = Color("#F7E3CC")
		p.position = r.position
		p.size = r.size
		add_child(p)
	tray_slots.clear()
	for i in 7:
		tray_slots.append(Vector2(r.position.x + r.size.x * (0.075 + i * 0.1417), r.position.y + r.size.y * 0.47))

func _tile(type: int, at: Vector2) -> TileView:
	var v := TileView.new(-1, type, TS)
	v.position = at - v.size / 2
	add_child(v)
	return v

## Board cell centre on a 5 x 2 grid above the tray.
func _cell(col: float, row: float) -> Vector2:
	var top := (size.y - TRAY_H) / 2 - TS * 0.54
	return Vector2(size.x / 2 + (col - 2) * TS * 1.08, top + row * TS * 1.08)

# ---------------------------------------------------------------- actions (all chained on one tween)

func _tap(tw: Tween, v: Control) -> void:
	tw.tween_callback(func():
		hand.texture = Art.ui("tutorial_hand")
		move_child(hand, get_child_count() - 1))
	tw.tween_property(hand, "modulate:a", 1.0, 0.15)
	tw.tween_property(hand, "position", v.position + v.size * Vector2(0.35, 0.45), 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func():
		var p := Art.ui("tutorial_hand_press")
		if p:
			hand.texture = p
		hand.scale = Vector2(0.92, 0.92))
	tw.tween_interval(0.14)
	tw.tween_callback(func():
		hand.texture = Art.ui("tutorial_hand")
		hand.scale = Vector2.ONE)

## Tap a tile and fly it into the next free tray cell.
func _take(tw: Tween, v: TileView, landed := Callable()) -> void:
	_tap(tw, v)
	tw.tween_callback(func():
		move_child(v, get_child_count() - 1)
		move_child(hand, get_child_count() - 1)
		tray_tiles.append(v))
	var slot: Vector2 = tray_slots[planned]
	planned += 1
	var k := 0.78
	tw.tween_property(v, "position", slot - v.size / 2, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(v, "scale", Vector2(k, k), 0.32)
	if landed.is_valid():
		tw.tween_callback(landed)

## The last three tray tiles pop and vanish.
func _clear3(tw: Tween) -> void:
	planned -= 3
	tw.tween_interval(0.1)
	tw.tween_callback(func():
		var three: Array = tray_tiles.slice(tray_tiles.size() - 3)
		tray_tiles.resize(tray_tiles.size() - 3)
		for v in three:
			var t := (v as Control).create_tween()
			t.tween_property(v, "scale", Vector2(0.95, 0.95), 0.1)
			t.tween_property(v, "scale", Vector2.ZERO, 0.18)
			t.tween_callback(v.queue_free)
			_sparkle((v as Control).position + (v as Control).size / 2))
	tw.tween_interval(0.35)

func _shake(tw: Tween, v: Control) -> void:
	tw.tween_callback(func():
		var x := v.position.x
		var t := v.create_tween()
		for d in [14.0, -14.0, 10.0, -10.0, 0.0]:
			t.tween_property(v, "position:x", x + d, 0.05))
	tw.tween_interval(0.3)

func _pop(tw: Tween, v: Control) -> void:
	tw.tween_property(v, "scale", Vector2(1.15, 1.15), 0.1)
	tw.tween_property(v, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK)

func _sparkle(at: Vector2) -> void:
	for i in 6:
		var s := TextureRect.new()
		s.texture = Art.ui("fx_sparkle")
		if s.texture == null:
			return
		s.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		s.size = Vector2(44, 44)
		s.pivot_offset = s.size / 2
		s.position = at - s.size / 2
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(s)
		var a := TAU * i / 6.0
		var t := s.create_tween().set_parallel()
		t.tween_property(s, "position", s.position + Vector2(cos(a), sin(a)) * 70, 0.4)
		t.tween_property(s, "modulate:a", 0.0, 0.4)
		t.chain().tween_callback(s.queue_free)

func _fade_hand(tw: Tween) -> void:
	tw.tween_property(hand, "modulate:a", 0.0, 0.2)

# ---------------------------------------------------------------- the five demos

## Mystery: the "?" tile shows its dessert once it reaches the tray.
func _mystery(tw: Tween) -> void:
	var m := _tile(A, _cell(0, 0.5))
	m.face_down = true
	var a1 := _tile(A, _cell(2, 0))
	var a2 := _tile(A, _cell(4, 0.5))
	_tile(B, _cell(1, 1))
	_tile(C, _cell(3, 1))
	_tile(B, _cell(2, 1))
	tw.tween_interval(0.5)
	_take(tw, m, func():
		var t := m.create_tween()
		t.tween_property(m, "scale:x", 0.0, 0.12)
		t.tween_callback(func(): m.face_down = false)
		t.tween_property(m, "scale:x", 0.78, 0.12))
	tw.tween_interval(0.5)
	_take(tw, a1)
	_take(tw, a2)
	_fade_hand(tw)
	_clear3(tw)

## Ice: each cleared group melts the ice one step; at 0 the tile is free.
func _ice(tw: Tween) -> void:
	var ice := _tile(C, _cell(2, 0.5))
	ice.ice = 2
	var a := [_tile(A, _cell(0, 0)), _tile(A, _cell(1, 0)), _tile(A, _cell(0, 1))]
	var b := [_tile(B, _cell(4, 0)), _tile(B, _cell(4, 1)), _tile(B, _cell(3, 1))]
	tw.tween_interval(0.5)
	for group in [a, b]:
		for v in group:
			_take(tw, v)
		_clear3(tw)
		tw.tween_callback(func():
			ice.ice -= 1
			_sparkle(ice.position + ice.size / 2))
		_pop(tw, ice)
	tw.tween_interval(0.3)
	_take(tw, ice)
	_fade_hand(tw)

## Stacks: only the top tile of a dessert box can be taken; the next one
## comes up after it.
func _stacks(tw: Tween) -> void:
	var step := TS * 0.3
	var left := _cell(0.2, 0).x
	var y := _cell(0, 0.5).y
	var box := TextureRect.new()
	box.texture = Art.ui("box_base_left")
	if box.texture:
		box.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		box.size = Vector2(TS + step * 2 + 40, (TS + step * 2 + 40) * 221.0 / 765.0)
		box.position = Vector2(left - TS / 2 - 20, y + TS * 0.18)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(box)
	var pile: Array = []
	for i in 3:
		var v := _tile([B, B, A][i], Vector2(left + i * step, y))
		v.blank = i < 2
		pile.append(v)
	var a1 := _tile(A, _cell(3, 0.5))
	var a2 := _tile(A, _cell(4, 0.5))
	tw.tween_interval(0.5)
	_tap(tw, pile[0])
	_shake(tw, pile[0])
	_take(tw, pile[2], func():
		(pile[1] as TileView).blank = false
		_pop_now(pile[1]))
	_take(tw, a1)
	_take(tw, a2)
	_fade_hand(tw)
	_clear3(tw)

func _pop_now(v: Control) -> void:
	var t := v.create_tween()
	t.tween_property(v, "scale", Vector2(1.12, 1.12), 0.1)
	t.tween_property(v, "scale", Vector2.ONE, 0.15)

## Locks: a locked tile cannot be taken until the group with its key clears.
func _locks(tw: Tween) -> void:
	var locked := _tile(C, _cell(2, 0.5))
	locked.lock_id = 0
	var k1 := _tile(A, _cell(0, 0))
	k1.key_id = 0
	var a := [k1, _tile(A, _cell(0, 1)), _tile(A, _cell(4, 0.5))]
	tw.tween_interval(0.5)
	_tap(tw, locked)
	_shake(tw, locked)
	for v in a:
		_take(tw, v)
	_clear3(tw)
	tw.tween_callback(func():
		locked.lock_id = -1
		_sparkle(locked.position + locked.size / 2))
	_pop(tw, locked)
	tw.tween_interval(0.3)
	_take(tw, locked)
	_fade_hand(tw)

## Candles: every take burns one step; take the candle before it reaches 0.
func _candles(tw: Tween) -> void:
	var candle := _tile(A, _cell(2, 0.5))
	candle.fuse = 3
	var b := [_tile(B, _cell(0, 0)), _tile(B, _cell(0, 1))]
	var a := [_tile(A, _cell(4, 0)), _tile(A, _cell(4, 1))]
	tw.tween_interval(0.5)
	for v in b:
		_take(tw, v)
		tw.tween_callback(func(): candle.fuse -= 1)
		_pop(tw, candle)
	tw.tween_interval(0.3)
	_take(tw, candle, func():
		candle.fuse = -1
		_sparkle(candle.position + candle.size / 2))
	for v in a:
		_take(tw, v)
	_fade_hand(tw)
	_clear3(tw)
