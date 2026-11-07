extends SceneTree
const Game = preload("res://scripts/bluff/core/engine.gd")
const Cards = preload("res://scripts/bluff/core/cards.gd")
const AI = preload("res://scripts/bluff/core/ai.gd")
const Strategy = preload("res://scripts/bluff/core/strategy.gd")
var checks = 0
var failures: Array = []

func _initialize() -> void:
	run()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("BLUFF STRATEGY FAIL: ", message)

func fixture(hand: Array, players: int = 3) -> Dictionary:
	var game = Game.new(); game.start(1107, {"players": players})
	var rest: Array = range(game.state.decks * 54).filter(func(id): return id not in hand)
	game.state.hands = [hand.duplicate()]
	for seat in range(1, players): game.state.hands.append([])
	for index in range(rest.size()): game.state.hands[1 + index % (players - 1)].append(rest[index])
	game.state.phase = "playing"; game.state.turn = 0
	return game.view(0)

func follow(view: Dictionary, rank: int, pile: int = 1) -> Dictionary:
	view = view.duplicate(true)
	view.last = {"seat": view.hand_counts.size() - 1, "count": 1, "rank": rank}
	view.rank = rank; view.pile_count = pile
	return view

func seeded(view: Dictionary, seed_value: int) -> Dictionary:
	var rng = RandomNumberGenerator.new(); rng.seed = seed_value
	return AI.choose(view, rng, false)

