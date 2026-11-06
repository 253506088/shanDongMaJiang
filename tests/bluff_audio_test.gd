extends SceneTree
const Voice = preload("res://scripts/bluff/voice.gd")
var checks = 0
var failures: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("BLUFF AUDIO FAIL: ", message)

func run() -> void:
	Engine.max_fps = 60
	var voice = Voice.new(); root.add_child(voice)
	AudioServer.set_bus_mute(0, true)
	for profile in ["male", "female"]:
		voice.set_profile(profile)
		var keys: Array = ["pass", "challenge", "truth", "lie", "dead", "win"]
		for count in range(1, 109): keys.append("count_%d" % count)
		for rank in range(3, 16): keys.append("rank_%d" % rank)
		for key in keys:
			var clip = voice.clip(key)
			check(clip != null and clip.get_length() > 0.15 and clip.get_length() < 8, "load nonempty " + profile + "/" + key)
	var view = {"round_id": 1, "revision": 1, "phase": "playing", "event": {"type": "play", "rank": 8, "count": 37}}
	check(voice.keys(view) == ["count_37", "rank_8"], "speak declared count and rank, never actual cards")
	check(voice.announce(view, false) > 1 and voice.playing and voice.queue.size() == 1, "declaration queues count then rank")
	await process_frame
	await process_frame
	check(voice.announce(view, false) == 0 and voice.queue.size() == 1, "same revision never repeats speech")
	voice.stream_paused = true
	check(voice.stream_paused, "active declaration pauses with the game")
	voice.stream_paused = false
	voice.set_profile("male")
	check(not voice.playing and voice.queue.is_empty() and voice.announce(view, false) == 0, "profile switch clears queue without replaying")
	view.revision += 1; view.event = {"type": "challenge", "truthful": false}
	check(voice.keys(view) == ["challenge", "lie"], "call and caught result phrases")
	voice.announce(view, false)
	await process_frame
	await process_frame
	view.revision += 1
	voice.announce(view, true)
	check(not voice.playing and voice.queue.is_empty(), "mute stops and clears speech")
	view.phase = "finished"; view.finish_reason = "accepted"
	check(voice.keys(view) == ["win"], "accepted final hand does not repeat preceding declaration")
	voice.stop_all(); voice.free()
	# stop() is handed to the mixer asynchronously. Let its real audio thread
	# retire aborted playbacks before quitting this sub-second test process.
	await create_timer(0.15).timeout
	print("BLUFF_AUDIO_RESULT: %d failures; %d checks" % [failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
