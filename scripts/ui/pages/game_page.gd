extends Control
## Hosts the game board for one level and connects it to the app: boosters
## come from the inventory, wins pay coins, losses offer revive or cost a life.

const GameView = preload("res://scripts/game/game_view.gd")

var app
var view

func setup(owner_app, args: Dictionary) -> void:
	app = owner_app
	view = Control.new()
	view.set_script(GameView)
	view.app = app
	view.level_index = int(args.get("level", 0))
	view.level_from_args = true
	view.start_boosters = args.get("start_boosters", {})
	add_child(view)
