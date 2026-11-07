extends SceneTree
## Consent, low-card announcements and independent game boundaries.
const Bluff = preload("res://scripts/bluff/core/engine.gd")
const Session = preload("res://scripts/bluff/session.gd")
const AI = preload("res://scripts/bluff/core/ai.gd")
const Voice = preload("res://scripts/bluff/voice.gd")
const Ddz = preload("res://scripts/doudizhu/core/engine.gd")
const DdzVoice = preload("res://scripts/doudizhu/audio/voice.gd")
var failures: Array = []
var checks = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("LOW HAND FAIL: ", message)

func act(game, seat: int, action: Dictionary) -> bool:
	action["revision"] = game.state.revision
	return game.act(seat, action)

func fixture(players: int, protected: int, amount: int, mode: String = "turn"):
	var game = Bluff.new(); game.start(117, {"players": players, "challenge": mode})
	var next_id = 0
	for seat in range(players):
		var count = amount if seat == protected else 5
		game.state.hands[seat] = range(next_id, next_id + count); next_id += count
	game.state.dead = range(next_id, game.state.decks * 54)
	game.state.phase = "playing"; game.state.turn = posmod(protected - 2, players)
	var target = game.state.turn
	check(act(game, target, {"type": "play", "cards": [game.state.hands[target][0]], "rank": 14}), "fixture plays latest hidden declaration")
	return game

func consent_boundaries() -> void:
	for players in range(3, 7):
		for protected in range(players):
			var caller = posmod(protected - 1, players)
			var target = posmod(protected - 2, players)
			for mode in ["turn", "any"]:
				for count in range(5):
					var game = fixture(players, protected, count, mode)
					var low = count in [1, 2, 3]
					check(game.can_challenge(caller) == not low, "only 1..3 requires consent, including wrapped seats")
					check(game.can_request_challenge(caller) == low, "request follows original turn/free challenge window")
					if not low: continue
					check(game.view(caller).challenge_approver == protected, "authority identifies exact downstream approver")
					var before = game.state.duplicate(true)
					check(not act(game, caller, {"type": "challenge", "allow": true}), "caller cannot self-authorize a direct reveal")
					check(game.state == before, "blocked direct call leaves all state unchanged")
					check(act(game, caller, {"type": "request_challenge"}), "caller requests consent")
					check(game.state.phase == "permission" and game.state.turn == caller, "request freezes original turn")
					check(game.state.pile == before.pile and game.state.hands == before.hands and game.state.stats == before.stats, "asking does not move cards or count as a challenge")
					for seat in range(players):
						var view = game.view(seat)
						check(not view.last.has("cards") and not view.event.has("cards") and not view.has("hands"), "request view contains no hidden identity")
						check(not game.can_challenge(seat) and not game.can_request_challenge(seat), "all other calls frozen until answer")
						if seat != protected: check(not act(game, seat, {"type": "challenge_permission", "allow": true}), "only protected seat may approve")
					check(not act(game, caller, {"type": "pass"}), "caller cannot skip unresolved request")
					check(not act(game, caller, {"type": "play", "cards": [game.state.hands[caller][0]], "rank": 14}), "caller cannot replace target while waiting")
					check(not act(game, protected, {"type": "challenge_permission", "allow": 1}), "approval must be an explicit boolean")
					check(not game.act(protected, {"type": "challenge_permission", "allow": true, "revision": game.state.revision - 1}), "stale answer rejected")
					check(act(game, protected, {"type": "challenge_permission", "allow": false}), "protected seat can decline")
					check(game.state.phase == "playing" and game.state.turn == caller and game.state.last == before.last, "decline resumes caller without altering last declaration")
					check(not act(game, caller, {"type": "request_challenge"}) and not act(game, caller, {"type": "challenge"}), "declined claim cannot be repeatedly requested or opened")
					check(act(game, caller, {"type": "pass"}), "declined caller can pass")
					check(game.can_challenge(protected), "protected seat still has its own normal right to call after pass")
					if mode == "any":
						for other in range(players):
							if other not in [caller, target]: check(game.can_challenge(other), "free-call unrelated seats keep normal rights")
					# A fresh declaration clears denial; permission applies to one attempt only.
					game.state.turn = target
					check(act(game, target, {"type": "play", "cards": [game.state.hands[target][0]], "rank": 14}), "fresh declaration after denial")
					check(game.can_request_challenge(caller), "new declaration may request permission again")
					check(act(game, caller, {"type": "request_challenge"}), "fresh permission request")
					var last_cards = game.state.last.cards.duplicate()
					var pile_size = game.state.pile.size()
					var decision = {"type": "challenge_permission", "allow": true, "revision": game.state.revision}
					check(game.act(protected, decision), "protected seat can approve")
					check(game.state.phase == "review" and game.state.event.caller == caller and game.state.event.seat == target, "approval opens exactly the requested latest hand")
					check(game.state.event.cards == last_cards and game.state.event.count == pile_size, "normal reveal and whole-pile collection still apply")
					check(not game.act(protected, decision), "duplicate approval cannot reveal twice")
					check(game.state.permission.is_empty(), "permission expires after resolution")
	# Following remains available after rejection, including simultaneous low hands.
	var game = fixture(3, 2, 1)
	game.state.hands[1] = game.state.hands[1].slice(0, 2)
	check(act(game, 1, {"type": "request_challenge"}), "two low seats still have one exact approver")
	check(act(game, 2, {"type": "challenge_permission", "allow": false}), "decline with two low seats")
	check(act(game, 1, {"type": "play", "cards": [game.state.hands[1][0]], "rank": 14}), "declined caller may follow, including a bluff")

