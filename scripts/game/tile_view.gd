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
## Multiply colour for covered tiles when real art is used (measured from the mockup).
static var cover_multiply := Color(0.62, 0.55, 0.55)
var dim := 0.0:
	set(value):
		dim = value
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
	if base:
		var aspect := float(base.get_height()) / base.get_width()
		draw_texture_rect(base, Rect2(Vector2.ZERO, Vector2(s, s * aspect)), false, shade)
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
	if icon:
		draw_texture_rect(icon, Rect2(size * 0.12, size * 0.76), false, shade)
	else:
		var d: Dictionary = Art.DESSERTS[type]
		draw_circle(Vector2(s / 2, s * 0.42), s * 0.24, d.color)
		draw_circle(Vector2(s * 0.43, s * 0.35), s * 0.07, Color(1, 1, 1, 0.55))
		var label: String = d.name.substr(0, 2)
		var fs := int(s * 0.17)
		var w := Art.font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(Art.font, Vector2((s - w) / 2, s * 0.86), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#7A4A32"))
	if dim > 0.0 and not base:
		var overlay := StyleBoxFlat.new()
		overlay.bg_color = Color(cover_tint, cover_tint.a * dim)
		overlay.set_corner_radius_all(int(s * 0.2))
		draw_style_box(overlay, Rect2(Vector2.ZERO, size))
