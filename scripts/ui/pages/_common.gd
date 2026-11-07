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
		bg.size = Vector2(1080, 1920)
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
		node = Kit.label("甜点三连", int(width / 4.6), Color("#F0508A"), Color("#FFF6E6"), 26)
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
	var l := Kit.label(text, 64, Kit.CREAM, Kit.OUTLINE, 12)
	l.position = r.position + Vector2(w * 0.2, w * 0.05)
	l.size = Vector2(w * 0.6, w * 0.17)
	Kit.shrink_to_fit(l)
	page.add_child(l)
