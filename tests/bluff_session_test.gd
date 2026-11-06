extends SceneTree
const Session = preload("res://scripts/bluff/session.gd")
const AI = preload("res://scripts/bluff/core/ai.gd")
var checks = 0
var failures: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("BLUFF SESSION FAIL: ", message)

func submit(session, action: Dictionary) -> bool:
	action.revision = session.engine.state.revision
	action.round_id = session.round_id
	return session.submit(action)

func run() -> void:
	create_timer(90).timeout.connect(func(): printerr("Bluff session watchdog"); quit(1))
	var session = Session.new(); root.add_child(session); session.set_process(false)
	session.start({}, 610)
	check(session.current_view().hand.size() == 18 and session.round_id == 1, "default session is human plus two bots")
	var before = session.engine.state.duplicate(true)
	session._process(500)
	check(session.engine.state == before, "guessing waits indefinitely for human")
	session.paused = true
	check(not submit(session, {"type": "rps", "gesture": 0}), "paused submissions rejected")
	session.paused = false
	check(not session.submit({"type": "rps", "gesture": 0, "revision": 0}), "round identity required")
	var stale = {"type": "rps", "gesture": 0, "revision": 0, "round_id": session.round_id}
	session.start({}, 611)
	check(not session.submit(stale), "new round rejects old callback even at matching revision")
	var rng = RandomNumberGenerator.new(); rng.seed = 616
	for count in range(3, 7):
		session.start({"players": count, "challenge": "any" if count % 2 else "turn"}, 620 + count)
		var moves = 0
		while session.engine.state.phase != "finished" and moves < 2500:
			var state = session.engine.state
			if state.phase == "rps":
				check(submit(session, {"type": "rps", "gesture": rng.randi_range(0, 2)}), "human RPS through boundary")
			elif state.phase == "review":
				var revision = state.revision
				session._process(100)
				check(state.revision == revision, "bots cannot skip opening/dead-pile review")
				check(submit(session, {"type": "continue"}), "manual review acknowledgment")
			elif state.turn == 0:
				if state.config.challenge == "turn":
					var revision = state.revision
					session._process(100)
					check(state.revision == revision, "human has no forced action timer")
				check(submit(session, AI.choose(session.current_view(), rng)), "human cropped-view action")
			else:
				var revision = state.revision
				session.delay = 2.8; session._process(1.0)
				check(state.revision == revision, "robot respects minimum presentation time")
				session.paused = true; session._process(50)
				check(state.revision == revision and session.delay > 0, "pause freezes robot countdown")
				session.paused = false; session._process(10)
				check(state.revision == revision + 1, "one bot action per presentation step")
			moves += 1
		check(session.engine.state.phase == "finished", "session completes %d-player game" % count)
		check(session.current_view().winner >= 0, "session publishes winner")
	session.start({"challenge": "any"}, 830)
	# Construct an impossible public claim on the human's turn. The bot's
	# certainty is based only on the six possible rank/wild cards in one pack.
	session.engine.state.phase = "playing"; session.engine.state.turn = 0
	session.engine.state.last = {"seat": 2, "cards": range(7), "count": 7, "rank": 3}
	session.engine.state.rank = 3
	session.engine.state.pile = range(7)
	for hand in session.engine.state.hands:
		for id in range(7): hand.erase(id)
	session._process(10)
	check(session.engine.state.phase == "review" and session.engine.state.event.caller == 1, "free-call bots may interrupt on human turn using public impossibility")
	session.shutdown()
	before = session.engine.state.duplicate(true); session._process(200)
	check(not session.active and before == session.engine.state, "shutdown stops all future bot actions")
	session.free()
	await app_isolation()
	print("BLUFF_SESSION_RESULT: %d failures; %d checks" % [failures.size(), checks])
	quit(0 if failures.is_empty() else 1)

func app_isolation() -> void:
	var directory = "user://qa-bluff-%d/" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var app = load("res://scenes/main.tscn").instantiate()
	app.qa_mode = true; app.preferences_path = directory + "preferences.json"
	root.add_child(app)
	app.session.storage_root = directory
	app.session.start_match({"jiang": "258", "chi": true, "rounds": 4, "field_rules": false})
	app.session.paused = true
	var saved = FileAccess.get_file_as_bytes(directory + "current_match.json")
	var before = JSON.stringify(app.session.engine.snapshot())
	app._open_bluff(); await process_frame
	check(app.current_screen == "bluff" and not app.table.visible and app.session.paused, "mode entry pauses Mahjong")
	check(app.bluff.table.view.is_empty(), "entry waits at seat configuration")
	app.bluff.table.settings.players = 6
	app.bluff.table.settings.challenge = "any"
	app.bluff.table.settings.theme = "guofeng"
	app.bluff.table.settings.voice = "female"
	app.bluff.table.settings_changed.emit(app.bluff.table.settings)
	check(not FileAccess.file_exists(app.preferences_path), "QA mode never writes preferences")
	app.qa_mode = false # Isolated path only; no read/write of real preferences.
	app.bluff.table.settings_changed.emit(app.bluff.table.settings)
	var prefs = JSON.parse_string(FileAccess.get_file_as_string(app.preferences_path))
	check(prefs.bluff_settings.players == 6 and prefs.bluff_settings.theme == "guofeng" and prefs.bluff_settings.voice == "female", "independent settings persist")
	app.bluff.table.start_requested.emit({"players": 6, "challenge": "any"})
	check(app.bluff.session.current_view().hand_counts.size() == 6, "configuration reaches engine")
	app.bluff.pause_on_background(); app.bluff.pause_on_background()
	check(app.bluff.session.paused and (not app.bluff.voice.playing or app.bluff.voice.stream_paused), "background pause is idempotent and pauses active speech")
	check(FileAccess.get_file_as_bytes(directory + "current_match.json") == saved and JSON.stringify(app.session.engine.snapshot()) == before, "bluff leaves Mahjong state and save bytes untouched")
	app.bluff.table.exit_requested.emit(); await process_frame
	check(app.current_screen == "lobby" and app.session.resume_match(), "Mahjong save resumes after leaving bluff")
	app.session.paused = true; app.free(); await process_frame
	app = load("res://scenes/main.tscn").instantiate()
	app.qa_mode = false; app.preferences_path = directory + "preferences.json"
	root.add_child(app)
	check(app.bluff_settings.players == 6 and app.bluff_settings.challenge == "any" and app.bluff_settings.voice == "female", "new app restores settings")
	app._open_bluff()
	check(app.bluff.table.settings.theme == "guofeng" and app.bluff.table.view.is_empty(), "restoring preferences never restores a discarded round")
	app.free(); await process_frame
	for filename in ["preferences.json", "current_match.json", "current_match.json.bak", "current_match.json.tmp"]:
		var path = directory + filename
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
