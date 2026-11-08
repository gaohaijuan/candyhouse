extends RefCounted
## Complete rules state for one level. Presentation reads this and animates;
## it never decides rules itself.

const BoardRules = preload("res://scripts/core/board_rules.gd")
const Generator = preload("res://scripts/core/level_generator.gd")

const TRAY_SIZE := 7
const HOLD_SIZE := 3
const MATCH := 3

var level: Dictionary
var tiles: Dictionary = {}       # id -> {id, layer, x, y, type, place}
var tray: Array = []             # tile ids, left to right
var hold: Array = []             # tile ids parked by "move out"
var boosters := {"undo": 1, "move_out": 1, "shuffle": 1}
var tray_size := TRAY_SIZE       # 8 with the "extra slot" start booster
var boosters_used := 0
var last_pick: Dictionary = {}   # undo record of the most recent unmatched pick
var solution: Array = []         # board tile ids in an order known to win from now
var cover: Dictionary = {}       # id -> ids that can cover it (fixed geometry)
var covers: Dictionary = {}      # id -> ids it can cover (reverse of `cover`)
var rng := RandomNumberGenerator.new()
var burned := false               # a candle ran out of steps on the board

func _init(level_def: Dictionary, empty := false) -> void:
	if empty:
		return
	level = level_def
	rng.seed = int(level_def.seed) * 7919
	var made: Dictionary
	if level_def.has("board"):
		made = {"tiles": level_def.board.tiles.duplicate(true), "order": level_def.board.order.duplicate()}
		for t in made.tiles:
			for k in ["id", "layer", "x", "y", "type", "stack", "depth", "ice", "key", "lock", "fuse"]:
				if t.has(k):
					t[k] = int(t[k])
	else:
		made = Generator.generate_with_solution(level_def)
	for t in made.tiles:
		t["place"] = "board"
		tiles[t.id] = t
	solution = []
	for id in made.order:
		solution.append(int(id))
	cover = BoardRules.coverers(made.tiles)
	for t in made.tiles:
		covers[t.id] = []
	for id in cover:
		for c in cover[id]:
			covers[c].append(id)

func board_tiles() -> Array:
	return tiles.values().filter(func(t): return t.place == "board")

func is_free(id: int) -> bool:
	if tiles[id].place != "board":
		return false
	for c in cover[id]:
		if tiles[c].place == "board":
			return false
	return true

## What the player can see: mystery tiles keep their dessert hidden until they
## are taken; buried box tiles are blank until they reach the top of the box.
func type_known(id: int) -> bool:
	var t: Dictionary = tiles[id]
	if t.get("mystery", false) and not t.get("revealed", false):
		return false
	if t.has("stack") and not is_free(id):
		return false
	return true

func is_frozen(id: int) -> bool:
	return int(tiles[id].get("ice", 0)) > 0

func is_locked(id: int) -> bool:
	return tiles[id].has("lock")

## Free, not frozen and not locked: the player may take it now.
func is_takeable(id: int) -> bool:
	return is_free(id) and not is_frozen(id) and not is_locked(id)

func can_pick(id: int) -> bool:
	if not tiles.has(id) or tray.size() >= tray_size or is_finished():
		return false
	var t: Dictionary = tiles[id]
	return (t.place == "board" and is_takeable(id)) or t.place == "hold"

