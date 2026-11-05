extends SceneTree
const Session = preload("res://scripts/doudizhu/session.gd")
const AI = preload("res://scripts/doudizhu/core/ai.gd")
var failures: Array = []
var checks = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("DDZ SESSION FAIL: ", message)

func run() -> void:
	create_timer(120).timeout.connect(func(): printerr("DDZ session watchdog"); quit(1))
	var session = Session.new()
	root.add_child(session)
	session.start(51050, 0)
	var before = session.current_view()
	check(before.hand.size() == 17 and before.round_id == 1, "session publishes a 17-card private opening")
	session.hold_presentation(3.0)
	session._process(0.5)
	check(session.delay >= 2.5, "speech keeps a readable beat")
	session._process(30.0)
	check(session.engine.state.revision == before.revision, "human has no action timeout")
	session.paused = true
	check(not session.submit({"type":"bid", "value":3, "revision":before.revision}), "paused input cannot advance")
	session.paused = false
	check(not session.submit({"type":"bid", "value":3}), "session requires an explicit revision")
	check(session.submit({"type":"bid", "value":3, "revision":before.revision}), "human can become landlord")
	check(not session.submit({"type":"bid", "value":3, "revision":before.revision}), "double submission is rejected")
	var hinted: Array = []
	session.hint_ready.connect(func(cards): hinted.append(cards))
	session.request_hint()
	# A previous round's asynchronous result cannot select or play the new hand.
	session.start(51051, 0)
	for frame in range(4): await process_frame
	check(hinted.is_empty() and session.current_view().round_id == 2, "new round invalidates in-flight hint")
	for game in range(2):
		var steps = 0
		while session.engine.state.phase != "finished" and steps < 2200:
			steps += 1
			session.delay = 0.0
			if session.engine.state.turn == 0:
				check(session.submit(AI.choose(session.current_view())), "human seat can submit a legal strategy action")
			await process_frame
		check(session.engine.state.phase == "finished", "two worker bots complete round %d" % game)
		if session.engine.state.phase != "finished": break
		var result = session.current_view().result
		check(result.scores.reduce(func(total, item): return total + item, 0) == 0, "round scores sum to zero")
		check(session.next_round(), "finished game can continue without match limit")
		check(session.current_view().result.is_empty() and session.current_view().multiplier == 1, "continuation clears scores and multipliers")
	session.shutdown()
	check(not session.active and session.worker == null, "shutdown joins the owned worker")
	session.free()
	await _check_app_isolation()
	print("DDZ_SESSION_RESULT: %d failures; %d checks" % [failures.size(), checks])
	quit(0 if failures.is_empty() else 1)

func _check_app_isolation() -> void:
	var app = load("res://scenes/main.tscn").instantiate()
	app.qa_mode = true
	root.add_child(app)
	var qa_path = "user://qa-ddz-isolation-%d/" % Time.get_ticks_usec()
	app.session.storage_root = qa_path
	app.session.start_match({"jiang":"258", "chi":true, "ai":"efficiency", "rounds":4, "field_rules":false})
	app.session.paused = true
	var saved = FileAccess.get_file_as_bytes(qa_path + "current_match.json")
	var old_state = JSON.stringify(app.session.engine.snapshot())
	app._open_doudizhu()
	await process_frame
	check(app.current_screen == "doudizhu" and not app.table.visible, "new mode has its own table")
	check(app.session.paused, "Mahjong simulation is paused outside its mode")
	var mode = app.doudizhu
	mode.session.submit({"type":"bid", "value":3, "revision":mode.session.current_view().revision})
	mode.pause_on_background()
	mode.pause_on_background()
	check(mode.session.paused, "repeated background notifications stay paused")
	check(FileAccess.get_file_as_bytes(qa_path + "current_match.json") == saved, "Dou Dizhu does not overwrite Mahjong save")
	check(JSON.stringify(app.session.engine.snapshot()) == old_state, "Dou Dizhu does not mutate Mahjong authority")
	mode._leave()
	await process_frame
	check(app.current_screen == "lobby", "leaving returns to mode selection")
	check(app.session.resume_match(), "Mahjong save still resumes after switching mode")
	app.session.paused = true
	app.free()
	for file in ["current_match.json", "current_match.json.bak", "current_match.json.tmp"]:
		var path = qa_path + file
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(qa_path))
