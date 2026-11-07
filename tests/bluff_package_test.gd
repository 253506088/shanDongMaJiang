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
	check(ProjectSettings.get_setting("application/config/version") == "0.10.1", "package version 0.10.1")
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
		for key in ["pass", "challenge", "truth", "lie", "dead", "win", "report_three"]: check(voice.clip(key) != null, "event speech ships")
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
				seat = game.state.permission.approver if game.state.phase == "permission" else game.state.turn
				action = ai.choose(game.view(seat), rng)
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
	session.set_process(false)
	session.start({"players": 3}, 8712)
	session.engine.state.phase = "playing"; session.engine.state.turn = 0
	session.engine.state.hands = [range(10), range(10, 32), range(32, 54)]
	session._publish()
	app.bluff.table.rank_buttons[0].pressed.emit()
	for id in range(10): app.bluff.table.toggle_card(id)
	check(not app.bluff.table.play_button.disabled and app.bluff.table.play_button.text == "扣下 10 张 A", "package enables ten-card ace lead without aces or jokers")
	await capture("package-ten-aces-ready")
	app.bluff.table.send_play()
	check(session.engine.state.last.count == 10 and session.engine.state.hands[0].is_empty(), "packaged UI delivers entire bluff hand to authority")
	await capture("package-ten-aces-played")
	session._process(session.delay + 0.1)
	check(session.engine.state.phase == "review" and session.engine.state.event.loser == 0, "package allows AI to call only after the impossible claim was played")
	session.start({"players": 3}, 8713)
	session.engine.state.phase = "playing"; session.engine.state.turn = 0
	session.engine.state.hands = [[40, 0, 4], [1, 5], [2, 6]]
	check(session.engine.act(0, {"type": "play", "cards": [40], "rank": 13, "revision": 0}), "packaged known-K fixture plays through authority")
	check(not session.engine.act(1, {"type": "challenge", "revision": 1}), "packaged low-hand protection rejects direct opening")
	check(session.engine.act(1, {"type": "request_challenge", "revision": 1}), "packaged known-K opening asks protected seat")
	check(session.engine.act(2, {"type": "challenge_permission", "allow": true, "revision": 2}), "packaged known-K reveal after consent")
	check(session.engine.view(2).memory.hands[1][13] == 1, "exported memory knows failed caller received K")
	for allow in [false, true]:
		session.start({"players": 3}, 8750)
		session.engine.state.phase = "playing"; session.engine.state.turn = 1
		session.engine.state.hands = [[0, 1, 2], range(3, 28), range(28, 54)]
		check(session.engine.act(1, {"type": "play", "cards": [3], "rank": 14, "revision": 0}), "package consent target plays")
		check(session.engine.act(2, {"type": "request_challenge", "revision": 1}), "package bot requests human permission")
		session._publish()
		check(app.bluff.table.permission_buttons.size() == 2 and app.bluff.table.report_labels.size() == 1, "package renders report and both permission choices")
		await capture("package-low-hand-consent")
		app.bluff.table.permission_buttons[1 if allow else 0].pressed.emit()
		check(session.engine.state.phase == ("review" if allow else "playing"), "packaged UI choice resolves through actual session")
		if not allow: check(session.engine.state.turn == 2 and not session.engine.can_request_challenge(2), "packaged denial resumes original turn without repeated request")
	session.start({"players": 6}, 8714)
	session.engine.state.phase = "playing"; session.engine.state.turn = 0
	session.engine.state.hands = [range(80), range(80, 86), range(86, 92), range(92, 98), range(98, 103), range(103, 108)]
	session._publish()
	check(app.bluff.table.hand_cards.size() == 80 and app.bluff.table.compact_hand(), "package shows accumulated hand without paging")
	for id in [0, 27, 54, 79]: app.bluff.table.toggle_card(id)
	check(app.bluff.table.selected.size() == 4 and not app.bluff.table.play_button.disabled, "packaged cross-row selection can submit")
	await capture("package-multirow-hand")
	app.bluff.table.exit_requested.emit(); await process_frame
	check(app.current_screen == "lobby", "packaged return works")
	app._open_doudizhu(); await process_frame
	check(app.doudizhu.table.hand_cards.size() == 17, "existing Dou Dizhu still uses shared poker renderer")
	var ddz = app.doudizhu.session
	ddz.set_process(false)
	ddz.engine.state.phase = "playing"; ddz.engine.state.turn = 0; ddz.engine.state.landlord = 0; ddz.engine.state.highest_bid = 1
	ddz.engine.state.hands = [[0, 4, 8, 12], [1, 5, 9], [2, 6]]
	check(ddz.submit({"type": "play", "cards": [0], "revision": ddz.engine.state.revision}), "package DDZ plays down to three")
	check(ddz.engine.state.turn == 1 and app.doudizhu.voice.clip_keys(ddz.current_view()).has("remaining_3"), "package DDZ warning preserves normal next turn")
	await capture("package-ddz-low-hand")
	app.free(); await process_frame
	print("BLUFF_PACKAGE_RESULT: %d failures; %d checks" % [failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
