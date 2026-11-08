extends Control
## Level map (mockup M5_B): a winding cream road through one landscape per
## chapter of ten levels, scrolled to the current level. The tenth level of a
## chapter is a chest. Tapping an unlocked node opens the level start popup.

const Kit = preload("res://scripts/ui/kit.gd")
const Common = preload("res://scripts/ui/pages/_common.gd")
const CHAPTERS := ["草莓烘焙屋", "巧克力工坊", "冰淇淋小站", "糖果花园", "节日甜品宴"]
const PER := 10
const BLOCK := 2300.0       # height of one chapter's landscape
const FIRST := 270.0        # first node of a chapter, above the chapter's bottom
const FADE := 260.0         # landscapes overlap and blend over this height
const STEP := 192.0         # vertical distance between levels
const TOP_PAD := 230.0      # room under the fixed header
const BOTTOM_PAD := 240.0   # room above the fixed bottom bar
## Horizontal zigzag of the ten nodes in a chapter (from the mockup).
const XS := [497, 275, 518, 351, 639, 544, 752, 551, 300, 520]

var app
var scroll: ScrollContainer
var height := 0.0
var chapter_label: Label
var chapter_name: Label
var chapters := 1

func setup(owner_app, _args: Dictionary) -> void:
	app = owner_app
	var bg := ColorRect.new()
	bg.color = Color("#9CCB5A")
	bg.position = Kit.screen_rect().position
	bg.size = Kit.screen_rect().size
	add_child(bg)
	var n: int = app.levels.size()
	chapters = ceili(n / float(PER))
	height = chapters * BLOCK + TOP_PAD + BOTTOM_PAD
	scroll = ScrollContainer.new()
	scroll.position = Kit.screen_rect().position
	scroll.size = Kit.screen_rect().size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(scroll)
	var content := Control.new()
	content.custom_minimum_size = Vector2(1080, height)
	scroll.add_child(content)
	_landscapes(content)
	var points: Array[Vector2] = []
	for i in n:
		points.append(_node_pos(i))
	_road(content, points)
	var current: int = app.current_level_index()
	var unlocked: int = app.levels.size() if app.unlock_all else int(app.profile.data.unlocked)
	for c in range(1, chapters):
		_chapter_banner(content, c, _block_top(c) + BLOCK)
	for i in n:
		var state := "done" if i < current else ("current" if i == current else "open")
		if i + 1 > unlocked:
			state = "locked"
		_node(content, i, points[i], state)
	_header()
	_bottom_bar()
	scroll.get_v_scroll_bar().value_changed.connect(func(_v): _update_chapter())
	await get_tree().process_frame
	scroll.scroll_vertical = int(points[current].y - 1000 - Kit.extra)
	_update_chapter()

## Chapter c spans [top, top + BLOCK); chapter 0 is at the bottom.
func _block_top(c: int) -> float:
	return height - BOTTOM_PAD - (c + 1) * BLOCK

func _node_pos(i: int) -> Vector2:
	var c := i / PER
	var j := i % PER
	var y := _block_top(c) + BLOCK - FIRST - j * STEP
	return Vector2(XS[j], y)

func _landscapes(content: Control) -> void:
	var t := Kit.tex("map_bg")
	if t == null:
		return
	# The art has a transparent rim; show only its painted frame.
	var frame := AtlasTexture.new()
	frame.atlas = t
	frame.region = Rect2(27, 81, 1279, 3837)
	var fade := preload("res://shaders/fade_bottom.gdshader")
	for c in chapters:
		var top := _block_top(c)
		var bottom := top + BLOCK
		if c == chapters - 1:
			top = 0.0
		var r := TextureRect.new()
		if c == 0:
			bottom = height
		else:
			# Reach down over the chapter below and fade into it.
			bottom += FADE
			var m := ShaderMaterial.new()
			m.shader = fade
			m.set_shader_parameter("h", bottom - top)
			m.set_shader_parameter("fade", FADE)
			r.material = m
		r.texture = frame
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		r.position = Vector2(0, top)
		r.size = Vector2(1080, bottom - top)
		r.clip_contents = true
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(r)

