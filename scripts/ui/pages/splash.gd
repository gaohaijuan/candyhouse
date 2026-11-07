extends Control
## Splash: logo, loading bar and the health notice, then privacy consent on
## first launch, then home.

const Kit = preload("res://scripts/ui/kit.gd")
const Common = preload("res://scripts/ui/pages/_common.gd")

var app

func setup(owner_app, _args: Dictionary) -> void:
	app = owner_app
	Common.background(self, "splash_bg")
	Common.logo(self, Vector2(540, 560), 900)
	var bar_w := 760.0
	var bg := Kit.picture("loading_bar_bg", Vector2(bar_w, 60), "", Color("#FFF1DC"))
	bg.position = Vector2((1080 - bar_w) / 2, 1500)
	add_child(bg)
	var fill := Kit.picture("loading_bar_fill", Vector2(bar_w - 24, 36), "", Color("#F0508A"))
	fill.position = bg.position + Vector2(12, 12)
	fill.size.x = 0
	add_child(fill)
	var notice := Kit.label("健康游戏忠告:抵制不良游戏,拒绝盗版游戏。注意自我保护,谨防受骗上当。\n适度游戏益脑,沉迷游戏伤身。合理安排时间,享受健康生活。", 30, Color.WHITE, Color("#9C3219"), 6)
	notice.position = Vector2(30, 1700)
	notice.size = Vector2(1020, 120)
	add_child(notice)
	var tw := create_tween()
	tw.tween_property(fill, "size:x", bar_w - 24, 1.2).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_loaded)

func _loaded() -> void:
	if app.profile.data.privacy_accepted:
		app.goto("home")
	else:
		app.popups.privacy(func(): app.goto("home"))
