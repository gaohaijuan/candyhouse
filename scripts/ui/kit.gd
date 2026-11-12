extends RefCounted
## Shared UI building blocks for every page and popup. Each block uses the
## sliced art when it exists (assets/ui/<name>.png) and a clean placeholder
## otherwise, so pages work before their art arrives.

const Lang = preload("res://scripts/core/lang.gd")
const USD_PER_YUAN := 0.99 / 6.0
const Art = preload("res://scripts/game/art.gd")

const BROWN := Color("#6B2404")
const CREAM := Color("#FFF6D5")
const PINK := Color("#F06292")
const OUTLINE := Color("#742507")

static var layout: Dictionary = {}
## Extra height above and below the 1080x1920 design canvas on screens taller
## than 9:16 (the canvas is centred; full-screen layers extend by this much).
static var extra := 0.0

## A full-screen rect in canvas coordinates that covers the whole screen.
static func screen_rect() -> Rect2:
	return Rect2(0, -extra, 1080, 1920 + 2 * extra)

## Screen-edge insets (camera cutout, gesture bar) in canvas units.
static var inset_top := 0.0
static var inset_bottom := 0.0
const EDGE_TOP := 40.0
const EDGE_BOTTOM := 24.0

## On tall screens the top menu moves up towards the screen top and the bottom
## menu down towards the bottom, each keeping a small gap from the edge (and
## clear of any cutout). Bands between move by a share of both, so the empty
## space is spread between the parts instead of piling up at the ends.
## t = 0 is the top menu, 1 the bottom menu.
static func band_shift(t: float) -> float:
	var up := -maxf(0.0, extra - maxf(inset_top, EDGE_TOP))
	var down := maxf(0.0, extra - maxf(inset_bottom, EDGE_BOTTOM))
	return lerpf(up, down, t)

## A full-canvas container for one band; build the band's widgets into it.
static func band(parent: Control, t: float) -> Control:
	var c := Control.new()
	c.size = Vector2(1080, 1920)
	c.position.y = band_shift(t)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c

static func _layout() -> Dictionary:
	if layout.is_empty():
		layout = JSON.parse_string(FileAccess.get_file_as_string("res://data/layout.json"))
	return layout

static func tex(name: String) -> Texture2D:
	return Art.ui(name)

static func words(name: String) -> Texture2D:
	return Art.ui_words(name)

