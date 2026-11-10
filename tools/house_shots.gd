extends SceneTree
## Walks the candy house page and saves screenshots (needs a window):
## godot --path . --script res://tools/house_shots.gd -- --profile=user://house_shots.json --fresh --page=house out=<dir>
## Buys a sofa, recolours it, fills every slot and claims the room reward,
## checking the save after each step.

var app
var out := "user://house_shots"
var shot := 0
var failures := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)

func _snap(name: String) -> void:
	await create_timer(0.8).timeout
	var img := root.get_texture().get_image()
	img.save_png("%s/%02d_%s.png" % [out, shot, name])
	shot += 1

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	app = load("res://scenes/app.tscn").instantiate()
	root.add_child(app)
	await create_timer(1.0).timeout
	app.profile.data.coins = 20000
	app.save()
	var page = app.page
	await _snap("empty")
	page._open_drawer("sofa")
	await _snap("drawer")
	page._show_preview("sofa", "sofa_cream", -1)
	await _snap("preview")
	# Browsing another drawer must put back the unbought preview.
	page._open_drawer("cabinet")
	page._show_preview("cabinet", "cabinet_glass", -1)
	page._open_drawer("chair")
	page._show_preview("chair", "chair_jelly", -1)
	page._close_panel()
	check(page.drawn.get("cabinet", []).is_empty() and page.drawn.get("chair", []).is_empty(), "unbought previews go away")
	page._open_drawer("sofa")
	page._show_preview("sofa", "sofa_cream", -1)
	page._buy("sofa")
	check(app.profile.house_slot("living", "sofa").get("item", "") == "sofa_cream", "sofa bought")
	await _snap("bought")
	page._select("sofa")
	await _snap("selected")
	page._open_colors("sofa")
	page._show_preview("sofa", "sofa_cream", 1)
	await _snap("colour_preview")
	for s in page.room.slots:
		if s.id != "sofa":
			page._open_drawer(s.id)
			page._show_preview(s.id, s.items[0].id, -1)
			page._buy(s.id)
	check(app.profile.house_progress(page.room).x == 10, "all slots filled")
	await _snap("full")
	await create_timer(2.5).timeout
	await _snap("reward")
	check(app.profile.data.house.rewarded.has("living"), "reward claimed")
	print("house_shots failures=%d" % failures)
	quit()
