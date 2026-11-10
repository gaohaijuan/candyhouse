extends Control
## Shop (mockup M8): starter pack, free coins by ad, six coin packs, booster
## bundle and remove-ads, in a scrolling list under a fixed header.
## Card rects are the mockup's, shifted up by the header height.

const Kit = preload("res://scripts/ui/kit.gd")
const Common = preload("res://scripts/ui/pages/_common.gd")
const Lang = preload("res://scripts/core/lang.gd")
const TOP := 170.0          # scroll area starts here; content y = mockup y - TOP
const BOOSTER_ICONS := ["icon_undo", "icon_move_out", "icon_shuffle"]

var app
var content: Control
var scroll: ScrollContainer
var balance: Label

func setup(owner_app, _args: Dictionary) -> void:
	app = owner_app
	Common.background(self, "shop_bg")
	scroll = ScrollContainer.new()
	var top := Kit.band(self, 0.0)
	scroll.position = Vector2(0, TOP + top.position.y)
	scroll.size = Vector2(1080, 1920 - TOP - top.position.y + Kit.extra)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(scroll)
	move_child(top, get_child_count() - 1)
	content = Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(content)
	var back := Kit.art_button(top, "button_back", Rect2(18, 14, 131, 132), "返")
	back.pressed.connect(func(): app.goto("home"))
	Kit.art(top, "popup_ribbon", Rect2(283, 13, 505, 152))
	Kit.ribbon_title(top, "商店", Rect2(283, 13, 505, 152))
	Kit.art(top, "coin_pill", Rect2(792, 36, 272, 92))
	balance = Kit.text_at(top, "", Rect2(868, 57, 135, 50), 42, Kit.BROWN)
	app.wallet_changed.connect(_rebuild)
	_rebuild()

func _rebuild() -> void:
	if not is_instance_valid(content):
		return
	balance.text = str(app.profile.data.coins)
	var keep: int = scroll.scroll_vertical
	for c in content.get_children():
		c.queue_free()
	var t: int = app.now()
	var y := 179.0 - TOP
	# Packs: the ¥0.1 limited pack (level 5, 3 days) and the starter pack (always).
	for id in ["limited", "starter"]:
		if not app.profile.iap_available(id, t):
			continue
		var pk: Dictionary = app.profile.iap(id)
		var card := _card("card_wide", Rect2(37, y, 1009, 271))
		if id == "starter":
			Kit.art(card, "starter_bundle", Rect2(30, 22, 480, 238), "礼包", Color("#FDE0EA"))
		else:
			Kit.art(card, "chest_big_open", Rect2(110, 18, 220, 232), "礼包", Color("#FDE0EA"))
		Kit.text_at(card, String(pk.name), Rect2(370, 24, 330, 72), 60, Kit.BROWN, Kit.CREAM, 6)
		if pk.has("tag"):
			# English tags are wider: they go on the gift art, clear of the name.
			_deal_sticker(card, String(pk.tag), Vector2(330, 60) if Lang.is_zh() else Vector2(120, 52), 0.8)
		var n := 0
		for k in pk.get("boosters", {}):
			n += int(pk.boosters[k])
		Kit.text_at(card, tr("%d 金币 + %d 个道具") % [int(pk.coins), n], Rect2(345, 102, 380, 42), 36, Kit.BROWN)
		var pid: String = id
		_price_button(card, Kit.price_text(pk), "pink", Rect2(707, 124, 265, 109), func(): app.popups.offer(pid))
		if pk.has("days"):
			Kit.art(card, "ribbon_limited", Rect2(816, -8, 188, 122), "", Color("#E53935"))
			Kit.text_at(card, "限时", Rect2(852, 14, 116, 58), 44, Kit.CREAM, Color("#B33319"), 6).rotation = 0.17
		y += 286
	var left: int = app.profile.ads_left("free_coins", t)
	var free := _card("card_wide", Rect2(37, y, 1010, 178))
	Kit.art(free, "icon_free_coins", Rect2(35, 16, 281, 145), "免费", Color("#C8E6C9"))
	Kit.text_at(free, "免费金币", Rect2(345, 22, 330, 64), 56, Kit.BROWN, Kit.CREAM, 6)
	Kit.text_at(free, tr("免费领 %d 金币" if app.profile.data.no_ads else "看广告领 %d 金币") % int(app.economy.ad_free_coins), Rect2(330, 92, 345, 48), 38, Kit.BROWN)
	var fb := _price_button(free, tr("免费 (%d/%d)") % [left, int(app.economy.ad_limits.free_coins)], "green", Rect2(687, 36, 293, 106), _free_coins)
	if left <= 0:
		fb.disabled = true
		fb.modulate.a = 0.5
	y += 193
	var packs: Array = app.economy.iap.filter(func(p): return str(p.id).begins_with("coins_"))
	for i in packs.size():
		_pack_card(packs[i], i + 1, Rect2(42 + (i % 2) * 501, y + (i / 2) * 330, 495, 318))
	y += ceili(packs.size() / 2.0) * 330 + 8
	var bundle := _card("card_wide", Rect2(37, y, 1010, 201))
	for k in 3:
		Kit.art(bundle, BOOSTER_ICONS[k], Rect2(28 + k * 88, 45, 110, 110), "", Color("#FDE0EA"))
	Kit.text_at(bundle, "道具组合包", Rect2(330, 30, 340, 66), 56, Kit.BROWN, Kit.CREAM, 6)
	Kit.text_at(bundle, tr("撤回、移出、洗牌 各 %d 个") % int(app.economy.booster_bundle.each), Rect2(320, 104, 360, 48), 36, Kit.BROWN)
	_price_button(bundle, "%d" % int(app.economy.booster_bundle.price), "pink", Rect2(687, 43, 293, 116), _buy_bundle, "coin_small")
	y += 216
	if not app.profile.data.no_ads:
		var na := _card("card_wide", Rect2(36, y, 1011, 201))
		Kit.art(na, "icon_no_ads", Rect2(64, 15, 247, 168), "去广告", Color("#FDE0EA"))
		Kit.text_at(na, "去除广告", Rect2(330, 30, 340, 66), 56, Kit.BROWN, Kit.CREAM, 6)
		Kit.text_at(na, "去除插屏广告", Rect2(330, 104, 340, 48), 40, Kit.BROWN)
		_price_button(na, Kit.price_text(app.profile.iap("no_ads")), "pink", Rect2(687, 40, 293, 122), func(): app.popups.purchase("no_ads"))
		y += 216
	content.custom_minimum_size = Vector2(1080, y + 40)
	scroll.set_deferred("scroll_vertical", keep)

