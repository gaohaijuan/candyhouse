extends RefCounted
## Every popup in the game. Each one reads and changes the app's profile and
## saves through the app, so the wallet stays consistent everywhere.

const Kit = preload("res://scripts/ui/kit.gd")

var app
var open: Array = []    # popup roots, top last

func _init(owner_app) -> void:
	app = owner_app

func _make(title: String, closable := false, width := 907.0) -> Dictionary:
	var info := Kit.popup(app.popup_layer, title, width, closable)
	open.append(info.root)
	if closable:
		info.close.pressed.connect(func(): close(info))
	return info

func close(info: Dictionary) -> void:
	var root: Control = info.root
	open.erase(root)
	root.queue_free()

func close_all() -> void:
	for r in open:
		if is_instance_valid(r):
			r.queue_free()
	open.clear()

func is_open() -> bool:
	return not open.is_empty()

func _button(info: Dictionary, text: String, style: String, action: Callable, sz := Vector2(700, 150)) -> TextureButton:
	var b := Kit.pill(text, style, sz)
	b.pressed.connect(func():
		app.sound.play("tap")
		action.call())
	info.body.add_child(Kit.centered(b))
	return b

## Rewarded-ad button that respects the daily limit; `reward` runs on success.
func _ad_button(info: Dictionary, text: String, kind: String, reward: Callable) -> TextureButton:
	var left: int = app.profile.ads_left(kind, app.now())
	var b := _button(info, "▶ " + text, "green", func():
		app.ads.show_rewarded(kind, func(ok):
			if ok:
				app.profile.note_ad(kind, app.now())
				reward.call()
				app.save()))
	if left <= 0:
		b.disabled = true
		b.modulate.a = 0.5
	return b

# ---------------------------------------------------------------- privacy & settings

func privacy(on_accept: Callable) -> void:
	var info := _make("温馨提示")
	info.body.add_child(Kit.text_block("欢迎来到甜点三连!\n请阅读并同意《用户协议》和《隐私政策》后开始游戏。"))
	var row_buttons: Array = []
	var no := Kit.pill("不同意", "cream", Vector2(330, 140))
	no.pressed.connect(func(): app.toast("需要同意后才能开始游戏"))
	var yes := Kit.pill("同意并继续", "pink", Vector2(400, 140))
	yes.pressed.connect(func():
		app.profile.data.privacy_accepted = true
		app.save()
		close(info)
		on_accept.call())
	row_buttons = [no, yes]
	info.body.add_child(Kit.row(row_buttons, 150))
	Kit.finish_popup(info)

func settings() -> void:
	var info := _make("设置", true)
	var st: Dictionary = app.profile.data.settings
	for entry in [["music", "音乐"], ["sfx", "音效"], ["vibrate", "震动"]]:
		var key: String = entry[0]
		var name := Kit.label(entry[1], 56, Kit.BROWN)
		name.custom_minimum_size = Vector2(420, 110)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		var toggle: Button = _toggle(bool(st[key]))
		toggle.toggled.connect(func(on):
			st[key] = on
			app.apply_settings()
			app.save()
			_style_toggle(toggle, on))
		info.body.add_child(Kit.row([name, toggle], 110, 120))
	for entry in [["用户协议", "用户协议内容将在正式版提供。"], ["隐私政策", "隐私政策内容将在正式版提供。"], ["联系我们", "客服邮箱将在正式版提供。"], ["恢复购买", ""]]:
		var b := Button.new()
		b.flat = true
		b.text = entry[0] + "  ›"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 50)
		b.add_theme_color_override("font_color", Kit.BROWN)
		b.custom_minimum_size = Vector2(700, 90)
		b.focus_mode = Control.FOCUS_NONE
		var msg: String = entry[1]
		var title: String = entry[0]
		b.pressed.connect(func():
			if title == "恢复购买":
				app.iap.restore(func(_list): app.toast("没有需要恢复的购买"))
			else:
				app.toast(msg))
		info.body.add_child(Kit.centered(b))
	var v := Kit.label("版本 1.0.0", 36, Kit.BROWN)
	v.custom_minimum_size = Vector2(0, 50)
	info.body.add_child(v)
	Kit.finish_popup(info)

