extends SceneTree

const Cards = preload("res://scripts/doudizhu/core/cards.gd")
const Rules = preload("res://scripts/doudizhu/core/rules.gd")
const EngineScript = preload("res://scripts/doudizhu/core/engine.gd")
const AI = preload("res://scripts/doudizhu/core/ai.gd")

var checks = 0
var failures: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("DOUDIZHU CORE FAIL: ", message)

func cards(ranks: Array) -> Array:
	var used = {}
	var output: Array = []
	for value in ranks:
		var count = int(used.get(value, 0))
		output.append(value + 36 if value >= 16 else (value - 3) * 4 + count)
		used[value] = count + 1
	return output

func submit(engine, action: Dictionary, seat: int = -1) -> bool:
	action.revision = engine.state.revision
	return engine.act(engine.state.turn if seat < 0 else seat, action)

func play(engine, ranks: Array) -> bool:
	var available = Cards.groups(engine.state.hands[engine.state.turn])
	var chosen: Array = []
	for value in ranks:
		if not available.has(value) or available[value].is_empty(): return false
		chosen.append(available[value].pop_front())
	return submit(engine, {"type": "play", "cards": chosen})

func rig(hands: Array, landlord: int = 0, base: int = 1):
	var engine = EngineScript.new(); engine.start(1)
	engine.state.hands = hands
	engine.state.phase = "playing"; engine.state.turn = landlord; engine.state.landlord = landlord
	engine.state.highest_bid = base
	return engine

func run() -> void:
	var started = Time.get_ticks_msec()
	_test_cards()
	_test_combinations()
	_test_generator()
	_test_bidding()
	_test_turns()
	_test_scores()
	_test_privacy()
	_test_ai()
	_test_simulations()
	print("DOUDIZHU_CORE_RESULT: %d checks, %d failures, %.2fs" % [checks, failures.size(), (Time.get_ticks_msec() - started) / 1000.0])
	quit(0 if failures.is_empty() else 1)

func _test_cards() -> void:
	check(Cards.deck().size() == 54 and Cards.valid_cards(Cards.deck()), "54 unique physical cards")
	check(Cards.rank(0) == 3 and Cards.rank(51) == 15 and Cards.rank(52) == 16 and Cards.rank(53) == 17, "rank coding")
	check(Cards.label(0) == "♠3" and Cards.label(53) == "大王", "readable labels")
	check(Cards.sort_cards([0, 53, 16, 52, 51]) == [53, 52, 51, 16, 0], "descending rank order")
	check(not Cards.valid_cards([0, 0]) and not Cards.valid_cards([-1]) and not Cards.valid_cards([54]) and not Cards.valid_cards([1.5]), "physical card validation")