## Text in the game's rounded font. `outline` is drawn only when size > 0.
static func label(text: String, size: int, color := BROWN, outline := Color.TRANSPARENT, outline_size := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline_size > 0:
		l.add_theme_color_override("font_outline_color", outline)
		l.add_theme_constant_override("outline_size", outline_size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Picture from assets/ui, or a soft rounded placeholder with a short caption.
static func picture(name: String, size: Vector2, placeholder_text := "", placeholder_color := Color("#F7C6D6")) -> Control:
	var t := tex(name)
	if t:
		var r := TextureRect.new()
		r.texture = t
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.custom_minimum_size = size
		r.size = size
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return r
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = placeholder_color
	sb.border_color = placeholder_color.darkened(0.25)
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(int(minf(size.x, size.y) * 0.25))
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = size
	p.size = size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if placeholder_text != "":
		var l := label(placeholder_text, int(minf(size.y * 0.32, size.x * 0.5 / maxf(1.0, placeholder_text.length() * 0.6))), BROWN)
		l.size = size
		p.add_child(l)
	return p

## Picture placed at a rect measured from the approved page mockup.
static func art(parent: Control, name: String, rect: Rect2, placeholder_text := "", placeholder_color := Color("#F7C6D6")) -> Control:
	var c := picture(name, rect.size, placeholder_text, placeholder_color)
	c.position = rect.position
	parent.add_child(c)
	return c

## Nine-slice picture stretched to `rect` (margins in texture pixels).
## `k` scales the texture (and its corners) before stretching.
static func nine(parent: Control, name: String, rect: Rect2, m: Array, placeholder_color := Color("#FFF1DC"), k := 1.0) -> Control:
	var t := tex(name)
	if t == null:
		return art(parent, name, rect, "", placeholder_color)
	var np := NinePatchRect.new()
	np.texture = t
	np.patch_margin_left = int(m[0]); np.patch_margin_top = int(m[1])
	np.patch_margin_right = int(m[2]); np.patch_margin_bottom = int(m[3])
	np.position = rect.position
	np.size = rect.size / k
	np.scale = Vector2(k, k)
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(np)
	return np

## Text box placed at a rect measured from the mockup; shrinks long text.
static func text_at(parent: Control, text: String, rect: Rect2, size: int, color := BROWN, outline := Color.TRANSPARENT, outline_size := 0) -> Label:
	var l := label(text, size, color, outline, outline_size)
	shrink_to_fit(l, rect.size.x)
	l.position = rect.position
	l.size = rect.size
	parent.add_child(l)
	return l

## One row of like labels (tabs, booster names) all take the smallest size
## any of them had to shrink to, so they share one size and baseline.
static func same_size(ls: Array) -> void:
	var fs := 1 << 20
	for l in ls:
		fs = mini(fs, l.get_theme_font_size("font_size"))
	for l in ls:
		l.add_theme_font_size_override("font_size", fs)

## Store price tiers: each dollar price and what the same tier sells for in
## Japan (yen) and Korea (won), as the stores price them (producer
## 2026-11-11: prices follow the currency). A release build shows the
## store's own localized price string instead when billing provides it.
const PRICE_TIERS := {
	"0.99": [160, 1500], "1.99": [300, 3000], "2.99": [500, 4400], "4.99": [800, 7500],
	"9.99": [1500, 15000], "19.99": [3000, 29000], "49.99": [7800, 73000], "99.99": [15000, 149000],
}
const YEN_PER_USD := 150.0
const WON_PER_USD := 1500.0

## The currency the current language shows: yuan in Chinese, yen in
## Japanese, won in Korean, dollars otherwise.
static func currency() -> String:
	return {"zh": "cny", "ja": "jpy", "ko": "krw"}.get(Lang.code, "usd")

## A store product's price in the language's currency: its dollar tier
## ($0.99), that tier in yen (¥160) or won (₩1,500); in Chinese yuan, whole
## without decimals, else one decimal (¥3, ¥0.1).
static func price_text(p: Dictionary) -> String:
	var usd := float(p.get("usd", 0.99))
	match currency():
		"cny":
			var f := float(p.price)
			return "¥%d" % int(f) if is_equal_approx(f, roundf(f)) else "¥%.1f" % f
		"jpy":
			return "¥" + _thousands(_tier(usd, 0, YEN_PER_USD, 10))
		"krw":
			return "₩" + _thousands(_tier(usd, 1, WON_PER_USD, 100))
	return "$%.2f" % usd

## An amount given in yuan (what a pack is worth) in the language's currency.
## Dollars follow the store tiers, where ¥6 sells at $0.99; yen and won
## convert those dollars at the tiers' rate, rounded like store prices.
static func money(yuan: float) -> String:
	var usd := yuan * USD_PER_YUAN
	match currency():
		"cny":
			return "¥%d" % int(yuan)
		"jpy":
			return "¥" + _thousands(int(roundf(usd * YEN_PER_USD / 10.0)) * 10)
		"krw":
			return "₩" + _thousands(int(roundf(usd * WON_PER_USD / 100.0)) * 100)
	return "$%.2f" % usd

static func _tier(usd: float, col: int, rate: float, step: int) -> int:
	var key := "%.2f" % usd
	if PRICE_TIERS.has(key):
		return int(PRICE_TIERS[key][col])
	return int(roundf(usd * rate / step)) * step

static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out

## Reward counts and amounts (+100, ×1, 3300): dark brown with a cream
## outline and a soft shadow, the same everywhere.
static func count_label(parent: Control, text: String, rect: Rect2, size: int) -> Label:
	var l := text_at(parent, text, rect, size, Color("#672709"), Color("#FFF7DD"), 10)
	l.add_theme_color_override("font_shadow_color", Color(0.4, 0.15, 0.05, 0.3))
	l.add_theme_constant_override("shadow_offset_y", 4)
	return l

## Invisible tap area over art (keeps the art's own look, adds press feedback).
static func art_button(parent: Control, name: String, rect: Rect2, glyph := "", ring := PINK) -> TextureButton:
	var b := round_button(name, minf(rect.size.x, rect.size.y), glyph, ring)
	b.size = rect.size
	b.custom_minimum_size = rect.size
	b.pivot_offset = rect.size / 2
	for ch in b.get_children():
		(ch as Control).size = rect.size
	b.position = rect.position
	parent.add_child(b)
	return b

## Invisible tap area.
static func hit_area(parent: Control, rect: Rect2) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.position = rect.position
	b.size = rect.size
	parent.add_child(b)
	return b

## Candy pill button (pink / green / cream) stretched by nine-slice.
static func pill(text: String, style := "pink", sz := Vector2(700, 160)) -> TextureButton:
	var b := TextureButton.new()
	b.custom_minimum_size = sz
	b.size = sz
	b.pivot_offset = sz / 2
	b.focus_mode = Control.FOCUS_NONE
	_press_feedback(b)
	var t := tex("button_pill_" + style)
	var pm: Dictionary = _layout().get("popup", {}).get("pill", {}).get(style, {})
	if t and not pm.is_empty():
		var vis: Array = pm.visible
		var nine: Array = pm.nine
		var k: float = sz.y / float(vis[3])
		var np := NinePatchRect.new()
		np.texture = t
		np.patch_margin_left = int(nine[0]); np.patch_margin_right = int(nine[1])
		np.patch_margin_top = int(nine[2]); np.patch_margin_bottom = int(nine[3])
		np.scale = Vector2(k, k)
		np.position = -Vector2(vis[0], vis[1]) * k
		np.size = Vector2(sz.x / k + (t.get_width() - float(vis[2])), t.get_height())
		np.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(np)
	else:
		var fill: Variant = {"pink": Color("#F0508A"), "green": Color("#7CC84A"), "cream": Color("#FFF1DC")}[style]
		var p := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = fill
		sb.border_color = Color("#E0457E") if style == "cream" else fill.darkened(0.2)
		sb.set_border_width_all(6)
		sb.set_corner_radius_all(int(sz.y / 2))
		p.add_theme_stylebox_override("panel", sb)
		p.size = sz
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(p)
	var l := label(text, int(sz.y * 0.42), BROWN if style == "cream" else CREAM, CREAM if style == "cream" else OUTLINE, 6 if style == "cream" else 12)
	# Keep clear of the rounded ends.
	shrink_to_fit(l, sz.x - sz.y * 0.55)
	l.size = sz - Vector2(40, 10)
	l.position = Vector2(20, 0)
	b.add_child(l)
	return b

## Puts an icon at the left end of a pill and keeps the text to its right.
static func pill_icon(b: TextureButton, icon: String) -> void:
	var sz := b.size
	var h := sz.y * 0.72
	var pic := picture(icon, Vector2(h, h), "▶", Color("#FFF6D5"))
	pic.position = Vector2(sz.y * 0.42, (sz.y - h) / 2 - sz.y * 0.04)
	b.add_child(pic)
	for c in b.get_children():
		if c is Label:
			var l: Label = c
			var x := pic.position.x + h + 8
			var w := sz.x - x - sz.y * 0.4
			l.add_theme_font_size_override("font_size", int(sz.y * 0.4))
			shrink_to_fit(l, w)
			l.position.x = x
			l.size.x = w

## Round icon button; `glyph` is a placeholder caption when the art is missing.
static func round_button(icon: String, sz: float, glyph := "", ring := PINK) -> TextureButton:
	var b := TextureButton.new()
	b.custom_minimum_size = Vector2(sz, sz)
	b.size = Vector2(sz, sz)
	b.pivot_offset = b.size / 2
	b.focus_mode = Control.FOCUS_NONE
	_press_feedback(b)
	var t := tex(icon)
	if t:
		var r := TextureRect.new()
		r.texture = t
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.size = b.size
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(r)
	else:
		var p := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#FFF6EA")
		sb.border_color = ring
		sb.set_border_width_all(int(sz * 0.07))
		sb.set_corner_radius_all(int(sz / 2))
		sb.shadow_color = Color(0.5, 0.25, 0.2, 0.3)
		sb.shadow_size = 6
		sb.shadow_offset = Vector2(0, 6)
		p.add_theme_stylebox_override("panel", sb)
		p.size = b.size
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(p)
		var l := label(glyph, int(sz * (0.42 if glyph.length() <= 1 else 0.3)), BROWN)
		l.size = b.size
		b.add_child(l)
	return b

static func _press_feedback(b: BaseButton) -> void:
	b.button_down.connect(func(): b.create_tween().tween_property(b, "scale", Vector2(0.93, 0.93), 0.06))
	b.button_up.connect(func(): b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_BACK))

## Shrinks the font so the widest line fits `max_w` (default: the label's
## width; pass it explicitly when the text may already have widened the label).
## Where the number goes on the coin / life pill art (594 x 168): the cream
## between the icon and the "+", inset 12 px (measured 2026-11-11; the coin
## pill's cream runs x 157-462, the life pill's 177-461; the box sits high
## because digits ink below their line box: measured ink 12 px low at y 40).
## That raise overshoots by about 5 screen px on both pill sizes (home bar
## 117 high, producer 2026-11-12; map/shop/house 92 high, sweet-update-31):
## measured against the pill's inner cream face, so PILL_DY lowers it back.
const PILL_DY := 5.0
const PILL_TEXT := {"coin_pill": Rect2(169, 22, 281, 88), "life_pill": Rect2(189, 22, 260, 88)}

static func pill_text_rect(art: String, rect: Rect2) -> Rect2:
	var k := rect.size / Vector2(594, 168)
	var box: Rect2 = PILL_TEXT.get(art, PILL_TEXT.coin_pill)
	return Rect2(rect.position + box.position * k + Vector2(0, PILL_DY), box.size * k)

## Sets a label's text at its base size, shrinking it to its own width.
static func set_fit(l: Label, text: String, base: int) -> void:
	l.text = text
	l.add_theme_font_size_override("font_size", base)
	shrink_to_fit(l, l.size.x)

static func shrink_to_fit(l: Label, max_w := 0.0) -> void:
	var w := max_w if max_w > 0.0 else l.size.x
	var fs := l.get_theme_font_size("font_size")
	var font := l.get_theme_font("font")
	var widest := 0.0
	for line in TranslationServer.translate(l.text).split("\n"):
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	if widest > w and widest > 0:
		l.add_theme_font_size_override("font_size", int(fs * w / widest))

## Title words for a popup_ribbon drawn into `rect` (the art keeps its
## proportions, centred): inside the ribbon's flat band, clear of the gloss
## strip above and the fold line below, sized from the band so every
## ribbon in the game reads the same.
static func ribbon_title(parent: Control, text: String, rect: Rect2) -> Label:
	var t := tex("popup_ribbon")
	var art := Vector2(t.get_width(), t.get_height()) if t else Vector2(762, 258)
	var k := minf(rect.size.x / art.x, rect.size.y / art.y)
	var o := rect.position + (rect.size - art * k) / 2
	var tb: Array = _layout().get("popup", {}).get("ribbon_text_box", [177, 40, 408, 110])
	var band := Rect2(o + Vector2(tb[0], tb[1]) * k, Vector2(tb[2], tb[3]) * k)
	var fs := int(band.size.y * 0.64)
	var l := label(text, fs, CREAM, OUTLINE, maxi(6, int(fs * 0.14)))
	l.add_theme_color_override("font_shadow_color", Color(0.39, 0.1, 0.03, 0.68))
	l.add_theme_constant_override("shadow_offset_y", maxi(3, int(fs * 0.07)))
	# Long titles may run onto the ribbon's front face beyond the flat band
	# (face is art x 120..645 at band height) before the letters shrink.
	shrink_to_fit(l, band.size.x * 1.1)
	# Centred on the ink, not the line box (re-measured 2026-11-11 after the
	# producer saw titles sitting low: the glyph middle lands 0.16 of the
	# size below the band's middle with the old 0.11 / 0.22 nudges).
	var ink := l.get_theme_font_size("font_size")
	l.position = band.position + Vector2(0, ink * (-0.04 if Lang.code == "en" else 0.06))
	l.size = band.size
	parent.add_child(l)
	return l

## Ribbon title over a pink-framed cream panel. Returns {root, panel, body, close}.
## Add content to `body` (a VBoxContainer), then call `finish_popup(info)`.
static func popup(host: Control, title: String, width := 907.0, closable := false) -> Dictionary:
	var root := Control.new()
	root.size = Vector2(1080, 1920)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(root)
	var dim: Array = _layout().get("popup_dim", [47, 11, 0, 0.6])
	var dimmer := ColorRect.new()
	dimmer.color = Color8(int(dim[0]), int(dim[1]), int(dim[2]), int(float(dim[3]) * 255))
	var sr := screen_rect()
	dimmer.position = sr.position
	dimmer.size = sr.size
	root.add_child(dimmer)
	var panel := Control.new()
	panel.size = Vector2(width, 400)
	root.add_child(panel)
	var pl: Dictionary = _layout().get("popup", {})
	var frame: Control
	var ptex := tex("popup_panel")
	if ptex and pl.has("panel_nine_slice"):
		var np := NinePatchRect.new()
		np.texture = ptex
		var m: Array = pl.panel_nine_slice
		np.patch_margin_left = int(m[0]); np.patch_margin_right = int(m[1])
		np.patch_margin_top = int(m[2]); np.patch_margin_bottom = int(m[3])
		var vis: Array = pl.panel_visible
		var k: float = width / float(vis[2])
		np.scale = Vector2(k, k)
		np.position = -Vector2(vis[0], vis[1]) * k
		frame = np
	else:
		var flat := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#FFF9F0"); sb.border_color = Color("#F06292")
		sb.set_border_width_all(14); sb.set_corner_radius_all(60)
		flat.add_theme_stylebox_override("panel", sb)
		frame = flat
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(frame)
	var rtex := tex("popup_ribbon")
	var rb: Array = pl.get("ribbon_rect", [100, -104, 707, 239])
	var rr := Rect2(rb[0] * width / 907.0, rb[1], rb[2] * width / 907.0, rb[3])
	if rtex:
		var ribbon := TextureRect.new()
		ribbon.texture = rtex
		ribbon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ribbon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ribbon.position = rr.position
		ribbon.size = rr.size
		ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(ribbon)
	# The ribbon's flat band, between its gloss strip and its lower fold line.
	ribbon_title(panel, title, rr)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 28)
	body.alignment = BoxContainer.ALIGNMENT_BEGIN
	body.position = Vector2(70, float(pl.get("content_top", 170)))
	body.size = Vector2(width - 140, 10)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(body)
	var info := {"root": root, "panel": panel, "frame": frame, "body": body, "width": width}
	if closable:
		var c := round_button("button_close", 120, "×", Color("#E0457E"))
		c.position = Vector2(width - 95, -25)
		panel.add_child(c)
		info.close = c
	return info