## Pink (on) / grey (off) switch; uses toggle_on/off art when available.
func _toggle(on: bool) -> Button:
	var t := Button.new()
	t.toggle_mode = true
	t.button_pressed = on
	t.focus_mode = Control.FOCUS_NONE
	t.custom_minimum_size = Vector2(200, 100)
	var knob := Panel.new()
	knob.name = "Knob"
	knob.size = Vector2(80, 80)
	var ks := StyleBoxFlat.new()
	ks.bg_color = Color("#FFF6E6"); ks.set_corner_radius_all(40)
	ks.shadow_color = Color(0, 0, 0, 0.2); ks.shadow_size = 4; ks.shadow_offset = Vector2(0, 3)
	knob.add_theme_stylebox_override("panel", ks)
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_child(knob)
	_style_toggle(t, on)
	return t

func _style_toggle(t: Button, on: bool) -> void:
	var art := Kit.tex("toggle_on" if on else "toggle_off")
	var knob: Panel = t.get_node("Knob")
	if art:
		var tb := StyleBoxTexture.new()
		tb.texture = art
		for s in ["normal", "hover", "pressed", "hover_pressed"]:
			t.add_theme_stylebox_override(s, tb)
		knob.visible = false
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#F0508A") if on else Color("#BDBDBD")
	sb.set_corner_radius_all(50)
	for s in ["normal", "hover", "pressed", "hover_pressed"]:
		t.add_theme_stylebox_override(s, sb)
	knob.position = Vector2(110 if on else 10, 10)

# ---------------------------------------------------------------- level start

func level_start(index: int) -> void:
	var t: int = app.now()
	var level_id := index + 1
	if app.profile.level_costs_life(level_id) and app.profile.lives(t) <= 0:
		lives()
		return
	var info := _make("第 %d 关" % level_id, true)
	var tag: String = app.difficulty(index)
	if tag != "normal":
		var l := Kit.label("困难" if tag == "hard" else "超难", 48, Color.WHITE, Color("#B71C1C") if tag == "hard" else Color("#6A1B9A"), 10)
		l.custom_minimum_size = Vector2(0, 70)
		info.body.add_child(l)
	var hint := Kit.label("选择开局道具", 56, Kit.BROWN)
	hint.custom_minimum_size = Vector2(0, 80)
	info.body.add_child(hint)
	var chosen := {}
	var cards: Array = []
	for entry in [["extra_slot", "多一格", "icon_extra_slot"], ["magnet", "磁铁", "icon_magnet"]]:
		cards.append(_booster_card(entry[0], entry[1], entry[2], chosen))
	info.body.add_child(Kit.row(cards, 360, 40))
	var cost_life: bool = app.profile.level_costs_life(level_id)
	_button(info, "开始" + ("  (体力 -1)" if cost_life else ""), "pink", func():
		for kind in chosen:
			if not app.profile.use_booster(kind):
				if not app.profile.buy_booster(kind):
					app.toast("金币不足")
					return
				app.profile.use_booster(kind)
		app.save()
		close(info)
		app.goto("game", {"level": index, "start_boosters": chosen.duplicate()}))
	Kit.finish_popup(info)

func _booster_card(kind: String, title: String, icon: String, chosen: Dictionary) -> Control:
	var card := Button.new()
	card.toggle_mode = true
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size = Vector2(330, 350)
	var sb_off := StyleBoxFlat.new()
	sb_off.bg_color = Color("#FFF4DE"); sb_off.border_color = Color("#EAC9A0")
	sb_off.set_border_width_all(6); sb_off.set_corner_radius_all(40)
	var sb_on := sb_off.duplicate()
	sb_on.border_color = Color("#F0508A"); sb_on.set_border_width_all(12)
	for s in ["normal", "hover", "disabled"]:
		card.add_theme_stylebox_override(s, sb_off)
	for s in ["pressed", "hover_pressed"]:
		card.add_theme_stylebox_override(s, sb_on)
	var pic := Kit.picture(icon, Vector2(220, 170), title, Color("#FDE0EA"))
	pic.position = Vector2(55, 30)
	card.add_child(pic)
	var name := Kit.label(title, 50, Kit.BROWN)
	name.position = Vector2(0, 205)
	name.size = Vector2(330, 70)
	card.add_child(name)
	var have: int = app.profile.booster_count(kind)
	var price: int = int(app.economy.booster_price[kind])
	var note := Kit.label("拥有 %d" % have if have > 0 else "%d 金币" % price, 40, Color("#E0457E") if have > 0 else Kit.BROWN)
	note.position = Vector2(0, 272)
	note.size = Vector2(330, 60)
	card.add_child(note)
	card.toggled.connect(func(on):
		if on:
			if have <= 0 and not app.profile.can_afford(price):
				card.set_pressed_no_signal(false)
				app.toast("金币不足")
				return
			chosen[kind] = true
		else:
			chosen.erase(kind))
	return card

