extends RefCounted
## Simulated player used to measure difficulty; never sees the hidden solution.

static func play(s) -> bool:
	while not s.is_finished():
		var free: Array = s.board_tiles().filter(func(t): return s.is_free(t.id))
		var in_tray := {}
		for id in s.tray:
			in_tray[s.tiles[id].type] = int(in_tray.get(s.tiles[id].type, 0)) + 1
		var visible := {}
		for t in free:
			visible[t.type] = int(visible.get(t.type, 0)) + 1
		var best = free[0]
		var best_score := -1
		for t in free:
			var have := int(in_tray.get(t.type, 0))
			var seen := int(visible[t.type])
			var score := 0
			if have == 2: score = 100
			elif have == 1 and seen >= 2: score = 80
			elif have == 0 and seen >= 3: score = 60
			elif have == 1: score = 40
			elif seen == 2: score = 20 - s.tray.size()
			else: score = 10 - s.tray.size() * 2
			if score > best_score:
				best_score = score; best = t
		s.pick(best.id)
	return s.is_won()
