extends RefCounted
## Every popup in the game. Each one reads and changes the app's profile and
## saves through the app, so the wallet stays consistent everywhere.

const Kit = preload("res://scripts/ui/kit.gd")
const Common = preload("res://scripts/ui/pages/_common.gd")

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

## Ad button caption: after "remove ads" the reward is free, so no "watch ad".
func _ad_label(text: String) -> String:
	if not app.profile.data.no_ads:
		return text
	return text.replace("看广告 ", "免费 ").replace("看广告", "免费").replace("免费 免费", "免费")

func _ad_icon() -> String:
	return "" if app.profile.data.no_ads else "icon_ad_tv"

## Rewarded-ad button that respects the daily limit; `reward` runs on success.
func _ad_button(info: Dictionary, text: String, kind: String, reward: Callable) -> TextureButton:
	var left: int = app.profile.ads_left(kind, app.now())
	var b := _button(info, _ad_label(text), "green", func():
		app.ads.show_rewarded(kind, func(ok):
			if ok:
				app.profile.note_ad(kind, app.now())
				reward.call()
				app.save()))
	if _ad_icon() != "":
		Kit.pill_icon(b, _ad_icon())
	if left <= 0:
		b.disabled = true
		b.modulate.a = 0.5
	return b

## Pill placed at a mockup rect inside an absolute-layout box.
func _pill_at(box: Control, text: String, style: String, rect: Rect2, action: Callable, icon := "") -> TextureButton:
	var b := Kit.pill(text, style, rect.size)
	b.position = rect.position
	box.add_child(b)
	if icon != "":
		Kit.pill_icon(b, icon)
	b.pressed.connect(func():
		app.sound.play("tap")
		action.call())
	return b

## Green rewarded-ad pill at a rect; greyed out when today's limit is used.
func _ad_pill_at(box: Control, text: String, kind: String, rect: Rect2, reward: Callable) -> TextureButton:
	var b := _pill_at(box, _ad_label(text), "green", rect, func():
		app.ads.show_rewarded(kind, func(ok):
			if ok:
				app.profile.note_ad(kind, app.now())
				reward.call()
				app.save()), _ad_icon())
	if app.profile.ads_left(kind, app.now()) <= 0:
		b.disabled = true
		b.modulate.a = 0.5
	return b

## Starts an absolute layout: returns a box whose origin is mockup point `o`.
func _abs_body(info: Dictionary, body_y: float, height: float) -> Control:
	var body: VBoxContainer = info.body
	body.position.y = body_y
	var box := _fixed_row(height)
	body.add_child(box)
	return box

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
	# Layout follows mockup M4_B (panel 917 wide; rows measured from it).
	var info := _make("设置", true, 917.0)
	var body: VBoxContainer = info.body
	body.position.y = 120
	body.add_theme_constant_override("separation", 0)
	var st: Dictionary = app.profile.data.settings
	for entry in [["music", "音乐", "icon_music"], ["sfx", "音效", "icon_sound"], ["vibrate", "震动", "icon_vibrate"]]:
		var key: String = entry[0]
		var row := _fixed_row(120)
		Kit.art(row, entry[2], Rect2(30, 12, 150, 96), "", Color("#F8BBD0"))
		Kit.text_at(row, entry[1], Rect2(205, 25, 160, 70), 56, Kit.BROWN).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		var toggle: Button = _toggle(bool(st[key]))
		toggle.position = Vector2(525, 18)
		toggle.toggled.connect(func(on):
			st[key] = on
			app.apply_settings()
			app.save()
			_style_toggle(toggle, on))
		row.add_child(toggle)
		body.add_child(row)
	body.add_child(_fixed_row(14))
	var links := [["用户协议", "用户协议内容将在正式版提供。"], ["隐私政策", "隐私政策内容将在正式版提供。"], ["联系我们", "客服邮箱将在正式版提供。"], ["恢复购买", ""]]
	for i in links.size():
		var title: String = links[i][0]
		var msg: String = links[i][1]
		var row := _fixed_row(97)
		var hit := Button.new()
		hit.flat = true
		hit.focus_mode = Control.FOCUS_NONE
		hit.size = Vector2(777, 97)
		hit.pressed.connect(func():
			if title == "恢复购买":
				app.iap.restore(func(_list): app.toast("没有需要恢复的购买"))
			else:
				app.toast(msg))
		row.add_child(hit)
		Kit.text_at(row, title, Rect2(45, 18, 300, 60), 50, Kit.BROWN).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		if Kit.tex("row_arrow"):
			Kit.art(row, "row_arrow", Rect2(694, 23, 31, 50))
		else:
			Kit.text_at(row, "›", Rect2(680, 18, 50, 60), 60, Kit.BROWN)
		if i < links.size() - 1:
			Kit.nine(row, "row_divider", Rect2(43, 93, 696, 4), [7, 0, 7, 0], Color("#F4B6C8"))
		body.add_child(row)
	var v := Kit.label("版本 1.0.0", 38, Kit.BROWN)
	v.custom_minimum_size = Vector2(0, 70)
	body.add_child(v)
	Kit.finish_popup(info, 50.0)

