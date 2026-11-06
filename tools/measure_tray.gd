extends SceneTree
## Measures the visible frame and slot interiors of assets/ui/tray.png.
## godot --headless --path . --script res://tools/measure_tray.gd

func _init() -> void:
	var img := Image.load_from_file("res://assets/ui/tray.png")
	var w := img.get_width()
	var h := img.get_height()
	var minx := w; var maxx := 0; var miny := h; var maxy := 0
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.5:
				minx = mini(minx, x); maxx = maxi(maxx, x)
				miny = mini(miny, y); maxy = maxi(maxy, y)
	print("size=%dx%d frame=[%d,%d,%d,%d]" % [w, h, minx, miny, maxx - minx + 1, maxy - miny + 1])
	# Slot interiors are recessed (darker) than the raised walls around them.
	var mid := (miny + maxy) / 2
	var lum: Array = []
	for x in w:
		var s := 0.0
		for y in range(mid - 20, mid + 21):
			s += img.get_pixel(x, y).get_luminance()
		lum.append(s / 41.0)
	var interior := 0.0
	for x in range(minx + 40, maxx - 40):
		interior += lum[x]
	interior /= float(maxx - minx - 80)
	var runs: Array = []
	var start := -1
	for x in range(minx, maxx + 1):
		var dark: bool = lum[x] < interior + 0.01 and img.get_pixel(x, mid).a > 0.9
		if dark and start < 0:
			start = x
		elif not dark and start >= 0:
			if x - start > 60:
				runs.append([start, x - 1])
			start = -1
	print("slots=", runs.size())
	for r in runs:
		# vertical extent of this slot at its centre column
		var cx: int = (int(r[0]) + int(r[1])) / 2
		var top := mid; var bottom := mid
		var ref: float = lum[cx]
		while top > miny and absf(img.get_pixel(cx, top - 1).get_luminance() - ref) < 0.05:
			top -= 1
		while bottom < maxy and absf(img.get_pixel(cx, bottom + 1).get_luminance() - ref) < 0.05:
			bottom += 1
		print("slot x=[%d,%d] cx=%.1f y=[%d,%d] cy=%.1f" % [r[0], r[1], (r[0] + r[1]) / 2.0, top, bottom, (top + bottom) / 2.0])
	quit()
