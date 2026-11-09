extends SceneTree
## Nudges an authored board towards its target rating:
## godot --headless --path . --script res://tools/tune.gd -- <id> src=<board.json> [iters=N] [trials=N] [verify=N] [aim=+R]
## Candidate boards are mostly all-or-nothing for the careful player (it wins
## every round or none), so fresh candidates rarely land in the middle. This
## walks from the closest board in small steps instead: swap the desserts of
## two tiles (kept only while the board's solution still wins) or move a
## candle's countdown by two, re-measure on the same rounds, keep the step
## when it gets closer. Writes build/boards_tune/<id>.json.
const GameState = preload("res://scripts/core/game_state.gd")
const Author = preload("res://tools/author.gd")

func _init() -> void:
	var id := 0
	var src := ""
	var iters := 40
	var trials := 24
	var verify := 40
	var aim := 0.0         # aim above target: tuned boards drop back on fresh rounds
	for a in OS.get_cmdline_user_args():
		if a.begins_with("src="):
			src = a.substr(4)
		elif a.begins_with("iters="):
			iters = int(a.substr(6))
		elif a.begins_with("trials="):
			trials = int(a.substr(7))
		elif a.begins_with("verify="):
			verify = int(a.substr(7))
		elif a.begins_with("aim="):
			aim = float(a.substr(4))
		else:
			id = int(a)
	var spec: Dictionary = {}
	for L in JSON.parse_string(FileAccess.get_file_as_string("res://data/level_plan.json")).levels:
		if int(L.id) == id:
			spec = L
	var target: float = float(spec.target_rating) + aim
	var start: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(src))
	var level := spec.duplicate(true)
	level.types = int(start.types)
	level.board = start.board
	var cur := Author._measure(level, trials, 0)
	var cur_miss := Author._miss(cur.rating, cur.skilled, target)
	printerr("L%d start skilled=%d%% casual=%d%% rating=%.1f" % [id, cur.skilled * 100, cur.casual * 100, cur.rating])
	var rng := RandomNumberGenerator.new()
	rng.seed = id * 7717 + 3
	for it in iters:
		if cur_miss < 0.3:
			break
		var trial := _mutate(level, rng)
		if trial.is_empty():
			continue
		var m := Author._measure(trial, trials, 0)
		var miss := Author._miss(m.rating, m.skilled, target)
		printerr("L%d step %d skilled=%d%% casual=%d%% rating=%.1f%s" % [id, it, m.skilled * 100, m.casual * 100, m.rating, " kept" if miss < cur_miss else ""])
		if miss < cur_miss:
			level = trial
			cur = m
			cur_miss = miss
	var v := Author._measure(level, verify, 1)
	var out := {"rating": v.rating, "skilled": v.skilled, "casual": v.casual, "types": level.types, "board": level.board, "impact": -1.0}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/boards_tune"))
	FileAccess.open("res://build/boards_tune/%d.json" % id, FileAccess.WRITE).store_string(JSON.stringify(out))
	print("L%d target=%.1f tuned rating=%.1f skilled=%d%% casual=%d%%" % [id, target, v.rating, v.skilled * 100, v.casual * 100])
	quit()

static func _mutate(level: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var out := level.duplicate(true)
	var tiles: Array = out.board.tiles
	var candles := tiles.filter(func(t): return t.has("fuse"))
	if not candles.is_empty() and rng.randf() < 0.25:
		var c: Dictionary = candles[rng.randi_range(0, candles.size() - 1)]
		c.fuse = maxi(4, int(c.fuse) + (2 if rng.randf() < 0.5 else -2))
	else:
		var a: Dictionary = tiles[rng.randi_range(0, tiles.size() - 1)]
		var b: Dictionary = tiles[rng.randi_range(0, tiles.size() - 1)]
		if a.type == b.type:
			return {}
		var t = a.type
		a.type = b.type
		b.type = t
	var check := GameState.new(out)
	if not check.wins_with(check.solution.duplicate()):
		return {}
	return out
