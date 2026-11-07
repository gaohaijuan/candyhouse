extends Control
## Level map: a vertical road of level nodes in chapters of ten, scrolled to
## the current level. Tapping an unlocked node opens the level start popup.

const Kit = preload("res://scripts/ui/kit.gd")
const Common = preload("res://scripts/ui/pages/_common.gd")
const CurrencyBar = preload("res://scripts/ui/currency_bar.gd")
const CHAPTERS := ["草莓烘焙屋", "巧克力工坊", "冰淇淋小站", "糖果花园", "节日甜品宴"]
const STEP := 230.0

var app
var scroll: ScrollContainer

func setup(owner_app, _args: Dictionary) -> void:
	app = owner_app
	Common.background(self, "map_bg")
	var n: int = app.levels.size()
	scroll = ScrollContainer.new()
	scroll.position = Vector2(0, 200)
	scroll.size = Vector2(1080, 1520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(scroll)
	var content := Control.new()
	var height := n * STEP + 400
	content.custom_minimum_size = Vector2(1080, height)
	scroll.add_child(content)
	var path := Line2D.new()
	path.width = 70
	path.default_color = Color("#FFF1DC")
	path.joint_mode = Line2D.LINE_JOINT_ROUND
	path.begin_cap_mode = Line2D.LINE_CAP_ROUND
	path.end_cap_mode = Line2D.LINE_CAP_ROUND
	content.add_child(path)
	var current: int = app.current_level_index()
	var unlocked: int = app.levels.size() if app.unlock_all else int(app.profile.data.unlocked)
	for i in n:
		var p := _node_pos(i, height)
		path.add_point(p)
	for i in n:
		var p := _node_pos(i, height)
		if i % 10 == 0:
			var ch := Kit.label("第 %d 章  %s" % [i / 10 + 1, CHAPTERS[mini(i / 10, CHAPTERS.size() - 1)]], 44, Kit.CREAM, Kit.OUTLINE, 10)
			ch.position = Vector2(0, p.y + 110)
			ch.size = Vector2(1080, 60)
			content.add_child(ch)
		var state := "done" if i < current else ("current" if i == current else ("open" if i < unlocked else "locked"))
		if i + 1 > unlocked:
			state = "locked"
		var sz := 200.0 if state == "current" else 160.0
		var art: String = {"done": "node_done", "current": "node_current", "open": "node_done", "locked": "node_locked"}[state]
		var ring: Color = {"done": Color("#26A69A"), "current": Color("#F0508A"), "open": Color("#80CBC4"), "locked": Color("#9E9E9E")}[state]
		var b := Kit.round_button(art, sz, "" if state != "locked" else "锁", ring)
		b.position = p - Vector2(sz, sz) / 2
		content.add_child(b)
		if state != "locked":
			var num := Kit.label(str(i + 1), int(sz * 0.36), Color.WHITE, Color("#5D2A0A"), 10)
			num.size = Vector2(sz, sz)
			b.add_child(num)
			var idx := i
			b.pressed.connect(func(): app.popups.level_start(idx))
		var stars := int(app.profile.data.stars.get(str(i + 1), 0))
		if state == "done":
			var s := Kit.label("★".repeat(stars) + "☆".repeat(3 - stars), 40, Color("#FFC233"), Color("#7A4A12"), 6)
			s.position = p + Vector2(-90, sz / 2 - 10)
			s.size = Vector2(180, 50)
			content.add_child(s)
		var tag: String = app.difficulty(i)
		if tag != "normal" and state != "locked":
			var t := Kit.label("困难" if tag == "hard" else "超难", 32, Color.WHITE, Color("#B71C1C") if tag == "hard" else Color("#6A1B9A"), 8)
			t.position = p + Vector2(sz / 2 - 10, -sz / 2 - 6)
			t.size = Vector2(100, 44)
			content.add_child(t)
	var back := Kit.round_button("button_back", 130, "返")
	back.position = Vector2(24, 24)
	back.pressed.connect(func(): app.goto("home"))
	add_child(back)
	Common.title_ribbon(self, "关卡地图")
	var bar := Control.new()
	bar.set_script(CurrencyBar)
	add_child(bar)
	bar.setup(app, false)
	bar.position = Vector2(770, -10)
	var bottom := Kit.picture("map_bottom_bar", Vector2(960, 130), "", Color("#FFF4DE"))
	bottom.position = Vector2(60, 1760)
	add_child(bottom)
	var pr: Vector2i = app.profile.chest_progress()
	var pl := Kit.label("★ %d/%d   点击开启星星宝箱" % [mini(pr.x, pr.y), pr.y] if pr.x >= pr.y else "★ %d/%d" % [pr.x, pr.y], 48, Kit.BROWN)
	pl.position = bottom.position
	pl.size = bottom.size
	add_child(pl)
	var chest := Button.new()
	chest.flat = true
	chest.position = bottom.position
	chest.size = bottom.size
	chest.pressed.connect(func(): app.popups.star_chest())
	add_child(chest)
	await get_tree().process_frame
	scroll.scroll_vertical = int(_node_pos(current, height).y - 760)

## Levels go bottom to top along a gentle S-curve.
func _node_pos(i: int, height: float) -> Vector2:
	var y := height - 260 - i * STEP
	var x := 540 + 260 * sin(i * 0.9)
	return Vector2(x, y)
