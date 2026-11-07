extends RefCounted
## Pure geometry of the stacked board and the side boxes. No nodes, no animation.

static func overlaps(a: Dictionary, b: Dictionary) -> bool:
	return absi(int(a.x) - int(b.x)) < 2 and absi(int(a.y) - int(b.y)) < 2

## Board tiles are covered by overlapping tiles on higher layers; box tiles are
## covered by any deeper-placed tile in the same box. The two never touch.
static func covered(tile: Dictionary, others: Array) -> bool:
	if tile.has("stack"):
		for o in others:
			if o.has("stack") and int(o.stack) == int(tile.stack) and int(o.depth) > int(tile.depth):
				return true
		return false
	for o in others:
		if not o.has("stack") and int(o.layer) > int(tile.layer) and overlaps(tile, o):
			return true
	return false

## For every tile, the ids of tiles that could ever cover it. Geometry never
## changes during a level, so this is computed once and checked cheaply later.
static func coverers(tiles: Array) -> Dictionary:
	var out := {}
	for t in tiles:
		var list: Array = []
		for o in tiles:
			if o.id == t.id:
				continue
			if t.has("stack"):
				if o.has("stack") and int(o.stack) == int(t.stack) and int(o.depth) > int(t.depth):
					list.append(o.id)
			elif not o.has("stack") and int(o.layer) > int(t.layer) and overlaps(t, o):
				list.append(o.id)
		out[t.id] = list
	return out
