extends SceneTree
## Headless rule tests: godot --headless --path . --script res://tests/run_tests.gd

const GameState = preload("res://scripts/core/game_state.gd")
const Generator = preload("res://scripts/core/level_generator.gd")
const BoardRules = preload("res://scripts/core/board_rules.gd")
const HumanPlayer = preload("res://tests/human_player.gd")

var failures := 0
var checks := 0

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", what)

func _init() -> void:
	var levels: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels.json")).levels
	for level in levels:
		if level.has("board"):
			continue  # authored boards are checked by _test_authored and _test_design
		_test_level_shape(level)
		_test_solution_wins(level)
	var by_id := {}
	for level in levels:
		by_id[int(level.id)] = level
	_test_tray_rules(by_id[1])
	_test_undo(by_id[2])
	_test_move_out(by_id[2])
	_test_shuffle(by_id[3])
	_test_shuffle(by_id[13])
	_test_shuffle(by_id[43])
	_test_seed_variety(by_id[3])
	_test_mystery(by_id[4])
	_test_ice(by_id[9])
	_test_stacks(by_id[19])
	_test_locks(by_id[24])
	_test_candles(by_id[34])
	_test_design(levels)
	_test_full_tray_rescue(by_id[3])
	_test_authored(levels)
	_test_start_boosters(levels)
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _test_level_shape(level: Dictionary) -> void:
	var made := Generator.generate_with_solution(level)
	var tiles: Array = made.tiles
	check(tiles.size() % 3 == 0, "L%d tile count multiple of 3" % level.id)
	var counts := {}
	for t in tiles:
		counts[t.type] = int(counts.get(t.type, 0)) + 1
	for k in counts:
		check(counts[k] % 3 == 0, "L%d type %d count %d multiple of 3" % [level.id, k, counts[k]])
	check(counts.size() == int(level.types), "L%d uses all %d types (got %d)" % [level.id, level.types, counts.size()])
	var free := tiles.filter(func(t): return not BoardRules.covered(t, tiles))
	check(free.size() > 0, "L%d has free tiles at start" % level.id)
	print("L%d tiles=%d layers=%d free_at_start=%d" % [level.id, tiles.size(), level.layers.size(), free.size()])

func _test_solution_wins(level: Dictionary) -> void:
	var s := GameState.new(level)
	var peak := 0
	var steps := 0
	while not s.is_finished() and steps < 500:
		var id: int = s.solution[0]
		var r := s.pick(id)
		check(r.ok, "L%d solution pick %d allowed" % [level.id, id])
		if not r.ok:
			return
		peak = maxi(peak, s.tray.size() + r.matched.size())
		steps += 1
	check(s.is_won(), "L%d following the solution wins" % level.id)
	check(peak <= GameState.TRAY_SIZE, "L%d solution never overflows tray (peak %d)" % [level.id, peak])

## A human-like player: prefer completing tray pairs, then tiles whose kind is
## visible several times among free tiles; never knows the hidden solution.
func _test_greedy_player(level: Dictionary) -> void:
	var wins := 0
	for trial in 40:
		var def := level.duplicate(true)
		def.seed = int(level.seed) + trial * 31
		if HumanPlayer.play(GameState.new(def)):
			wins += 1
	var rate := wins * 100 / 40
	print("L%d human-like player wins %d%%" % [level.id, rate])
	var band: Array = level.get("target_win_pct", [0, 100])
	check(rate >= int(band[0]) and rate <= int(band[1]), "L%d win rate %d%% within %s" % [level.id, rate, str(band)])

func _test_tray_rules(level: Dictionary) -> void:
	var s := GameState.new(level)
	# Find a free tile and a covered tile.
	var covered := s.board_tiles().filter(func(t): return not s.is_free(t.id))
	check(not covered.is_empty() and not s.pick(covered[0].id).ok, "covered tile cannot be picked")
	var first: int = s.solution[0]
	var r := s.pick(first)
	check(r.ok and s.tray == [first] and s.tiles[first].place == "tray", "pick moves tile into tray")
	check(not s.pick(first).ok, "tile already in tray cannot be picked again")
	# Same-type tiles are grouped together.
	var s2 := GameState.new(level)
	var by_type := {}
	var guard := 0
	while not s2.is_finished() and guard < 100:
		var id: int = s2.solution[0]
		s2.pick(id)
		guard += 1
		for i in range(1, s2.tray.size()):
			var a = s2.tiles[s2.tray[i - 1]].type
			var b = s2.tiles[s2.tray[i]].type
			if a != b:
				by_type[a] = by_type.get(a, 0) + 1
	check(s2.is_won(), "grouping run still wins")

