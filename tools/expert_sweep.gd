extends SceneTree
## Win rate of the expert player (plans ahead, see tests/players.gd), no boosters:
## godot --headless --path . --script res://tools/expert_sweep.gd -- [trials=N] [ids...]
const GameState = preload("res://scripts/core/game_state.gd")
const Players = preload("res://tests/players.gd")

func _init() -> void:
	var trials := 20
	var ids: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("trials="):
			trials = int(a.substr(7))
		else:
			ids.append(int(a))
	var levels: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels.json")).levels
	for L in levels:
		if not ids.is_empty() and not ids.has(int(L.id)):
			continue
		var wins := 0
		var t0 := Time.get_ticks_msec()
		for trial in trials:
			var def: Dictionary = L.duplicate(true)
			def.seed = int(L.seed) + trial * 31 + 300000
			var s := GameState.new(def)
			var rng := RandomNumberGenerator.new()
			rng.seed = trial * 7919 + 3
			if Players.play(s, "expert", false, rng):
				wins += 1
		print("L%d target=%.1f expert=%d%% (%d/%d) %.1fs/game" % [L.id, float(L.target_rating), wins * 100 / trials, wins, trials, (Time.get_ticks_msec() - t0) / 1000.0 / trials])
	quit()
