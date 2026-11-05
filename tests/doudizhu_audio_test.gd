extends SceneTree
## Run only with --headless (Godot's Dummy audio driver). No speakers,
## recording, microphones, preferences or desktop input are used.
const VoiceScript = preload("res://scripts/doudizhu/audio/voice.gd")
const ModeScript = preload("res://scripts/doudizhu/mode.gd")

var checks = 0
var failures: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("DDZ AUDIO FAIL: ", message)

func run() -> void:
	if DisplayServer.get_name() != "headless":
		printerr("DDZ audio tests require --headless; no playback was started.")
		quit(1)
		return
	# Belt and braces: even a caller explicitly overriding the headless audio
	# driver cannot emit these fixtures to a physical output device.
	AudioServer.set_bus_mute(0, true)
	create_timer(30).timeout.connect(func(): printerr("DDZ audio watchdog"); quit(1))
	var voice = VoiceScript.new()
	root.add_child(voice)
	_test_assets(voice)
	_test_mapping(voice)
	_test_queue(voice)
	voice.stop_all()
	voice.queue_free()
	await process_frame
	await _test_result_panel()
	print("DDZ_AUDIO_RESULT: %d failures; %d checks" % [failures.size(), checks])
	quit(0 if failures.is_empty() else 1)

func _test_assets(voice) -> void:
	var expected: Array[String] = []
	for value in range(3, 18): expected.append("single_%d" % value)
	for value in range(3, 16):
		expected.append("pair_%d" % value)
		expected.append("triple_%d" % value)
	for kind in ["triple_single", "triple_pair", "straight", "pair_chain", "airplane", "airplane_single", "airplane_pair", "four_two_single", "four_two_pair", "bomb", "rocket"]:
		expected.append(kind)
	for value in range(4): expected.append("bid_%d" % value)
	for kind in ["pass", "redeal", "spring", "counter_spring"]: expected.append(kind)
	check(expected.size() == 60 and voice.clips.size() == 60, "all 60 distinct voice keys are loaded")
	for key in expected:
		check(voice.clips.has(key), "voice exists: " + key)
		if not voice.clips.has(key): continue
		var clip = voice.clips[key]
		check(clip is AudioStreamWAV, "offline WAV resource: " + key)
		var duration = float(clip.get_length())
		check(is_finite(duration) and duration >= 0.15 and duration <= 8.0, "voice length is 0.15..8 seconds: %s (%.3fs)" % [key, duration])
		if clip is AudioStreamWAV: check(not clip.data.is_empty(), "decoded voice has audio data: " + key)

func _test_mapping(voice) -> void:
	for value in range(3, 18):
		check(voice.clip_keys(_view(1, 1, _play("single", value))) == ["single_%d" % value], "single announces its rank %d" % value)
	for value in range(3, 16):
		for kind in ["pair", "triple"]:
			check(voice.clip_keys(_view(1, 1, _play(kind, value))) == ["%s_%d" % [kind, value]], "%s announces its rank %d" % [kind, value])
	for kind in ["triple_single", "triple_pair", "straight", "pair_chain", "airplane", "airplane_single", "airplane_pair", "four_two_single", "four_two_pair", "bomb", "rocket"]:
		check(voice.clip_keys(_view(1, 1, _play(kind, 9))) == [kind], "composite combination announces shape: " + kind)
	for value in range(4):
		check(voice.clip_keys(_view(1, 1, {"type": "bid", "seat": 0, "value": value})) == ["bid_%d" % value], "bid voice %d" % value)
	for kind in ["pass", "redeal"]:
		check(voice.clip_keys(_view(1, 1, {"type": kind, "seat": 0})) == [kind], "action voice: " + kind)
	check(voice.clip_keys(_view(1, 1, _play("rocket", 17), "finished", "spring")) == ["rocket", "spring"], "last play precedes spring announcement")
	check(voice.clip_keys(_view(1, 1, _play("single", 14), "finished", "counter_spring")) == ["single_14", "counter_spring"], "last rank precedes counter spring announcement")
	check(voice.clip_keys(_view(1, 1, _play("pair", 10), "finished")) == ["pair_10"], "ordinary victory does not invent spring")
	check(voice.clip_keys(_view(1, 1, _play("single", 3), "playing", "spring")) == ["single_3"], "spring is voiced only after the round finishes")
	check(voice.clip_keys(_view(1, 1, {"type": "deal", "seat": 0})).is_empty(), "silent opening does not invent a spoken action")
	check(voice.clip_keys({}).is_empty(), "empty view has no announcement")