func _test_undo(level: Dictionary) -> void:
	var s := GameState.new(level)
	var id: int = s.solution[0]
	var before: Dictionary = s.tiles[id].duplicate()
	s.pick(id)
	check(s.can_undo(), "undo available after unmatched pick")
	var r := s.undo()
	check(r.ok and s.tiles[id].place == "board" and s.tray.is_empty(), "undo returns tile to board")
	check(s.tiles[id].x == before.x and s.tiles[id].y == before.y, "undo keeps position")
	check(not s.can_undo(), "undo used up")
	check(s.stars() == 2, "one booster -> 2 stars")

func _test_move_out(level: Dictionary) -> void:
	var s := GameState.new(level)
	for i in 4:
		if s.tray.size() < 3:
			s.pick(s.solution[0])
	var left := s.tray.slice(0, 3)
	var r := s.move_out()
	check(r.ok and s.hold == left and s.tray.size() <= 4, "move out parks 3 leftmost tiles")
	check(not s.can_move_out(), "move out used up")
	var h: int = s.hold[0]
	check(s.pick(h).ok and not s.hold.has(h), "hold tile can be picked back")

func _test_shuffle(level: Dictionary) -> void:
	for trial in 10:
		var def := level.duplicate(true)
		def.seed = int(level.seed) + trial
		var s := GameState.new(def)
		for i in 7:
			var free: Array = s.board_tiles().filter(func(t): return s.can_pick(t.id))
			if s.tray.size() < 5 and not free.is_empty():
				s.pick(free[s.rng.randi_range(0, free.size() - 1)].id)
		var before := {}
		for t in s.board_tiles():
			before[t.type] = int(before.get(t.type, 0)) + 1
		var r := s.shuffle()
		if not r.ok and s.boosters.shuffle > 0:
			continue  # ice can make an immediate safe re-deal impossible; the deal is kept
		check(r.ok, "shuffle allowed")
		var after := {}
		for t in s.board_tiles():
			after[t.type] = int(after.get(t.type, 0)) + 1
		var totals := {}
		for t in s.tiles.values():
			if t.place != "gone":
				totals[t.type] = int(totals.get(t.type, 0)) + 1
		var ok := true
		for k in totals:
			ok = ok and totals[k] % 3 == 0
		check(ok, "shuffle keeps every remaining type a multiple of 3 (trial %d)" % trial)
		var steps := 0
		while not s.is_finished() and steps < 200:
			s.pick(s.solution[0])
			steps += 1
		check(s.is_won(), "after shuffle the solution still wins (trial %d)" % trial)

func _test_ice(level: Dictionary) -> void:
	var s := GameState.new(level)
	var frozen: Array = s.tiles.values().filter(func(t): return int(t.get("ice", 0)) > 0)
	check(frozen.size() == level.ice.size(), "L%d places %d frozen tiles" % [level.id, level.ice.size()])
	for t in frozen:
		check(not s.can_pick(t.id), "frozen tile %d cannot be picked" % t.id)
	var before := {}
	for t in frozen:
		before[t.id] = int(t.ice)
	var thawed_once := false
	while not s.is_finished():
		var r := s.pick(s.solution[0])
		check(r.ok, "L%d solution respects ice" % level.id)
		if not r.ok:
			return
		if not r.matched.is_empty() and not thawed_once:
			thawed_once = true
			for t in frozen:
				check(int(s.tiles[t.id].get("ice", 0)) == before[t.id] - 1 or s.tiles[t.id].place != "board", "first triple thaws ice by one")
	check(s.is_won(), "L%d with ice is winnable along its solution" % level.id)

func _test_stacks(level: Dictionary) -> void:
	var s := GameState.new(level)
	for stack_id in level.stacks.size():
		var pile: Array = s.tiles.values().filter(func(t): return t.has("stack") and int(t.stack) == stack_id)
		var top := 0
		for t in pile:
			top = maxi(top, int(t.depth))
		for t in pile:
			check(s.is_free(t.id) == (int(t.depth) == top), "box %d: only the top tile is free" % stack_id)
	check(s.board_tiles().size() == s.tiles.size(), "box tiles start on the board")

func _test_mystery(level: Dictionary) -> void:
	var s := GameState.new(level)
	var hidden: Array = s.tiles.values().filter(func(t): return t.get("mystery", false))
	check(hidden.size() == int(level.mystery), "L%d places %d mystery tiles" % [level.id, level.mystery])
	for t in hidden:
		check(not s.type_known(t.id), "mystery dessert hidden until taken")
	var free_hidden: Array = hidden.filter(func(t): return s.is_free(t.id))
	if not free_hidden.is_empty():
		var id: int = free_hidden[0].id
		s.pick(id)
		check(s.type_known(id), "mystery dessert revealed once taken")

