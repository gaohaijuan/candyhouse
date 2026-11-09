extends SceneTree
## Hand-made level 1 (producer, 2026-11-09): the guide must show a real
## triple, so the twelve tiles on top hold three cupcakes and three donuts;
## thirty tiles in all, easy. Writes the board into build/boards/1.json.
## godot --headless --path . --script res://tools/make_level1.gd
const GameState = preload("res://scripts/core/game_state.gd")
const Solver = preload("res://scripts/core/solver.gd")
const Author = preload("res://tools/author.gd")

# Dessert letters are tile types (A = 0 ...). Top layer, x 1..7, y 1..5:
const TOP := ["ABCA", "DBEC", "EADB"]
# Bottom layer, x 0..8, y 0..6; "." = no tile.
const BOTTOM := ["CADB.", "EDCAE", "BCEDA", ".DBEC"]

func _init() -> void:
	var tiles: Array = []
	for y in BOTTOM.size():
		for x in String(BOTTOM[y]).length():
			var ch: String = BOTTOM[y][x]
			if ch != ".":
				tiles.append({"id": tiles.size(), "layer": 0, "type": ch.unicode_at(0) - 65, "x": x * 2, "y": y * 2})
	for y in TOP.size():
		for x in String(TOP[y]).length():
			tiles.append({"id": tiles.size(), "layer": 1, "type": String(TOP[y]).unicode_at(x) - 65, "x": 1 + x * 2, "y": 1 + y * 2})
	var counts := {}
	for t in tiles:
		counts[t.type] = int(counts.get(t.type, 0)) + 1
	print("tiles=%d counts=%s" % [tiles.size(), counts])
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/level_plan.json")).levels[0]
	var level := plan.duplicate(true)
	level.types = counts.size()
	level.board = {"tiles": tiles, "order": []}
	var probe := GameState.new(level)
	var order := Solver.solve_rules(tiles, probe.cover, 20, [])
	level.board.order = order
	var check := GameState.new(level)
	var free := tiles.filter(func(t): return check.is_free(t.id)).map(func(t): return char(65 + int(t.type)))
	print("free at start: ", "".join(free))
	print("solution wins: ", check.wins_with(check.solution.duplicate()), " length ", order.size())
	var m := Author._measure_players(level, 40, 1)
	print("skilled=%d%% casual=%d%% rating=%.1f" % [m.skilled * 100, m.casual * 100, m.rating])
	FileAccess.open("res://build/boards/1.json", FileAccess.WRITE).store_string(JSON.stringify(
		{"rating": m.rating, "skilled": m.skilled, "casual": m.casual, "types": level.types, "board": level.board, "impact": -1.0}))
	quit()