## A fixed-height row for absolute layouts inside a popup body.
func _fixed_row(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(777, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

## Pink (on) / grey (off) switch; uses toggle_on/off art when available.
func _toggle(on: bool) -> Button:
	var t := Button.new()
	t.toggle_mode = true
	t.button_pressed = on
	t.focus_mode = Control.FOCUS_NONE
	t.custom_minimum_size = Vector2(196, 84)
	t.size = t.custom_minimum_size
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
	# Layout follows mockup M6_A; positions are mockup pixels minus the body origin.
	var info := _make("第 %d 关" % level_id, true, 1020.0)
	var body: VBoxContainer = info.body
	body.position.y = 50
	var tag: String = app.difficulty(index)
	var dy := 0.0 if tag != "normal" else -100.0
	var o := Vector2(98, 522 - dy)
	var box := _fixed_row(1026 + dy)
	body.add_child(box)
	if tag != "normal":
		Kit.art(box, "tag_hard" if tag == "hard" else "tag_super", Rect2(Vector2(380, 521) - o, Vector2(319, 142)), "", Color("#E53935") if tag == "hard" else Color("#8E24AA"))
		Kit.text_at(box, "困难" if tag == "hard" else "超难", Rect2(Vector2(459, 571) - o, Vector2(166, 64)), 60, Kit.CREAM, Color("#A9171C") if tag == "hard" else Color("#5E1A78"), 8)
	Kit.text_at(box, "选择开局道具", Rect2(Vector2(286, 697) - o, Vector2(515, 75)), 66, Kit.BROWN)
	var chosen := {}
	_booster_card(box, Rect2(Vector2(104, 810) - o, Vector2(420, 485)), "extra_slot", "多一格", "icon_extra_slot", Rect2(45, 101, 337, 177), chosen)
	_booster_card(box, Rect2(Vector2(546, 811) - o, Vector2(420, 485)), "magnet", "磁铁", "icon_magnet", Rect2(39, 33, 339, 279), chosen)
	var cost_life: bool = app.profile.level_costs_life(level_id)
	var start := Kit.pill("开始", "pink", Vector2(624, 194))
	start.position = Vector2(218, 1354) - o
	box.add_child(start)
	if cost_life:
		Kit.art(box, "heart_cost_badge", Rect2(Vector2(678, 1322) - o, Vector2(139, 109)), "", Color("#E5484D"))
		Kit.text_at(box, "-1", Rect2(Vector2(708, 1340) - o, Vector2(80, 62)), 54, Color.WHITE, Color("#B5262C"), 6)
	start.pressed.connect(func():
		for kind in chosen:
			if not app.profile.use_booster(kind):
				if not app.profile.buy_booster(kind):
					app.toast("金币不足")
					return
				app.profile.use_booster(kind)
		app.save()
		close(info)
		app.goto("game", {"level": index, "start_boosters": chosen.duplicate()}))
	Kit.finish_popup(info, 80.0)

## A start-booster card: owned count badge, or the coin price when none left.
func _booster_card(parent: Control, rect: Rect2, kind: String, title: String, icon: String, icon_rect: Rect2, chosen: Dictionary) -> void:
	var card := Button.new()
	card.toggle_mode = true
	card.flat = true
	card.focus_mode = Control.FOCUS_NONE
	card.position = rect.position
	card.size = rect.size
	parent.add_child(card)
	var face_off := Kit.picture("booster_card", rect.size, "", Color("#FFF4DE"))
	var face_on := Kit.picture("booster_card_selected", rect.size, "", Color("#FFD6E4"))
	face_on.visible = false
	card.add_child(face_off)
	card.add_child(face_on)
	Kit.art(card, icon, icon_rect, title, Color("#FDE0EA"))
	Kit.text_at(card, title, Rect2(60, 312, 300, 72), 60, Kit.BROWN)
	var have: int = app.profile.booster_count(kind)
	var price: int = int(app.economy.booster_price[kind])
	if have > 0:
		Kit.art(card, "badge", Rect2(292, 380, 109, 80), "", Color("#E5484D"))
		Kit.text_at(card, str(have), Rect2(292, 386, 109, 64), 52, Color.WHITE, Color("#B5291F"), 6)
	else:
		Kit.art(card, "price_chip", Rect2(172, 384, 226, 78), "", Color("#FFF4DE"))
		Kit.text_at(card, str(price), Rect2(250, 392, 130, 58), 46, Kit.BROWN)
	card.toggled.connect(func(on):
		if on and have <= 0 and not app.profile.can_afford(price):
			card.set_pressed_no_signal(false)
			app.toast("金币不足")
			return
		face_on.visible = on
		face_off.visible = not on
		if on:
			chosen[kind] = true
		else:
			chosen.erase(kind))

# ---------------------------------------------------------------- lives

func lives() -> void:
	# Mockup M13_A: panel 949 wide at (63, 557); body origin (133, 667).
	var t: int = app.now()
	var have: int = app.profile.lives(t)
	var info := _make("体力不足" if have <= 0 else "体力", true, 949.0)
	var o := Vector2(133, 667)
	var box := _abs_body(info, 110, 740)
	for i in int(app.economy.lives.max):
		Kit.art(box, "heart" if i < have else "heart_empty", Rect2(Vector2(194 + i * 140, 706) - o, Vector2(132, 119)), "♥" if i < have else "♡", Color("#F06292") if i < have else Color("#E0C9C9"))
	var timer := Kit.text_at(box, "", Rect2(Vector2(240, 860) - o, Vector2(610, 62)), 58, Kit.BROWN)
	var tick := func():
		var wait: int = app.profile.next_life_in(app.now())
		timer.text = "体力已满" if wait <= 0 else "下一点体力 %02d:%02d" % [wait / 60, wait % 60]
	tick.call()
	var clock := Timer.new()
	clock.wait_time = 1.0
	clock.autostart = true
	clock.timeout.connect(tick)
	box.add_child(clock)
	_pill_at(box, "%d 金币 补满体力" % int(app.economy.lives.refill_price), "pink", Rect2(Vector2(154, 954) - o, Vector2(774, 178)), func():
		if app.profile.refill_lives(app.now()):
			app.save()
			app.toast("体力已补满")
			close(info)
		else:
			app.toast("金币不足" if app.profile.lives(app.now()) < int(app.economy.lives.max) else "体力已满"), "coin_small")
	_ad_pill_at(box, "看广告 +1 体力", "life", Rect2(Vector2(154, 1154) - o, Vector2(774, 177)), func():
		app.profile.add_life(app.now())
		app.toast("+1 体力")
		close(info))
	Kit.text_at(box, "今日剩余 %d 次" % app.profile.ads_left("life", t), Rect2(Vector2(340, 1353) - o, Vector2(400, 56)), 50, Kit.BROWN)
	Kit.finish_popup(info, 95.0)

# ---------------------------------------------------------------- boosters & purchases

## Shown when a booster runs out mid-level; `got` runs after one is obtained.
func booster_shortage(kind: String, got: Callable) -> void:
	# Mockup M9: panel 966 wide at (53, 472); body origin (123, 582).
	var names := {"undo": "撤回", "move_out": "移出", "shuffle": "洗牌"}
	var info := _make("道具不足", true, 966.0)
	var o := Vector2(123, 582)
	var box := _abs_body(info, 110, 866)
	Kit.art(box, "booster_disc", Rect2(Vector2(365, 565) - o, Vector2(343, 325)), "", Color("#FDE0EA"))
	Kit.art(box, "icon_" + kind, Rect2(Vector2(409, 616) - o, Vector2(255, 220)), names[kind], Color("#FDE0EA"))
	Kit.text_at(box, "%s ×1" % names[kind], Rect2(Vector2(343, 893) - o, Vector2(403, 87)), 72, Kit.BROWN, Kit.CREAM, 6)
	_pill_at(box, "%d 金币购买" % int(app.economy.booster_price[kind]), "pink", Rect2(Vector2(164, 993) - o, Vector2(748, 185)), func():
		if app.profile.buy_booster(kind):
			app.save()
			close(info)
			got.call()
		else:
			close(info)
			app.toast("金币不足,去商店看看吧"), "coin_small")
	_ad_pill_at(box, "看广告 免费获得", "booster", Rect2(Vector2(164, 1189) - o, Vector2(748, 183)), func():
		app.profile.add_booster(kind)
		close(info)
		got.call())
	Kit.text_at(box, "今日剩余 %d 次" % app.profile.ads_left("booster", app.now()), Rect2(Vector2(343, 1386) - o, Vector2(400, 62)), 50, Kit.BROWN)
	Kit.finish_popup(info, 86.0)

## Picture for a store product: its coin tier, the starter bundle or no-ads.
func _product_art(product_id: String) -> String:
	if product_id == "starter":
		return "starter_bundle"
	if product_id == "limited":
		return "chest_big_open"
	if product_id == "no_ads":
		return "icon_no_ads"
	var packs: Array = app.economy.iap.filter(func(q): return str(q.id).begins_with("coins_"))
	for i in packs.size():
		if packs[i].id == product_id:
			return "coin_tier_%d" % (i + 1)
	return "coin_pile_big"

func _product_name(product_id: String, p: Dictionary) -> String:
	if p.has("name"):
		return String(p.name)
	if product_id == "no_ads":
		return "去除插屏广告"
	return "%d 金币" % int(p.get("coins", 0))

## Pack offer from the home (starter pack, or the ¥0.1 limited pack from
## level 5): only this pack, shown as a big glowing gift with what is inside,
## what it is worth and the price, so it reads as a bargain (producer,
## 2026-11-10). Worth uses the shop's own rates: coins at the ¥6 pack's 100
## per yuan, boosters at their coin prices.
## "仅剩2天" / "仅剩5小时" for a time-limited offer.
func offer_time_left(id: String) -> String:
	var left: int = app.profile.iap_seconds_left(id, app.now())
	if left >= 86400:
		return "仅剩%d天" % ceili(left / 86400.0)
	return "仅剩%d小时" % maxi(1, ceili(left / 3600.0))

func offer(id: String) -> void:
	var p: Dictionary = app.profile.iap(id)
	if p.is_empty() or not app.profile.iap_available(id, app.now()):
		app.goto("shop")
		return
	var root := Control.new()
	root.size = Vector2(1080, 1920)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	app.popup_layer.add_child(root)
	open.append(root)
	var info := {"root": root}
	var dim := ColorRect.new()
	dim.color = Color(0.133, 0.078, 0.094, 0.78)
	dim.position = Kit.screen_rect().position
	dim.size = Kit.screen_rect().size
	root.add_child(dim)
	var glow := Kit.art(root, "glow_rays", Rect2(90, 250, 900, 900))
	glow.pivot_offset = glow.size / 2
	glow.create_tween().set_loops().tween_property(glow, "rotation", TAU, 14.0).from(0.0)
	var gift := Kit.art(root, "starter_bundle", Rect2(230, 430, 620, 317), "礼包", Color("#FDE0EA")) if id == "starter" else Kit.art(root, _product_art(id), Rect2(330, 420, 420, 442), "礼包", Color("#FDE0EA"))
	gift.pivot_offset = gift.size / 2
	gift.scale = Vector2(0.4, 0.4)
	var gt := gift.create_tween()
	gt.tween_property(gift, "scale", Vector2(1.05, 1.05), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	gt.tween_property(gift, "scale", Vector2.ONE, 0.15)
	gt.tween_callback(func():
		var bob := gift.create_tween().set_loops()
		bob.tween_property(gift, "position:y", gift.position.y - 12, 1.0).set_trans(Tween.TRANS_SINE)
		bob.tween_property(gift, "position:y", gift.position.y, 1.0).set_trans(Tween.TRANS_SINE))
	Kit.art(root, "popup_ribbon", Rect2(100, 140, 877, 295))
	var t := Kit.text_at(root, _product_name(id, p), Rect2(262, 183, 571, 140), 120, Kit.CREAM, Kit.OUTLINE, 16)
	t.add_theme_color_override("font_shadow_color", Color(0.39, 0.1, 0.03, 0.68))
	t.add_theme_constant_override("shadow_offset_y", 6)
	if p.has("days"):
		Kit.art(root, "ribbon_limited", Rect2(770, 400, 230, 135), "", Color("#E53935"))
		Kit.text_at(root, offer_time_left(id), Rect2(800, 425, 175, 60), 40, Kit.CREAM, Color("#B33319"), 7).rotation = 0.17
	var items: Array = [["coin_pile_small", "%d" % int(p.coins)]]
	var icons := {"undo": "icon_undo", "move_out": "icon_move_out", "shuffle": "icon_shuffle", "magnet": "icon_magnet", "extra_slot": "icon_extra_slot"}
	for k in p.get("boosters", {}):
		items.append([icons.get(k, "icon_shuffle"), "×%d" % int(p.boosters[k])])
	# Up to four cards in one row; more go in rows of three and the rest of
	# the popup moves down by the extra row.
	var cw := 230.0
	var gap := 18.0
	var per := items.size() if items.size() <= 4 else 3
	var rows := ceili(items.size() / float(per))
	var top_y := 880.0 if rows == 1 else 800.0
	var drop := (rows - 1) * (265 + gap) - (880.0 - top_y)
	for i in items.size():
		var row := i / per
		var in_row := mini(per, items.size() - row * per)
		var x0 := (1080 - in_row * cw - (in_row - 1) * gap) / 2
		var card := Control.new()
		card.position = Vector2(x0 + (i % per) * (cw + gap), top_y + row * (265 + gap))
		card.size = Vector2(cw, 265)
		root.add_child(card)
		Kit.art(card, "reward_card", Rect2(Vector2.ZERO, card.size), "", Color("#FFF4DE"))
		Kit.art(card, items[i][0], Rect2(35, 18, 160, 130))
		Kit.count_label(card, items[i][1], Rect2(10, 146, cw - 20, 56), 54)
		card.pivot_offset = card.size / 2
		card.scale = Vector2.ZERO
		card.create_tween().tween_property(card, "scale", Vector2.ONE, 0.3).set_delay(0.3 + i * 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var worth := int(p.coins) / 100.0
	for k in p.get("boosters", {}):
		worth += int(p.boosters[k]) * int(app.economy.booster_price.get(k, 0)) / 100.0
	var times := worth / float(p.price)
	var times_text := ("%d" % int(times)) if times >= 10 else ("%.1f" % times)
	# Worth, struck through, then the price: the bargain at a glance.
	var was := Kit.text_at(root, "价值 ¥%d" % int(worth), Rect2(240, 1175 + drop, 300, 70), 52, Color("#FFE9EF"), Color("#7A1E3A"), 8)
	var strike := ColorRect.new()
	strike.color = Color("#FF5C7A")
	strike.position = Vector2(270, 1207 + drop)
	strike.size = Vector2(240, 7)
	strike.rotation = -0.06
	root.add_child(strike)
	if p.has("tag"):
		# A pack's own deal tag ("1折") as a big red sticker.
		Common.deal_sticker(root, String(p.tag), Vector2(700, 1205 + drop), 1.35)
	else:
		var deal := Kit.art(root, "bonus_tag", Rect2(560, 1168 + drop, 270, 90), "", Color("#7CC84A"))
		Kit.text_at(root, "超值 %s 倍" % times_text, Rect2(585, 1182 + drop, 225, 60), 44, Color("#FFF7E0"), Color("#3D7415"), 7)
		deal.pivot_offset = deal.size / 2
		var pulse := deal.create_tween().set_loops()
		pulse.tween_property(deal, "scale", Vector2(1.08, 1.08), 0.5).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(deal, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_SINE)
	was.modulate.a = 0.95
	var buy := Kit.pill("仅需 " + Kit.price_text(p.price), "pink", Vector2(861, 209))
	buy.position = Vector2(108, 1300 + drop)
	root.add_child(buy)
	buy.pressed.connect(func():
		app.sound.play("tap")
		app.iap.buy(id, func(success):
			if success and app.profile.grant_purchase(id, app.now()):
				close(info)
				app.save()
				purchase_done(id, p)
				if app.page_name == "home":
					app.goto("home")
			else:
				app.toast("购买未完成")))
	var later := Kit.text_at(root, "以后再说", Rect2(390, 1540 + drop, 300, 80), 50, Color("#FFF1E6"), Color("#5A1A2A"), 8)
	var later_hit := Kit.hit_area(root, Rect2(390, 1530 + drop, 300, 100))
	later_hit.pressed.connect(func(): close(info))
	later.modulate.a = 0.9
	var x := Kit.art_button(root, "button_close", Rect2(900, 150, 120, 123), "×")
	x.pressed.connect(func(): close(info))

func purchase(product_id: String) -> void:
	var p: Dictionary = app.profile.iap(product_id)
	if p.is_empty() or not app.profile.iap_available(product_id, app.now()):
		app.toast("该商品暂不可购买")
		return
	# Mockup M10 (upper): panel 930 wide; body origin (145, 253).
	var info := _make("确认购买", true, 930.0)
	var o := Vector2(145, 253)
	var box := _abs_body(info, 90, 624)
	Kit.art(box, _product_art(product_id), Rect2(Vector2(371, 266) - o, Vector2(320, 224)), "金币", Color("#FFE7A8"))
	Kit.text_at(box, _product_name(product_id, p), Rect2(Vector2(291, 509) - o, Vector2(504, 91)), 74, Kit.BROWN, Kit.CREAM, 6)
	Kit.text_at(box, "支付 " + Kit.price_text(p.price), Rect2(Vector2(342, 610) - o, Vector2(413, 82)), 68, Kit.BROWN)
	_pill_at(box, "取消", "cream", Rect2(Vector2(161, 714) - o, Vector2(363, 163)), func(): close(info))
	_pill_at(box, "确认", "pink", Rect2(Vector2(546, 714) - o, Vector2(373, 163)), func():
		close(info)
		app.iap.buy(product_id, func(success):
			if success and app.profile.grant_purchase(product_id, app.now()):
				app.save()
				purchase_done(product_id, p)
			else:
				app.toast("购买未完成")))
	Kit.finish_popup(info, 73.0)

func purchase_done(product_id: String, p: Dictionary) -> void:
	app.sound.play("win")
	# Mockup M10 (lower): panel 929 wide; body origin (146, 1179).
	var info := _make("购买成功", false, 929.0)
	var o := Vector2(146, 1179)
	var box := _abs_body(info, 90, 613)
	var art := "coin_pile_big" if p.has("coins") and not p.has("boosters") else _product_art(product_id)
	Kit.art(box, art, Rect2(Vector2(238, 1169) - o, Vector2(592, 316)), "金币", Color("#FFE7A8"))
	var what := "+%d" % int(p.coins) if p.has("coins") else "已去除插屏广告"
	Kit.text_at(box, what, Rect2(Vector2(252, 1500) - o, Vector2(582, 105)), 90 if p.has("coins") else 66, Kit.BROWN, Kit.CREAM, 8)
	_pill_at(box, "好的", "pink", Rect2(Vector2(270, 1621) - o, Vector2(539, 171)), func(): close(info))
	Kit.finish_popup(info, 72.0)

## In-level pause: continue, restart / home (heart badge when a life is
## spent) and settings; the close button also continues.
func pause(costs_life: bool, resume: Callable, restart: Callable, home: Callable) -> void:
	var info := _make("暂停", true, 907.0)
	info.close.pressed.connect(resume)
	var box := _abs_body(info, 165, 4 * 190 - 30)
	var rows := [["继续", "pink", resume, false], ["重新开始", "cream", restart, costs_life], ["返回主页", "cream", home, costs_life], ["设置", "cream", func(): settings(), false]]
	for i in rows.size():
		var r: Array = rows[i]
		var rect := Rect2(52, i * 190, 663, 160)
		var act: Callable = r[2]
		_pill_at(box, r[0], r[1], rect, func():
			close(info)
			act.call())
		if r[3]:
			Kit.art(box, "heart_cost_badge", Rect2(rect.end.x - 110, rect.position.y - 22, 120, 103), "", Color("#E5484D"))
			Kit.text_at(box, "-1", Rect2(rect.end.x - 92, rect.position.y - 4, 84, 56), 48, Color.WHITE, Color("#B5262C"), 6)
	Kit.finish_popup(info, 60.0)

# ---------------------------------------------------------------- results

## Win: stars, coins, double-by-ad, next level (with interstitial pacing).
func win(index: int, stars: int, coins: int, on_next: Callable) -> void:
	# Mockup M11_A: panel 971 wide at (54, 544); body origin (124, 644).
	var info := _make("过关!", false, 971.0)
	var o := Vector2(124, 644)
	var box := _abs_body(info, 100, 849)
	for i in 3:
		var r := Rect2(Vector2(191 + i * 242.5, 657) - o, Vector2(213, 210))
		Kit.art(box, "star_off", r, "☆", Color("#D7C2B5"))
		if i < stars:
			var st := Kit.art(box, "star", r, "★", Color("#FFC233"))
			st.pivot_offset = r.size / 2
			st.scale = Vector2.ZERO
			st.create_tween().tween_property(st, "scale", Vector2.ONE, 0.32).set_delay(0.25 + i * 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Kit.art(box, "coin_reward_chip", Rect2(Vector2(303, 906) - o, Vector2(465, 156)), "", Color("#FFF4DE"))
	var c := Kit.text_at(box, "+%d" % coins, Rect2(Vector2(510, 930) - o, Vector2(220, 88)), 80, Kit.BROWN)
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var ad := _ad_pill_at(box, "看广告 双倍金币", "win_double", Rect2(Vector2(153, 1121) - o, Vector2(775, 184)), func():
		app.profile.add_coins(coins)
		c.text = "+%d" % (coins * 2)
		app.toast("金币翻倍!"))
	ad.pressed.connect(func(): ad.disabled = true; ad.modulate.a = 0.5, CONNECT_DEFERRED)
	Kit.nine(box, "tag_x2", Rect2(Vector2(449, 1078) - o, Vector2(182, 84)), [45, 20, 45, 20], Color("#F06292"))
	Kit.text_at(box, "×2", Rect2(Vector2(480, 1092) - o, Vector2(120, 54)), 50, Kit.CREAM, Color("#B5262C"), 6)
	var last: bool = index >= app.levels.size() - 1
	_pill_at(box, "再玩一次" if last else "下一关", "pink", Rect2(Vector2(153, 1318) - o, Vector2(775, 175)), func():
		close(info)
		app.save()
		if app.profile.interstitial_due(index + 1, app.now()):
			app.ads.show_interstitial(on_next)
		else:
			on_next.call())
	Kit.finish_popup(info, 87.0)

## Loss: revive by coins or ad once per level, or restart / go home (costs a life).
func lose(index: int, title: String, subtitle: String, can_revive: bool, revive: Callable, give_up: Callable) -> void:
	# Mockup M12_A: panel 932 wide at (73, 412); body origin (143, 482).
	var info := _make(title, false, 932.0)
	var o := Vector2(143, 482)
	var dy := 0.0 if can_revive else -330.0
	var box := _abs_body(info, 70, 1030 + dy)
	Kit.art(box, "macaron_cry", Rect2(Vector2(357, 479) - o, Vector2(352, 296)), "呜呜", Color("#F8BBD0"))
	var desc := Kit.text_at(box, "移出 3 块甜点,继续挑战!" if can_revive else subtitle, Rect2(Vector2(172, 795) - o, Vector2(736, 66)), 64, Kit.BROWN)
	desc.autowrap_mode = TextServer.AUTOWRAP_OFF
	if can_revive:
		var price := int(app.economy.revive_price)
		_pill_at(box, "%d 金币复活" % price, "pink", Rect2(Vector2(172, 892) - o, Vector2(720, 154)), func():
			if app.profile.spend(price):
				app.save()
				close(info)
				revive.call()
			else:
				app.toast("金币不足"), "coin_small")
		_ad_pill_at(box, "看广告复活", "revive", Rect2(Vector2(171, 1063) - o, Vector2(723, 157)), func():
			close(info)
			revive.call())
	var y := 1246 + dy
	_pill_at(box, "重新开始", "cream", Rect2(Vector2(172, y) - o, Vector2(723, 173)), func():
		close(info)
		give_up.call("restart"))
	if app.profile.level_costs_life(index + 1):
		Kit.art(box, "heart_cost_badge", Rect2(Vector2(732, y - 20) - o, Vector2(131, 119)), "", Color("#E5484D"))
		Kit.text_at(box, "-1", Rect2(Vector2(756, y + 2) - o, Vector2(80, 60)), 52, Color.WHITE, Color("#B5262C"), 6)
	var home := Kit.hit_area(box, Rect2(Vector2(372, y + 185) - o, Vector2(320, 80)))
	Kit.text_at(home, "返回主页", Rect2(0, 0, 320, 80), 50, Kit.BROWN)
	home.pressed.connect(func():
		close(info)
		give_up.call("home"))
	Kit.finish_popup(info, 60.0)

# ---------------------------------------------------------------- rewards

func checkin() -> void:
	# Mockup M14_A: panel 992 wide at (44, 317); body origin (114, 417).
	var t: int = app.now()
	var today: int = app.profile.checkin_today(t)
	var info := _make("每日签到", true, 992.0)
	var o := Vector2(114, 417)
	var box := _abs_body(info, 100, 1332 if today >= 0 else 1120)
	var claimed_upto: int = int(app.profile.data.checkin.day) if today < 0 else today
	var icons := {"undo": "icon_undo", "move_out": "icon_move_out", "shuffle": "icon_shuffle", "extra_slot": "icon_extra_slot", "magnet": "icon_magnet"}
	for i in 7:
		var r: Dictionary = app.economy.checkin[i]
		var claimed := i < claimed_upto
		var rect := Rect2(126, 1014, 824, 338) if i == 6 else Rect2(127 + (i % 3) * 281, 426 + (i / 3) * 292, 265, 270)
		rect.position -= o
		var cell := Control.new()
		cell.position = rect.position
		cell.size = rect.size
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(cell)
		var art := "checkin_cell_wide" if i == 6 else ("checkin_cell_claimed" if claimed else ("checkin_cell_today" if i == today else "checkin_cell"))
		var margin := 62 if art == "checkin_cell_today" else (74 if i == 6 else 57)
		var frame_rect := Rect2(Vector2.ZERO, rect.size)
		if i == today and i < 6:
			frame_rect = frame_rect.grow(8)
		Kit.nine(cell, art, frame_rect, [margin, margin, margin, margin], Color("#E8DCCB") if claimed else Color("#FFF4DE"))
		if i == 6 and claimed:
			cell.modulate = Color(0.85, 0.8, 0.76)
		var ink := Color("#915C41") if claimed else Kit.BROWN
		var w := rect.size.x
		Kit.text_at(cell, "第%d天" % (i + 1), Rect2(0, 14, w, 52), 50, ink)
		var amount := ""
		if i == 6:
			Kit.art(cell, "chest_small", Rect2(w / 2 - 124, 66, 248, 160), "宝箱", Color("#F8BBD0"))
			amount = "%d+道具" % int(r.get("coins", 0))
			Kit.count_label(cell, amount, Rect2(w / 2 - 200, 230, 400, 60), 58)
		else:
			if r.has("coins"):
				Kit.art(cell, "coin_small", Rect2(w / 2 - 56, 64, 112, 109), "金", Color("#F5B82E"))
				amount = str(int(r.coins))
			else:
				var k: String = r.boosters.keys()[0]
				Kit.art(cell, icons.get(k, "icon_shuffle"), Rect2(w / 2 - 70, 70, 140, 96), "道具", Color("#C8E6C9"))
				amount = "×%d" % int(r.boosters[k])
			# Kept clear of the cell's rounded bottom edge (UI audit 2026-11-10).
			Kit.count_label(cell, amount, Rect2(0, 174, w, 56), 52)
		if claimed:
			Kit.art(cell, "check_stamp", Rect2(w / 2 + 34, 135, 72, 71), "✔", Color("#7CC84A"))
	if today >= 0:
		_ad_pill_at(box, "看广告 双倍领取", "checkin_double", Rect2(Vector2(141, 1383) - o, Vector2(793, 176)), func():
			app.profile.claim_checkin(app.now(), true)
			app.sound.play("win")
			close(info)
			app.toast("签到奖励已翻倍领取"))
		_pill_at(box, "领取", "pink", Rect2(Vector2(141, 1572) - o, Vector2(793, 177)), func():
			app.profile.claim_checkin(app.now())
			app.save()
			app.sound.play("match")
			close(info)
			app.toast("签到成功"))
	else:
		Kit.text_at(box, "今天已签到,明天再来哦", Rect2(Vector2(141, 1400) - o, Vector2(793, 90)), 56, Kit.BROWN)
	Kit.finish_popup(info, 77.0)

func star_chest() -> void:
	var p: Vector2i = app.profile.chest_progress()
	if not app.profile.can_open_chest():
		app.toast("再收集 %d 颗星星就能开启宝箱" % (p.y - p.x))
		return
	var r: Dictionary = app.profile.open_chest(randi() % 3)
	app.save()
	reward(r)

## The three-star chest of one level (opened from its stars on the map).
func perfect_chest(index: int, claimed := Callable()) -> void:
	var r: Dictionary = app.profile.claim_perfect_chest(index + 1, app.difficulty(index), [randi() % 3, randi() % 3])
	if r.is_empty():
		return
	app.save()
	if claimed.is_valid():
		claimed.call()
	reward(r, Callable(), "三星宝箱")

## "Congratulations" (mockup M7_A): open chest in a glow, one card per
## reward, ad doubling and claim. Full screen, no panel.
func reward(r: Dictionary, then := Callable(), title := "恭喜获得") -> void:
	app.sound.play("win")
	var root := Control.new()
	root.size = Vector2(1080, 1920)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	app.popup_layer.add_child(root)
	open.append(root)
	var info := {"root": root}
	var dim := ColorRect.new()
	dim.color = Color(0.133, 0.078, 0.094, 0.72)
	dim.position = Kit.screen_rect().position
	dim.size = Kit.screen_rect().size
	root.add_child(dim)
	var glow := Kit.art(root, "glow_rays", Rect2(130, 280, 820, 820))
	glow.pivot_offset = glow.size / 2
	glow.modulate.a = 0.9
	glow.create_tween().set_loops().tween_property(glow, "rotation", TAU, 12.0).from(0.0)
	var chest := Kit.art(root, "chest_big_open", Rect2(287, 410, 485, 524), "宝箱", Color("#FFE7A8"))
	chest.pivot_offset = chest.size / 2
	chest.scale = Vector2(0.3, 0.3)
	chest.create_tween().tween_property(chest, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Kit.art(root, "popup_ribbon", Rect2(100, 125, 877, 295))
	var t := Kit.text_at(root, title, Rect2(262, 168, 571, 140), 120, Kit.CREAM, Kit.OUTLINE, 16)
	t.add_theme_color_override("font_shadow_color", Color(0.39, 0.1, 0.03, 0.68))
	t.add_theme_constant_override("shadow_offset_y", 6)
	var items: Array = []
	if int(r.get("coins", 0)) > 0:
		items.append(["coin_pile_small", "+%d" % int(r.coins), Rect2(53, 24, 200, 162)])
	var icons := {"undo": "icon_undo", "move_out": "icon_move_out", "shuffle": "icon_shuffle", "extra_slot": "icon_extra_slot", "magnet": "icon_magnet"}
	for k in r.get("boosters", {}):
		items.append([icons.get(k, "icon_shuffle"), "×%d" % int(r.boosters[k]), Rect2(63, 26, 180, 156)])
	var cw := 306.0
	var gap := 14.0
	# Four or more cards shrink to fit the screen width.
	var fit := minf(1.0, 1040.0 / (items.size() * cw + (items.size() - 1) * gap))
	var x0 := (1080 - (items.size() * cw + (items.size() - 1) * gap) * fit) / 2
	for i in items.size():
		var it: Array = items[i]
		var card := Control.new()
		card.position = Vector2(x0 + i * (cw + gap) * fit - cw * (1 - fit) / 2, 967 - 352 * (1 - fit) / 2)
		card.size = Vector2(cw, 352)
		root.add_child(card)
		Kit.art(card, "reward_card", Rect2(Vector2.ZERO, card.size), "", Color("#FFF4DE"))
		Kit.art(card, it[0], it[2])
		# The card's face ends at y 277 (its lip below); the count sits on the face.
		Kit.count_label(card, it[1], Rect2(20, 192, cw - 40, 74), 66)
		card.pivot_offset = card.size / 2
		card.scale = Vector2.ZERO
		card.create_tween().tween_property(card, "scale", Vector2(fit, fit), 0.3).set_delay(0.25 + i * 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var finish := func():
		close(info)
		app.save()
		if then.is_valid():
			then.call()
	var left: int = app.profile.ads_left("chest_double", app.now())
	var ad := Kit.pill(_ad_label("看广告 双倍领取"), "green", Vector2(861, 203))
	ad.position = Vector2(108, 1381)
	root.add_child(ad)
	if _ad_icon() != "":
		Kit.pill_icon(ad, _ad_icon())
	if left <= 0:
		ad.disabled = true
		ad.modulate.a = 0.5
	ad.pressed.connect(func():
		app.sound.play("tap")
		app.ads.show_rewarded("chest_double", func(ok):
			if not ok:
				return
			app.profile.note_ad("chest_double", app.now())
			app.profile.add_coins(int(r.get("coins", 0)))
			for k in r.get("boosters", {}):
				app.profile.add_booster(k, int(r.boosters[k]))
			app.toast("奖励翻倍!")
			finish.call()))
	var claim := Kit.pill("领取", "pink", Vector2(861, 209))
	claim.position = Vector2(108, 1604)
	root.add_child(claim)
	claim.pressed.connect(func():
		app.sound.play("tap")
		finish.call())

# ---------------------------------------------------------------- debug

func debug_open(name: String) -> void:
	match name:
		"settings": settings()
		"privacy": privacy(func(): pass)
		"lives": lives()
		"checkin": checkin()
		"chest": reward({"coins": 100, "boosters": {"shuffle": 1, "move_out": 1}})
		"perfect": perfect_chest(0)
		"start": level_start(app.current_level_index())
		"shortage": booster_shortage("shuffle", func(): pass)
		"purchase": purchase("coins_3300")
		"purchase_done": purchase_done("coins_3300", app.profile.iap("coins_3300"))
		"starter": offer("starter")
		"limited": offer("limited")
		"win": win(0, 2, 30, func(): pass)
		"lose": lose(5, "托盘满了", "再想想顺序吧", true, func(): pass, func(_w): pass)
