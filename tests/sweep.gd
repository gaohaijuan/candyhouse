extends SceneTree
## Difficulty sweep for one level: godot --headless --path . --script res://tests/sweep.gd
const GameState = preload("res://scripts/core/game_state.gd")
const HumanPlayer = preload("res://tests/human_player.gd")

func _init() -> void:
	var levels: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels.json")).levels
	var base: Dictionary = levels[2]
	for types in [7, 8]:
		for open in [1]:
			var wins := 0
			for trial in 200:
				var def := base.duplicate(true)
				def.types = types; def.max_open = open; def.seed = 900 + trial * 13
				if HumanPlayer.play(GameState.new(def)):
					wins += 1
			print("types=%d max_open=%d win=%d%%" % [types, open, wins * 100 / 200])
	quit()
