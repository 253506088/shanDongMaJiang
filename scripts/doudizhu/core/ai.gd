class_name DdzAI
extends RefCounted
## A lightweight, deterministic partner-aware bot. It consumes only seat view.
const Cards = preload("res://scripts/doudizhu/core/cards.gd")
const Rules = preload("res://scripts/doudizhu/core/rules.gd")

static func choose(view: Dictionary) -> Dictionary:
	if view.is_empty() or view.get("phase") == "finished": return {}
	var seat = int(view.get("seat", view.turn))
	if seat != view.turn: return {}
	if view.phase == "bidding": return {"type": "bid", "value": _bid_value(view), "revision": view.revision}
	var moves = Rules.legal_plays(view.hand, view.target)
	if moves.is_empty(): return {"type": "pass", "revision": view.revision}
	for cards in moves:
		if cards.size() == view.hand.size(): return {"type": "play", "cards": cards, "revision": view.revision}
	var teammate = seat != view.landlord and not view.target.is_empty() and view.target_seat != view.landlord and view.target_seat != seat
	if teammate:
		# Preserve a farmer's winning initiative; never bomb one's partner.
		if view.hand_counts[view.target_seat] <= 2 or view.hand_counts[view.landlord] > 2:
			return {"type": "pass", "revision": view.revision}
	var danger = false
	for other in range(3):
		if other != seat and (seat == view.landlord or other == view.landlord) and view.hand_counts[other] <= 2: danger = true
	var best: Array = moves[0]
	var best_score = -INF
	for cards in moves:
		var combo = Rules.classify(cards)
		var remaining = view.hand.duplicate()
		for card in cards: remaining.erase(card)
		var score = float(cards.size()) * 2.4 - _burden(remaining) * 1.4 - float(combo.main) * 0.16
		if combo.kind in ["bomb", "rocket"]: score -= 15.0 if not danger else 3.0
		if teammate: score -= 12.0
		if danger and combo.kind == "single": score += combo.main * 0.7
		if danger and combo.kind == "pair": score += combo.main * 0.5
		if score > best_score: best = cards; best_score = score
	return {"type": "play", "cards": best, "revision": view.revision}

static func _bid_value(view: Dictionary) -> int:
	var groups = Cards.groups(view.hand)
	var strength = 0.0
	for value in groups:
		var count = groups[value].size()
		if count == 4: strength += 4.0
		elif count == 3: strength += 1.6
		if value == 17: strength += 3.5
		elif value == 16: strength += 2.0
		elif value == 15: strength += count * 1.4
		elif value == 14: strength += count * 0.6
	if groups.has(16) and groups.has(17): strength += 2.0
	var desired = 3 if strength >= 10.0 else (2 if strength >= 7.0 else (1 if strength >= 4.0 else 0))
	return desired if desired > view.highest_bid else 0

static func _burden(cards: Array) -> float:
	var groups = Cards.groups(cards)
	var burden = float(groups.size())
	for value in groups:
		if groups[value].size() == 1 and value < 12: burden += 0.75
		if groups[value].size() == 3: burden -= 0.3
		if groups[value].size() == 4: burden -= 0.6
	# Reward retained sequences without enumerating the rest of the game tree.
	for count in [1, 2, 3]:
		var chain = 0
		for value in range(3, 16):
			if value < 15 and groups.has(value) and groups[value].size() >= count: chain += 1
			else:
				if chain >= (5 if count == 1 else (3 if count == 2 else 2)): burden -= (chain - 1) * 0.45
				chain = 0
	return burden
