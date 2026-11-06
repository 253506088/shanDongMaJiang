extends SceneTree
const Game = preload("res://scripts/bluff/core/engine.gd")
const Cards = preload("res://scripts/bluff/core/cards.gd")
const AI = preload("res://scripts/bluff/core/ai.gd")
var checks = 0
var failures: Array = []

func _initialize() -> void:
	run()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message); printerr("BLUFF FAIL: ", message)

func act(game, seat: int, action: Dictionary) -> bool:
	action["revision"] = game.state.revision
	return game.act(seat, action)

func fixture(hands: Array, challenge: String = "turn"):
	var game = Game.new(); game.start(12, {"players": hands.size(), "challenge": challenge})
	game.state.phase = "playing"; game.state.turn = 0
	game.state.hands = hands.duplicate(true)
	game.state.dead = range(game.state.decks * 54).filter(func(id): return not hands.any(func(hand): return id in hand))
	return game

func invariant(game) -> void:
	var cards: Array = game.state.pile.duplicate()
	cards.append_array(game.state.dead)
	for hand in game.state.hands: cards.append_array(hand)
	check(cards.size() == game.state.decks * 54 and Cards.valid(cards, game.state.decks), "all physical cards conserved exactly once")
	for seat in range(game.state.config.players):
		var view = game.view(seat)
		check(not view.has("hands") and not view.has("pile") and not view.has("dead") and not view.last.has("cards"), "view conceals all hidden identities")
		check(view.hand.size() == game.state.hands[seat].size(), "private hand count")
		check(not view.event.has("cards") or view.event.type == "challenge", "only challenged hand is revealed")

