extends SceneTree
## Re-measures one authored board on fresh rounds:
## godot --headless --path . --script res://tools/remeasure.gd -- <id> <board.json> [trials=N]
const Author = preload("res://tools/author.gd")

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var id := int(args[0])
	var trials := 100
	for a in args:
		if a.begins_with("trials="):
			trials = int(a.substr(7))
		if a == "ref=planner":
			Author.planner = true
	var spec: Dictionary = {}
	for L in JSON.parse_string(FileAccess.get_file_as_string("res://data/level_plan.json")).levels:
		if int(L.id) == id:
			spec = L
	var b: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	var level := spec.duplicate(true)
	level.types = int(b.types)
	level.board = b.board
	var m := Author._measure(level, trials, 2)
	print("L%d %s target=%.1f rating=%.1f skilled=%d%% casual=%d%%" % [id, args[1], spec.target_rating, m.rating, m.skilled * 100, m.casual * 100])
	quit()
