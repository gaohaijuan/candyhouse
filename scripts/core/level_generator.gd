extends RefCounted
## Builds a level whose tile types guarantee at least one winning order.
## Tiles live on a half-cell grid: a tile at (x, y) covers [x, x+2) x [y, y+2).

const BoardRules = preload("res://scripts/core/board_rules.gd")

static func positions(level: Dictionary) -> Array:
	var tiles: Array = []
	var layer_index := 0
	for layer in level.layers:
		var ox := int(layer.offset[0])
		var oy := int(layer.offset[1])
		for row in int(layer.rows):
			for col in int(layer.cols):
				tiles.append({"id": tiles.size(), "layer": layer_index, "x": ox + col * 2, "y": oy + row * 2})
		layer_index += 1
	return tiles

## Assigns types along a free-first removal order. At most `max_open` triples are
## half-collected at any point of that order, so following it never fills the tray.
static func generate(level: Dictionary) -> Array:
	return generate_with_solution(level).tiles

## Same as generate(), plus the removal order that is known to win.
static func generate_with_solution(level: Dictionary) -> Dictionary:
	var tiles := positions(level)
	assert(tiles.size() % 3 == 0, "tile count must be a multiple of 3")
	var rng := RandomNumberGenerator.new()
	rng.seed = int(level.seed)
	var order := removal_order(tiles, rng)
	var group_types := _group_types(tiles.size() / 3, int(level.types), rng)
	var types := assign_along(order.size(), group_types, int(level.max_open), rng, [])
	for i in order.size():
		tiles[order[i]]["type"] = types[i]
	return {"tiles": tiles, "order": order}

## Random order that only ever removes tiles not covered by remaining tiles.
static func removal_order(tiles: Array, rng: RandomNumberGenerator, only_ids: Array = []) -> Array:
	var remaining: Dictionary = {}
	for t in tiles:
		if only_ids.is_empty() or only_ids.has(t.id):
			remaining[t.id] = t
	var order: Array = []
	while not remaining.is_empty():
		var free: Array = []
		for id in remaining:
			if not BoardRules.covered(remaining[id], remaining.values()):
				free.append(id)
		var pick: int = free[rng.randi_range(0, free.size() - 1)]
		order.append(pick)
		remaining.erase(pick)
	return order

## `pending` lists types that must be completed first (partial groups already
## outside the board); each entry appears once per missing tile.
static func assign_along(count: int, group_types: Array, max_open: int, rng: RandomNumberGenerator, pending: Array) -> Array:
	var out: Array = []
	var queue := pending.duplicate()
	for t in queue:
		out.append(t)
	var open: Array = []  # [{type, have}]
	var next_group := 0
	while out.size() < count:
		var left := count - out.size()
		var to_close := 0
		for g in open:
			to_close += 3 - g.have
		var can_open := next_group < group_types.size() and open.size() < max_open and left - 1 >= to_close + 2
		var must_open := open.is_empty()
		if must_open or (can_open and rng.randf() < 0.5):
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
		for i in range(round.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = round[i]; round[i] = round[j]; round[j] = tmp
		out.append_array(round)
	out.resize(groups)
	return out
