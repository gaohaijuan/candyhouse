extends RefCounted
## Helpers shared by full-screen pages.

const Kit = preload("res://scripts/ui/kit.gd")

## Full-screen background: page art, else the game background, else a colour.
static func background(page: Control, art: String) -> void:
	var t := Kit.tex(art)
	if t == null:
		t = Kit.tex("background")
	if t:
		# Page art may carry a transparent rim; show only the painted part.
		var img := t.get_image()
		if img.is_compressed():
			img.decompress()
		var used := img.get_used_rect()
		if used.size != img.get_size() and used.size.x > 0:
			var frame := AtlasTexture.new()
			frame.atlas = t
			frame.region = Rect2(used)
			t = frame
		var bg := TextureRect.new()
		bg.texture = t
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		var sr := Kit.screen_rect()
		bg.position = sr.position
		bg.size = sr.size
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page.add_child(bg)
	else:
		var c := ColorRect.new()
		c.color = Color("#FCE4EC")
		c.size = Vector2(1080, 1920)
		page.add_child(c)

## The game logo: art if present, else big candy-style text.
static func logo(page: Control, centre: Vector2, width: float) -> Control:
	var t := Kit.tex("logo")
	var node: Control
	if t:
		node = Kit.picture("logo", Vector2(width, width * t.get_height() / t.get_width()))
	else:
		node = Kit.label("甜蜜糖果屋", int(width / 5.6), Color("#F0508A"), Color("#FFF6E6"), 26)
		node.size = Vector2(width, width / 3.2)
		node.add_theme_color_override("font_shadow_color", Color(0.6, 0.15, 0.25, 0.6))
		node.add_theme_constant_override("shadow_offset_y", 10)
	node.position = centre - node.size / 2
	page.add_child(node)
	return node

## Ribbon title bar used by the map and shop pages.
static func title_ribbon(page: Control, text: String, y := 20.0) -> void:
	var w := 620.0
	var r := Kit.picture("popup_ribbon", Vector2(w, w * 0.34))
	r.position = Vector2((1080 - w) / 2, y)
	page.add_child(r)
	Kit.ribbon_title(page, text, Rect2(r.position, r.size))

## Exaggerated deal sticker ("1折"): a tilted red ribbon with big cream text
## and a thick outline, pulsing so it catches the eye.
static func deal_sticker(parent: Control, text: String, centre: Vector2, k := 1.0) -> Control:
	var box := Control.new()
	box.size = Vector2(230, 135) * k
	box.position = centre - box.size / 2
	box.pivot_offset = box.size / 2
	box.rotation = -0.2
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(box)
	Kit.art(box, "ribbon_limited", Rect2(Vector2.ZERO, box.size), "", Color("#E53935"))
	var l := Kit.text_at(box, text, Rect2(box.size.x * 0.12, box.size.y * 0.12, box.size.x * 0.76, box.size.y * 0.62), int(64 * k), Color("#FFF27A"), Color("#8E1E12"), int(12 * k))
	l.rotation = 0.17
	l.pivot_offset = l.size / 2
	var tw := box.create_tween().set_loops()
	tw.tween_property(box, "scale", Vector2(1.1, 1.1), 0.45).set_trans(Tween.TRANS_SINE)
	tw.tween_property(box, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_SINE)
	return box
