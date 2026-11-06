extends SceneTree
const Game = preload("res://scripts/bluff/core/engine.gd")
const Cards = preload("res://scripts/bluff/core/cards.gd")
const AI = preload("res://scripts/bluff/core/ai.gd")
const Knowledge = preload("res://scripts/bluff/core/knowledge.gd")
var checks = 0
var failures: Array = []

func _initialize() -> void:
	run()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("BLUFF AI FAIL: ", message)

func fixture(hands: Array):
	var game = Game.new(); game.start(93, {"players": hands.size()})
	game.state.hands = hands.duplicate(true); game.state.phase = "playing"; game.state.turn = 0
	game.state.dead = range(game.state.decks * 54).filter(func(id): return not hands.any(func(h): return id in h))
	return game

func act(game, seat: int, action: Dictionary) -> void:
	action.revision = game.state.revision
	check(game.act(seat, action), "fixture action accepted " + str(action))

func bounds(game) -> void:
	for observer in range(game.state.config.players):
		var memory: Dictionary = game.view(observer).memory
		for seat in range(game.state.config.players):
			var actual = Knowledge.counts(game.state.hands[seat])
			for rank in actual:
				check(memory.hands[seat][rank] >= 0 and memory.hands[seat][rank] <= actual[rank], "remembered hand lower bound never invents a card")
		var dead = Knowledge.counts(game.state.dead)
		for rank in dead: check(memory.dead[rank] <= dead[rank], "known dead counts never exceed actual dead")
		var offset = 0
		for entry_index in range(memory.pile.size()):
			var count = game.state.trick[entry_index].count
			var actual = Knowledge.counts(game.state.pile.slice(offset, offset + count))
			for rank in actual: check(memory.pile[entry_index].known[rank] <= actual[rank], "concealed-play bounds remain facts")
			offset += count

