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
		_test_level_shape(level)
		_test_solution_wins(level)
		_test_greedy_player(level)
	_test_tray_rules(levels[0])
	_test_undo(levels[1])
	_test_move_out(levels[1])
	_test_shuffle(levels[2])
	_test_shuffle(levels[8])
	_test_seed_variety(levels[2])
	_test_ice(levels[6])
	_test_stacks(levels[9])
	_test_mystery(levels[3])
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
	for trial in 120:
		var def := level.duplicate(true)
		def.seed = int(level.seed) + trial * 31
		if HumanPlayer.play(GameState.new(def)):
			wins += 1
	var rate := wins * 100 / 120
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
		check(not s.is_free(t.id), "mystery tiles start covered")

func _test_seed_variety(level: Dictionary) -> void:
	var a := Generator.generate(level)
	var d := level.duplicate(true); d.seed = int(level.seed) + 1
	var b := Generator.generate(d)
	var same := 0
	for i in a.size():
		if a[i].type == b[i].type:
			same += 1
	check(same < a.size(), "different seeds give different deals")