# ---------------------------------------------------------------- lives

func lives() -> void:
	var info := _make("体力不足" if app.profile.lives(app.now()) <= 0 else "体力", true)
	var t: int = app.now()
	var hearts := Kit.label("♥".repeat(app.profile.lives(t)) + "♡".repeat(int(app.economy.lives.max) - app.profile.lives(t)), 90, Color("#F06292"), Color.WHITE, 8)
	hearts.custom_minimum_size = Vector2(0, 120)
	info.body.add_child(hearts)
	var wait: int = app.profile.next_life_in(t)
	var timer := Kit.label("体力已满" if wait <= 0 else "下一点体力 %02d:%02d" % [wait / 60, wait % 60], 52, Kit.BROWN)
	timer.custom_minimum_size = Vector2(0, 80)
	info.body.add_child(timer)
	_button(info, "%d 金币 补满体力" % int(app.economy.lives.refill_price), "pink", func():
		if app.profile.refill_lives(app.now()):
			app.save()
			app.toast("体力已补满")
			close(info)
		else:
			app.toast("金币不足" if app.profile.lives(app.now()) < int(app.economy.lives.max) else "体力已满"))
	_ad_button(info, "看广告 +1 体力", "life", func():
		app.profile.add_life(app.now())
		app.toast("+1 体力")
		close(info))
	var left := Kit.label("今日剩余 %d 次" % app.profile.ads_left("life", t), 36, Kit.BROWN)
	left.custom_minimum_size = Vector2(0, 50)
	info.body.add_child(left)
	Kit.finish_popup(info)

# ---------------------------------------------------------------- boosters & purchases

## Shown when a booster runs out mid-level; `got` runs after one is obtained.
func booster_shortage(kind: String, got: Callable) -> void:
	var names := {"undo": "撤回", "move_out": "移出", "shuffle": "洗牌"}
	var info := _make("道具不足", true)
	var pic := Kit.picture("icon_" + kind, Vector2(260, 260), names[kind], Color("#FDE0EA"))
	info.body.add_child(Kit.centered(pic))
	var n := Kit.label("%s ×1" % names[kind], 60, Kit.BROWN)
	n.custom_minimum_size = Vector2(0, 80)
	info.body.add_child(n)
	_button(info, "%d 金币购买" % int(app.economy.booster_price[kind]), "pink", func():
		if app.profile.buy_booster(kind):
			app.save()
			close(info)
			got.call()
		else:
			close(info)
			app.toast("金币不足,去商店看看吧")
			purchase_hint())
	_ad_button(info, "看广告 免费获得", "booster", func():
		app.profile.add_booster(kind)
		close(info)
		got.call())
	var left := Kit.label("今日剩余 %d 次" % app.profile.ads_left("booster", app.now()), 36, Kit.BROWN)
	left.custom_minimum_size = Vector2(0, 50)
	info.body.add_child(left)
	Kit.finish_popup(info)

func purchase_hint() -> void:
	pass

func purchase(product_id: String) -> void:
	var p: Dictionary = app.profile.iap(product_id)
	if p.is_empty() or not app.profile.iap_available(product_id, app.now()):
		app.toast("该商品暂不可购买")
		return
	var info := _make("确认购买", true)
	var what := "%d 金币" % int(p.get("coins", 0)) if p.has("coins") else "去除插屏广告"
	if product_id == "starter":
		what = "新手礼包"
	info.body.add_child(Kit.centered(Kit.picture("coin_pile_big", Vector2(300, 220), "金币", Color("#FFE7A8"))))
	var t := Kit.label(what, 60, Kit.BROWN)
	t.custom_minimum_size = Vector2(0, 80)
	info.body.add_child(t)
	var price := Kit.label("支付 ¥%d" % int(p.price), 52, Kit.BROWN)
	price.custom_minimum_size = Vector2(0, 70)
	info.body.add_child(price)
	var cancel := Kit.pill("取消", "cream", Vector2(330, 140))
	cancel.pressed.connect(func(): close(info))
	var ok := Kit.pill("确认", "pink", Vector2(330, 140))
	ok.pressed.connect(func():
		close(info)
		app.iap.buy(product_id, func(success):
			if success and app.profile.grant_purchase(product_id, app.now()):
				app.save()
				purchase_done(p)
			else:
				app.toast("购买未完成")))
	info.body.add_child(Kit.row([cancel, ok], 150))
	Kit.finish_popup(info)