func run() -> void:
	# User's example: a failed caller receives the exposed K, everybody knows.
	var game = fixture([[40, 0, 4], [1, 5], [2, 6]])
	act(game, 0, {"type": "play", "cards": [40], "rank": 13})
	act(game, 1, {"type": "challenge"})
	check(game.view(2).memory.hands[1][13] == 1, "failed caller publicly holds at least one K")
	check(game.view(2).memory.hands[0][13] == 0, "K no longer attributed to its old owner")
	act(game, 0, {"type": "continue"})
	act(game, 0, {"type": "play", "cards": [0], "rank": 13})
	check(game.view(2).memory.hands[1][13] == 1, "unrelated players' actions do not erase the K")
	act(game, 1, {"type": "play", "cards": [40], "rank": 13})
	var informed = game.view(2)
	var uninformed = informed.duplicate(true)
	uninformed.memory.pile.back().before[13] = 0; uninformed.memory.pile.back().expected[13] = 0
	check(AI.assessment(informed).false_chance < AI.assessment(uninformed).false_chance, "remembered K makes a one-K declaration more credible, not certain")
	check(not AI.assessment(informed).certain, "having a K does not prove this concealed card is a K")
	check(informed.memory.hands[1][13] == 0 and informed.memory.likely[1][13] > 0, "hidden play weakens certainty but retains soft context")
	act(game, 2, {"type": "challenge"})
	check(game.view(0).memory.hands[2][13] == 1 and game.view(0).memory.hands[1][13] == 0, "revealed K transfers again")
	bounds(game)
	# Earlier concealed cards are known ONLY to their original player/collector.
	game = fixture([[4, 8], [40, 12, 24], [16, 20]])
	act(game, 0, {"type": "play", "cards": [4], "rank": 13})
	act(game, 1, {"type": "play", "cards": [40], "rank": 13})
	act(game, 2, {"type": "challenge"})
	check(game.view(0).memory.hands[2][4] == 1, "original player tracks own concealed card into another hand")
	check(game.view(1).memory.hands[2][4] == 0, "other bot cannot see the earlier hidden four")
	check(game.view(1).memory.hands[2][13] == 1, "all observers see the final revealed K")
	bounds(game)
	# Known K was not necessarily used when its holder made a false declaration.
	act(game, 0, {"type": "continue"})
	act(game, 1, {"type": "play", "cards": [12], "rank": 13})
	act(game, 2, {"type": "play", "cards": [16], "rank": 13})
	act(game, 0, {"type": "challenge"})
	check(game.view(1).memory.hands[2][13] == 1, "reveal of a different card restores the unsent known K")
	check(game.view(1).memory.profiles[2].lies == 1, "public caught bluff contributes to per-player history")
	bounds(game)
	# Knowledge must survive the short UI history's truncation and reset per game.
	game.state.history.clear()
	check(game.view(1).memory.hands[2][13] == 1, "memory is independent of truncated display log")
	var isolated = game.view(1); isolated.memory.hands[2][13] = 99
	check(game.view(1).memory.hands[2][13] == 1, "seat view cannot mutate authority memory")
	game.start(93)
	check(game.view(1).memory.hands[2][13] == 0 and game.view(1).memory.profiles[2].lies == 0, "new game resets all remembered opponents")
	# Certain deductions use other owners and own cleared cards, never claims.
	game = fixture([[40, 41, 42, 43, 52, 53, 0], [4, 8], [12, 16]])
	act(game, 0, {"type": "play", "cards": [40, 41, 42, 43, 52, 53], "rank": 13})
	act(game, 1, {"type": "challenge"}); act(game, 0, {"type": "continue"})
	act(game, 0, {"type": "play", "cards": [0], "rank": 13})
	var v = game.view(2)
	check(AI.assessment(v).certain and AI.assessment(v).false_chance == 1, "known matching cards in another hand prove latest K impossible")
	game = fixture([[40, 41, 42, 43, 52, 53, 0], [4, 8], [12, 16]])
	act(game, 0, {"type": "play", "cards": [40, 41, 42, 43, 52, 53], "rank": 13})
	act(game, 1, {"type": "pass"}); act(game, 2, {"type": "pass"})
	act(game, 0, {"type": "play", "cards": [0], "rank": 13})
	act(game, 1, {"type": "play", "cards": [4], "rank": 13})
	check(AI.assessment(game.view(0)).false_chance == 1, "own cleared matching cards are unavailable without double counting recorder")
	check(game.view(2).memory.dead[13] == 0, "unopened dead cards remain unknown to others")
	bounds(game)
	# Paired worlds differ only in opponents' secret cards; visible input and
	# same-seed decisions must agree. Own memory can legitimately differ.
	var a = fixture([[0, 4], [8, 12], [16, 20]])
	var b = fixture([[16, 20], [8, 12], [0, 4]])
	act(a, 0, {"type": "play", "cards": [0], "rank": 3})
	act(b, 0, {"type": "play", "cards": [16], "rank": 3})
	check(a.view(1) == b.view(1), "changing hidden truth leaves another seat's entire view identical")
	for seed_value in range(30):
		var ra = RandomNumberGenerator.new(); ra.seed = seed_value
		var rb = RandomNumberGenerator.new(); rb.seed = seed_value
		check(AI.choose(a.view(1), ra) == AI.choose(b.view(1), rb), "same evidence gives same decision despite hidden truth")
	# Mixed strategic play, with no wildcard in any deliberate lie.
	var rates: Array = []
	for follow in [false, true]:
		game = fixture([[0, 1, 4, 8, 12, 16, 20, 24, 40, 44, 52, 53], [2, 6], [3, 7]])
		var view = game.view(0)
		if follow: view.last = {"seat": 2, "count": 1, "rank": 3}; view.rank = 3; view.pile_count = 1
		var lies = 0; var truths = 0
		for seed_value in range(600):
			var random = RandomNumberGenerator.new(); random.seed = seed_value + 7300
			var action = AI.choose(view, random, false)
			if action.type != "play": continue
			var truth = action.cards.all(func(id): return Cards.matches(id, action.rank))
			if truth: truths += 1
			else:
				lies += 1
				check(action.cards.all(func(id): return Cards.rank(id) < 16), "bluff never squanders a wildcard")
		var rate = float(lies) / maxi(1, lies + truths); rates.append(rate)
		check(rate > 0.30 and rate < 0.65, "intentional bluff rate is varied rather than overwhelmingly truthful")
	var games = 0
	for players in range(3, 7):
		for seed_value in range(3):
			game = Game.new(); game.start(seed_value + 9800, {"players": players})
			var random = RandomNumberGenerator.new(); random.seed = seed_value + 13
			var moves = 0
			while game.state.phase != "finished" and moves < 2500:
				if game.state.phase == "rps": act(game, 0, {"type": "rps", "gesture": random.randi_range(0, 2)})
				elif game.state.phase == "review": act(game, 0, {"type": "continue"})
				else:
					var seat = game.state.turn
					check(game.act(seat, AI.choose(game.view(seat), random)), "new strategy generates legal moves")
				if moves % 11 == 0: bounds(game)
				moves += 1
			check(game.state.phase == "finished", "memory-enabled game terminates")
			games += 1
	print("BLUFF_AI_RESULT: %d failures; %d checks; %d games; lead/follow bluff rates %s" % [failures.size(), checks, games, rates])
	quit(0 if failures.is_empty() else 1)