## The road: the path art's centre strip tiled along a smooth curve.
func _road(content: Control, points: Array[Vector2]) -> void:
	var curve := Curve2D.new()
	for k in points.size():
		var p := points[k]
		var prev := points[maxi(k - 1, 0)]
		var next := points[mini(k + 1, points.size() - 1)]
		# Leave each node sideways so the road swings in wide S-bends.
		var dir := signf(next.x - prev.x)
		if dir == 0.0:
			dir = 1.0
		var tangent := Vector2(dir * 150.0, -40.0)
		curve.add_point(p, -tangent, tangent)
	var line := Line2D.new()
	line.points = curve.tessellate(5, 3)
	line.width = 92
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	var t := Kit.tex("map_path")
	if t:
		var img := t.get_image()
		if img.is_compressed():
			img.decompress()
		line.texture = ImageTexture.create_from_image(img.get_region(Rect2i(205, 2, 102, 54)))
		line.texture_mode = Line2D.LINE_TEXTURE_TILE
		line.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	else:
		line.default_color = Color("#FFF1DC")
	content.add_child(line)

func _chapter_banner(content: Control, c: int, y: float) -> void:
	var w := 560.0
	var r := Kit.picture("popup_ribbon", Vector2(w, w * 258.0 / 762.0))
	r.position = Vector2((1080 - w) / 2, y - r.size.y / 2)
	content.add_child(r)
	Kit.text_at(content, "第 %d 章  %s" % [c + 1, CHAPTERS[mini(c, CHAPTERS.size() - 1)]], Rect2(r.position.x + w * 0.2, r.position.y + w * 0.06, w * 0.6, w * 0.15), 48, Kit.CREAM, Kit.OUTLINE, 10)

func _node(content: Control, i: int, p: Vector2, state: String) -> void:
	var chest := i % PER == PER - 1
	var art: String
	var sz: Vector2
	if chest:
		art = "chest_open" if state == "done" else "chest_closed"
		sz = Vector2(227, 268) if state == "done" else Vector2(230, 192)
	else:
		art = {"done": "node_done", "open": "node_done", "current": "node_current", "locked": "node_locked"}[state]
		sz = {"done": Vector2(186, 150), "open": Vector2(186, 150), "current": Vector2(217, 173), "locked": Vector2(166, 128)}[state]
	var rect := Rect2(p - sz / 2, sz)
	if chest and state == "done":
		rect.position.y -= 50
	if state == "current":
		var glow := Kit.picture("glow_rays", Vector2(520, 520))
		glow.position = p - glow.size / 2 + Vector2(0, -30)
		glow.pivot_offset = glow.size / 2
		glow.modulate.a = 0.75
		content.add_child(glow)
		glow.create_tween().set_loops().tween_property(glow, "rotation", TAU, 14.0).from(0.0)
	var b := Kit.art_button(content, art, rect, "锁" if state == "locked" else "", {"done": Color("#26A69A"), "open": Color("#80CBC4"), "current": Color("#F0508A"), "locked": Color("#9E9E9E")}[state])
	if state != "locked":
		var idx := i
		b.pressed.connect(func(): app.popups.level_start(idx))
	var num := str(i + 1)
	if chest:
		if state == "done":
			# The open chest has a number plate; the art is fitted by height.
			var k := sz.y / 300.0
			Kit.text_at(b, num, Rect2(Vector2((sz.x - 230 * k) / 2 + 71 * k, 230 * k), Vector2(95, 37) * k), 40, Kit.BROWN)
		else:
			Kit.nine(content, "tag_plate", Rect2(p.x - 62, p.y + 70, 124, 56), [42, 14, 43, 14], Color("#FFF4DE"), 56.0 / 79.0)
			Kit.text_at(content, num, Rect2(p.x - 62, p.y + 72, 124, 50), 40, Kit.BROWN)
	elif state != "locked":
		var outline := Color("#B2133A") if state == "current" else Color("#047363")
		var ty := 0.2 if state == "current" else 0.22
		Kit.text_at(b, num, Rect2(sz.x * 0.2, sz.y * ty, sz.x * 0.6, sz.y * 0.48), 72 if num.length() < 2 else 66, Color.WHITE, outline, 10)
	if state == "current":
		Kit.art(content, "node_flag", Rect2(rect.position + Vector2(53, -160), Vector2(184, 189)))
	if state == "done" and not chest:
		var stars := int(app.profile.data.stars.get(str(i + 1), 0))
		var s := 56.0
		for k in stars:
			var star := Kit.picture("map_star_small", Vector2(s, s), "★", Color("#FFC233"))
			star.position = Vector2(p.x - stars * s * 0.5 + k * s, p.y + 40)
			content.add_child(star)
	var tag: String = app.difficulty(i)
	if tag != "normal" and state != "locked" and state != "done":
		var tr := Rect2(p.x + sz.x * 0.25, p.y - sz.y * 0.75, 150, 75)
		Kit.art(content, "tag_hard" if tag == "hard" else "tag_super", tr, "", Color("#E53935") if tag == "hard" else Color("#8E24AA"))
		Kit.text_at(content, "困难" if tag == "hard" else "超难", Rect2(tr.position.x + 32, tr.position.y + 27, 86, 28), 30, Kit.CREAM, Color("#8E1E25"), 6)

