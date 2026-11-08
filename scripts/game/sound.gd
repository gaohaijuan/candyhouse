extends Node
## Background music and sound effects. One looping music player and a small
## pool of effect players so overlapping sounds do not cut each other off.

const MUSIC_DB := -9.0
const SFX := ["tap", "match", "win", "lose", "booster", "nope", "unlock"]

var music: AudioStreamPlayer
var pool: Array = []
var streams := {}
var enabled := true      # effects
var music_on := true
var vibrate_on := true

func _ready() -> void:
	music = AudioStreamPlayer.new()
	music.volume_db = MUSIC_DB
	var bgm := load("res://assets/audio/bgm_game.wav") as AudioStreamWAV
	if bgm:
		# The WAV carries loop points; make sure looping is on even if import drops them.
		bgm.loop_mode = AudioStreamWAV.LOOP_FORWARD
		if bgm.loop_end <= 0:
			bgm.loop_end = int(bgm.get_length() * bgm.mix_rate)
		music.stream = bgm
	add_child(music)
	for name in SFX:
		var path := "res://assets/audio/sfx_%s.wav" % name
		if ResourceLoader.exists(path):
			streams[name] = load(path)
	for i in 6:
		var p := AudioStreamPlayer.new()
		pool.append(p)
		add_child(p)
	# Stop each player while it is still in the tree when the game quits;
	# a playback left running is reported as a leak at exit.
	for p in pool + [music]:
		var player: AudioStreamPlayer = p
		player.tree_exiting.connect(func():
			player.stop()
			player.stream = null)

## Legacy single switch (standalone game page): music and effects together.
func set_enabled(on: bool) -> void:
	set_music(on)
	set_effects(on)

func set_music(on: bool) -> void:
	music_on = on
	if on:
		start_music()
	else:
		music.stop()

func set_effects(on: bool) -> void:
	enabled = on
	if not on:
		for p in pool:
			p.stop()

func start_music() -> void:
	# Headless runs (tests, smoke checks) have no audio device; a looping
	# playback there is never released and shows up as a leak at exit.
	if DisplayServer.get_name() == "headless":
		return
	if silent:
		return
	if music_on and music.stream and not music.playing:
		music.play()

func vibrate(ms := 30) -> void:
	if vibrate_on:
		Input.vibrate_handheld(ms)

## `pitch` lets combos climb; `db` adjusts loudness per use.
## Debug screenshot runs (--capture) are silent: they end with --quit-after
## while sounds may still be releasing, which the engine reports as leaks.
static var silent := Array(OS.get_cmdline_user_args()).any(func(x): return String(x).begins_with("--capture"))

func play(name: String, pitch := 1.0, db := 0.0) -> void:
	if silent or not enabled or not streams.has(name):
		return
	var p: AudioStreamPlayer = null
	for q in pool:
		if not q.playing:
			p = q
			break
	if p == null:
		p = pool[0]
	p.stream = streams[name]
	p.pitch_scale = pitch
	p.volume_db = db
	p.play()

## Lowers the music briefly so a jingle stands out.
func duck(seconds: float) -> void:
	if not music_on:
		return
	var tw := create_tween()
	tw.tween_property(music, "volume_db", MUSIC_DB - 12.0, 0.15)
	tw.tween_interval(seconds)
	tw.tween_property(music, "volume_db", MUSIC_DB, 0.6)

## Closing the window: stop all sound at once.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		music.stop()
		for p in pool:
			p.stop()
