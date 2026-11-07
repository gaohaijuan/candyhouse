extends Control
## Shop: starter pack, free coins by ad, six coin packs, booster bundle and
## remove-ads. Purchases go through the app's purchase service.

const Kit = preload("res://scripts/ui/kit.gd")
const Common = preload("res://scripts/ui/pages/_common.gd")
const CurrencyBar = preload("res://scripts/ui/currency_bar.gd")

var app
var list: VBoxContainer

func setup(owner_app, _args: Dictionary) -> void:
	app = owner_app
	Common.background(self, "shop_bg")
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(30, 190)
	scroll.size = Vector2(1020, 1720)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(scroll)
	list = VBoxContainer.new()
	list.custom_minimum_size = Vector2(1020, 0)
	list.add_theme_constant_override("separation", 22)
	scroll.add_child(list)
	var back := Kit.round_button("button_back", 130, "返")
	back.position = Vector2(24, 24)
	back.pressed.connect(func(): app.goto("home"))
	add_child(back)
	Common.title_ribbon(self, "商店")
	var bar := Control.new()
	bar.set_script(CurrencyBar)
	add_child(bar)
	bar.setup(app, false)
	bar.position = Vector2(770, -10)
	app.wallet_changed.connect(_rebuild)
	_rebuild()

func _rebuild() -> void:
	if not is_instance_valid(list):
		return
	for c in list.get_children():
		c.queue_free()
	var t: int = app.now()
	if app.profile.iap_available("starter", t):
		list.add_child(_wide_card("starter_bundle", "新手礼包", "1000 金币 + 道具各 3 个", "¥6", "pink", func(): app.popups.purchase("starter")))
	var left: int = app.profile.ads_left("free_coins", t)
	list.add_child(_wide_card("icon_free_coins", "免费金币", "看广告领 %d 金币" % int(app.economy.ad_free_coins), "免费 (%d/%d)" % [left, int(app.economy.ad_limits.free_coins)], "green", _free_coins, left <= 0))
	var packs: Array = app.economy.iap.filter(func(p): return str(p.id).begins_with("coins_"))
	for r in range(0, packs.size(), 2):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		row.custom_minimum_size = Vector2(1020, 420)
		for k in 2:
			if r + k < packs.size():
				row.add_child(_pack_card(packs[r + k], r + k + 1))
		list.add_child(row)
	list.add_child(_wide_card("booster_bundle", "道具组合包", "撤回、移出、洗牌 各 %d 个" % int(app.economy.booster_bundle.each), "%d 金币" % int(app.economy.booster_bundle.price), "pink", _buy_bundle))
	if not app.profile.data.no_ads:
		list.add_child(_wide_card("icon_no_ads", "去除广告", "去除插屏广告", "¥18", "pink", func(): app.popups.purchase("no_ads")))

func _wide_card(icon: String, title: String, sub: String, price: String, style: String, action: Callable, disabled := false) -> Control:
	var card := Kit.picture("card_wide", Vector2(1020, 230), "", Color("#FFF4DE"))
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var pic := Kit.picture(icon, Vector2(200, 180), "", Color("#FDE0EA"))
	pic.position = Vector2(26, 25)
	card.add_child(pic)
	var t := Kit.label(title, 58, Kit.BROWN)
	t.position = Vector2(240, 30)
	t.size = Vector2(440, 80)
	card.add_child(t)
	var s := Kit.label(sub, 36, Kit.BROWN)
	s.position = Vector2(240, 110)
	s.size = Vector2(440, 70)
	Kit.shrink_to_fit(s)
	card.add_child(s)
	var b := Kit.pill(price, style, Vector2(300, 120))
	b.position = Vector2(690, 55)
	b.disabled = disabled
	b.modulate.a = 0.5 if disabled else 1.0
	b.pressed.connect(action)
	card.add_child(b)
	return card

func _pack_card(p: Dictionary, tier: int) -> Control:
	var card := Kit.picture("card_square", Vector2(500, 420), "", Color("#FFF4DE"))
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var pic := Kit.picture("coin_tier_%d" % tier, Vector2(260, 170), "金币", Color("#FFE7A8"))
	pic.position = Vector2(120, 30)
	card.add_child(pic)
	var n := Kit.label(str(int(p.coins)), 64, Kit.BROWN)
	n.position = Vector2(0, 205)
	n.size = Vector2(500, 80)
	card.add_child(n)
	var b := Kit.pill("¥%d" % int(p.price), "pink", Vector2(360, 110))
	b.position = Vector2(70, 290)
	b.pressed.connect(func(): app.popups.purchase(p.id))
	card.add_child(b)
	if p.has("bonus"):
		var tag := Kit.label(p.bonus, 36, Color.WHITE, Color("#2E7D32"), 8)
		tag.position = Vector2(360, 10)
		tag.size = Vector2(130, 56)
		card.add_child(tag)
	return card

func _free_coins() -> void:
	var t: int = app.now()
	if app.profile.ads_left("free_coins", t) <= 0:
		return
	app.ads.show_rewarded("free_coins", func(ok):
		if ok:
			app.profile.note_ad("free_coins", app.now())
			app.profile.add_coins(int(app.economy.ad_free_coins))
			app.save()
			app.toast("+%d 金币" % int(app.economy.ad_free_coins)))

func _buy_bundle() -> void:
	if app.profile.buy_bundle():
		app.sound.play("booster")
		app.save()
		app.toast("获得道具组合包")
	else:
		app.toast("金币不足")
