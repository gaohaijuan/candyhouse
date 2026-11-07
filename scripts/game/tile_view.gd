extends Control
## One dessert tile. Draws sliced art when present, a placeholder otherwise.

const Art = preload("res://scripts/game/art.gd")

var tile_id := -1
var type := 0:
	set(value):
		type = value
		queue_redraw()
## Overlay for covered tiles; replaced by the colour measured from the mockup.
static var cover_tint := Color(0.18, 0.12, 0.2, 0.5)
## Where the visible biscuit sits inside tile_base.png (texture pixels): the face
## alone, and the face plus its thickness edge. The face is scaled to fill
## `face_fill` of the cell so tiles look the same size in the board and the tray.
static var face_box := Rect2(17, 18, 349, 336)
static var visible_box := Rect2(17, 18, 349, 370)
static var face_fill := 0.97
## Multiply colour for covered tiles when real art is used (measured from the mockup).
static var cover_multiply := Color(0.62, 0.55, 0.55)
var dim := 0.0:
	set(value):
		dim = value
		queue_redraw()
## Mystery or buried box tile: the dessert is drawn face-down until revealed.
var face_down := false:
	set(value):
		face_down = value
		queue_redraw()
## Remaining ice; 0 means not frozen.
var ice := 0:
	set(value):
		ice = value
		queue_redraw()

func _init(id: int, kind: int, side: float) -> void:
	tile_id = id
	type = kind
	size = Vector2(side, side)
	pivot_offset = size / 2
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_side(side: float) -> void:
	size = Vector2(side, side)
	pivot_offset = size / 2
	queue_redraw()

func _draw() -> void:
	var s := size.x
	var base := Art.ui("tile_base")
	var icon := Art.dessert_icon(type)
	var shade := Color.WHITE.lerp(cover_multiply, dim) if base else Color.WHITE
	var icon_rect := Rect2(size * 0.12, size * 0.76)
	if base:
		var k := (s * face_fill) / face_box.size.x
		var origin := (Vector2(s, s) - visible_box.size * k) / 2 - visible_box.position * k
		draw_texture_rect(base, Rect2(origin, Vector2(base.get_width(), base.get_height()) * k), false, shade)
		var face := Rect2(origin + face_box.position * k, face_box.size * k)
		icon_rect = face.grow(-face.size.x * 0.1)
	else:
		var face := StyleBoxFlat.new()
		face.bg_color = Color("#FFF6E6")
		face.border_color = Color("#E9B98F")
		face.set_border_width_all(int(s * 0.035))
		face.set_corner_radius_all(int(s * 0.2))
		face.shadow_color = Color(0.55, 0.35, 0.25, 0.35)
		face.shadow_size = int(s * 0.05)
		face.shadow_offset = Vector2(0, s * 0.06)
		draw_style_box(face, Rect2(Vector2.ZERO, size))
	if face_down:
		_draw_mystery(icon_rect, shade)
	elif icon:
		draw_texture_rect(icon, icon_rect, false, shade)
	else:
		var d: Dictionary = Art.DESSERTS[type]
		draw_circle(Vector2(s / 2, s * 0.42), s * 0.24, d.color)
		draw_circle(Vector2(s * 0.43, s * 0.35), s * 0.07, Color(1, 1, 1, 0.55))
		var label: String = d.name.substr(0, 2)
		var fs := int(s * 0.17)
		var w := Art.font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(Art.font, Vector2((s - w) / 2, s * 0.86), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#7A4A32"))
	if ice > 0:
		_draw_ice(icon_rect.grow(icon_rect.size.x * 0.12))
	if dim > 0.0 and not base:
		var overlay := StyleBoxFlat.new()
		overlay.bg_color = Color(cover_tint, cover_tint.a * dim)
		overlay.set_corner_radius_all(int(s * 0.2))
		draw_style_box(overlay, Rect2(Vector2.ZERO, size))

func _draw_mystery(rect: Rect2, shade: Color) -> void:
	var cover := Art.ui("mystery_cover")
	if cover:
		draw_texture_rect(cover, rect.grow(rect.size.x * 0.1), false, shade)
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#F7A8C4") * shade
	sb.border_color = Color("#E06A97") * shade
	sb.set_border_width_all(int(rect.size.x * 0.05))
	sb.set_corner_radius_all(int(rect.size.x * 0.22))
	draw_style_box(sb, rect)
	var fs := int(rect.size.y * 0.7)
	var w := Art.font.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string_outline(Art.font, Vector2(rect.get_center().x - w / 2, rect.position.y + rect.size.y * 0.78), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(fs * 0.12), Color("#B8326A") * shade)
	draw_string(Art.font, Vector2(rect.get_center().x - w / 2, rect.position.y + rect.size.y * 0.78), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE * shade)

func _draw_ice(rect: Rect2) -> void:
	var overlay := Art.ui("ice_overlay")
	if overlay:
		draw_texture_rect(overlay, rect, false)
	else:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.72, 0.9, 1.0, 0.55)
		sb.border_color = Color(0.92, 0.98, 1.0, 0.95)
		sb.set_border_width_all(int(rect.size.x * 0.05))
		sb.set_corner_radius_all(int(rect.size.x * 0.2))
		draw_style_box(sb, rect)
		draw_line(rect.position + rect.size * Vector2(0.2, 0.25), rect.position + rect.size * Vector2(0.45, 0.15), Color(1, 1, 1, 0.8), rect.size.x * 0.04)
	var r := rect.size.x * 0.17
	var c := rect.position + Vector2(rect.size.x - r * 0.6, r * 0.6)
	draw_circle(c, r, Color.WHITE)
	draw_circle(c, r, Color("#4FA3E0"), false, r * 0.18)
	var label := str(ice)
	var fs := int(r * 1.5)
	var w := Art.font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(Art.font, Vector2(c.x - w / 2, c.y + fs * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#2A7CC7"))
