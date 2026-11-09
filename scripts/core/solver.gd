extends RefCounted
## Beam-search solver for a full-information board (designer's view). Finding
## an order proves the board is winnable without boosters; failing to find one
## within the beam is treated as "not proven" and the board is rejected.

const TRAY_SIZE := 7

## `tiles`: Array of {id, type, ...}; `cover`: id -> ids that cover it.
## `start_tray`: types already waiting in the tray (for re-deals).
## Returns the winning order of tile ids, or [] when none was found.
static func solve(tiles: Array, cover: Dictionary, beam := 80, start_tray: Array = []) -> Array:
	var n := tiles.size()
	var index := {}
	for i in n:
		index[tiles[i].id] = i
	var types := PackedInt32Array()
	var type_count := 0
	for t in tiles:
		types.append(int(t.type))
		type_count = maxi(type_count, int(t.type) + 1)
	for ty in start_tray:
		type_count = maxi(type_count, int(ty) + 1)
	var covers: Array = []
	covers.resize(n)
	for i in n:
		covers[i] = PackedInt32Array()
	var left0 := PackedInt32Array()
	left0.resize(n)
	for t in tiles:
		var i: int = index[t.id]
		for c in cover[t.id]:
			if index.has(c):
				left0[i] += 1
				covers[index[c]].append(i)
	var tray0 := PackedInt32Array()
	tray0.resize(type_count)
	var size0 := 0
	for ty in start_tray:
		tray0[int(ty)] += 1
		size0 += 1
	var gone0 := PackedByteArray()
	gone0.resize(n)
	var states: Array = [{"left": left0, "gone": gone0, "tray": tray0, "size": size0, "order": PackedInt32Array()}]
	for step in n:
		var children: Array = []
		var seen := {}
		for st in states:
			for i in n:
				if st.gone[i] or st.left[i] > 0:
					continue
				var ty := types[i]
				var have: int = st.tray[ty]
				var size: int = st.size + 1
				if have < 2 and size >= TRAY_SIZE:
					continue
				var gone: PackedByteArray = st.gone.duplicate()
				gone[i] = 1
				var key := gone.hex_encode()
				if seen.has(key):
					continue
				seen[key] = true
				var tray: PackedInt32Array = st.tray.duplicate()
				tray[ty] = have + 1
				if have == 2:
					tray[ty] = 0
					size -= 3
				var left: PackedInt32Array = st.left.duplicate()
				for j in covers[i]:
					left[j] -= 1
				var order: PackedInt32Array = st.order.duplicate()
				order.append(i)
				children.append({"left": left, "gone": gone, "tray": tray, "size": size, "order": order, "score": _score(left, gone, tray, size, types, n)})
		if children.is_empty():
			return []
		children.sort_custom(func(a, b): return a.score > b.score)
		states = children.slice(0, beam)
	var best: Dictionary = states[0]
	var out: Array = []
	for i in best.order:
		out.append(tiles[i].id)
	return out

## Prefers a lighter tray, pairs waiting in it, and free tiles that match it.
static func _score(left: PackedInt32Array, gone: PackedByteArray, tray: PackedInt32Array, size: int, types: PackedInt32Array, n: int) -> float:
	var sc := -12.0 * size
	var free_match := 0
	var free_count := 0
	for i in n:
		if gone[i] == 0 and left[i] == 0:
			free_count += 1
			if tray[types[i]] > 0:
				free_match += 1 + tray[types[i]]
	for c in tray:
		if c == 2:
			sc += 4.0
	return sc + 3.0 * free_match + 0.5 * free_count