func _test_combinations() -> void:
	var valid = [
		[[3], "single", 3], [[15, 15], "pair", 15], [[3, 3, 3], "triple", 3],
		[[7, 7, 7, 17], "triple_single", 7], [[8, 8, 8, 3, 3], "triple_pair", 8],
		[[10, 11, 12, 13, 14], "straight", 14], [[3, 3, 4, 4, 5, 5], "pair_chain", 5],
		[[3, 3, 3, 4, 4, 4], "airplane", 4],
		[[3, 3, 3, 4, 4, 4, 8, 9], "airplane_single", 4],
		[[3, 3, 3, 4, 4, 4, 8, 8], "airplane_single", 4],
		[[3, 3, 3, 4, 4, 4, 8, 8, 9, 9], "airplane_pair", 4],
		[[6, 6, 6, 6, 3, 4], "four_two_single", 6],
		[[6, 6, 6, 6, 3, 3], "four_two_single", 6],
		[[6, 6, 6, 6, 3, 3, 4, 4], "four_two_pair", 6],
		[[15, 15, 15, 15], "bomb", 15], [[16, 17], "rocket", 17],
		[[12, 12, 12, 13, 13, 13, 14, 14, 14], "airplane", 14],
		[[3, 3, 3, 4, 4, 4, 5, 5, 5, 8, 8, 9], "airplane_single", 5],
		[[3, 3, 3, 4, 4, 4, 5, 5, 5, 6, 6, 6, 7, 7, 7, 8, 8, 9, 9, 10], "airplane_single", 7],
		[[3, 3, 3, 4, 4, 4, 5, 5, 5, 6, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10], "airplane_pair", 6],
		[[3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12], "pair_chain", 12]
	]
	for example in valid:
		var combo = Rules.classify(cards(example[0]))
		check(combo.valid and combo.kind == example[1] and combo.main == example[2] and combo.length == example[0].size(), "classify " + str(example))
		check(Rules.beats(combo, {}), "valid combination can lead " + str(example[1]))
		check(not Rules.beats(combo, combo), "equal combination cannot beat itself " + str(example[1]))
		check(Rules.legal_plays(cards(example[0])).any(func(move): return move.size() == example[0].size()), "generator retains whole-hand finish " + str(example[1]))
	var invalid = [
		[], [3, 4], [3, 3, 4], [3, 3, 4, 4], [3, 3, 3, 4, 5],
		[3, 4, 5, 6], [11, 12, 13, 14, 15], [12, 13, 14, 15, 16],
		[3, 3, 4, 4], [13, 13, 14, 14, 15, 15],
		[3, 3, 3, 5, 5, 5], [14, 14, 14, 15, 15, 15],
		[3, 3, 3, 4, 4, 4, 16, 17],
		[3, 3, 3, 3, 4, 4, 4, 5],
		[3, 3, 3, 4, 4, 4, 8, 8, 8, 8],
		[3, 3, 3, 4, 4, 4, 5, 5, 5, 9, 9, 9],
		[3, 3, 3, 3, 16, 17], [3, 3, 3, 3, 4, 4, 4, 4]
	]
	for example in invalid: check(not Rules.classify(cards(example)).valid, "reject invalid " + str(example))
	check(not Rules.classify([0, 0]).valid and not Rules.classify([54]).valid, "classify rejects forged cards")
	check(Rules.beats(cards([4]), Rules.classify(cards([3]))) and not Rules.beats(cards([3]), Rules.classify(cards([4]))), "single comparison")
	check(Rules.beats(cards([4, 4, 4, 3]), Rules.classify(cards([3, 3, 3, 17]))), "triple body decides; attachment does not")
	check(not Rules.beats(cards([4, 5, 6, 7, 8, 9]), Rules.classify(cards([3, 4, 5, 6, 7]))), "sequence lengths must match")
	check(Rules.beats(cards([3, 3, 3, 3]), Rules.classify(cards([17]))), "small bomb beats large ordinary card")
	check(Rules.beats(cards([16, 17]), Rules.classify(cards([15, 15, 15, 15]))), "rocket beats greatest bomb")
	check(not Rules.beats(cards([15, 15, 15, 15]), Rules.classify(cards([16, 17]))), "rocket cannot be beaten")
	check(not Rules.beats(cards([4, 4, 4, 4, 3, 3]), Rules.classify(cards([3, 3, 3, 3]))), "four with attachments is not a bomb")