## Sizes the panel to its content, centres it and plays the pop-in.
static func finish_popup(info: Dictionary, bottom_pad := 70.0) -> void:
	var panel: Control = info.panel
	var body: VBoxContainer = info.body
	var h := body.get_combined_minimum_size().y
	body.size.y = h
	panel.size.y = body.position.y + h + bottom_pad
	var frame: Control = info.frame
	if frame is NinePatchRect:
		var t: Texture2D = frame.texture
		var vis: Array = _layout().popup.panel_visible
		frame.size = panel.size / frame.scale.x + Vector2(t.get_width() - float(vis[2]), t.get_height() - float(vis[3]))
	else:
		frame.size = panel.size
	panel.position = (Vector2(1080, 1920) - panel.size) / 2 + Vector2(0, 40)
	panel.pivot_offset = panel.size / 2
	panel.scale = Vector2(0.7, 0.7)
	panel.modulate.a = 0.0
	var tw := panel.create_tween().set_parallel()
	tw.tween_property(panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, 0.15)

## A centred row inside a popup body.
static func row(children: Array, height: float, gap := 24.0) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", int(gap))
	h.custom_minimum_size = Vector2(0, height)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in children:
		h.add_child(c)
	return h

## A body line of text (word-wrapped to the popup width).
static func text_block(text: String, size := 56, color := BROWN) -> Label:
	var l := label(text, size, color, CREAM, 4)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(700, 0)
	return l

## A pill button wrapped so a VBox keeps its fixed size and centres it.
static func centered(c: Control) -> CenterContainer:
	var cc := CenterContainer.new()
	cc.custom_minimum_size = Vector2(0, c.custom_minimum_size.y)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(c)
	return cc
