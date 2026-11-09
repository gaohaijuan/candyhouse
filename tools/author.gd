extends SceneTree
## Authors fixed boards: godot --headless --path . --script res://tools/author.gd -- <id> [candidates=K] [trials=N]
## Reads data/level_plan.json, writes build/boards/<id>.json with the candidate
## whose difficulty rating is closest to the level's target: candidates are
## screened with `trials` rounds, the best three re-measured with `verify`.
const GameState = preload("res://scripts/core/game_state.gd")
const Generator = preload("res://scripts/core/level_generator.gd")
const Players = preload("res://tests/players.gd")
const Sweep = preload("res://tests/sweep_levels.gd")

func _init() -> void:
	var plan_path := "res://data/level_plan.json"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("plan="):
			plan_path = a.substr(5)
	var plan: Array = JSON.parse_string(FileAccess.get_file_as_string(plan_path)).levels
	var id := 0
	var candidates := 10
	var trials := 16
	var verify := 40
	for a in OS.get_cmdline_user_args():
		if a.begins_with("candidates="):
			candidates = int(a.substr(11))
		elif a.begins_with("trials="):
			trials = int(a.substr(7))
		elif a.begins_with("verify="):
			verify = int(a.substr(7))
		elif a.begins_with("plan="):
			pass
		else:
			id = int(a)
	var spec: Dictionary = {}
	for L in plan:
		if int(L.id) == id:
			spec = L
	var target: float = spec.target_rating
	var impact_min: float = float(spec.get("impact", 0.0))
	var shortlist: Array = []
	var tried := 0
	var seed := 0
	# Dessert variety is the main difficulty lever: start mid-range and step
	# towards the target after every measured candidate.
	var spread_types: Array = spec.get("types_range", [spec.types, spec.types])
	var types := int(round((float(spread_types[0]) + float(spread_types[1])) / 2.0))
	while tried < candidates and seed < candidates * 6:
		seed += 1
		var rng := RandomNumberGenerator.new()
		rng.seed = id * 100003 + seed
		var spec_try := spec.duplicate(true)
		spec_try.types = types
		var made := Generator.author_candidate(spec_try, rng)
		if made.is_empty():
			continue
		var level := spec_try.duplicate(true)
		level.board = made
		var check := GameState.new(level)
		if not check.wins_with(check.solution.duplicate()):
			continue
		tried += 1
		var m := _measure(level, trials, 0)
		printerr("L%d cand %d types=%d skilled=%d%% casual=%d%% rating=%.1f" % [id, tried, spec_try.types, m.skilled * 100, m.casual * 100, m.rating])
		if m.rating > target + 0.4:
			types = maxi(int(spread_types[0]), types - 1)
		elif m.rating < target - 0.4:
			types = mini(int(spread_types[1]), types + 1)
		m.types = spec_try.types
		m.board = made
		m.level = level
		shortlist.append(m)
		shortlist.sort_custom(func(a, b): return _miss(a.rating, a.skilled, target) < _miss(b.rating, b.skilled, target))
		shortlist = shortlist.slice(0, 4)
	# The screen above picks lucky measurements; re-measure the best four on
	# fresh seeds (as tests/sweep_levels.gd does) and choose on that.
	var best := {}
	var best_miss := INF
	for c in shortlist:
		var m := _measure(c.level, verify, 1)
		var miss := _miss(m.rating, m.skilled, target)
		var line := "L%d verify types=%d skilled=%d%% casual=%d%% rating=%.1f" % [id, c.types, m.skilled * 100, m.casual * 100, m.rating]
		if impact_min > 0.0:
			var plain := _measure(_strip(c.level), verify, 1)
			m.impact = plain.skilled - m.skilled
			line += " impact=%d%%" % int(m.impact * 100)
			if m.impact < impact_min:
				miss += 10.0
		printerr(line)
		if miss < best_miss:
			best_miss = miss
			best = {"rating": m.rating, "skilled": m.skilled, "casual": m.casual, "types": c.types, "board": c.board, "impact": m.get("impact", -1.0)}
			_save(id, best)  # keep progress even if the run is cut short
	_save(id, best)
	print("L%d target=%.1f chosen rating=%.1f types=%d skilled=%d%% casual=%d%% impact=%d%%" % [id, target, best.get("rating", -1), best.get("types", 0), best.get("skilled", 0) * 100, best.get("casual", 0) * 100, best.get("impact", -1.0) * 100])
	quit()

## Plays `trials` rounds per player without boosters. `pass_no` picks a seed
## family so the verify pass never reuses the screening rounds.
static func _measure(level: Dictionary, trials: int, pass_no: int) -> Dictionary:
	var wins := {"casual": 0, "skilled": 0}
	for trial in trials:
		for skill in ["casual", "skilled"]:
			var def: Dictionary = level.duplicate(true)
			def.seed = int(level.seed) + trial * 31 + pass_no * 100000
			var s := GameState.new(def)
			var prng := RandomNumberGenerator.new()
			prng.seed = trial * 7919 + (1 if skill == "casual" else 2) + pass_no * 104729
			# Rated without boosters: every level must be winnable on skill alone
			# (producer, 2026-11-08); boosters only make it easier.
			if Players.play(s, skill, false, prng):
				wins[skill] += 1
	var sk: float = wins.skilled / float(trials)
	var ca: float = wins.casual / float(trials)
	return {"skilled": sk, "casual": ca, "rating": Sweep.rating(sk, ca)}

## The same board with its mechanics taken away (box piles stay).
static func _strip(level: Dictionary) -> Dictionary:
	var out := level.duplicate(true)
	for t in out.board.tiles:
		for k in ["ice", "key", "lock", "fuse", "mystery"]:
			t.erase(k)
	return out

func _save(id: int, best: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/boards"))
	var f := FileAccess.open("res://build/boards/%d.json" % id, FileAccess.WRITE)
	f.store_string(JSON.stringify(best))

static func _miss(r: float, skilled: float, target: float) -> float:
	var gap := (r - target) * 2.0 if r > target else target - r
	# Hard levels may be rare wins, but a board the careful player never wins is out.
	var min_win := 0.3 if target <= 7.0 else (0.2 if target <= 8.5 else 0.12)
	return gap + (20.0 if skilled < min_win else 0.0)