## Big tilted red "1折" sticker that pulses, for a pack's deal tag.
func _deal_sticker(parent: Control, text: String, centre: Vector2, k := 1.0) -> void:
	Common.deal_sticker(parent, text, centre, k)

## A card frame (nine-sliced) holding absolutely placed children.
func _card(art: String, rect: Rect2) -> Control:
	var card := Control.new()
	card.position = rect.position
	card.size = rect.size
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	content.add_child(card)
	var k := 0.72 if art == "card_wide" else 0.85
	Kit.nine(card, art, Rect2(Vector2.ZERO, rect.size), [90, 90, 90, 90], Color("#FFF4DE"), k)
	return card

func _price_button(card: Control, text: String, style: String, rect: Rect2, action: Callable, icon := "") -> TextureButton:
	var b := Kit.pill(text, style, rect.size)
	b.position = rect.position
	card.add_child(b)
	if icon != "":
		Kit.pill_icon(b, icon)
	else:
		for c in b.get_children():
			if c is Label:
				c.add_theme_font_size_override("font_size", int(rect.size.y * 0.52))
				Kit.shrink_to_fit(c, rect.size.x - 60)
	b.pressed.connect(func():
		app.sound.play("tap")
		action.call())
	return b

func _pack_card(p: Dictionary, tier: int, rect: Rect2) -> void:
	var card := _card("card_square", rect)
	Kit.art(card, "coin_tier_%d" % tier, Rect2(97, 12, 300, 138), "金币", Color("#FFE7A8"))
	Kit.count_label(card, str(int(p.coins)), Rect2(0, 146, rect.size.x, 60), 54)
	_price_button(card, Kit.price_text(p), "pink", Rect2(92, 208, 310, 92), func(): app.popups.purchase(p.id))
	if p.has("bonus"):
		Kit.art(card, "bonus_tag", Rect2(331, 5, 153, 84), "", Color("#7CC84A"))
		Kit.text_at(card, str(p.bonus), Rect2(345, 18, 128, 50), 38, Color("#FFF7E0"), Color("#3D7415"), 6)

func _free_coins() -> void:
	var t: int = app.now()
	if app.profile.ads_left("free_coins", t) <= 0:
		return
	app.ads.show_rewarded("free_coins", func(ok):
		if ok:
			app.profile.note_ad("free_coins", app.now())
			app.profile.add_coins(int(app.economy.ad_free_coins))
			app.save()
			app.toast(tr("+%d 金币") % int(app.economy.ad_free_coins)))

func _buy_bundle() -> void:
	if app.profile.buy_bundle():
		app.sound.play("booster")
		app.save()
		app.toast("获得道具组合包")
	else:
		app.toast("金币不足")
