class_name DdzEngine
extends RefCounted
## Synchronous local authority; hidden hands never leave view(seat).
const Cards = preload("res://scripts/doudizhu/core/cards.gd")
const Rules = preload("res://scripts/doudizhu/core/rules.gd")

var state: Dictionary = {}
var _rng = RandomNumberGenerator.new()

func start(seed_value: int, first_bidder: int = 0) -> void:
	_rng.seed = seed_value
	state = {"revision": 0, "deal": 0}
	_deal(posmod(first_bidder, 3), false)

func act(seat: int, action: Dictionary) -> bool:
	if state.is_empty() or seat < 0 or seat > 2 or seat != state.turn or state.phase == "finished": return false
	if action.has("revision") and (typeof(action.revision) != TYPE_INT or action.revision != state.revision): return false
	var type = str(action.get("type", ""))
	if state.phase == "bidding": return _bid(seat, action) if type == "bid" else false
	if type == "pass": return _pass(seat)
	if type != "play" or not action.get("cards") is Array: return false
	var cards: Array = action.cards
	if not cards.all(func(card): return state.hands[seat].has(card)): return false
	var combo = Rules.classify(cards)
	if not Rules.beats(combo, state.target): return false
	for card in cards: state.hands[seat].erase(card)
	state.played_cards.append_array(combo.cards)
	state.revision += 1
	state.play_counts[seat] += 1
	state.passes = 0
	state.target = combo
	state.target_seat = seat
	state.event = {"type": "play", "seat": seat, "cards": combo.cards.duplicate(), "combo": combo.duplicate(true)}
	state.event["remaining"] = state.hands[seat].size()
	state.last_actions[seat] = state.event.duplicate(true)
	if combo.kind in ["bomb", "rocket"]:
		state.bomb_count += 1
		state.multiplier *= 2
	if state.hands[seat].is_empty(): _finish(seat)
	else: state.turn = (seat + 1) % 3
	return true

func view(seat: int) -> Dictionary:
	if state.is_empty() or seat < 0 or seat > 2: return {}
	var output = {}
	for key in ["phase", "revision", "turn", "landlord", "highest_bid", "bids", "bid_starter", "target", "target_seat", "passes", "last_actions", "event", "multiplier", "bomb_count", "result", "play_counts", "deal", "played_cards"]:
		output[key] = state[key].duplicate(true) if state[key] is Array or state[key] is Dictionary else state[key]
	output.seat = seat
	output.hand = state.hands[seat].duplicate()
	output.hand_counts = state.hands.map(func(hand): return hand.size())
	output.bottom = [] if state.phase == "bidding" else state.bottom.duplicate()
	if state.phase == "finished": output.reveal_hands = state.hands.duplicate(true)
	return output

func _deal(first_bidder: int, redeal: bool) -> void:
	var revision = state.revision + 1
	var deal = state.deal + 1
	var deck = Cards.deck()
	for index in range(deck.size() - 1, 0, -1):
		var other = _rng.randi_range(0, index)
		var card = deck[index]; deck[index] = deck[other]; deck[other] = card
	var hands: Array = [[], [], []]
	for index in range(51): hands[index % 3].append(deck[index])
	for seat in range(3): hands[seat] = Cards.sort_cards(hands[seat])
	state = {
		"phase": "bidding", "revision": revision, "deal": deal, "hands": hands,
		"bottom": deck.slice(51), "turn": first_bidder, "landlord": -1,
		"highest_bid": 0, "bid_starter": first_bidder, "bids": [-1, -1, -1],
		"target": {}, "target_seat": -1, "passes": 0, "last_actions": [{}, {}, {}],
		"event": {"type": "redeal" if redeal else "deal", "seat": first_bidder},
		"multiplier": 1, "bomb_count": 0, "result": {}, "play_counts": [0, 0, 0], "played_cards": []
	}

func _bid(seat: int, action: Dictionary) -> bool:
	var value = action.get("value", -1)
	if typeof(value) != TYPE_INT or value < 0 or value > 3 or (value != 0 and value <= state.highest_bid): return false
	state.revision += 1
	state.bids[seat] = value
	state.event = {"type": "bid", "seat": seat, "value": value}
	state.last_actions[seat] = state.event.duplicate(true)
	if value > 0: state.highest_bid = value
	if value == 3 or not state.bids.has(-1):
		if state.highest_bid == 0: _deal((state.bid_starter + 1) % 3, true)
		else:
			state.landlord = state.bids.find(state.highest_bid)
			state.phase = "playing"
			state.turn = state.landlord
			state.hands[state.landlord].append_array(state.bottom)
			state.hands[state.landlord] = Cards.sort_cards(state.hands[state.landlord])
			state.last_actions = [{}, {}, {}]
	else: state.turn = (seat + 1) % 3
	return true

func _pass(seat: int) -> bool:
	if state.target.is_empty() or state.target_seat == seat: return false
	state.revision += 1
	state.passes += 1
	state.event = {"type": "pass", "seat": seat}
	state.last_actions[seat] = state.event.duplicate(true)
	state.turn = (seat + 1) % 3
	if state.passes == 2:
		state.turn = state.target_seat
		state.target = {}
		state.target_seat = -1
		state.passes = 0
		state.last_actions = [{}, {}, {}]
	return true

func _finish(winner: int) -> void:
	var landlord_won = winner == state.landlord
	var spring = ""
	if landlord_won:
		var farmer_moves = 0
		for seat in range(3):
			if seat != state.landlord: farmer_moves += state.play_counts[seat]
		if farmer_moves == 0: spring = "spring"
	elif state.play_counts[state.landlord] == 1: spring = "counter_spring"
	if not spring.is_empty(): state.multiplier *= 2
	var unit = state.highest_bid * state.multiplier
	var scores = [0, 0, 0]
	for seat in range(3): scores[seat] = unit * (2 if seat == state.landlord else -1) * (1 if landlord_won else -1)
	state.phase = "finished"
	state.turn = -1
	state.result = {"winner": winner, "landlord_won": landlord_won, "base": state.highest_bid, "multiplier": state.multiplier, "spring": spring, "scores": scores}
