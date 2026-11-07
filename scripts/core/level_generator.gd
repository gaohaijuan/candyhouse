extends RefCounted
## Builds a level whose tile types guarantee at least one winning order.
## Board tiles live on a half-cell grid: a tile at (x, y) covers [x, x+2) x [y, y+2).
## Side boxes ("stacks") are piles where only the deepest-placed tile is free.

const BoardRules = preload("res://scripts/core/board_rules.gd")
const MAX_ATTEMPTS := 80

static func positions(level: Dictionary) -> Array:
	var tiles: Array = []
	var layer_index := 0
	for layer in level.layers:
		var ox := int(layer.offset[0])
		var oy := int(layer.offset[1])
		var mask: Array = layer.get("mask", [])
		for row in int(layer.rows):
			for col in int(layer.cols):
				if not mask.is_empty() and String(mask[row])[col] != "1":
					continue
				tiles.append({"id": tiles.size(), "layer": layer_index, "x": ox + col * 2, "y": oy + row * 2})
		layer_index += 1
	var s := 0
	for stack in level.get("stacks", []):
		for d in int(stack.count):
			tiles.append({"id": tiles.size(), "layer": 100 + d, "x": 0, "y": 0, "stack": s, "depth": d})
		s += 1
	return tiles

const Solver = preload("res://scripts/core/solver.gd")