func _test_queue(voice) -> void:
	# Predictable silent waveforms test timing and queue ownership independently
	# of the recordings' exact duration or a real-time audio callback schedule.
	var first = _silence(2.0)
	var second = _silence(1.0)
	var rocket = _silence(1.25)
	var spring = _silence(0.75)
	voice.clips = {"single_3": first, "pair_4": second, "rocket": rocket, "spring": spring}
	voice.last_key = ""
	var opening = _view(5, 7, _play("single", 3))
	var hold = voice.announce(opening, false)
	check(absf(hold - 2.3) < 0.04, "first hold includes full clip plus reading gap")
	check(voice.playing and voice.stream == first and voice.queue.is_empty(), "first clip begins once and leaves no duplicate in queue")
	check(voice.announce(opening, false) == 0.0 and voice.queue.is_empty() and voice.stream == first, "same round/deal/revision never repeats")
	var remaining = maxf(0.0, first.get_length() - voice.get_playback_position())
	hold = voice.announce(_view(6, 7, _play("pair", 4)), false)
	check(voice.stream == first and voice.queue == [second], "same revision in a new round queues a new announcement")
	check(absf(hold - (remaining + second.get_length() + 0.3)) < 0.08, "hold includes current remainder and queued clip")
	remaining = maxf(0.0, first.get_length() - voice.get_playback_position())
	hold = voice.announce(_view(6, 8, _play("rocket", 17), "finished", "spring"), false)
	check(voice.stream == first and voice.queue == [second, rocket, spring], "new actions and final spring preserve chronological queue order")
	check(absf(hold - (remaining + second.get_length() + rocket.get_length() + spring.get_length() + 0.3)) < 0.08, "hold accounts for all pending voices, including spring")
	# Deliver the same signal as an audio completion, without waiting or letting
	# an actual output device drive these queue assertions.
	for clip in [second, rocket, spring]:
		voice.stop()
		voice.finished.emit()
		check(voice.playing and voice.stream == clip, "finished signal advances to the next queued clip")
	voice.stop()
	voice.finished.emit()
	check(not voice.playing and voice.queue.is_empty(), "empty queue does not restart a completed clip")
	voice.announce(_view(7, 1, _play("single", 3)), false)
	voice.announce(_view(7, 2, _play("pair", 4)), false)
	var muted_view = _view(7, 3, _play("rocket", 17))
	check(voice.announce(muted_view, true) == 0.0 and not voice.playing and voice.queue.is_empty(), "mute stops current playback and clears pending voices")
	check(voice.announce(muted_view, false) == 0.0 and not voice.playing, "unmuting does not replay the action skipped while muted")
	voice.announce(_view(7, 3, _play("single", 3), "playing", "", 2), false)
	check(voice.playing, "different deal identity does not suppress a fresh action")
	voice.stop_all()
	check(not voice.playing and voice.queue.is_empty(), "explicit shutdown clears all audio work")

func _test_result_panel() -> void:
	var mode = ModeScript.new()
	mode.qa_mode = true
	mode.muted = false
	root.add_child(mode)
	mode.session.set_process(false)
	# Only in-memory fixture state is replaced; no Mahjong objects or saves are
	# created. The actual session, table, result modal and voice bridge run.
	var engine = mode.session.engine
	engine.state.phase = "playing"
	engine.state.turn = 0
	engine.state.landlord = 0
	engine.state.highest_bid = 1
	engine.state.hands = [[0], [4], [8]]
	engine.state.target = {}
	engine.state.target_seat = -1
	engine.state.play_counts = [0, 0, 0]
	var previous = _silence(3.0)
	var last_card = _silence(1.0)
	var spring = _silence(0.75)
	mode.voice.stop_all()
	mode.voice.clips = {"single_4": previous, "single_3": last_card, "spring": spring}
	mode.voice.announce(_view(mode.session.round_id, 999, _play("single", 4)), false)
	check(mode.voice.playing and mode.voice.stream == previous, "previous spoken action is active before the winning play")
	var accepted = mode.session.submit({"type": "play", "cards": [0], "revision": engine.state.revision})
	check(accepted and mode.table._modal_kind == "result" and mode.session.paused, "winning play opens the real result panel")
	check(mode.voice.playing and not mode.voice.stream_paused and mode.voice.stream == previous, "result modal does not pause or replace the previous announcement")
	check(mode.voice.queue == [last_card, spring], "last card and spring wait behind the previous voice")
	var expected_hold = maxf(0.0, previous.get_length() - mode.voice.get_playback_position()) + last_card.get_length() + spring.get_length() + 0.3
	check(absf(mode.session.delay - expected_hold) < 0.08, "mode reserves the entire final announcement duration")
	mode.pause_on_background()
	check(mode.voice.stream_paused, "actual app backgrounding still pauses result audio")
	mode._next_round()
	check(mode.voice.queue.is_empty() and not mode.voice.playing and not mode.voice.stream_paused, "next round clears all old result audio")
	mode.session.shutdown()
	mode.voice.stop_all()
	mode.queue_free()
	await process_frame

func _play(kind: String, rank_value: int) -> Dictionary:
	return {"type": "play", "seat": 0, "combo": {"kind": kind, "main": rank_value}}

func _view(round_id: int, revision: int, event: Dictionary, phase: String = "playing", spring: String = "", deal: int = 1) -> Dictionary:
	return {"round_id": round_id, "deal": deal, "revision": revision, "event": event, "phase": phase, "result": {"spring": spring}}

func _silence(seconds: float) -> AudioStreamWAV:
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 16000
	var data = PackedByteArray()
	data.resize(int(seconds * 32000))
	stream.data = data
	return stream
