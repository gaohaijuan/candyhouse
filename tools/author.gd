extends SceneTree
## Authors fixed boards: godot --headless --path . --script res://tools/author.gd -- <id> [candidates=K] [trials=N]
## Reads data/level_plan.json, writes build/boards/<id>.json with the candidate
## whose difficulty rating is closest to the level's target.
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
	for a in OS.get_cmdline_user_args():
		if a.begins_with("candidates="):
			candidates = int(a.substr(11))
		elif a.begins_with("trials="):
			trials = int(a.substr(7))
		elif a.begins_with("plan="):
			pass
		else:
			id = int(a)
	var spec: Dictionary = {}
	for L in plan:
		if int(L.id) == id:
			spec = L
	var target: float = spec.target_rating
	var best := {}
	var tried := 0
	var seed := 0
	# Dessert variety is the main difficulty lever: start mid-range and step
	# towards the target after every measured candidate.
	var spread_types: Array = spec.get("types_range", [spec.types, spec.types])
	var types := int(round((float(spread_types[0]) + float(spread_types[1])) / 2.0))
	while tried < candidates and seed < candidates * 12:
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
		var wins := {"casual": 0, "skilled": 0}
		for trial in trials:
			for skill in ["casual", "skilled"]:
				var s := GameState.new(level)
				var prng := RandomNumberGenerator.new()
				prng.seed = trial * 7919 + (1 if skill == "casual" else 2)
				# Rated without boosters: every level must be winnable on skill alone
				# (producer, 2026-11-08); boosters only make it easier.
				if Players.play(s, skill, false, prng):
					wins[skill] += 1
		var sk: float = wins.skilled / float(trials)
		var ca: float = wins.casual / float(trials)
		var r: float = Sweep.rating(sk, ca)
		printerr("L%d cand %d types=%d skilled=%d%% casual=%d%% rating=%.1f" % [id, tried, spec_try.types, sk * 100, ca * 100, r])
		if r > target + 0.4:
			types = maxi(int(spread_types[0]), types - 1)
		elif r < target - 0.4:
			types = mini(int(spread_types[1]), types + 1)
		# Too hard counts double (a board people cannot win is worse than an
		# easy one); a board the skilled player almost never wins is a last resort.
		if best.is_empty() or _miss(r, sk, target) < _miss(best.rating, best.skilled, target):
			best = {"rating": r, "skilled": sk, "casual": ca, "types": spec_try.types, "board": made}
			_save(id, best)  # keep progress even if the run is cut short
	_save(id, best)
	print("L%d target=%.1f chosen rating=%.1f types=%d skilled=%d%% casual=%d%%" % [id, target, best.get("rating", -1), best.get("types", 0), best.get("skilled", 0) * 100, best.get("casual", 0) * 100])
	quit()

func _save(id: int, best: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/boards"))
	var f := FileAccess.open("res://build/boards/%d.json" % id, FileAccess.WRITE)
	f.store_string(JSON.stringify(best))

static func _miss(r: float, skilled: float, target: float) -> float:
	var gap := (r - target) * 2.0 if r > target else target - r
	return gap + (20.0 if skilled < (0.3 if target <= 7.0 else 0.15) else 0.0)