func _header() -> void:
	var top := Kit.band(self, 0.0)
	var back := Kit.art_button(top, "button_back", Rect2(14, 25, 141, 141), "返")
	back.pressed.connect(func(): app.goto("home"))
	Kit.art(top, "popup_ribbon", Rect2(201, 0, 629, 218))
	chapter_label = Kit.text_at(top, "", Rect2(396, 17, 264, 71), 66, Kit.CREAM, Kit.OUTLINE, 10)
	chapter_name = Kit.text_at(top, "", Rect2(346, 90, 364, 79), 56, Kit.CREAM, Kit.OUTLINE, 10)
	Kit.art(top, "coin_pill", Rect2(838, 54, 239, 84))
	var coins := Kit.text_at(top, str(app.profile.data.coins), Rect2(905, 72, 112, 48), 40, Kit.BROWN)
	var hit := Kit.hit_area(top, Rect2(838, 54, 239, 84))
	hit.pressed.connect(func(): app.goto("shop"))
	app.wallet_changed.connect(func():
		if is_instance_valid(coins):
			coins.text = str(app.profile.data.coins))

func _bottom_bar() -> void:
	var bottom := Kit.band(self, 1.0)
	var r := Rect2(53, 1711, 994, 172)
	Kit.art(bottom, "map_bottom_bar", r, "", Color("#FFF4DE"))
	Kit.art(bottom, "star", Rect2(215, 1740, 123, 116), "★", Color("#FFC233"))
	var pr: Vector2i = app.profile.chest_progress()
	var ready := pr.x >= pr.y
	Kit.text_at(bottom, "%d/%d" % [mini(pr.x, pr.y), pr.y], Rect2(345, 1752, 330, 92), 72, Kit.BROWN).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var chest := Kit.art_button(bottom, "chest_closed", Rect2(736, 1717, 178, 164), "箱")
	chest.pressed.connect(func(): app.popups.star_chest())
	if ready:
		chest.create_tween().set_loops().tween_property(chest, "rotation", 0.08, 0.15).from(-0.08).set_trans(Tween.TRANS_SINE)
	var hit := Kit.hit_area(bottom, r)
	hit.pressed.connect(func(): app.popups.star_chest())
	bottom.move_child(chest, bottom.get_child_count() - 1)

func _update_chapter() -> void:
	var mid: float = scroll.scroll_vertical + 960.0 + Kit.extra
	var c := clampi(int((height - BOTTOM_PAD - mid) / BLOCK), 0, chapters - 1)
	chapter_label.text = "第 %d 章" % (c + 1)
	chapter_name.text = CHAPTERS[mini(c, CHAPTERS.size() - 1)]
