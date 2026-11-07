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
