extends Control
## Splash: logo, loading bar and the health notice, then privacy consent on
## first launch, then home.

const Kit = preload("res://scripts/ui/kit.gd")
const Common = preload("res://scripts/ui/pages/_common.gd")
const Lang = preload("res://scripts/core/lang.gd")

var app

func setup(owner_app, _args: Dictionary) -> void:
	app = owner_app
	Common.background(self, "splash_bg")
	# Rects from mockup M1_A.
	Kit.art(self, "logo", Rect2(91, 199, 901, 563))
	if not Kit.tex("logo"):
		Common.logo(self, Vector2(540, 480), 900)
	Kit.nine(self, "loading_bar_bg", Rect2(34, 1594, 1012, 96), [41, 11, 41, 11], Color("#FFF1DC"), 96.0 / 57.0)
	var fill := Kit.nine(self, "loading_bar_fill", Rect2(56, 1615, 968, 54), [38, 10, 38, 10], Color("#F0508A"), 54.0 / 50.0)
	var full_w := fill.size.x
	fill.size.x = 76.0
	# The health notice is a mainland China requirement: Chinese only.
	if Lang.is_zh():
		var notice := Kit.label("健康游戏忠告:抵制不良游戏,拒绝盗版游戏。注意自我保护,谨防受骗上当。\n适度游戏益脑,沉迷游戏伤身。合理安排时间,享受健康生活。", 30, Color("#F9E8DE"), Color("#8E2425"), 6)
		notice.position = Vector2(30, 1772)
		notice.size = Vector2(1020, 110)
		add_child(notice)
	var tw := create_tween()
	tw.tween_property(fill, "size:x", full_w, 1.2).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_loaded)

func _loaded() -> void:
	if app.profile.data.privacy_accepted:
		app.goto("home")
	else:
		app.popups.privacy(func(): app.goto("home"))
