extends SceneTree
## Win rate of the simulated player for chosen levels:
## godot --headless --path . --script res://tests/sweep_levels.gd -- 13 14 ...
const GameState = preload("res://scripts/core/game_state.gd")
const HumanPlayer = preload("res://tests/human_player.gd")

func _init() -> void:
	var levels: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels.json")).levels
	var ids: Array = Array(OS.get_cmdline_user_args()).map(func(a): return int(a))
	for level in levels:
		if not ids.is_empty() and not ids.has(int(level.id)):
			continue
		var wins := 0
		var fails := {}
		var trials := 60
		var broken := 0
		for trial in trials:
			var def: Dictionary = level.duplicate(true)
			def.seed = int(level.seed) + trial * 31
			var s := GameState.new(def)
			if s.tiles.is_empty():
				broken += 1
				continue
			if HumanPlayer.play(s):
				wins += 1
			else:
				var r: String = s.lose_reason()
				fails[r] = int(fails.get(r, 0)) + 1
		print("L%d win=%d%% fails=%s broken=%d" % [level.id, wins * 100 / trials, str(fails), broken])
	quit()
