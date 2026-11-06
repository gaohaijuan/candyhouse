extends SceneTree
## Prints luminance down one slot column of tray.png to find the slot's top and bottom walls.
func _init() -> void:
	var img: Image = load("res://assets/ui/tray.png").get_image()
	var out := ""
	for y in range(10, 300, 4):
		out += "%d:%.3f " % [y, img.get_pixel(264, y).get_luminance()]
	print(out)
	quit()
