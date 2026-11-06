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
var boosters_used := 0
var last_pick: Dictionary = {}   # undo record of the most recent unmatched pick
var solution: Array = []         # board tile ids in an order known to win from now
var rng := RandomNumberGenerator.new()

func _init(level_def: Dictionary) -> void:
	level = level_def
	rng.seed = int(level_def.seed) * 7919
	var made := Generator.generate_with_solution(level_def)
	for t in made.tiles:
		t["place"] = "board"
		tiles[t.id] = t
	solution = made.order

func board_tiles() -> Array:
	return tiles.values().filter(func(t): return t.place == "board")

func is_free(id: int) -> bool:
	var t: Dictionary = tiles[id]
	return t.place == "board" and not BoardRules.covered(t, board_tiles())

func can_pick(id: int) -> bool:
	if not tiles.has(id) or tray.size() >= TRAY_SIZE or is_finished():
		return false
	var t: Dictionary = tiles[id]
	return (t.place == "board" and is_free(id)) or t.place == "hold"

## Moves a tile into the tray next to its kind and resolves a triple.
## Returns {ok, index, from, matched: [ids], won, lost}.
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
	var matched := _take_triple(int(t.type))
	solution.erase(id)
	last_pick = {} if not matched.is_empty() else {"id": id, "from": from, "hold_index": hold_index}
	return {"ok": true, "index": index, "from": from, "matched": matched, "won": is_won(), "lost": is_lost()}

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

func can_undo() -> bool:
	return boosters.undo > 0 and not last_pick.is_empty() and not is_finished()

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
	last_pick = {}
	_spend("undo")
	return {"ok": true, "id": id, "to": to}

func can_move_out() -> bool:
	return boosters.move_out > 0 and hold.is_empty() and not tray.is_empty() and not is_finished()

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
	var order := Generator.removal_order(tiles.values(), rng, board_ids)
	var free_slots := TRAY_SIZE - tray.size()
	var max_open := clampi((free_slots - 1) / 2, 1, 3)
	var types := Generator.assign_along(order.size(), groups, max_open, rng, pending)
	for i in order.size():
		tiles[order[i]].type = types[i]
	solution = order
	last_pick = {}
	_spend("shuffle")
	return {"ok": true, "ids": board_ids}

func _spend(kind: String) -> void:
	boosters[kind] -= 1
	boosters_used += 1

func remaining() -> int:
	return tiles.values().filter(func(t): return t.place != "gone").size()

func is_won() -> bool:
	return remaining() == 0

func is_lost() -> bool:
	return tray.size() >= TRAY_SIZE and not is_won()

func is_finished() -> bool:
	return is_won() or is_lost()

func stars() -> int:
	return 3 if boosters_used == 0 else (2 if boosters_used == 1 else 1)