func _test_generator() -> void:
	var hands = [
		cards([3, 3, 3, 3, 4, 4, 4, 5, 5, 5, 6, 6, 7, 8, 9, 10, 11, 15, 16, 17]),
		cards([3, 3, 3, 4, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 10, 11, 12, 13, 14])
	]
	var found = {}
	for hand in hands:
		for move in Rules.legal_plays(hand):
			var combo = Rules.classify(move)
			check(combo.valid and Cards.valid_cards(move) and move.all(func(card): return hand.has(card)), "generated move is valid and owned")
			found[combo.kind] = true
	for kind in Rules.NAMES: check(found.has(kind), "generator covers " + kind)
	var hand = cards([4, 4, 4, 4, 5, 5, 5, 6, 6, 6, 7, 7, 8, 8, 16, 17])
	for target_cards in [[3], [3, 3], [3, 3, 3], [3, 3, 3, 8], [3, 3, 3, 8, 8], [3, 3, 3, 4, 4, 4], [3, 3, 3, 4, 4, 4, 8, 9], [3, 3, 3, 4, 4, 4, 8, 8, 9, 9], [3, 3, 3, 3]]:
		var target = Rules.classify(cards(target_cards))
		var moves = Rules.legal_plays(hand, target)
		check(not moves.is_empty(), "response exists " + str(target_cards))
		for move in moves: check(Rules.beats(move, target), "generated response beats target")
	check(Rules.legal_plays(hand, Rules.classify(cards([16, 17]))).is_empty(), "no response to rocket")
	# Enumerate every subset of smaller hands to ensure generator includes a
	# representative with the same rank multiset, independent of suit choice.
	for small in [cards([3, 3, 3, 4, 4, 4, 5, 5, 6, 7]), cards([3, 3, 3, 3, 4, 4, 5, 5, 16, 17])]:
		var represented = {}
		for move in Rules.legal_plays(small): represented[_rank_key(move)] = true
		for mask in range(1, 1 << small.size()):
			var chosen: Array = []
			for index in range(small.size()):
				if mask & (1 << index): chosen.append(small[index])
			if Rules.classify(chosen).valid: check(represented.has(_rank_key(chosen)), "subset move represented " + str(chosen))

func _rank_key(hand: Array) -> String:
	var ranks = hand.map(func(card): return Cards.rank(card)); ranks.sort()
	return str(ranks)

func _test_bidding() -> void:
	var engine = EngineScript.new(); engine.start(982, 1)
	check(engine.state.turn == 1 and engine.state.hands.map(func(hand): return hand.size()) == [17, 17, 17] and engine.state.bottom.size() == 3, "17/17/17 plus three bottom; chosen bidder")
	check(Cards.valid_cards(engine.state.hands[0] + engine.state.hands[1] + engine.state.hands[2] + engine.state.bottom), "shuffle conserves complete pack")
	var twin = EngineScript.new(); twin.start(982, 1)
	check(engine.state == twin.state, "seeded opening deterministic")
	var before = JSON.stringify(engine.state)
	check(not submit(engine, {"type": "bid", "value": 4}) and not submit(engine, {"type": "bid", "value": 1}, 0), "reject invalid bid and wrong seat")
	check(before == JSON.stringify(engine.state), "rejected bids leave authority untouched")
	check(submit(engine, {"type": "bid", "value": 1}) and engine.state.turn == 2, "one point bids")
	check(engine.view(0).landlord == -1 and engine.view(0).bottom.is_empty(), "roles wait until bidding actually finishes")
	check(not submit(engine, {"type": "bid", "value": 1}) and not submit(engine, {"type": "bid", "value": 0.5}), "must raise; bids must be integers")
	check(submit(engine, {"type": "bid", "value": 2}) and submit(engine, {"type": "bid", "value": 0}), "single clockwise bidding round")
	check(engine.state.phase == "playing" and engine.state.landlord == 2 and engine.state.turn == 2 and engine.state.hands[2].size() == 20 and engine.state.highest_bid == 2, "high bidder receives bottom and leads")
	engine.start(983)
	check(submit(engine, {"type": "bid", "value": 3}) and engine.state.phase == "playing" and engine.state.bids == [3, -1, -1], "three points ends bidding immediately")
	engine.start(984)
	var initial = engine.state.hands.duplicate(true)
	var revision = engine.state.revision
	for ignored in range(3): check(submit(engine, {"type": "bid", "value": 0}), "decline bid")
	check(engine.state.phase == "bidding" and engine.state.event.type == "redeal" and engine.state.bid_starter == 1 and engine.state.deal == 2, "all decline redeals and rotates first bidder")
	check(engine.state.hands != initial and engine.state.revision > revision and engine.state.bids == [-1, -1, -1], "redeal shuffles and keeps revisions monotonic")

