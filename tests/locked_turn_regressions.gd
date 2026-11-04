extends SceneTree

var checks = 0
var failures: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("LOCKED TURN FAIL: ", message)

func fixture() -> LocalSession:
	var session = LocalSession.new()
	session.storage_root = "user://qa-locked-turn/"
	session.engine.start({}, 481)
	var p = session.engine.state.players[0]
	p.hand = [0,1,2,3,4,5,9,10,11,18,19,20,22,27]
	p.melds = []; p.bao = true; p.ming = false; p.drawn = 13
	session.engine._turn_options()
	session.paused = false
	return session

func run() -> void:
	_test_automatic_turns()
	_test_human_choices()
	_test_timing_and_stale_actions()
	_test_saved_turn()
	print("LOCKED_TURN_RESULT: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_automatic_turns() -> void:
	for declaration in ["bao", "ming"]:
		var session = fixture()
		var engine = session.engine
		var p = engine.state.players[0]
		p.bao = declaration == "bao"; p.ming = declaration == "ming"
		engine._turn_options()
		var hand = p.hand.slice(0, 13)
		check(not engine.state.pending.any(func(a): return a.kind == "win"), "fixture has no self draw")
		check(not session.locked_discard_action().is_empty(), declaration + " chooses automatic drawn discard")
		session._process(0.01)
		check(engine.state.revision == 1 and p.discards == [27], declaration + " advances without a click")
		check(p.hand == hand, declaration + " keeps every locked hand tile")
		check(engine.journal.size() == 1 and engine.journal[0].action.kind == "discard", declaration + " journals normal discard")
		check(not session.autopilot and session.worker == null, declaration + " does not enable AI control")
		session.free()
	var session = fixture()
	var p = session.engine.state.players[0]
	p.bao = false
	session.engine._turn_options()
	check(session.engine.state.pending.any(func(a): return a.kind == "bao"), "undeclared fixture can declare")
	session._process(5.0)
	check(session.engine.state.revision == 0, "waiting-shaped hand stays manual until actual declaration")
	session.free()

func _test_human_choices() -> void:
	var session = fixture()
	var engine = session.engine
	var p = engine.state.players[0]
	p.hand[-1] = 22
	engine._turn_options()
	check(engine.state.pending.any(func(a): return a.kind == "win"), "self draw offered")
	session._process(10.0)
	check(engine.state.revision == 0 and session.locked_discard_action().is_empty(), "self draw waits indefinitely for human")
	session.free()
	for kong in ["bugang", "angang"]:
		session = fixture()
		engine = load("res://tests/ux_regressions.gd").screenshot_engine()
		session.engine = engine; p = engine.state.players[0]
		if kong == "angang":
			p.hand = [0,1,2,3,4,5,6,7,8,9,9,9,13,9]
			p.drawn = 13; p.melds = []; engine._turn_options()
		check(engine.state.pending.any(func(a): return a.kind == kong), "legal " + kong + " offered")
		session._process(10.0)
		check(engine.state.revision == 0 and session.locked_discard_action().is_empty(), kong + " remains a human choice")
		session.free()
	session = fixture(); engine = session.engine; p = engine.state.players[0]
	p.hand.pop_back(); p.drawn = -1
	engine.state.players[3].discards = [22]
	engine._begin_claims(3, 22)
	check(engine.state.phase == "claim" and engine.decision_seat() == 0, "discard win fixture reaches human claim")
	session._process(10.0)
	check(engine.state.revision == 0 and session.locked_discard_action().is_empty(), "discard win is never passed automatically")
	session.free()

func _test_timing_and_stale_actions() -> void:
	var session = fixture()
	session.delay = 0.5; session.presentation_delay = 0.8
	session._process(0.4)
	check(session.engine.state.revision == 0, "visible action beat holds automatic discard")
	session.paused = true
	var delay = session.delay; var presentation = session.presentation_delay
	session._process(20.0)
	check(session.engine.state.revision == 0 and session.delay == delay and session.presentation_delay == presentation, "pause freezes both automatic timers")
	session.paused = false; session._process(0.15)
	check(session.engine.state.revision == 0, "voice presentation can outlast the action beat")
	session._process(0.3)
	check(session.engine.state.revision == 1, "automatic discard resumes after both waits")
	session.free()
	session = fixture(); session.delay = 1.0
	var move = session.locked_discard_action()
	check(session.play(move.id), "manual new-tile discard is still accepted before its timer")
	session._process(0.01)
	check(session.engine.state.revision == 1 and session.engine.state.players[0].discards == [27], "manual discard invalidates any would-be automatic duplicate")
	session.free()

func _test_saved_turn() -> void:
	# A physical 144-tile opening and accepted commands make this a real replay,
	# rather than a saved mutated test state that restore correctly rejects.
	var hand = [0,1,2,3,4,5,9,10,11,18,19,20,22,27]
	var draws = [6,7,8,6]
	var remaining = Tiles.wall()
	for tile in hand + draws: remaining.erase(tile)
	var others: Array = []
	for index in range(39): others.append(remaining.pop_front())
	# A non-flower tail prevents ensure_tail from moving a flower to the first draw.
	remaining.append(remaining.pop_front())
	var engine = GameEngine.new()
	engine.start({}, 481, 1, [], hand + others + draws + remaining)
	var declaration = engine.state.pending.filter(func(a): return a.kind == "bao" and a.tile == 27)
	check(not declaration.is_empty(), "replay opening can declare East discard")
	if declaration.is_empty(): return
	check(engine.submit(0, engine.state.revision, declaration[0].id), "replay records actual declaration")
	var decisions = 0
	while engine.state.phase != "settled" and not (engine.state.phase == "turn" and engine.decision_seat() == 0) and decisions < 30:
		var legal = engine.state.pending.filter(func(a): return a.kind == ("discard" if engine.state.phase == "turn" else "pass"))
		if legal.is_empty(): break
		engine.submit(engine.decision_seat(), engine.state.revision, legal[0].id)
		decisions += 1
	check(engine.state.phase == "turn" and engine.decision_seat() == 0, "replay reaches locked next draw")
	var session = LocalSession.new()
	session.storage_root = "user://qa-locked-replay/"; session.engine = engine
	session._save()
	var revision = engine.state.revision
	check(session.resume_match(), "save resumes through accepted replay journal")
	check(not session.locked_discard_action().is_empty(), "restored locked turn retains automatic discard")
	session._process(0.1)
	check(session.engine.state.revision == revision, "resume provides a readable beat before auto discard")
	session._process(2.0)
	check(session.engine.state.revision == revision + 1, "restored locked turn automatically discards once")
	var restored = GameEngine.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(session.engine.snapshot()))), "automatic discard replays with existing version and action IDs")
	check(restored.state == session.engine.state, "automatic discard replay preserves exact state")
	session.free()
