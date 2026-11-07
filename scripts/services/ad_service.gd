extends Node
## Ads behind one interface. This is the mock used until a real ad SDK is
## wired in: it shows a short "ad playing" overlay, then reports the result.
## A real implementation keeps the same two calls and the same callbacks.

signal ad_finished(placement: String, rewarded: bool)

const MOCK_SECONDS := 2.0

var overlay_parent: Control
var fail_next := false          # testing: make the next ad fail to load
var busy := false

## Rewarded video. `done` is called with true only when the reward is earned.
func show_rewarded(placement: String, done: Callable) -> void:
	if busy:
		return
	if fail_next:
		fail_next = false
		_toast("广告加载失败,请稍后再试")
		done.call(false)
		return
	_play(placement, done, true)

## Interstitial between levels; `done` always runs afterwards.
func show_interstitial(done: Callable) -> void:
	if busy:
		done.call()
		return
	_play("interstitial", func(_ok): done.call(), false)

func _play(placement: String, done: Callable, rewarded: bool) -> void:
	busy = true
	var o := Control.new()
	o.size = Vector2(1080, 1920)
	o.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.06, 0.1, 0.94)
	bg.size = o.size
	o.add_child(bg)
	var l := Label.new()
	l.text = "广告播放中…\n(测试版模拟广告)"
	l.size = Vector2(1080, 300)
	l.position = Vector2(0, 800)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 56)
	l.add_theme_color_override("font_color", Color.WHITE)
	o.add_child(l)
	overlay_parent.add_child(o)
	get_tree().create_timer(MOCK_SECONDS).timeout.connect(func():
		o.queue_free()
		busy = false
		ad_finished.emit(placement, rewarded)
		done.call(true))

func _toast(text: String) -> void:
	if overlay_parent and overlay_parent.has_method("toast"):
		overlay_parent.toast(text)
