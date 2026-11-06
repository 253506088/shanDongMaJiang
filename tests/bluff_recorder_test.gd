extends SceneTree
const Game = preload("res://scripts/bluff/core/engine.gd")
const Cards = preload("res://scripts/bluff/core/cards.gd")
const Recorder = preload("res://scripts/bluff/core/recorder.gd")
const AI = preload("res://scripts/bluff/core/ai.gd")
var checks = 0
var failures: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("BLUFF RECORDER FAIL: ", message)

func act(game, seat: int, action: Dictionary) -> void:
	action.revision = game.state.revision
	check(game.act(seat, action), "recorder fixture action is legal")

func fixture(hands: Array):
	var game = Game.new(); game.start(25, {"players": hands.size()})
	game.state.phase = "playing"; game.state.turn = 0; game.state.hands = hands.duplicate(true)
	return game

func run() -> void:
	var game = fixture([[4, 5, 8], [6, 12], [7, 16]])
	act(game, 0, {"type": "play", "cards": [4], "rank": 4})
	check(game.view(0).recorder.counts[4] == 0, "face-down card is not cleared while still on table")
	act(game, 1, {"type": "pass"}); act(game, 2, {"type": "pass"})
	check(game.view(0).recorder.counts[4] == 1 and game.view(0).recorder.total == 1, "user example: own four becomes one cleared four")
	check(game.view(1).recorder.total == 0 and game.view(2).recorder.total == 0, "other seats do not inherit declarer's private knowledge")
	var before = game.view(0).recorder
	game.view(0).recorder.counts[4] = 99
	check(game.view(0).recorder == before, "recorder view is detached from authority")
	act(game, 0, {"type": "play", "cards": [8], "rank": 4})
	act(game, 1, {"type": "play", "cards": [6], "rank": 4})
	act(game, 2, {"type": "pass"}); act(game, 0, {"type": "pass"})
	check(game.view(0).recorder.counts[5] == 1 and game.view(0).recorder.counts[4] == 1, "own bluff counts its real five, not declared four or opponent's four")
	check(game.view(1).recorder.counts[4] == 1 and game.view(1).recorder.counts[5] == 0, "each seat gets only its own cleared cards")
	check(game.state.phase == "playing" and game.state.trick.is_empty(), "next trick starts immediately while recorder persists")
	game = fixture([[4, 8], [5, 12], [6, 16]])
	act(game, 0, {"type": "play", "cards": [8], "rank": 4})
	act(game, 1, {"type": "challenge"})
	check(game.view(0).recorder.total == 0 and game.view(1).recorder.total == 0, "collected pile is not cleared")
	act(game, 0, {"type": "continue"})
	act(game, 1, {"type": "play", "cards": [5], "rank": 4})
	act(game, 2, {"type": "pass"})
	act(game, 0, {"type": "play", "cards": [8], "rank": 4})
	act(game, 1, {"type": "pass"}); act(game, 2, {"type": "pass"})
	check(game.view(0).recorder.counts[5] == 1 and game.view(0).recorder.total == 1, "returned then re-played card counted once only when cleared")
	game = fixture([[4, 58, 52, 106], [0], [1], [2]])
	act(game, 0, {"type": "play", "cards": [4, 58, 52, 106], "rank": 8})
	for seat in [1, 2, 3]: act(game, seat, {"type": "pass"})
	check(game.view(0).recorder.counts[4] == 2 and game.view(0).recorder.counts[16] == 2 and game.view(0).recorder.counts[8] == 0, "two decks and wildcards retain actual rank even on winning bluff")
	check(game.state.phase == "finished", "final unanimous pass still wins")
	game = fixture([range(50), [50, 51], [52, 53]])
	for i in range(30):
		act(game, 0, {"type": "play", "cards": [i], "rank": 3})
		act(game, 1, {"type": "pass"}); act(game, 2, {"type": "pass"})
	check(game.state.history.size() == 80 and game.view(0).recorder.total == 30, "cleared memory survives bounded history trimming")
	game.start(99)
	check(game.view(0).recorder.total == 0, "new match resets cleared memory")
	var simulations = 0
	for count in range(3, 7):
		for seed_value in range(2):
			game = Game.new(); game.start(64500 + seed_value, {"players": count})
			var rng = RandomNumberGenerator.new(); rng.seed = 113300 + seed_value
			var expected: Array = []; var pending: Array = []
			for seat in range(count): expected.append(Recorder.empty_counts())
			var steps = 0
			while game.state.phase != "finished" and steps < 2500:
				var phase = game.state.phase; var action: Dictionary; var seat = 0
				if phase == "rps": action = {"type": "rps", "gesture": rng.randi_range(0, 2)}
				elif phase == "review": action = {"type": "continue"}
				else:
					seat = game.state.turn; action = AI.choose(game.view(seat), rng)
				act(game, seat, action)
				if phase == "playing":
					if action.type == "challenge": pending.clear()
					elif action.type == "play" and game.state.phase != "finished": pending.append({"seat": seat, "cards": action.cards.duplicate()})
					elif action.type == "pass" and game.state.event.type == "dead":
						for play in pending:
							for id in play.cards: expected[play.seat][Cards.rank(id)] += 1
						pending.clear()
				for viewer in range(count):
					check(game.view(viewer).recorder.counts == expected[viewer], "per-seat recorder equals only their own cleared action cards")
				steps += 1
			check(game.state.phase == "finished", "recorder simulation completed")
			simulations += 1
	print("BLUFF_RECORDER_RESULT: %d failures; %d checks; %d games" % [failures.size(), checks, simulations])
	quit(0 if failures.is_empty() else 1)