func purchase_done(p: Dictionary) -> void:
	app.sound.play("win")
	var info := _make("购买成功")
	info.body.add_child(Kit.centered(Kit.picture("coin_pile_big", Vector2(360, 260), "金币", Color("#FFE7A8"))))
	var t := Kit.label("+%d" % int(p.coins) if p.has("coins") else "已去除插屏广告", 72, Kit.BROWN)
	t.custom_minimum_size = Vector2(0, 100)
	info.body.add_child(t)
	_button(info, "好的", "pink", func(): close(info))
	Kit.finish_popup(info)

# ---------------------------------------------------------------- results

## Win: stars, coins, double-by-ad, next level (with interstitial pacing).
func win(index: int, stars: int, coins: int, on_next: Callable) -> void:
	var info := _make("过关!")
	var s := Kit.label("★".repeat(stars) + "☆".repeat(3 - stars), 130, Color("#FFC233"), Color("#7A4A12"), 10)
	s.custom_minimum_size = Vector2(0, 170)
	info.body.add_child(s)
	var c := Kit.label("金币 +%d" % coins, 64, Kit.BROWN)
	c.custom_minimum_size = Vector2(0, 90)
	info.body.add_child(c)
	var doubled := {"done": false}
	var ad := _ad_button(info, "看广告 双倍金币", "win_double", func():
		app.profile.add_coins(coins)
		doubled.done = true
		c.text = "金币 +%d" % (coins * 2)
		app.toast("金币翻倍!"))
	ad.pressed.connect(func(): ad.disabled = true; ad.modulate.a = 0.5, CONNECT_DEFERRED)
	var last: bool = index >= app.levels.size() - 1
	_button(info, "再玩一次" if last else "下一关", "pink", func():
		close(info)
		if app.profile.interstitial_due(index + 1, app.now()):
			app.save()
			app.ads.show_interstitial(on_next)
		else:
			app.save()
			on_next.call())
	Kit.finish_popup(info)

## Loss: revive by coins or ad once per level, or restart / go home (costs a life).
func lose(index: int, title: String, subtitle: String, can_revive: bool, revive: Callable, give_up: Callable) -> void:
	var info := _make(title)
	info.body.add_child(Kit.centered(Kit.picture("macaron_cry", Vector2(300, 240), "呜呜", Color("#F8BBD0"))))
	info.body.add_child(Kit.text_block(subtitle if not can_revive else "移出 3 块甜点,继续挑战!"))
	if can_revive:
		var price := int(app.economy.revive_price)
		_button(info, "%d 金币复活" % price, "pink", func():
			if app.profile.spend(price):
				app.save()
				close(info)
				revive.call()
			else:
				app.toast("金币不足"))
		var ad := Kit.pill("▶ 看广告复活", "green", Vector2(700, 150))
		ad.pressed.connect(func():
			app.ads.show_rewarded("revive", func(ok):
				if ok:
					close(info)
					revive.call()))
		info.body.add_child(Kit.centered(ad))
	var cost: String = "  (体力 -1)" if app.profile.level_costs_life(index + 1) else ""
	_button(info, "重新开始" + cost, "cream", func():
		close(info)
		give_up.call("restart"))
	_button(info, "返回主页", "cream", func():
		close(info)
		give_up.call("home"))
	Kit.finish_popup(info)

# ---------------------------------------------------------------- rewards

