extends Control
## Placeholder tutorial cue: a soft pulsing ring around the target tile.

var t := 0.0

func _process(delta: float) -> void:
	t += delta
	queue_redraw()

func _draw() -> void:
	var k := 0.5 + 0.5 * sin(t * 6.0)
	var grow := 6.0 + 10.0 * k
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = Color(1.0, 0.85, 0.2, 0.6 + 0.4 * k)
	sb.set_border_width_all(8)
	sb.set_corner_radius_all(int(size.x * 0.24))
	draw_style_box(sb, Rect2(-Vector2.ONE * grow, size + Vector2.ONE * grow * 2))
