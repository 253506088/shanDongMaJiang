extends SceneTree
## Run with --path build/windows --main-pack <absolute EXE> --script <this file>.
## All game loads then resolve against the exported package, never source files.
var failures: Array = []
var checks = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("BLUFF PACKAGE FAIL: ", message)

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var args = OS.get_cmdline_user_args(); var index = args.find("--capture-dir")
	if index < 0: return
	for frame in range(5): await process_frame
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(args[index + 1].path_join(name + ".png")) == OK, "actual package screenshot " + name)

func run() -> void:
	check(ProjectSettings.get_setting("application/config/version") == "0.8.1", "package version 0.8.1")
	check(not FileAccess.file_exists("res://tests/bluff_package_test.gd") and not FileAccess.file_exists("res://tools/generate_bluff_audio.py"), "tests and generation tools excluded")
	for file in ["bluff-voice-manifest.json", "bluff-voice-NOTICE.txt", "doudizhu-Apache-2.0.txt", "doudizhu-cards-source.svg.txt", "doudizhu-guofeng-manifest.json"]:
		check(FileAccess.file_exists("res://assets/licenses/" + file), "license/provenance ships: " + file)
	for theme in ["cards", "guofeng"]:
		for id in range(54): check(ResourceLoader.exists("res://assets/doudizhu/%s/%02d.png" % [theme, id]), "shared face ships")
		check(ResourceLoader.exists("res://assets/doudizhu/%s/back.png" % theme), "back ships")
	var voice = load("res://scripts/bluff/voice.gd").new(); root.add_child(voice)
	for profile in ["male", "female"]:
		voice.set_profile(profile)
		for count in range(1, 109): check(voice.clip("count_%d" % count) != null, "all quantities ship")
		for rank in range(3, 16): check(voice.clip("rank_%d" % rank) != null, "all declared ranks ship")
		for key in ["pass", "challenge", "truth", "lie", "dead", "win"]: check(voice.clip(key) != null, "event speech ships")
	voice.free()
	var ai = load("res://scripts/bluff/core/ai.gd")
	var rng = RandomNumberGenerator.new(); rng.seed = 29117
	for count in range(3, 7):
		var game = load("res://scripts/bluff/core/engine.gd").new(); game.start(8390 + count, {"players": count})
		var steps = 0
		while game.state.phase != "finished" and steps < 2500:
			var action = {"revision": game.state.revision}
			var seat = 0
			if game.state.phase == "rps": action.merge({"type": "rps", "gesture": rng.randi_range(0, 2)})
			elif game.state.phase == "review": action["type"] = "continue"
			else:
				seat = game.state.turn; action = ai.choose(game.view(seat), rng)
			check(game.act(seat, action), "exported engine accepts complete match actions")
			steps += 1
		check(game.state.phase == "finished", "exported %d-player match finishes" % count)
		var cleared = 0
		for viewer in range(count): cleared += int(game.view(viewer).recorder.total)
		check(cleared == game.state.dead.size(), "exported recorder accounts for each seat's own cleared cards once")
	var app = load("res://scenes/main.tscn").instantiate(); app.qa_mode = true; root.add_child(app)
	app._open_bluff(); await process_frame
	check(app.current_screen == "bluff" and app.session.paused and not app.table.visible, "packaged lobby reaches isolated bluff setup")
	await capture("package-bluff-setup")
	app.bluff.table.settings.players = 6
	app.bluff.table.settings.theme = "guofeng"
	app.bluff.table.settings_changed.emit(app.bluff.table.settings)
	app.bluff.table.start_requested.emit({"players": 6})
	var session = app.bluff.session
	while session.engine.state.phase != "playing":
		var action = {"revision": session.engine.state.revision, "round_id": session.round_id}
		if session.engine.state.phase == "rps":
			action.merge({"type": "rps", "gesture": 0})
			check(session.submit(action), "packaged RPS boundary")
		else:
			session._process(session.delay + 0.1)
			check(session.engine.state.phase == "playing", "packaged result advances automatically")
	session.paused = true
	check(app.bluff.table.hand_cards.size() == 18 and app.bluff.table.hand_cards.all(func(card): return "guofeng/" in card._face().resource_path), "six-seat actual package uses shared Guofeng art")
	# Clear a real six-player trick, then display a second one: the screenshot
	# must exercise the new recorder and per-player history, not just the lobby.
	for i in range(6):
		var seat = session.engine.state.turn
		check(session.engine.act(seat, {"type": "play", "cards": [session.engine.state.hands[seat][0]], "rank": 8, "revision": session.engine.state.revision}), "packaged public trick play")
	for i in range(5):
		check(session.engine.act(session.engine.state.turn, {"type": "pass", "revision": session.engine.state.revision}), "packaged unanimous pass")
	check(session.engine.state.phase == "playing" and session.engine.view(0).recorder.total == 1, "package clears own card and resumes without confirmation")
	for i in range(6):
		var seat = session.engine.state.turn
		check(session.engine.act(seat, {"type": "play", "cards": [session.engine.state.hands[seat][0]], "rank": 8, "revision": session.engine.state.revision}), "packaged next-trick play")
	session._publish()
	check(app.bluff.table.round_rows.size() == 6 and app.bluff.table.recorder.data.total == 1, "packaged history and recorder are visible")
	await capture("package-bluff-six")
	app.bluff.table.exit_requested.emit(); await process_frame
	check(app.current_screen == "lobby", "packaged return works")
	app._open_doudizhu(); await process_frame
	check(app.doudizhu.table.hand_cards.size() == 17, "existing Dou Dizhu still uses shared poker renderer")
	app.free(); await process_frame
	print("BLUFF_PACKAGE_RESULT: %d failures; %d checks" % [failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