func run() -> void:
	check(Cards.rank(0) == Cards.rank(54) and Cards.valid([0, 54], 2), "duplicate faces retain physical identity")
	check(not Cards.valid([0, 0], 2) and not Cards.valid([108], 2) and not Cards.valid([2.0], 2), "invalid physical cards rejected")
	for id in [52, 53, 106, 107]:
		for rank in Cards.DECLARATIONS: check(Cards.matches(id, rank), "all jokers substitute any rank")
	for count in range(3, 7):
		var game = Game.new(); game.start(111, {"players": count})
		var sizes = game.state.hands.map(func(hand): return hand.size())
		check(sizes.max() - sizes.min() <= 1, "fair deal for every player count")
		check(game.state.decks == (1 if count == 3 else 2), "requested pack count")
		invariant(game)
		var duplicate = Game.new(); duplicate.start(111, {"players": count})
		check(game.state == duplicate.state, "deterministic dealing")
		var rounds = 0
		while game.state.phase == "rps" and rounds < 300:
			var previous = game.state.contenders.duplicate()
			check(act(game, 0, {"type": "rps", "gesture": rounds % 3}), "valid RPS")
			check(game.state.contenders.all(func(seat): return seat in previous), "eliminated players never rejoin RPS")
			rounds += 1
		check(game.state.phase == "review" and game.state.contenders.size() == 1, "RPS yields one winner")
		var winner = game.state.contenders[0]
		check(act(game, 0, {"type": "continue"}) and game.state.turn == winner, "RPS winner leads")
	var game = fixture([[0, 4, 8], [1, 5], [2, 6]])
	check(not act(game, 1, {"type": "play", "cards": [1], "rank": 3}), "wrong turn rejected")
	check(not act(game, 0, {"type": "pass"}) and not act(game, 0, {"type": "challenge"}), "cannot pass or call an empty table")
	for cards in [[0, 0], [1], [], [108], [0.0]]:
		check(not act(game, 0, {"type": "play", "cards": cards, "rank": 3}), "invalid play rejected atomically")
	check(not act(game, 0, {"type": "play", "cards": [0], "rank": 16}), "cannot declare joker rank")
	check(act(game, 0, {"type": "play", "cards": [0], "rank": 3}), "truthful lead")
	var revision = game.state.revision
	check(not game.act(1, {"type": "pass", "revision": revision - 1}), "stale action rejected")
	check(not act(game, 1, {"type": "play", "cards": [1], "rank": 4}), "follow must preserve rank")
	check(not act(game, 2, {"type": "challenge"}), "turn-only call enforced")
	check(act(game, 1, {"type": "play", "cards": [5], "rank": 3}), "bluff is a legal declaration")
	check(act(game, 2, {"type": "challenge"}), "next player can call")
	check(not game.state.event.truthful and game.state.event.cards == [5], "only latest hand revealed, not older truthful card")
	check(0 in game.state.hands[1] and 5 in game.state.hands[1] and game.state.next_leader == 2, "liar collects entire pile, caller leads")
	invariant(game)
	game = fixture([[0, 4, 8], [1, 52, 53, 9], [2, 6]])
	act(game, 0, {"type": "play", "cards": [4], "rank": 3})
	act(game, 1, {"type": "play", "cards": [1, 52, 53], "rank": 3})
	act(game, 2, {"type": "challenge"})
	check(game.state.event.truthful and game.state.event.cards.size() == 3, "jokers all truthful; history bluff does not matter")
	check(game.state.event.loser == 2 and game.state.event.count == 4 and game.state.next_leader == 1, "failed caller collects all, declarer leads")
	invariant(game)
	game = fixture([[0, 4], [1, 5], [2, 6]])
	act(game, 0, {"type": "play", "cards": [0], "rank": 3})
	act(game, 1, {"type": "pass"})
	check(game.state.phase == "playing" and game.can_challenge(2), "pass leaves latest hand challengeable by next seat")
	act(game, 2, {"type": "play", "cards": [2], "rank": 3})
	check(game.state.passed.is_empty(), "following resets all-pass cycle")
	act(game, 0, {"type": "pass"}); act(game, 1, {"type": "pass"})
	check(game.state.event.type == "dead" and game.state.event.count == 2 and game.state.next_leader == 2 and game.state.pile.is_empty(), "full pass cycle clears hidden dead cards")
	check(game.state.phase == "playing" and game.state.turn == 2 and game.state.trick.is_empty(), "dead pile immediately starts the next empty trick")
	check(not game.view(0).event.has("cards"), "dead identities never exposed")
	invariant(game)
	game = fixture([[0, 4, 8, 12, 16], [1, 5, 9, 13, 17, 21], [2, 6]])
	act(game, 0, {"type": "play", "cards": [0], "rank": 3})
	check(act(game, 1, {"type": "play", "cards": [1, 5, 9, 13, 17, 21], "rank": 3}), "follow has no card-count cap")
	check(game.state.phase == "playing" and game.state.hands[1].is_empty(), "empty hand awaits response")
	act(game, 2, {"type": "challenge"})
	check(game.state.winner == -1 and game.state.hands[1].size() == 7, "false final play cannot win")
	for ending in ["pass", "truth", "accept"]:
		game = fixture([[0], [1, 5], [2, 6]])
		act(game, 0, {"type": "play", "cards": [0], "rank": 3})
		if ending == "pass":
			act(game, 1, {"type": "pass"}); act(game, 2, {"type": "pass"})
		elif ending == "truth": act(game, 1, {"type": "challenge"})
		else:
			var before = game.state.hands[1].duplicate()
			act(game, 1, {"type": "play", "cards": [1], "rank": 3})
			check(game.state.hands[1] == before, "accepting final hand does not remove new cards")
		check(game.state.phase == "finished" and game.state.winner == 0, "final play settles after " + ending)
		check(not act(game, 0, {"type": "continue"}), "finished games cannot continue actions")
		invariant(game)
	game = fixture([[0, 4], [1, 5], [2, 6], [54, 58]], "any")
	act(game, 0, {"type": "play", "cards": [4], "rank": 3})
	check(not game.can_challenge(0) and game.can_challenge(3), "free call excludes declarer, includes non-next seat")
	check(act(game, 3, {"type": "challenge"}) and game.state.next_leader == 3, "non-next caller can win lead")
	check(not act(game, 2, {"type": "challenge"}), "only first valid call settles")
	# User screenshot: all four aces plus both jokers are a valid six-card lead.
	game = fixture([range(44, 54), [0, 4], [1, 5]])
	check(act(game, 0, {"type": "play", "cards": [44, 45, 46, 47, 52, 53], "rank": 14}), "six truthful aces may lead")
	act(game, 1, {"type": "challenge"})
	check(game.state.event.truthful and game.state.event.count == 6 and game.state.event.loser == 1, "all four aces and both jokers prove true")
	invariant(game)
	# Both the screenshot's entire hand and ten non-aces without jokers may lie.
	for hand in [range(44, 54), range(10)]:
		var others = range(54).filter(func(id): return id not in hand)
		game = fixture([hand, others.slice(0, 22), others.slice(22)])
		check(act(game, 0, {"type": "play", "cards": hand, "rank": 14}), "whole ten-card hand may claim aces regardless of faces")
		check(game.state.phase == "playing" and game.state.last.count == 10 and game.state.hands[0].is_empty(), "whole-hand bluff waits for challenge rather than being blocked")
		var random = RandomNumberGenerator.new(); random.seed = 805
		var response = AI.choose(game.view(1), random)
		check(response.type == "challenge", "AI may call ten aces because a single pack has at most six matches")
		check(game.act(1, response) and not game.state.event.truthful and game.state.hands[0].size() == 10 and game.state.winner == -1, "legal impossible claim loses only after being called")
		invariant(game)
	game = fixture([[44, 45, 46, 47, 98, 99, 100, 101, 52, 53, 106, 107], [0], [1], [2]])
	check(act(game, 0, {"type": "play", "cards": game.state.hands[0].duplicate(), "rank": 14}), "twelve truthful aces may lead in two decks")
	act(game, 1, {"type": "challenge"})
	check(game.state.event.truthful and game.state.winner == 0, "large truthful final hand can win")
	invariant(game)
	game = fixture([range(105), [105], [106], [107]])
	check(act(game, 0, {"type": "play", "cards": range(105), "rank": 14}), "large accumulated hand has no artificial lead cap")
	for seat in [1, 2, 3]: act(game, seat, {"type": "pass"})
	check(game.state.winner == 0 and game.view(0).recorder.total == 105, "unchallenged large bluff clears and wins normally")
	invariant(game)
	var games = 0; var most_moves = 0
	for count in range(3, 7):
		for seed_value in range(24):
			game = Game.new(); game.start(712000 + seed_value, {"players": count, "challenge": "any" if seed_value % 2 else "turn"})
			var random = RandomNumberGenerator.new(); random.seed = 912000 + seed_value
			var moves = 0
			while game.state.phase != "finished" and moves < 2500:
				if game.state.phase == "rps": check(act(game, 0, {"type": "rps", "gesture": random.randi_range(0, 2)}), "simulated RPS")
				elif game.state.phase == "review": check(act(game, 0, {"type": "continue"}), "review continues")
				else:
					var seat = game.state.turn
					check(game.act(seat, AI.choose(game.view(seat), random)), "AI chooses a legal action from cropped view")
				invariant(game)
				moves += 1
			check(game.state.phase == "finished", "AI simulation completes %d players seed %d" % [count, seed_value])
			most_moves = maxi(most_moves, moves); games += 1
	print("BLUFF_CORE_RESULT: %d failures; %d checks; %d games; max %d moves" % [failures.size(), checks, games, most_moves])
	quit(0 if failures.is_empty() else 1)
