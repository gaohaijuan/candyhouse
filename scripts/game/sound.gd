extends Node
## Background music and sound effects. One looping music player and a small
## pool of effect players so overlapping sounds do not cut each other off.

const MUSIC_DB := -9.0
const SFX := ["tap", "match", "win", "lose", "booster", "nope", "unlock"]

var music: AudioStreamPlayer
var pool: Array = []
var streams := {}
var enabled := true

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

func set_enabled(on: bool) -> void:
	enabled = on
	if on:
		if not music.playing:
			music.play()
	else:
		music.stop()
		for p in pool:
			p.stop()

func start_music() -> void:
	if enabled and music.stream and not music.playing:
		music.play()

## `pitch` lets combos climb; `db` adjusts loudness per use.
func play(name: String, pitch := 1.0, db := 0.0) -> void:
	if not enabled or not streams.has(name):
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
	if not enabled:
		return
	var tw := create_tween()
	tw.tween_property(music, "volume_db", MUSIC_DB - 12.0, 0.15)
	tw.tween_interval(seconds)
	tw.tween_property(music, "volume_db", MUSIC_DB, 0.6)