## Authoring: desserts are placed at random (so they do not cluster), the board
## is proven winnable with the solver, then ice, locks and candles are placed
## along that winning order. Returns {tiles, order} or {} when not proven.
static func author_candidate(level: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var tiles := positions(level)
	if tiles.size() % 3 != 0:
		return {}
	_place_mechanics(tiles, {"mystery": level.get("mystery", 0)}, rng)
	var types: Array = []
	for g in _group_types(tiles.size() / 3, int(level.types), rng):
		types.append_array([g, g, g])
	_shuffle(types, rng)
	for i in tiles.size():
		tiles[i]["type"] = types[i]
	var cover := BoardRules.coverers(tiles)
	_peek = BoardRules.peeking(tiles)
	var order: Array = []
	for beam in [150, 600]:
		order = Solver.solve(tiles, cover, beam)
		if order.size() == tiles.size():
			break
	if order.size() != tiles.size():
		return {}
	if not _place_ice_along(tiles, order, level.get("ice", []), rng):
		return {}
	if not _place_locks(tiles, order, int(level.get("locks", 0)), rng):
		return {}
	if not _place_candles(tiles, order, level.get("candles", []), rng, int(level.get("candle_min", 5))):
		return {}
	return {"tiles": tiles, "order": order}

## Ice of strength v goes on a visible tile that the winning order takes only
## after at least v triples have been cleared, so it has thawed by then.
static func _place_ice_along(tiles: Array, order: Array, ice: Array, rng: RandomNumberGenerator) -> bool:
	if ice.is_empty():
		return true
	var by_id := {}
	for t in tiles:
		by_id[t.id] = t
	var done_before: Array = []
	var counts := {}
	var done := 0
	for id in order:
		done_before.append(done)
		var ty = by_id[id].type
		counts[ty] = int(counts.get(ty, 0)) + 1
		if int(counts[ty]) % 3 == 0:
			done += 1
	var top := _top_layer(tiles)
	for v in ice:
		var picks: Array = []
		for p in order.size():
			var t: Dictionary = by_id[order[p]]
			if _plain(t) and _visible(t, top) and int(done_before[p]) >= int(v):
				picks.append(p)
		if picks.is_empty():
			return false
		by_id[order[picks[rng.randi_range(0, picks.size() - 1)]]]["ice"] = int(v)
	return true

static func generate(level: Dictionary) -> Array:
	return generate_with_solution(level).tiles

## Tiles plus a removal order known to win. Frozen tiles are only ordered after
## enough triples are guaranteed to have been cleared to thaw them.
static func generate_with_solution(level: Dictionary) -> Dictionary:
	var max_open := int(level.max_open)
	for attempt in MAX_ATTEMPTS:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(level.seed) * 1000 + attempt
		var tiles := positions(level)
		assert(tiles.size() % 3 == 0, "tile count must be a multiple of 3")
		_peek = BoardRules.peeking(tiles)
		_place_mechanics(tiles, level, rng)
		var order := removal_order(tiles, rng, [], ice_min_positions(tiles, max_open, 0))
		if order.size() != tiles.size():
			continue
		var group_types := _group_types(tiles.size() / 3, int(level.types), rng)
		var types := assign_along(order.size(), group_types, max_open, rng, [], float(level.get("spread", 0.5)))
		if level.get("random_types", false):
			# Experiment: desserts placed at random, no solvability guarantee.
			types = []
			for g in group_types:
				types.append_array([g, g, g])
			_shuffle(types, rng)
		for i in order.size():
			tiles[order[i]]["type"] = types[i]
		if not _place_locks(tiles, order, int(level.get("locks", 0)), rng):
			continue
		if not _place_candles(tiles, order, level.get("candles", []), rng, int(level.get("candle_min", 5))):
			continue
		return {"tiles": tiles, "order": order}
	push_error("level %s: no solvable layout after %d attempts" % [level.get("id"), MAX_ATTEMPTS])
	return {"tiles": [], "order": []}

static func _place_mechanics(tiles: Array, level: Dictionary, rng: RandomNumberGenerator) -> void:
	var board := tiles.filter(func(t): return not t.has("stack"))
	var top := 0
	for t in board:
		top = maxi(top, int(t.layer))
	# Mystery tiles hide their dessert until taken, so they matter on any
	# layer: about half sit where the player can reach them early.
	var pool := board.duplicate()
	_shuffle(pool, rng)
	var want := int(level.get("mystery", 0))
	var near: Array = pool.filter(func(t): return int(t.layer) >= top - 1)
	var far: Array = pool.filter(func(t): return int(t.layer) < top - 1)
	var take_near := mini(want / 2 + want % 2, near.size())
	for i in take_near:
		near[i]["mystery"] = true
	for i in mini(want - take_near, far.size()):
		far[i]["mystery"] = true
	var upper := board.filter(func(t): return _peek.has(t.id) and not t.get("mystery", false))
	_shuffle(upper, rng)
	var ice: Array = level.get("ice", [])
	for i in mini(ice.size(), upper.size()):
		upper[i]["ice"] = int(ice[i])

## Index in `order` where the triple containing order[i] is completed.
static func group_end(tiles: Array, order: Array, i: int) -> int:
	var type: int = tiles[order[i]].type
	var seen := 0
	for j in i + 1:
		if int(tiles[order[j]].type) == type:
			seen += 1
	var need := int(ceil(seen / 3.0)) * 3
	if seen == need:
		return i
	for j in range(i + 1, order.size()):
		if int(tiles[order[j]].type) == type:
			seen += 1
			if seen == need:
				return j
	return order.size() - 1

static func _plain(t: Dictionary) -> bool:
	return not (t.get("mystery", false) or int(t.get("ice", 0)) > 0 or t.has("key") or t.has("lock") or t.has("fuse") or t.has("stack"))

static func _top_layer(tiles: Array) -> int:
	var top := 0
	for t in tiles:
		if not t.has("stack"):
			top = maxi(top, int(t.layer))
	return top

## The player can see part of this board tile from the start (see BoardRules.peeking).
static var _peek: Dictionary = {}

static func _visible(t: Dictionary, _top: int) -> bool:
	return not t.has("stack") and _peek.has(t.id)

## Puts a key on a tile and a lock on a tile the winning order takes only after
## the key's triple is complete, so following the order never hits a closed lock.
## Both sit where the player can see them from the first move.
static func _place_locks(tiles: Array, order: Array, count: int, rng: RandomNumberGenerator) -> bool:
	var top := _top_layer(tiles)
	for k in count:
		var keys: Array = []
		for i in range(0, order.size() / 2):
			var t: Dictionary = tiles[order[i]]
			if _plain(t) and _visible(t, top):
				keys.append(i)
		if keys.is_empty():
			return false
		var ki: int = keys[rng.randi_range(0, keys.size() - 1)]
		var end := group_end(tiles, order, ki)
		var locks: Array = []
		for j in range(end + 1, order.size()):
			var t: Dictionary = tiles[order[j]]
			if _plain(t) and _visible(t, top):
				locks.append(j)
		if locks.is_empty():
			return false
		var li: int = locks[rng.randi_range(0, mini(locks.size(), 6) - 1)]
		tiles[order[ki]]["key"] = k
		tiles[order[li]]["lock"] = k
	return true

## Candles burn one step per pick while on the board. A candle starts covered
## but visible, never earlier than `min_index` in the winning order, so the
## player sees the countdown and has to work towards it. Steps = its place in
## the winning order plus the level's slack.
static func _place_candles(tiles: Array, order: Array, slacks: Array, rng: RandomNumberGenerator, min_index: int) -> bool:
	if slacks.is_empty():
		return true
	var top := _top_layer(tiles)
	var cover := BoardRules.coverers(tiles)
	for slack in slacks:
		# Keep candles early enough that the countdown is felt: at most ~12
		# picks into the winning order, plus the level's slack.
		var hi := maxi(min_index + 1, mini(order.size() * 3 / 5, min_index + 20))
		var picks: Array = []
		for i in range(min_index, mini(hi, order.size())):
			var t: Dictionary = tiles[order[i]]
			if _plain(t) and _visible(t, top) and not cover[t.id].is_empty():
				picks.append(i)
		if picks.is_empty():
			return false
		var i: int = picks[rng.randi_range(0, picks.size() - 1)]
		tiles[order[i]]["fuse"] = i + 1 + int(slack)
	return true

## Earliest order position for each frozen tile: with at most `max_open` triples
## half-collected, k tiles taken guarantee at least (k - 2*max_open) / 3 triples.
static func ice_min_positions(tiles: Array, max_open: int, already: int) -> Dictionary:
	var out := {}
	for t in tiles:
		if int(t.get("ice", 0)) > 0 and t.get("place", "board") == "board":
			out[t.id] = already + 3 * int(t.ice) + 2 * max_open
	return out

## Random order that only ever removes tiles not covered by remaining tiles and
## never takes a frozen tile before its earliest position. Returns a shorter
## array when it gets stuck.
static func removal_order(tiles: Array, rng: RandomNumberGenerator, only_ids: Array = [], ice_min: Dictionary = {}) -> Array:
	var remaining: Dictionary = {}
	for t in tiles:
		if only_ids.is_empty() or only_ids.has(t.id):
			remaining[t.id] = t
	var cover := BoardRules.coverers(remaining.values())
	var order: Array = []
	while not remaining.is_empty():
		var free: Array = []
		for id in remaining:
			var blocked := false
			for c in cover[id]:
				if remaining.has(c):
					blocked = true
					break
			if blocked:
				continue
			if ice_min.has(id) and order.size() < int(ice_min[id]):
				continue
			free.append(id)
		if free.is_empty():
			return order
		var pick: int = free[rng.randi_range(0, free.size() - 1)]
		order.append(pick)
		remaining.erase(pick)
	return order

## `pending` lists types that must be completed first (partial groups already
## outside the board); each entry appears once per missing tile.
static func assign_along(count: int, group_types: Array, max_open: int, rng: RandomNumberGenerator, pending: Array, spread := 0.5) -> Array:
	var out: Array = pending.duplicate()
	var open: Array = []  # [{type, have}]
	var next_group := 0
	while out.size() < count:
		var left := count - out.size()
		var to_close := 0
		for g in open:
			to_close += 3 - g.have
		var can_open := next_group < group_types.size() and open.size() < max_open and left - 1 >= to_close + 2
		var must_open := open.is_empty()
		if must_open or (can_open and rng.randf() < spread):
			open.append({"type": group_types[next_group], "have": 0})
			next_group += 1
		var g: Dictionary = open[rng.randi_range(0, open.size() - 1)] if not must_open else open[0]
		out.append(g.type)
		g.have += 1
		if g.have == 3:
			open.erase(g)
	return out

static func _group_types(groups: int, type_count: int, rng: RandomNumberGenerator) -> Array:
	var pool: Array = []
	for t in type_count:
		pool.append(t)
	var out: Array = []
	while out.size() < groups:
		var round := pool.duplicate()
		_shuffle(round, rng)
		out.append_array(round)
	out.resize(groups)
	return out

static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]; a[i] = a[j]; a[j] = tmp