func _test_locks(level: Dictionary) -> void:
	for trial in 10:
		var def := level.duplicate(true)
		def.seed = int(level.seed) + trial
		var s := GameState.new(def)
		var locked: Array = s.tiles.values().filter(func(t): return t.has("lock"))
		var keys: Array = s.tiles.values().filter(func(t): return t.has("key"))
		check(locked.size() == int(level.locks) and keys.size() == int(level.locks), "L%d places %d key/lock pairs" % [level.id, level.locks])
		for t in locked:
			check(not s.can_pick(t.id), "locked tile cannot be picked")
		var opened := false
		while not s.is_finished():
			var r := s.pick(s.solution[0])
			check(r.ok, "L%d solution respects locks" % level.id)
			if not r.ok:
				return
			if not r.unlocked.is_empty():
				opened = true
		check(opened and s.is_won(), "L%d locks open and the solution wins (trial %d)" % [level.id, trial])

func _test_candles(level: Dictionary) -> void:
	var s := GameState.new(level)
	var candle: Array = s.tiles.values().filter(func(t): return t.has("fuse"))
	check(candle.size() == level.candles.size(), "L%d places candles" % level.id)
	var start := int(candle[0].fuse)
	var other: Array = s.board_tiles().filter(func(t): return s.can_pick(t.id) and not t.has("fuse"))
	var r := s.pick(other[0].id)
	check(int(s.tiles[candle[0].id].fuse) == start - 1, "each pick burns one candle step")
	check(s.undo().ok and int(s.tiles[candle[0].id].fuse) == start, "undo gives the step back")
	# Burning out loses.
	var c: GameState = s.clone()
	c.tiles[candle[0].id].fuse = 1
	var free: Array = c.board_tiles().filter(func(t): return c.can_pick(t.id) and not t.has("fuse"))
	c.pick(free[0].id)
	check(c.is_lost() and c.lose_reason() == "candle", "a candle reaching zero on the board loses")
	# The solution always takes candles in time.
	for trial in 10:
		var def := level.duplicate(true)
		def.seed = int(level.seed) + trial
		var g := GameState.new(def)
		while not g.is_finished():
			g.pick(g.solution[0])
		check(g.is_won(), "L%d solution beats every candle (trial %d)" % [level.id, trial])

## Level design rules agreed with the producer: every mechanic is introduced
## with a popup, then used for several levels; special tiles are visible from
## the start; a candle can never be taken on the first moves.
func _test_design(levels: Array) -> void:
	var seen := {}
	for level in levels:
		var kinds: Array = []
		for k in ["mystery", "ice", "stacks", "locks", "candles"]:
			if level.has(k):
				kinds.append(k)
		for k in kinds:
			if not seen.has(k):
				seen[k] = level.id
				check(level.has("intro"), "L%d introduces %s with a popup" % [level.id, k])
		for trial in 6:
			var def: Dictionary = level.duplicate(true)
			def.seed = int(level.seed) + trial * 17
			var s := GameState.new(def)
			check(not s.tiles.is_empty(), "L%d generates (trial %d)" % [level.id, trial])
			if s.tiles.is_empty():
				continue
			var top := 0
			for t in s.tiles.values():
				if not t.has("stack"):
					top = maxi(top, int(t.layer))
			var peek := BoardRules.peeking(s.tiles.values())
			var free_start := s.board_tiles().filter(func(t): return s.can_pick(t.id)).size()
			check(free_start >= 3, "L%d offers at least 3 moves at the start" % level.id)
			for t in s.tiles.values():
				if t.has("fuse"):
					check(not s.is_free(t.id), "L%d candle is not free at the start" % level.id)
					check(int(t.fuse) >= 8 and int(t.fuse) <= 26, "L%d candle starts with 8-26 steps (%d)" % [level.id, t.fuse])
					check(peek.has(t.id), "L%d candle is visible at the start" % level.id)
				if t.has("lock") or t.has("key"):
					check(peek.has(t.id), "L%d lock/key visible at the start" % level.id)
				if int(t.get("ice", 0)) > 0:
					check(peek.has(t.id), "L%d ice visible at the start" % level.id)
			var g: GameState = s.clone()
			var plan: Array = s.solution.duplicate()
			check(g.wins_with(plan), "L%d has a winning order (trial %d)" % [level.id, trial])

