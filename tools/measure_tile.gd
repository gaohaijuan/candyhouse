extends SceneTree
## Measures the visible face of assets/ui/tile_base.png (alpha box and where the
## light face ends and the darker thickness edge begins).
func _init() -> void:
	var img: Image = load("res://assets/ui/tile_base.png").get_image()
	var w := img.get_width(); var h := img.get_height()
	var minx := w; var maxx := 0; var miny := h; var maxy := 0
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.5:
				minx = mini(minx, x); maxx = maxi(maxx, x); miny = mini(miny, y); maxy = maxi(maxy, y)
	print("size=%dx%d alpha_box=[%d,%d,%d,%d]" % [w, h, minx, miny, maxx - minx + 1, maxy - miny + 1])
	var cx := (minx + maxx) / 2
	var out := ""
	for y in range(miny, maxy + 1, 6):
		out += "%d:%.2f " % [y, img.get_pixel(cx, y).get_luminance()]
	print(out)
	var cy := (miny + maxy) / 2
	out = ""
	for x in range(minx, maxx + 1, 6):
		out += "%d:%.2f " % [x, img.get_pixel(x, cy).get_luminance()]
	print(out)
	quit()
