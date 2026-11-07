extends Control
## Home: wallet, logo, current level, the big play button and four entries.

const Kit = preload("res://scripts/ui/kit.gd")
const Common = preload("res://scripts/ui/pages/_common.gd")
const CurrencyBar = preload("res://scripts/ui/currency_bar.gd")

var app
var chest_label: Label
var checkin_dot: Control

func setup(owner_app, _args: Dictionary) -> void:
	app = owner_app
	Common.background(self, "home_bg")
	var bar := Control.new()
	bar.set_script(CurrencyBar)
	add_child(bar)
	bar.setup(app)
	var gear := Kit.round_button("button_settings", 130, "设")
	gear.position = Vector2(920, 22)
	gear.pressed.connect(func(): app.popups.settings())
	add_child(gear)
	Common.logo(self, Vector2(540, 470), 860)
	var plaque := Kit.picture("level_plaque", Vector2(480, 120), "", Color("#FFF4DE"))
	plaque.position = Vector2(300, 760)
	add_child(plaque)
	var lv := Kit.label("第 %d 关" % (app.current_level_index() + 1), 60, Kit.BROWN)
	lv.position = plaque.position
	lv.size = plaque.size
	add_child(lv)
	var play := Kit.pill("开始游戏", "pink", Vector2(820, 200))
	play.position = Vector2(130, 1300)
	play.pressed.connect(func(): app.popups.level_start(app.current_level_index()))
	add_child(play)
	var entries := [
		["home_icon_shop", "商店", "店", func(): app.goto("shop")],
		["home_icon_checkin", "签到", "签", func(): app.popups.checkin()],
		["home_icon_map", "地图", "图", func(): app.goto("map")],
		["home_icon_chest", "宝箱", "箱", func(): app.popups.star_chest()],
	]
	for i in entries.size():
		var e: Array = entries[i]
		var b := Kit.round_button(e[0], 210, e[2], Color("#F06292") if i % 2 == 0 else Color("#7CC84A"))
		b.position = Vector2(40 + i * 255, 1560)
		b.pressed.connect(e[3])
		add_child(b)
		var cap := Kit.label(e[1], 52, Kit.BROWN, Kit.CREAM, 8)
		cap.position = b.position + Vector2(-20, 215)
		cap.size = Vector2(250, 70)
		add_child(cap)
		if e[1] == "签到":
			checkin_dot = Kit.picture("dot_red", Vector2(44, 44), "", Color("#E5484D"))
			checkin_dot.position = b.position + Vector2(160, 6)
			add_child(checkin_dot)
		if e[1] == "宝箱":
			chest_label = Kit.label("", 30, Color.WHITE, Color("#2E7D32"), 6)
			chest_label.position = b.position + Vector2(20, 150)
			chest_label.size = Vector2(170, 44)
			add_child(chest_label)
	if app.profile.iap_available("starter", app.now()):
		var gift := Kit.round_button("starter_gift", 170, "礼包", Color("#F5B82E"))
		gift.position = Vector2(20, 900)
		gift.pressed.connect(func(): app.goto("shop"))
		add_child(gift)
		var tag := Kit.label("新手礼包", 34, Kit.CREAM, Kit.OUTLINE, 8)
		tag.position = gift.position + Vector2(-20, 170)
		tag.size = Vector2(210, 50)
		add_child(tag)
	app.wallet_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	if not is_instance_valid(chest_label):
		return
	var p: Vector2i = app.profile.chest_progress()
	chest_label.text = "%d/%d" % [mini(p.x, p.y), p.y]
	checkin_dot.visible = app.profile.checkin_today(app.now()) >= 0