func _test_turns() -> void:
	var engine = rig([cards([3, 3, 4]), cards([5, 5, 6]), cards([7, 7, 8])])
	check(not submit(engine, {"type": "pass"}), "leader cannot pass")
	var before = JSON.stringify(engine.state)
	check(not submit(engine, {"type": "play", "cards": [0, 0]}) and not submit(engine, {"type": "play", "cards": [53]}), "cannot duplicate or play unowned card")
	check(not submit(engine, {"type": "play", "cards": []}) and not submit(engine, {"type": "play", "cards": "3"}), "empty and malformed play rejected")
	check(before == JSON.stringify(engine.state), "rejected plays leave authority untouched")
	var stale = {"type": "play", "cards": cards([3]), "revision": engine.state.revision - 1}
	check(not engine.act(0, stale), "stale command rejected")
	check(play(engine, [3, 3]) and engine.state.turn == 1 and engine.state.target.kind == "pair", "valid pair advances turn")
	check(not play(engine, [6]), "single cannot follow pair")
	check(submit(engine, {"type": "pass"}) and engine.state.passes == 1, "first pass retains target")
	check(submit(engine, {"type": "pass"}) and engine.state.turn == 0 and engine.state.target.is_empty() and engine.state.passes == 0, "two passes returns lead and clears comparison")
	check(play(engine, [4]) and engine.state.phase == "finished", "new leader can change shape and finish")
	check(not submit(engine, {"type": "bid", "value": 3}, 0), "finished round refuses actions")
	engine = rig([cards([3, 9]), cards([4, 10]), cards([5, 11])])
	check(play(engine, [3]) and play(engine, [4]) and submit(engine, {"type": "pass"}) and submit(engine, {"type": "pass"}), "last successful player wins trick")
	check(engine.state.turn == 1 and engine.state.target.is_empty(), "trick initiative goes to overcaller")

func _test_scores() -> void:
	var engine = rig([cards([3]), cards([4]), cards([5])], 0, 2)
	check(play(engine, [3]) and engine.state.result.spring == "spring" and engine.state.result.multiplier == 2 and engine.state.result.scores == [8, -4, -4], "landlord spring score")
	engine = rig([cards([3, 5]), cards([4]), cards([6])], 0, 3)
	check(play(engine, [3]) and play(engine, [4]) and engine.state.result.spring == "counter_spring" and engine.state.result.scores == [-12, 6, 6], "farmer victory and counter spring scores both farmers")
	engine = rig([cards([3, 3, 3, 3]), cards([4]), cards([5])], 0, 1)
	check(play(engine, [3, 3, 3, 3]) and engine.state.bomb_count == 1 and engine.state.result.multiplier == 4 and engine.state.result.scores == [8, -4, -4], "bomb plus spring doubles twice")
	engine = rig([cards([16, 17]), cards([4]), cards([5])], 0, 3)
	check(play(engine, [16, 17]) and engine.state.bomb_count == 1 and engine.state.result.multiplier == 4 and engine.state.result.scores == [24, -12, -12], "rocket doubles and scores with bid")
	engine = rig([cards([3, 3, 3, 3, 4, 4]), cards([5]), cards([6])])
	check(play(engine, [3, 3, 3, 3, 4, 4]) and engine.state.bomb_count == 0 and engine.state.result.multiplier == 2, "four with two does not count as bomb")
	engine = rig([cards([3, 7]), cards([4, 8]), cards([5, 9])])
	check(play(engine, [3]) and play(engine, [4]) and play(engine, [5]) and play(engine, [7]), "ordinary landlord win path")
	check(engine.state.result.spring == "" and engine.state.result.scores == [2, -1, -1], "ordinary victory without spring")
	engine = rig([cards([3, 5, 9]), cards([4, 6]), cards([7, 10])])
	check(play(engine, [3]) and play(engine, [4]) and submit(engine, {"type": "pass"}) and play(engine, [5]) and play(engine, [6]), "ordinary farmer win path")
	check(engine.state.result.spring == "" and engine.state.result.scores == [-2, 1, 1], "two landlord plays excludes counter spring")