func checkin() -> void:
	var t: int = app.now()
	var today: int = app.profile.checkin_today(t)
	var info := _make("每日签到", true, 960)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	var claimed_upto: int = int(app.profile.data.checkin.day) if today < 0 else today
	var wide: Panel = null
	for i in 7:
		var r: Dictionary = app.economy.checkin[i]
		var cell := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#FFF4DE") if i >= claimed_upto else Color("#E8DCCB")
		sb.border_color = Color("#F0508A") if i == today else Color("#EAC9A0")
		sb.set_border_width_all(10 if i == today else 5)
		sb.set_corner_radius_all(32)
		cell.add_theme_stylebox_override("panel", sb)
		var cw := 250.0 if i < 6 else 790.0
		cell.custom_minimum_size = Vector2(cw, 220)
		var d := Kit.label("第%d天" % (i + 1), 40, Kit.BROWN)
		d.position = Vector2(0, 12); d.size = Vector2(cw, 50)
		cell.add_child(d)
		var what := "%d 金币" % int(r.coins) if r.has("coins") else ""
		if r.has("boosters"):
			what += (" + " if what != "" else "") + "道具"
		var w := Kit.label(what, 44, Color("#C2185B"))
		w.position = Vector2(0, 80); w.size = Vector2(cw, 80)
		Kit.shrink_to_fit(w)
		cell.add_child(w)
		if i < claimed_upto:
			var ok := Kit.label("✔ 已领", 38, Color("#2E7D32"))
			ok.position = Vector2(0, 160); ok.size = Vector2(cw, 50)
			cell.add_child(ok)
		if i < 6:
			grid.add_child(cell)
		else:
			wide = cell
	info.body.add_child(Kit.centered(grid))
	info.body.add_child(Kit.centered(wide))
	if today >= 0:
		_ad_button(info, "看广告 双倍领取", "checkin_double", func():
			app.profile.claim_checkin(app.now(), true)
			app.sound.play("win")
			close(info)
			app.toast("签到奖励已翻倍领取"))
		_button(info, "领取", "pink", func():
			app.profile.claim_checkin(app.now())
			app.save()
			app.sound.play("match")
			close(info)
			app.toast("签到成功"))
	else:
		var l := Kit.label("今天已签到,明天再来哦", 48, Kit.BROWN)
		l.custom_minimum_size = Vector2(0, 80)
		info.body.add_child(l)
	Kit.finish_popup(info)

func star_chest() -> void:
	var p: Vector2i = app.profile.chest_progress()
	if not app.profile.can_open_chest():
		app.toast("再收集 %d 颗星星就能开启宝箱" % (p.y - p.x))
		return
	var r: Dictionary = app.profile.open_chest(randi() % 3)
	app.save()
	reward(r)

## "Congratulations" popup listing coins and boosters, with ad doubling.
func reward(r: Dictionary) -> void:
	app.sound.play("win")
	var info := _make("恭喜获得")
	info.body.add_child(Kit.centered(Kit.picture("chest_big_open", Vector2(420, 320), "宝箱", Color("#FFE7A8"))))
	var names := {"undo": "撤回", "move_out": "移出", "shuffle": "洗牌", "extra_slot": "多一格", "magnet": "磁铁"}
	var parts: Array = []
	if int(r.get("coins", 0)) > 0:
		parts.append("金币 +%d" % int(r.coins))
	for k in r.get("boosters", {}):
		parts.append("%s ×%d" % [names.get(k, k), int(r.boosters[k])])
	info.body.add_child(Kit.text_block("   ".join(parts), 56))
	_ad_button(info, "看广告 双倍领取", "chest_double", func():
		app.profile.add_coins(int(r.get("coins", 0)))
		for k in r.get("boosters", {}):
			app.profile.add_booster(k, int(r.boosters[k]))
		close(info)
		app.toast("奖励翻倍!"))
	_button(info, "领取", "pink", func():
		app.save()
		close(info))
	Kit.finish_popup(info)

# ---------------------------------------------------------------- debug

func debug_open(name: String) -> void:
	match name:
		"settings": settings()
		"privacy": privacy(func(): pass)
		"lives": lives()
		"checkin": checkin()
		"chest": reward({"coins": 100, "boosters": {"shuffle": 1}})
		"start": level_start(app.current_level_index())
		"shortage": booster_shortage("shuffle", func(): pass)
		"purchase": purchase("coins_3300")
		"win": win(0, 2, 30, func(): pass)
		"lose": lose(5, "托盘满了", "再想想顺序吧", true, func(): pass, func(_w): pass)