## Like solve(), but with the special tiles from the current position: `tiles`
## carry ice (triples still needed before it can be taken), lock / key ids and
## candle steps left (fuse). Used by the expert test player to plan ahead.
## A move is either one tile or, when a kind can be finished from free tiles,
## the whole triple; the plain one-tile beam stalls on open boards because a
## triple first makes the tray heavier.
static func solve_rules(tiles: Array, cover: Dictionary, beam := 12, start_tray: Array = []) -> Array:
	var n := tiles.size()
	var index := {}
	for i in n:
		index[tiles[i].id] = i
	var g := {"n": n, "types": PackedInt32Array(), "ice": PackedInt32Array(), "lock": PackedInt32Array(),
		"key": PackedInt32Array(), "candles": [], "covers": []}
	var type_count := 0
	for t in tiles:
		g.types.append(int(t.type))
		type_count = maxi(type_count, int(t.type) + 1)
		g.ice.append(int(t.get("ice", 0)))
		g.lock.append(int(t.lock) if t.has("lock") else -1)
		g.key.append(int(t.key) if t.has("key") else -1)
	for ty in start_tray:
		type_count = maxi(type_count, int(ty) + 1)
	for i in n:
		if tiles[i].has("fuse"):
			g.candles.append([i, int(tiles[i].fuse)])
	g.covers.resize(n)
	for i in n:
		g.covers[i] = PackedInt32Array()
	var left0 := PackedInt32Array()
	left0.resize(n)
	for t in tiles:
		var i: int = index[t.id]
		for c in cover[t.id]:
			if index.has(c):
				left0[i] += 1
				g.covers[index[c]].append(i)
	var tray0 := PackedInt32Array()
	tray0.resize(type_count)
	var size0 := 0
	for ty in start_tray:
		tray0[int(ty)] += 1
		size0 += 1
	var pend0 := PackedInt32Array()
	pend0.resize(type_count)
	var gone0 := PackedByteArray()
	gone0.resize(n)
	var states: Array = [{"left": left0, "gone": gone0, "tray": tray0, "size": size0, "order": PackedInt32Array(),
		"cleared": 0, "opened": 0, "pend": pend0}]
	while true:
		if states[0].order.size() >= n:
			break
		var children: Array = []
		var seen := {}
		for st in states:
			var free_by_type := {}
			for i in n:
				if _open_tile(g, st, i):
					var ty: int = g.types[i]
					if not free_by_type.has(ty):
						free_by_type[ty] = []
					free_by_type[ty].append(i)
			var moves: Array = []
			for ty in free_by_type:
				var need: int = 3 - int(st.tray[ty])
				if free_by_type[ty].size() >= need:
					moves.append(free_by_type[ty].slice(0, need))
			for ty in free_by_type:
				for i in free_by_type[ty]:
					moves.append([i])
			for mv in moves:
				var c = st
				for i in mv:
					c = _take(g, c, i)
					if c == null:
						break
				if c == null:
					continue
				var k: String = c.gone.hex_encode()
				if seen.has(k):
					continue
				seen[k] = true
				c["score"] = _score_rules(c.left, c.gone, c.tray, c.size, g.types, n, c.cleared)
				children.append(c)
		if children.is_empty():
			return []
		children.sort_custom(func(a, b): return a.score > b.score)
		states = children.slice(0, beam)
	var out: Array = []
	for i in states[0].order:
		out.append(tiles[i].id)
	return out

static func _open_tile(g: Dictionary, st: Dictionary, i: int) -> bool:
	if st.gone[i] or st.left[i] > 0 or g.ice[i] > st.cleared:
		return false
	return g.lock[i] < 0 or (st.opened & (1 << g.lock[i])) != 0

## One take on a copy of `st`, or null when it is not allowed or loses.
static func _take(g: Dictionary, st: Dictionary, i: int):
	if not _open_tile(g, st, i):
		return null
	var ty: int = g.types[i]
	var have: int = st.tray[ty]
	var size: int = st.size + 1
	if have < 2 and size >= TRAY_SIZE:
		return null
	var steps: int = st.order.size() + 1
	for c in g.candles:
		if c[0] != i and not st.gone[c[0]] and int(c[1]) - steps <= 0:
			return null
	var gone: PackedByteArray = st.gone.duplicate()
	gone[i] = 1
	var tray: PackedInt32Array = st.tray.duplicate()
	var pend: PackedInt32Array = st.pend
	var opened: int = st.opened
	var cleared: int = st.cleared
	if g.key[i] >= 0:
		pend = pend.duplicate()
		pend[ty] |= 1 << g.key[i]
	tray[ty] = have + 1
	if have == 2:
		tray[ty] = 0
		size -= 3
		cleared += 1
		if pend[ty] != 0:
			opened |= pend[ty]
			pend = pend.duplicate()
			pend[ty] = 0
	var left: PackedInt32Array = st.left.duplicate()
	for j in g.covers[i]:
		left[j] -= 1
	var order: PackedInt32Array = st.order.duplicate()
	order.append(i)
	return {"left": left, "gone": gone, "tray": tray, "size": size, "order": order, "cleared": cleared, "opened": opened, "pend": pend}

## solve_rules' ranking: a light tray first, then tray kinds that can be
## finished from free tiles right now.
static func _score_rules(left: PackedInt32Array, gone: PackedByteArray, tray: PackedInt32Array, size: int, types: PackedInt32Array, n: int, cleared: int) -> float:
	var free_of := PackedInt32Array()
	free_of.resize(tray.size())
	var free_count := 0
	for i in n:
		if gone[i] == 0 and left[i] == 0:
			free_count += 1
			free_of[types[i]] += 1
	var sc := -20.0 * size + 0.3 * free_count + 1.0 * cleared
	for ty in tray.size():
		var c := tray[ty]
		if c > 0 and free_of[ty] >= 3 - c:
			sc += 8.0
		if c == 2:
			sc += 3.0
	return sc