func run() -> void:
	var probability = Strategy.distribution(4, 2, 2)
	check(is_equal_approx(probability[0], 1.0 / 6) and is_equal_approx(probability[1], 4.0 / 6) and is_equal_approx(probability[2], 1.0 / 6), "finite-pool counting agrees with six equally possible pairs")
	check(Strategy.distribution(0, 0, 0) == [1.0], "fully known pool needs no hidden sampling")
	var view = follow(fixture([40, 41, 42, 0, 4, 8]), 13)
	view.last.count = 5
	check(AI.assessment(view).certain and AI.assessment(view).false_chance == 1, "three real K disprove five K in one deck even including both jokers")
	var double = follow(fixture([40, 41, 42, 0, 4, 8], 4), 13)
	double.last.count = 5
	check(not AI.assessment(double).certain, "five K are not automatically false with two decks")
	# Ordinary opening hand: all six K/wildcards are outside our hand, but
	# their owners are unknown. The distribution must deter a five-K bluff.
	view = follow(fixture([0, 1, 4, 8, 12, 16, 20, 24, 28, 32, 36, 44, 48, 49, 5, 9, 13, 17]), 13)
	var original = view.duplicate(true)
	var context = Strategy.context(view, 13)
	var five = Strategy.exposure(view, context, 5)
	var one = Strategy.exposure(view, context, 1)
	check(five.proof > 0.5 and five.call > one.call, "unknown large opposing hands make five-K bluff readily countable")
	for seed_value in range(160):
		var action = seeded(view, seed_value)
		check(action.type != "play" or action.cards.size() < 5, "does not blindly draw five false K from a random size range")
	check(view == original, "planning never mutates the cropped view or memory")
	view.memory.hands[1][13] = 3
	check(Strategy.exposure(view, Strategy.context(view, 13), 5).certain, "remembered three K in a recipient hand make five-K bluff knowingly exposed")
	check(Strategy.rank_actions(view).all(func(a): return a.type != "play" or a.cards.size() <= 3), "known holder excludes every disprovable bluff candidate")
	view.memory.pile.append({"seat": 1, "known": {13: 1}})
	check(Strategy.exposure(view, Strategy.context(view, 13), 3).certain, "known earlier K is also counted by the player who put it face down")
	var truth = fixture([40, 41, 42, 43, 52, 53])
	for seed_value in range(20):
		var action = seeded(truth, seed_value)
		check(action.type == "play" and action.rank == 13 and action.cards.size() == 6, "six truthful K including jokers remain a winning legal play")
	truth = follow(truth, 13)
	truth.can_challenge = true
	var rng = RandomNumberGenerator.new(); rng.seed = 7
	var finish_action = AI.choose(truth, rng)
	check(finish_action.get("cards", []).size() == 6, "truthful finish is not thrown away by a speculative challenge")
	var last_win = follow(fixture([40, 41]), 13)
	last_win.hand_counts[2] = 0; last_win.can_challenge = true
	check(AI.choose(last_win, rng).type == "challenge", "following an uncertain final hand would concede even with our own matching finish")
	last_win.memory.pile.append({"seat": 2, "before": {13: 1}, "expected": {13: 1}, "known": {13: 1}})
	check(AI.choose(last_win, rng).type != "challenge", "accept a final hand that is provably true")
	var reserve = fixture([40, 41, 42, 43, 0, 1, 4, 5, 52])
	check(Strategy.rank_actions(reserve)[0].cards.all(func(id): return Cards.rank(id) < 16), "ordinary group can go out while retaining a flexible joker")
	var small = follow(fixture([0, 4, 8, 12, 16, 20, 24, 28, 32, 36]), 13)
	var large = small.duplicate(true); large.pile_count = 32
	check(Strategy.rank_actions(small)[0].type == "play", "small pile permits a useful modest bluff when lacking the rank")
	check(Strategy.rank_actions(large)[0].type == "pass", "large pile makes passing preferable to unsupported bluff")
	for seed_value in range(40): check(seeded(large, seed_value).type == "pass", "near-score variety cannot reintroduce a costly bluff")
	var free = small.duplicate(true); free.config.challenge = "any"
	check(Strategy.exposure(free, Strategy.context(free, 13), 2).call > Strategy.exposure(small, Strategy.context(small, 13), 2).call, "free challenge accounts for more potential callers")
	var wary = small.duplicate(true)
	for seat in [1, 2]:
		wary.memory.profiles[seat].calls = 30; wary.memory.profiles[seat].opportunities = 30
	check(Strategy.rank_actions(wary)[0].analysis.score < Strategy.rank_actions(small)[0].analysis.score, "frequent callers lower the value of bluffing")
	# Equivalent whole-rank alternatives remain varied; inferior moves do not
	# receive an arbitrary 44 percent chance simply to meet a bluff quota.
	var alternatives = fixture([0, 1, 2, 3, 40, 41, 42, 43])
	var ranks = {}
	for seed_value in range(50):
		var action = seeded(alternatives, seed_value); ranks[action.rank] = true
		check(action.cards.size() == 4 and action.cards.all(func(id): return Cards.matches(id, action.rank)), "prefer a strong truthful group over random large lies")
	check(ranks.has(3) and ranks.has(13), "equally useful rank groups do not always break ties on the same rank")
	var cross_deck = follow(fixture([0, 54, 4, 58, 8, 62], 4), 13)
	check(Strategy.candidates(cross_deck).any(func(a): return a.cards == [0, 54]), "shedding groups keeps matching ranks together across both physical decks")
	# Whole candidate sets, not only selected actions, respect physical IDs,
	# rank following and the deliberate no-joker-in-lies convention.
	for players in range(3, 7):
		var game = Game.new()
		game.start(players + 713, {"players": players})
		for actor in range(players):
			var sample = game.view(actor); sample.phase = "playing"; sample.turn = actor
			for action in Strategy.rank_actions(sample):
				if action.type != "play": continue
				check(Cards.valid(action.cards, sample.decks) and action.cards.all(func(id): return id in sample.hand), "candidate uses unique owned physical cards")
				if not action.analysis.truthful: check(action.cards.all(func(id): return Cards.rank(id) < 16), "deliberate bluff does not squander a joker")
	print("BLUFF_STRATEGY_RESULT: %d failures; %d checks; five-K proof risk %.4f" % [failures.size(), checks, five.proof])
	quit(0 if failures.is_empty() else 1)
