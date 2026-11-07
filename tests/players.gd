extends RefCounted
## Simulated players for difficulty measurement. Both see what a person sees:
## every board dessert except unrevealed mystery tiles and buried box tiles.
## Both use the three boosters the way a person would.

const GameState = preload("res://scripts/core/game_state.gd")

## Plays a round. `skill` is "casual" or "skilled". Returns true on a win.
## `rng` adds human-like slips: a casual player sometimes takes one of its top
## three options instead of the best, a skilled one rarely its second best.
static func play(s, skill: String, use_boosters := true, rng: RandomNumberGenerator = null) -> bool:
	var guard := 0
	var banned := -1
	while not s.is_won() and guard < 400:
		guard += 1
		if s.is_lost():
			if use_boosters and s.can_undo():
				banned = int(s.last_pick.id)
				s.undo()
				continue
			if use_boosters and s.can_move_out():
				s.move_out()
				continue
			return false
		var choice := _choose(s, skill, banned, rng)
		banned = -1
		if choice.is_empty():
			if use_boosters and s.can_move_out():
				s.move_out()
				continue
			return false
		# A careful player spends a booster rather than make a losing pick.
		if use_boosters and choice.score <= -900:
			if s.can_move_out():
				s.move_out()
				continue
			if s.can_shuffle() and s.shuffle().ok:
				continue
		s.pick(choice.id)
	return s.is_won()

static func _tray_counts(s) -> Dictionary:
	var counts := {}
	for id in s.tray:
		counts[s.tiles[id].type] = int(counts.get(s.tiles[id].type, 0)) + 1
	return counts

## Tiles the player can take now: board tiles plus parked ones.
static func _takeable(s) -> Array:
	var out: Array = s.board_tiles().filter(func(t): return s.can_pick(t.id))
	for id in s.hold:
		out.append(s.tiles[id])
	return out

static func _choose(s, skill: String, banned: int, rng: RandomNumberGenerator = null) -> Dictionary:
	var options := _takeable(s).filter(func(t): return t.id != banned)
	if options.is_empty():
		options = _takeable(s)
	if options.is_empty():
		return {}
	var counts := _tray_counts(s)
	var visible := _visible_counts(s)
	# Candle urgency: dig out a candle whose countdown is close.
	for c in s.board_tiles().filter(func(t): return t.has("fuse")):
		var blockers: Array = s.cover[c.id].filter(func(x): return s.tiles[x].place == "board")
		if int(c.fuse) <= 3 + 2 * blockers.size():
			for t in options:
				if t.id == c.id or blockers.has(t.id):
					return {"id": t.id, "score": 0}
	var ranked: Array = []
	for t in options:
		var sc := _score(s, t, counts, s.tray.size(), visible)
		if skill == "skilled" and sc > -900:
			sc += 0.6 * _best_follow_up(s, t, counts, visible)
		ranked.append({"id": t.id, "score": sc})
	ranked.sort_custom(func(a, b): return a.score > b.score)
	if rng != null:
		var slip := 0.25 if skill == "casual" else 0.08
		var width := 3 if skill == "casual" else 2
		if rng.randf() < slip:
			var pool: Array = ranked.slice(0, mini(width, ranked.size())).filter(func(c): return c.score > -900)
			if not pool.is_empty():
				return pool[rng.randi_range(0, pool.size() - 1)]
	return ranked[0]

## How many of each dessert the player can see on the board right now.
static func _visible_counts(s) -> Dictionary:
	var out := {}
	for t in s.board_tiles():
		if s.type_known(t.id):
			out[t.type] = int(out.get(t.type, 0)) + 1
	return out

static func _score(s, t: Dictionary, counts: Dictionary, size: int, visible: Dictionary) -> float:
	if not s.type_known(t.id):
		# Unknown dessert: a gamble that gets worse as the tray fills.
		return -900.0 if size >= 6 else -12.0 - 6.0 * size
	var have := int(counts.get(t.type, 0))
	if have == 2:
		return 100.0
	if size >= 6:
		return -1000.0
	var seen := int(visible.get(t.type, 0)) - (1 if t.place == "board" else 0)
	var sc := 0.0
	if have == 1:
		sc = 40.0 + 6.0 * mini(seen, 3)
	else:
		sc = -8.0 - 5.0 * size + 5.0 * mini(seen, 3)
	# Prefer picks that uncover tiles matching what is waiting in the tray.
	for o in _uncovered_by(s, t):
		if s.type_known(o.id) and counts.has(o.type):
			sc += 12.0
		sc += 2.0
	return sc

static func _uncovered_by(s, t: Dictionary) -> Array:
	var out: Array = []
	if t.place != "board":
		return out
	for oid in s.covers[t.id]:
		var o: Dictionary = s.tiles[oid]
		if o.place != "board":
			continue
		var only := true
		for x in s.cover[oid]:
			if x != t.id and s.tiles[x].place == "board":
				only = false
				break
		if only:
			out.append(o)
	return out

## Value of the best next pick after taking `t`, judged from visible desserts.
static func _best_follow_up(s, t: Dictionary, counts: Dictionary, visible: Dictionary) -> float:
	var c2 := counts.duplicate()
	var size: int = s.tray.size() + 1
	var key = t.type if s.type_known(t.id) else -1
	if key != -1:
		c2[key] = int(c2.get(key, 0)) + 1
		if int(c2[key]) == 3:
			c2.erase(key)
			size -= 3
	var options: Array = _takeable(s).filter(func(o): return o.id != t.id)
	options.append_array(_uncovered_by(s, t).filter(func(o): return not o.has("lock") and int(o.get("ice", 0)) == 0))
	var best := -1000.0
	for o in options:
		best = maxf(best, _score(s, o, c2, size, visible))
	return best