## BUG-1: after the tray fills up, "move out" must free it and play must go on.
func _test_full_tray_rescue(level: Dictionary) -> void:
	var filled := 0
	for trial in 20:
		var def := level.duplicate(true)
		def.seed = int(level.seed) + trial * 7
		var s := GameState.new(def)
		# Fill the tray without ever completing a triple.
		while s.tray.size() < GameState.TRAY_SIZE:
			var counts := {}
			for id in s.tray:
				counts[s.tiles[id].type] = int(counts.get(s.tiles[id].type, 0)) + 1
			var options: Array = s.board_tiles().filter(func(t): return s.can_pick(t.id) and int(counts.get(t.type, 0)) < 2)
			if options.is_empty():
				break
			s.pick(options[0].id)
		if s.tray.size() < GameState.TRAY_SIZE:
			continue
		filled += 1
		check(s.is_lost() and s.lose_reason() == "tray", "full tray loses (trial %d)" % trial)
		check(s.can_move_out(), "move out is offered on a full tray (trial %d)" % trial)
		var r := s.move_out()
		check(r.ok and s.tray.size() == GameState.TRAY_SIZE - 3 and s.hold.size() == 3, "move out parks three tiles (trial %d)" % trial)
		check(not s.is_lost() and not s.is_finished(), "round continues after move out (trial %d)" % trial)
		var movable: Array = s.board_tiles().filter(func(t): return s.can_pick(t.id))
		check(not movable.is_empty() or not s.hold.is_empty(), "something can be picked after move out (trial %d)" % trial)
		check(s.pick(s.hold[0]).ok, "a parked tile can be picked back (trial %d)" % trial)
	check(filled > 0, "found boards that fill the tray")
	# Undo also rescues the pick that filled the tray.
	var u := GameState.new(level)
	while not u.is_finished():
		var counts := {}
		for id in u.tray:
			counts[u.tiles[id].type] = int(counts.get(u.tiles[id].type, 0)) + 1
		var options: Array = u.board_tiles().filter(func(t): return u.can_pick(t.id) and int(counts.get(t.type, 0)) < 2)
		if options.is_empty():
			break
		u.pick(options[0].id)
	if u.lose_reason() == "tray":
		check(u.can_undo() and u.undo().ok and not u.is_lost(), "undo rescues a full tray")

## Authored boards: winnable along the stored order, rated near the planned
## difficulty, and mystery desserts stay hidden while the tile is on the board.
func _test_authored(levels: Array) -> void:
	for level in levels:
		if not level.has("board"):
			continue
		var s := GameState.new(level)
		check(s.wins_with(s.solution.duplicate()), "L%d authored board wins along its order" % level.id)
		var r: float = level.get("rating", -1.0)
		check(absf(r - float(level.target_rating)) <= 1.5, "L%d rating %.1f near target %.1f" % [level.id, r, level.target_rating])
		for t in s.tiles.values():
			if t.get("mystery", false):
				check(not s.type_known(t.id), "L%d mystery dessert hidden on the board" % level.id)

## Magnet keeps every authored board winnable; the extra slot gives an 8th place.
func _test_start_boosters(levels: Array) -> void:
	for level in levels:
		if not level.has("board"):
			continue
		var s := GameState.new(level)
		var before := s.remaining()
		var r := s.magnet()
		check(r.ok and s.remaining() == before - 3, "L%d magnet clears a triple" % level.id)
		check(s.wins_with(s.solution.duplicate()), "L%d still winnable after magnet" % level.id)
	var e := GameState.new(levels[2])
	e.tray_size = 8
	var counts := {}
	var picked := 0
	while picked < 8:
		var options: Array = e.board_tiles().filter(func(t): return e.can_pick(t.id) and int(counts.get(t.type, 0)) < 2)
		if options.is_empty():
			break
		counts[options[0].type] = int(counts.get(options[0].type, 0)) + 1
		e.pick(options[0].id)
		picked += 1
	if e.tray.size() == 8:
		check(e.is_lost(), "eight tiles fill an extra-slot tray")
	elif e.tray.size() == 7:
		check(not e.is_lost(), "seven tiles do not fill an extra-slot tray")

func _test_seed_variety(level: Dictionary) -> void:
	var a := Generator.generate(level)
	var d := level.duplicate(true); d.seed = int(level.seed) + 1
	var b := Generator.generate(d)
	var same := 0
	for i in a.size():
		if a[i].type == b[i].type:
			same += 1
	check(same < a.size(), "different seeds give different deals")