func _test_privacy() -> void:
	var engine = EngineScript.new(); engine.start(151)
	var view = engine.view(1)
	check(view.seat == 1 and view.hand == engine.state.hands[1] and view.bottom.is_empty() and not view.has("hands") and not view.has("reveal_hands"), "bidding view hides opponents and bottom")
	view.hand.clear(); view.bids[0] = 9
	check(engine.state.hands[1].size() == 17 and engine.state.bids[0] == -1, "view mutation cannot modify authority")
	submit(engine, {"type": "bid", "value": 3})
	view = engine.view(2)
	check(view.bottom.size() == 3 and view.hand_counts == [20, 17, 17] and not view.has("hands") and not view.has("reveal_hands"), "only bottom revealed during play")
	view.bottom.clear(); view.event.value = -1
	check(engine.state.bottom.size() == 3 and engine.state.event.value == 3, "nested public view copied")
	check(engine.view(-1).is_empty() and engine.view(3).is_empty(), "invalid seats get no state")
	engine = rig([cards([3]), cards([4]), cards([5])])
	play(engine, [3])
	check(engine.view(0).reveal_hands == engine.state.hands, "finished round reveals remaining cards")

func _test_ai() -> void:
	var engine = rig([cards([3, 9]), cards([4, 4, 10]), cards([5, 11])])
	play(engine, [3]); play(engine, [4])
	check(AI.choose(engine.view(2)).type == "pass", "farmer yields to partner with two cards left")
	check(AI.choose(engine.view(0)).is_empty(), "AI does not act out of turn")
	var input = engine.view(2)
	var before = input.duplicate(true)
	AI.choose(input)
	check(before == input, "AI does not mutate caller view")
	engine = rig([cards([3, 9]), cards([4, 10]), cards([5])])
	play(engine, [3]); play(engine, [4])
	var chosen = AI.choose(engine.view(2))
	check(chosen.type == "play" and chosen.cards == Cards.sort_cards(cards([5])), "farmer goes out over teammate when winning")

func _test_simulations() -> void:
	for seed_value in range(40):
		var engine = EngineScript.new(); engine.start(19000 + seed_value, seed_value % 3)
		var steps = 0
		while engine.state.phase != "finished" and steps < 500:
			var view = engine.view(engine.state.turn)
			var action = AI.choose(view)
			var old_revision = engine.state.revision
			var old_size = engine.state.hands.reduce(func(total, hand): return total + hand.size(), 0)
			var old_phase = engine.state.phase
			var accepted = engine.act(view.seat, action)
			check(accepted, "AI command accepted seed %d step %d" % [seed_value, steps])
			if not accepted: break
			check(engine.state.revision > old_revision, "revision advances every accepted action")
			var all_hands = engine.state.hands[0] + engine.state.hands[1] + engine.state.hands[2]
			check(Cards.valid_cards(all_hands), "simulation keeps physical cards disjoint")
			if old_phase == "playing":
				check(all_hands.size() == old_size - (action.cards.size() if action.type == "play" else 0), "only played cards removed")
			steps += 1
		check(engine.state.phase == "finished", "AI round terminates seed %d (%d actions)" % [seed_value, steps])
		if engine.state.phase == "finished":
			check(engine.state.result.scores.reduce(func(total, value): return total + value, 0) == 0, "round score is zero sum")
			check(engine.state.hands[engine.state.result.winner].is_empty(), "winner has no remaining cards")