func reports() -> void:
	var voice = Voice.new()
	for remaining in [1, 2, 3]:
		var game = Bluff.new(); game.start(41)
		game.state.phase = "playing"; game.state.turn = 0
		game.state.hands = [[0, 4, 8, 12, 16], [1, 5, 9, 13], [2, 6, 10, 14]]
		check(act(game, 0, {"type": "play", "cards": game.state.hands[0].slice(0, 5 - remaining), "rank": 3}), "jump into small hand accepted")
		check(game.state.event.report_seat == 0 and voice.keys(game.view(0)).back() == "report_three", "1/2/3 all use fixed bluff report")
		check(act(game, 1, {"type": "pass"}) and voice.keys(game.view(0)) == ["pass"], "pass does not repeat report")
		check(act(game, 2, {"type": "pass"}), "clear and lead again")
		check(act(game, 0, {"type": "play", "cards": [game.state.hands[0][0]], "rank": 3}), "next small-hand play accepted")
		check(not game.state.event.has("report_seat"), "no repeated report within same low-hand period or at zero")
	var game = fixture(3, 2, 3)
	game.state.hands[2].append_array([40, 41])
	check(game.can_challenge(1) and not game.can_request_challenge(1), "collecting beyond three releases protection immediately")
	game.state.turn = 2
	check(act(game, 2, {"type": "play", "cards": [40, 41], "rank": 14}) and game.state.event.report_seat == 2, "returning to three reports again")
	voice.free()
	var ddz_voice = DdzVoice.new()
	for seat in range(3):
		for remaining in [0, 1, 2, 3, 4]:
			var ddz = Ddz.new(); ddz.start(720, 0)
			ddz.state.phase = "playing"; ddz.state.turn = seat; ddz.state.landlord = 0; ddz.state.highest_bid = 1
			ddz.state.hands[seat] = range(remaining + 1)
			check(act(ddz, seat, {"type": "play", "cards": [0]}), "every DDZ seat may play down to low counts")
			check(ddz.state.event.remaining == remaining, "DDZ event records actual post-play count")
			var keys = ddz_voice.clip_keys(ddz.view(0))
			check(keys.has("remaining_%d" % remaining) == (remaining in [1, 2, 3]), "DDZ speaks matching 3/2/1 only")
			if remaining > 0:
				check(ddz.state.turn == (seat + 1) % 3 and ddz.state.phase == "playing", "DDZ warning adds no permission phase or turn restriction")
				check(act(ddz, (seat + 1) % 3, {"type": "pass"}), "other DDZ players continue normally")
				check(ddz_voice.clip_keys(ddz.view(0)) == ["pass"], "DDZ passing never repeats old count warning")
	ddz_voice.free()

func session_permission() -> void:
	var session = Session.new(); root.add_child(session); session.set_process(false)
	session.start({}, 780)
	session.engine = fixture(3, 0, 3)
	check(session.engine.act(2, {"type": "request_challenge", "revision": session.engine.state.revision}), "bot requests human protection consent")
	var before = session.engine.state.duplicate(true)
	session._process(10000)
	check(before == session.engine.state, "human permission has no timeout")
	var answer = {"type": "challenge_permission", "allow": true, "revision": session.engine.state.revision, "round_id": session.round_id}
	session.paused = true
	check(not session.submit(answer), "pause blocks answers")
	session.paused = false
	check(session.submit(answer) and session.engine.state.phase == "review", "human approval reveals via real session")
	check(session.delay == Session.REVEAL_SECONDS, "approved reveal retains readable result duration")
	session.start({}, 781)
	check(not session.submit(answer), "old-round answer cannot act in a new game")
	session.engine = fixture(3, 1, 3)
	check(session.submit({"type": "request_challenge", "revision": session.engine.state.revision, "round_id": session.round_id}), "human request reaches bot approver")
	var decision = AI.permission_response(session.engine.view(1))
	session._process(session.pace - 0.1)
	check(session.engine.state.phase == "permission", "bot consent waits normal readable pace")
	session._process(0.2)
	check(session.engine.state.phase != "permission" and session.engine.state.event.type == ("challenge" if decision.allow else "challenge_permission"), "bot answers from own information without deadlock")
	# A denied request must neither reroll its caller nor suppress other bots.
	session.start({"challenge": "any"}, 782)
	session.engine.state.phase = "playing"; session.engine.state.turn = 0
	session.engine.state.hands = [range(7), range(7, 51), range(51, 54)]
	check(act(session.engine, 0, {"type": "play", "cards": range(7), "rank": 14}), "free-call impossible claim fixture")
	session._process(100)
	check(session.engine.state.phase == "permission" and session.engine.state.permission.caller == 1, "free-call bot requests instead of bypassing consent")
	check(act(session.engine, 2, {"type": "challenge_permission", "allow": false}), "decline first free-call bot")
	session._process(100)
	check(session.engine.state.phase == "review" and session.engine.state.event.caller == 2, "remaining free-call bot is evaluated after denial")
	check(session.calls_checked_seats == [1, 2], "each free-call bot is considered once per declaration")
	session.shutdown(); session.free()

func run() -> void:
	consent_boundaries()
	reports()
	session_permission()
	await process_frame
	print("POKER_LOW_HAND_RESULT: %d failures; %d checks" % [failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