## Moves a tile into the tray next to its kind and resolves a triple.
## Returns {ok, index, from, matched, thawed, unlocked, burning, won, lost}:
## `thawed` frozen tiles whose ice dropped, `unlocked` tiles whose lock opened,
## `burning` candle tiles whose steps dropped (lost when one reaches zero).
func pick(id: int) -> Dictionary:
	if not can_pick(id):
		return {"ok": false}
	var t: Dictionary = tiles[id]
	var from: String = t.place
	var hold_index := hold.find(id)
	if from == "hold":
		hold.remove_at(hold_index)
	var index := _insert_index(int(t.type))
	tray.insert(index, id)
	t.place = "tray"
	t["revealed"] = true
	var matched := _take_triple(int(t.type))
	solution.erase(id)
	var thawed: Array = []
	var unlocked: Array = []
	if not matched.is_empty():
		var keys: Array = []
		for m in matched:
			if tiles[m].has("key"):
				keys.append(int(tiles[m].key))
		for other in tiles.values():
			if other.place == "board" and int(other.get("ice", 0)) > 0:
				other.ice = int(other.ice) - 1
				thawed.append(other.id)
			if other.has("lock") and keys.has(int(other.lock)):
				other.erase("lock")
				unlocked.append(other.id)
	var burning: Array = []
	for other in tiles.values():
		if other.place == "board" and other.has("fuse"):
			other.fuse = int(other.fuse) - 1
			burning.append(other.id)
			if int(other.fuse) <= 0:
				burned = true
	last_pick = {} if not matched.is_empty() else {"id": id, "from": from, "hold_index": hold_index, "burning": burning}
	return {"ok": true, "index": index, "from": from, "matched": matched, "thawed": thawed, "unlocked": unlocked, "burning": burning, "won": is_won(), "lost": is_lost()}

func _insert_index(type: int) -> int:
	var last := -1
	for i in tray.size():
		if int(tiles[tray[i]].type) == type:
			last = i
	return tray.size() if last < 0 else last + 1

func _take_triple(type: int) -> Array:
	var same: Array = tray.filter(func(id): return int(tiles[id].type) == type)
	if same.size() < MATCH:
		return []
	var matched := same.slice(0, MATCH)
	for id in matched:
		tray.erase(id)
		tiles[id].place = "gone"
	return matched

## Undo also rescues the pick that filled the tray or burned out a candle.
func can_undo() -> bool:
	return boosters.undo > 0 and not last_pick.is_empty() and not is_won()

## Returns the tile to where it came from. Result {ok, id, to}.
func undo() -> Dictionary:
	if not can_undo():
		return {"ok": false}
	var id: int = last_pick.id
	tray.erase(id)
	if last_pick.from == "hold":
		hold.insert(mini(int(last_pick.hold_index), hold.size()), id)
		tiles[id].place = "hold"
	else:
		tiles[id].place = "board"
	var to: String = last_pick.from
	for b in last_pick.get("burning", []):
		tiles[b].fuse = int(tiles[b].fuse) + 1
	burned = false
	last_pick = {}
	_spend("undo")
	return {"ok": true, "id": id, "to": to}

## Also allowed after a full or stuck tray ends the round: parking tiles frees
## the tray and play continues. A burned-out candle cannot be saved this way.
func can_move_out() -> bool:
	return boosters.move_out > 0 and hold.is_empty() and not tray.is_empty() and not is_won() and not burned

## Parks up to three leftmost tray tiles in the hold row. Result {ok, ids}.
func move_out() -> Dictionary:
	if not can_move_out():
		return {"ok": false}
	var ids := tray.slice(0, mini(HOLD_SIZE, tray.size()))
	for id in ids:
		tray.erase(id)
		tiles[id].place = "hold"
		hold.append(id)
	last_pick = {}
	_spend("move_out")
	return {"ok": true, "ids": ids}

func can_shuffle() -> bool:
	return boosters.shuffle > 0 and board_tiles().size() > 1 and not is_finished()

