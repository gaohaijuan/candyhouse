extends RefCounted
## Pure geometry of the stacked board. No nodes, no animation.

static func overlaps(a: Dictionary, b: Dictionary) -> bool:
	return absi(int(a.x) - int(b.x)) < 2 and absi(int(a.y) - int(b.y)) < 2

## True when any other tile in `others` sits on a higher layer and overlaps `tile`.
static func covered(tile: Dictionary, others: Array) -> bool:
	for o in others:
		if int(o.layer) > int(tile.layer) and overlaps(tile, o):
			return true
	return false
