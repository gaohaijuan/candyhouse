extends SceneTree
## Plays a level as text, for playtesters who cannot use the window (Codex):
## godot --headless --path . --script res://tools/play_text.gd -- level=<n> [moves=<id,id,...>]
## Replays the moves (tile ids, no boosters), then prints what a player sees:
## the tray, every tile still on the board (covered ones too, as on screen,
## except desserts a mystery or a box still hides) and which can be taken now.
const GameState = preload("res://scripts/core/game_state.gd")

func _init() -> void:
	var level_no := 1
	var moves: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("level="):
			level_no = int(a.substr(6))
		elif a.begins_with("moves="):
			for m in a.substr(6).split(",", false):
				moves.append(int(m))
	var levels: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels.json")).levels
	var def: Dictionary = levels[level_no - 1]
	var s := GameState.new(def)
	for i in moves.size():
		var id: int = moves[i]
		if not s.can_pick(id):
			print("MOVE %d (tile %d) IS NOT ALLOWED; the position before it is shown." % [i + 1, id])
			break
		s.pick(id)
	print("LEVEL %d  moves=%d  tiles left on board=%d" % [level_no, moves.size(), s.board_tiles().size()])
	print("TRAY (%d/%d): %s" % [s.tray.size(), s.tray_size, " ".join(s.tray.map(func(id): return _name(s, id)))])
	if s.is_won():
		print("RESULT: WON")
		quit()
		return
	if s.is_lost():
		print("RESULT: LOST (%s)" % s.lose_reason())
		quit()
		return
	print("RULES: take a free tile into the tray; three of a kind clear; a full tray (7) loses.")
	if s.board_tiles().any(func(t): return t.has("fuse")):
		print("       a candle tile loses the level when its steps reach 0 (every take is a step).")
	if s.board_tiles().any(func(t): return int(t.get("ice", 0)) > 0):
		print("       ice: a frozen tile thaws by one each time any triple clears.")
	if s.board_tiles().any(func(t): return t.has("lock")):
		print("       lock: opens when a triple containing its key tile clears.")
	var free: Array = []
	var covered: Array = []
	for t in s.board_tiles():
		(free if s.is_free(t.id) else covered).append(t)
	free.sort_custom(func(a, b): return a.id < b.id)
	covered.sort_custom(func(a, b): return a.id < b.id)
	print("CAN TAKE NOW:")
	for t in free:
		if s.is_takeable(t.id):
			print("  tile %d: %s%s" % [t.id, _name(s, t.id), _notes(s, t)])
	print("ON TOP BUT BLOCKED (ice or lock):")
	for t in free:
		if not s.is_takeable(t.id):
			print("  tile %d: %s%s" % [t.id, _name(s, t.id), _notes(s, t)])
	print("COVERED (dessert visible unless ?; covered by tile ids):")
	for t in covered:
		var by: Array = s.cover[t.id].filter(func(c): return s.tiles[c].place == "board")
		print("  tile %d: %s layer %d, under %s%s" % [t.id, _name(s, t.id), int(t.layer), str(by), _notes(s, t)])
	quit()

## Desserts are letters A, B, C ...; "?" while a mystery or a box hides it.
static func _name(s, id: int) -> String:
	# In the tray every dessert shows (a box tile is only blank on the board).
	if s.tiles[id].place == "board" and not s.type_known(id):
		return "?"
	return char(65 + int(s.tiles[id].type))

static func _notes(s, t: Dictionary) -> String:
	var n: Array = []
	if int(t.get("ice", 0)) > 0:
		n.append("ice %d" % int(t.ice))
	if t.has("lock"):
		n.append("locked")
	if t.has("key"):
		n.append("key")
	if t.has("fuse"):
		n.append("candle %d steps" % int(t.fuse))
	return "" if n.is_empty() else "  [" + ", ".join(n) + "]"