## Re-deals board types so the remaining tiles still have a winning order that
## first completes the partial triples waiting in tray and hold.
func shuffle() -> Dictionary:
	if not can_shuffle():
		return {"ok": false}
	var board_ids: Array = board_tiles().map(func(t): return t.id)
	var counts: Dictionary = {}
	for id in board_ids:
		counts[tiles[id].type] = int(counts.get(tiles[id].type, 0)) + 1
	var pending: Array = []
	for type in counts.keys():
		var outside := (tray + hold).filter(func(id): return int(tiles[id].type) == int(type)).size()
		var need := (MATCH - outside % MATCH) % MATCH
		for i in need:
			pending.append(type)
		counts[type] -= need
	var groups: Array = []
	for type in counts.keys():
		for g in int(counts[type]) / MATCH:
			groups.append(type)
	for i in range(groups.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = groups[i]; groups[i] = groups[j]; groups[j] = tmp
	var free_slots := tray_size - tray.size()
	var max_open := clampi((free_slots - 1) / 2, 1, 3)
	var ice_min := Generator.ice_min_positions(tiles.values(), max_open, pending.size())
	var old_types := {}
	for bid in board_ids:
		old_types[bid] = tiles[bid].type
	var found := false
	for attempt in 40:
		var order := Generator.removal_order(tiles.values(), rng, board_ids, ice_min)
		if order.size() != board_ids.size():
			continue
		var types := Generator.assign_along(order.size(), groups, max_open, rng, pending)
		for i in order.size():
			tiles[order[i]].type = types[i]
		var plan: Array = hold.duplicate()
		plan.append_array(order)
		if wins_with(plan):
			solution = order
			found = true
			break
	if not found:
		# Ice, locks or candles leave no safe re-deal right now; keep the deal.
		for bid in board_ids:
			tiles[bid].type = old_types[bid]
		return {"ok": false}
	last_pick = {}
	_spend("shuffle")
	return {"ok": true, "ids": board_ids}

## "Magnet" start booster: clears one whole triple from the board before play.
## Picks the dessert of the earliest winning move whose three tiles are all on
## the board and not locked or frozen, so the stored winning order stays valid.
## Counts as a match (thaws ice, opens locks). Returns {ok, ids, unlocked, thawed}.
func magnet() -> Dictionary:
	var tried := {}
	for sid in solution:
		var type: int = tiles[sid].type
		if tried.has(type):
			continue
		tried[type] = true
		# The first three of this dessert along the winning order form one
		# complete triple there, so removing exactly them keeps the order valid.
		var ids: Array = []
		for oid in solution:
			if int(tiles[oid].type) == type:
				ids.append(oid)
			if ids.size() == MATCH:
				break
		if ids.size() < MATCH:
			continue
		var blocked := false
		for id in ids:
			if tiles[id].place != "board" or tiles[id].has("lock") or int(tiles[id].get("ice", 0)) > 0:
				blocked = true
		if blocked:
			continue
		var keys: Array = []
		for id in ids:
			tiles[id].place = "gone"
			tiles[id]["revealed"] = true
			solution.erase(id)
			if tiles[id].has("key"):
				keys.append(int(tiles[id].key))
		var unlocked: Array = []
		var thawed: Array = []
		for other in tiles.values():
			if other.place != "board":
				continue
			if int(other.get("ice", 0)) > 0:
				other.ice = int(other.ice) - 1
				thawed.append(other.id)
			if other.has("lock") and keys.has(int(other.lock)):
				other.erase("lock")
				unlocked.append(other.id)
		return {"ok": true, "ids": ids, "unlocked": unlocked, "thawed": thawed}
	return {"ok": false}

## Copy of the rules state for look-ahead checks.
func clone():
	var c = get_script().new({}, true)
	c.level = level
	c.tiles = tiles.duplicate(true)
	c.tray = tray.duplicate()
	c.hold = hold.duplicate()
	c.boosters = boosters.duplicate()
	c.cover = cover
	c.covers = covers
	c.burned = burned
	c.tray_size = tray_size
	return c

## True when taking `plan` (hold tiles, then board tiles) in order wins.
func wins_with(plan: Array) -> bool:
	var c = clone()
	for id in plan:
		if not c.pick(id).ok:
			return false
	return c.is_won()

func _spend(kind: String) -> void:
	boosters[kind] -= 1
	boosters_used += 1

## True once the player has taken any tile (leaving now costs a life).
func started() -> bool:
	return tiles.values().any(func(t): return t.place != "board")

func remaining() -> int:
	return tiles.values().filter(func(t): return t.place != "gone").size()

func is_won() -> bool:
	return remaining() == 0

## True while some tile could still be moved into the tray.
func has_moves() -> bool:
	if tray.size() >= tray_size:
		return false
	if not hold.is_empty():
		return true
	for t in board_tiles():
		if is_takeable(t.id):
			return true
	return false

## Lost when the tray is full, a candle burned out, or nothing can be taken.
func is_lost() -> bool:
	return not is_won() and (burned or not has_moves())

func lose_reason() -> String:
	if burned:
		return "candle"
	return "tray" if tray.size() >= tray_size else "stuck"

func is_finished() -> bool:
	return is_won() or is_lost()

func stars() -> int:
	return 3 if boosters_used == 0 else (2 if boosters_used == 1 else 1)
