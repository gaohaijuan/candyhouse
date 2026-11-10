extends Control
## Home (mockup M3_B): wallet, logo, current level, the big play button,
## the starter gift and four entries. Rects are measured from the mockup.

const Kit = preload("res://scripts/ui/kit.gd")
const Common = preload("res://scripts/ui/pages/_common.gd")
const CurrencyBar = preload("res://scripts/ui/currency_bar.gd")

var app
var chest_label: Label
var chest_fill: Control
var checkin_dot: Control

func setup(owner_app, _args: Dictionary) -> void:
	app = owner_app
	Common.background(self, "home_bg")
	# Tall screens: the wallet row and the entries go to the screen edges.
	var top := Kit.band(self, 0.0)
	var mid := Kit.band(self, 0.4)
	var low := Kit.band(self, 0.6)
	var bottom := Kit.band(self, 1.0)
	var bar := Control.new()
	bar.set_script(CurrencyBar)
	top.add_child(bar)
	bar.setup(app)
	var gear := Kit.art_button(top, "button_settings", Rect2(894, 37, 150, 143), "设")
	gear.pressed.connect(func(): app.popups.settings())
	Kit.art(mid, "logo", Rect2(92, 239, 902, 543))
	if not Kit.tex("logo"):
		Common.logo(mid, Vector2(540, 510), 860)
	Kit.nine(mid, "level_plaque", Rect2(302, 792, 473, 150), [185, 55, 185, 55], Color("#FFF4DE"), 150.0 / 228.0)
	# Centred between the plaque's two wheat sprigs (x 377 and 706), on its face.
	Kit.text_at(mid, "第 %d 关" % (app.current_level_index() + 1), Rect2(386, 826, 311, 78), 64, Kit.BROWN)
	var play := Kit.art_button(low, "button_play", Rect2(90, 1209, 900, 233), "开始游戏")
	play.pressed.connect(func(): app.popups.level_start(app.current_level_index()))
	var pt := Kit.text_at(play, "开始游戏", Rect2(175, 48, 554, 121), 108, Kit.CREAM, Kit.OUTLINE, 14)
	pt.add_theme_color_override("font_shadow_color", Color(0.45, 0.08, 0.2, 0.55))
	pt.add_theme_constant_override("shadow_offset_y", 6)
	var entries := [
		["home_icon_shop", "商店", "店", Rect2(34, 1516, 248, 243), func(): app.goto("shop")],
		["home_icon_checkin", "签到", "签", Rect2(296, 1516, 244, 243), func(): app.popups.checkin()],
		["home_icon_map", "地图", "图", Rect2(557, 1516, 245, 243), func(): app.goto("map")],
		["home_icon_house", "糖果屋", "屋", Rect2(808, 1516, 244, 243), func(): app.goto("house")],
	]
	for e in entries:
		var r: Rect2 = e[3]
		var b := Kit.art_button(bottom, e[0], r, e[2])
		b.pressed.connect(e[4])
		Kit.text_at(bottom, e[1], Rect2(r.position.x, 1756, r.size.x, 72), 60, Kit.BROWN, Kit.CREAM, 8)
	checkin_dot = Kit.art(bottom, "dot_red", Rect2(460, 1521, 51, 55), "", Color("#E5484D"))
	# Star chest on the right, mirroring the starter gift (swapped with the
	# candy house, producer 2026-11-10): icon, progress bar, caption plate.
	var chest := Kit.art_button(mid, "home_icon_chest", Rect2(803, 752, 244, 243), "箱")
	chest.pressed.connect(func(): app.popups.star_chest())
	Kit.nine(mid, "chest_progress_bg", Rect2(835, 906, 180, 48), [29, 10, 30, 10])
	chest_fill = Kit.nine(mid, "chest_progress_fill", Rect2(835, 906, 180, 48), [29, 10, 30, 10], Color("#7CC84A"))
	chest_label = Kit.text_at(mid, "", Rect2(852, 908, 146, 44), 34, Kit.BROWN, Kit.CREAM, 5)
	Kit.nine(mid, "tag_plate", Rect2(830, 985, 190, 67), [42, 14, 43, 14])
	Kit.text_at(mid, "宝箱", Rect2(846, 994, 158, 48), 38, Kit.BROWN)
	var now: int = app.now()
	if not app.profile.start_offers(now).is_empty():
		app.save()
	# One pack spot on the left (producer, 2026-11-10): the ¥0.1 limited pack
	# while it runs, then the 1折 pack once it is bought or over. Icons come
	# from icon_pack_<id> when sliced, else the older gift art.
	var shown := "limited" if app.profile.iap_available("limited", now) else ("starter" if app.profile.iap_available("starter", now) else "")
	if shown != "":
		var pk: Dictionary = app.profile.iap(shown)
		var art := "icon_pack_" + shown
		var own_art := Kit.tex(art) != null
		if not own_art:
			art = "starter_gift" if shown == "starter" else "chest_small"
		var gift := Kit.art_button(mid, art, Rect2(27, 760, 256, 236), "礼包", Color("#F5B82E"))
		gift.pressed.connect(func(): app.popups.offer(shown))
		gift.pivot_offset = gift.size / 2
		var bob := gift.create_tween().set_loops()
		bob.tween_property(gift, "scale", Vector2(1.05, 1.05), 0.6).set_trans(Tween.TRANS_SINE)
		bob.tween_property(gift, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE)
		# The icon carries a blank cream plate (x 55-255, centre y 940) for the name.
		Kit.text_at(mid, String(pk.get("name", "礼包")), Rect2(65, 914, 180, 52), 40, Kit.CREAM, Kit.OUTLINE, 9)
		if not own_art:
			if pk.has("tag"):
				Common.deal_sticker(mid, String(pk.tag), Vector2(215, 770), 1.25)
			elif shown == "limited":
				Common.deal_sticker(mid, Kit.price_text(pk.price), Vector2(215, 770), 1.25)
		if pk.has("days"):
			Kit.nine(mid, "tag_plate", Rect2(70, 985, 172, 67), [42, 14, 43, 14])
			Kit.text_at(mid, app.popups.offer_time_left(shown).trim_prefix("仅"), Rect2(84, 994, 144, 48), 34, Kit.BROWN)
		if shown == "limited" and app.profile.offer_first_show("limited"):
			app.save()
			get_tree().create_timer(0.6).timeout.connect(func():
				if is_inside_tree() and app.popups.open.is_empty():
					app.popups.offer("limited"))
	app.wallet_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	if not is_instance_valid(chest_label):
		return
	var p: Vector2i = app.profile.chest_progress()
	chest_label.text = "%d/%d" % [mini(p.x, p.y), p.y]
	# Fill keeps its rounded ends: the narrowest width is the two end caps.
	var k: float = clampf(float(p.x) / maxf(1.0, float(p.y)), 0.0, 1.0)
	chest_fill.visible = k > 0.0
	chest_fill.size.x = lerpf(60.0, 180.0, k)
	checkin_dot.visible = app.profile.checkin_today(app.now()) >= 0
