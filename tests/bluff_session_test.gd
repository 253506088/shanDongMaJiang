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
				check(not submit(session, {"type": "continue"}), "review is timer-owned, with no manual acknowledgment")
				session._process(session.delay - 0.25)
				check(state.revision == revision and session.delay > 0, "opening remains visible for its presentation time")
				session.paused = true; session._process(30)
				check(state.revision == revision and session.delay > 0, "inspection pauses the review countdown")
				session.paused = false; session._process(0.3)
				check(state.phase == "playing" and state.revision == revision + 1, "review automatically resumes one new trick when timer expires")
			elif state.phase == "permission":
				if state.permission.approver == 0:
					var before_permission = state.duplicate(true)
					session._process(100)
					check(state == before_permission, "human permission never times out")
					check(submit(session, AI.permission_response(session.current_view())), "human answers request")
				else:
					session._process(100)
					check(state.phase != "permission", "bot answers permission request")
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
		var finished = session.engine.state.duplicate(true)
		session._process(200)
		check(session.engine.state == finished, "automatic trick advance never restarts a finished match")
	session.start({"challenge": "any"}, 830)
	# Construct an impossible public claim on the human's turn. The bot's
	# certainty is based only on the six possible rank/wild cards in one pack.
	session.engine.state.phase = "playing"; session.engine.state.turn = 2
	session.engine.state.hands = [range(7, 22), range(22, 40), range(7) + range(40, 54)]
	check(session.engine.act(2, {"type": "play", "cards": range(7), "rank": 3, "revision": 0}), "free-call fixture enters through normal play and memory updates")
	session._process(10)
	check(session.engine.state.phase == "review" and session.engine.state.event.caller == 1, "free-call bots may interrupt on human turn using public impossibility")
	check(session.delay == Session.REVEAL_SECONDS, "both bluff outcomes get a four-second reveal")
	session._process(3.0)
	check(session.engine.state.phase == "review", "reveal does not disappear before four seconds")
	session._process(1.1)
	check(session.engine.state.phase == "playing" and session.engine.state.turn == 1, "caught declarer yields lead automatically")
	# No intermediate review or second action after all remaining players pass.
	session.start({}, 832)
	session.engine.state.phase = "playing"; session.engine.state.turn = 1
	var lead = session.engine.state.hands[1][0]
	session.engine.act(1, {"type": "play", "cards": [lead], "rank": 3, "revision": 0})
	session.engine.act(2, {"type": "pass", "revision": 1})
	check(submit(session, {"type": "pass"}), "human can finish unanimous pass cycle")
	check(session.engine.state.phase == "playing" and session.engine.state.turn == 1 and session.engine.state.event.type == "dead", "unanimous pass immediately gives the last declarer a new trick")
	check(session.current_view().review_remaining == 0, "dead clearing introduces no review countdown")
	session.start({}, 834)
	session.engine.state.phase = "playing"; session.engine.state.turn = 0
	session.engine.state.hands = [range(10), range(10, 32), range(32, 54)]
	check(submit(session, {"type": "play", "cards": range(10), "rank": 14}), "session accepts ten non-aces as a whole-hand ace lead")
	check(session.engine.state.last.count == 10 and session.engine.state.winner == -1, "obvious lie is accepted until another seat acts")
	session._process(10)
	check(session.engine.state.phase == "review" and session.engine.state.event.loser == 0 and session.engine.state.event.count == 10, "bot opens impossible claim after presentation, without preventing its submission")
	# One free-call assessment belongs to the declaration, not to later passes.
	session.start({"challenge": "any"}, 835)
	session.engine.state.phase = "playing"; session.engine.state.turn = 2
	var card = session.engine.state.hands[2][0]
	check(session.engine.act(2, {"type": "play", "cards": [card], "rank": 3, "revision": 0}), "free-call identity fixture")
	var claim_revision = session.engine.state.last.revision
	session.calls_checked_revision = claim_revision
	session.calls_checked_seats = [1, 2]
	var rng_state = session.rng.state
	session._process(100)
	check(session.rng.state == rng_state, "idle human turn never rerolls a checked free-call claim")
	check(submit(session, {"type": "pass"}), "human passes on the same claim")
	check(session.engine.state.last.revision == claim_revision and session.engine.state.revision != claim_revision, "pass increments action revision while preserving declaration identity")
	session._process(100)
	check(session.calls_checked_revision == claim_revision and session.engine.state.event.type != "challenge", "next bot does not reroll challenge after a pass or duplicate its first assessment")
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
	app._set_character("female_02")
	app.bluff.table.settings_changed.emit(app.bluff.table.settings)
	check(not FileAccess.file_exists(app.preferences_path), "QA mode never writes preferences")
	app.qa_mode = false # Isolated path only; no read/write of real preferences.
	app.bluff.table.settings_changed.emit(app.bluff.table.settings)
	var prefs = JSON.parse_string(FileAccess.get_file_as_string(app.preferences_path))
	check(prefs.bluff_settings.players == 6 and prefs.bluff_settings.theme == "guofeng" and prefs.character_id == "female_02" and not prefs.bluff_settings.has("voice"), "independent settings persist")
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
	check(app.bluff_settings.players == 6 and app.bluff_settings.challenge == "any" and app.character_id == "female_02", "new app restores settings")
	app._open_bluff()
	check(app.bluff.table.settings.theme == "guofeng" and app.bluff.table.view.is_empty(), "restoring preferences never restores a discarded round")
	app.free(); await process_frame
	for filename in ["preferences.json", "current_match.json", "current_match.json.bak", "current_match.json.tmp"]:
		var path = directory + filename
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
