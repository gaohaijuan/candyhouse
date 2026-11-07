extends SceneTree
## Difficulty sweep: godot --headless --path . --script res://tests/sweep_levels.gd -- [trials=N] [ids...]
## Reports win rates of a casual and a skilled player, both using boosters,
## and the difficulty rating (1-10) derived from the skilled player's rate.
const GameState = preload("res://scripts/core/game_state.gd")
const Players = preload("res://tests/players.gd")

static func rating(skilled: float, casual: float) -> float:
	# Calibrated with the producer: 2 = nearly everyone wins, 6 = a careful
	# player wins about two thirds and a casual one about a third, 8 = most fail.
	var pts := [[1.0, 2.0], [0.9, 4.0], [0.65, 6.0], [0.35, 8.0], [0.1, 10.0]]
	var r := 2.0
	for i in pts.size() - 1:
		var a: Array = pts[i]; var b: Array = pts[i + 1]
		if skilled <= a[0] and skilled >= b[0]:
			r = lerpf(a[1], b[1], (a[0] - skilled) / (a[0] - b[0]))
	if skilled < 0.1:
		r = 10.0
	# A casual player winning often pulls the rating down.
	return clampf(r - maxf(0.0, casual - 0.5) * 4.0, 1.0, 10.0)

func _init() -> void:
	var path := "res://data/levels.json"
	var ids: Array = []
	var trials := 40
	for a in OS.get_cmdline_user_args():
		if a.begins_with("trials="):
			trials = int(a.substr(7))
		elif a.begins_with("levels="):
			path = a.substr(7)
		else:
			ids.append(int(a))
	var levels: Array = JSON.parse_string(FileAccess.get_file_as_string(path)).levels
	for level in levels:
		if not ids.is_empty() and not ids.has(int(level.id)):
			continue
		var wins := {"casual": 0, "skilled": 0}
		for trial in trials:
			for skill in ["casual", "skilled"]:
				var def: Dictionary = level.duplicate(true)
				def.seed = int(level.seed) + trial * 31
				var s := GameState.new(def)
				var rng := RandomNumberGenerator.new()
				rng.seed = trial * 7919 + (1 if skill == "casual" else 2)
				if Players.play(s, skill, true, rng):
					wins[skill] += 1
		var sk: float = wins.skilled / float(trials)
		var ca: float = wins.casual / float(trials)
		print("L%d skilled=%d%% casual=%d%% rating=%.1f" % [level.id, sk * 100, ca * 100, rating(sk, ca)])
	quit()
