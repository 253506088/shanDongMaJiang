extends RefCounted
## Enumerate plays, then compare the resulting hand and the cost of being called.
## Like MahjongAI.rank(), this only consumes the acting seat's cropped view.
const Cards = preload("res://scripts/bluff/core/cards.gd")
const Knowledge = preload("res://scripts/bluff/core/knowledge.gd")
const SHAPE_WEIGHT = 1.15
const WILD_RESERVE = 1.65
const CLOSE_SCORE = 0.55

static func total(counts: Dictionary) -> int:
	var result = 0
	for count in counts.values(): result += int(count)
	return result

static func matching(counts: Dictionary, rank: int) -> int:
	return int(counts.get(rank, 0)) + int(counts.get(16, 0)) + int(counts.get(17, 0))

static func groups(counts: Dictionary) -> int:
	var result = 0
	for rank in Cards.DECLARATIONS:
		if counts.get(rank, 0) > 0: result += 1
	return result

static func combination(n: int, k: int) -> float:
	if k < 0 or k > n: return 0.0
	var result = 1.0
	for i in range(1, mini(k, n - k) + 1): result *= float(n - i + 1) / i
	return result

static func distribution(pool: int, matches: int, slots: int) -> Array:
	# Hypergeometric marginal: unknown cards are exchangeable, not secretly read.
	matches = clampi(matches, 0, pool); slots = clampi(slots, 0, pool)
	var result: Array = []
	var denominator = combination(pool, slots)
	for count in range(matches + 1):
		result.append(combination(matches, count) * combination(pool - matches, slots - count) / denominator)
	return result

static func context(view: Dictionary, rank: int) -> Dictionary:
	var memory: Dictionary = view.get("memory", {})
	var known_hands: Array = memory.get("hands", [])
	var excluded = Knowledge.counts(view.hand)
	var pool = int(view.decks) * 54 - view.hand.size()
	var remaining = int(view.decks) * 6 - matching(excluded, rank)
	var known_places: Array = [memory.get("dead", view.get("recorder", {}).get("counts", {}))]
	for entry in memory.get("pile", []): known_places.append(entry.known)
	for seat in range(known_hands.size()):
		if seat != int(view.seat): known_places.append(known_hands[seat])
	for place in known_places:
		pool -= total(place); remaining -= matching(place, rank)
	pool = maxi(0, pool); remaining = clampi(remaining, 0, pool)
	var opponents: Array = []
	var profiles: Array = memory.get("profiles", [])
	for offset in range(1, view.hand_counts.size()):
		var seat = (int(view.seat) + offset) % view.hand_counts.size()
		var known: Dictionary = known_hands[seat] if seat < known_hands.size() else {}
		var blockers = matching(known, rank)
		# A player also knows their own earlier face-down cards. Only count
		# identities this observer can actually establish, not their claims.
		for entry in memory.get("pile", []):
			if int(entry.seat) == seat: blockers += matching(entry.known, rank)
		var slots = maxi(0, int(view.hand_counts[seat]) - total(known))
		var profile: Dictionary = profiles[seat] if seat < profiles.size() else {}
		opponents.append({"known": blockers, "size": int(view.hand_counts[seat]),
			"distribution": distribution(pool, remaining, slots),
			"call_rate": (1.0 + profile.get("calls", 0)) / (4.0 + profile.get("opportunities", 0))})
	var own_profile: Dictionary = profiles[view.seat] if int(view.seat) < profiles.size() else {}
	return {"opponents": opponents, "reputation": (2.0 + own_profile.get("lies", 0)) / (5.0 + own_profile.get("revealed", 0))}

static func exposure(view: Dictionary, rank_context: Dictionary, amount: int, finish: bool = false) -> Dictionary:
	var threshold = int(view.decks) * 6 - amount + 1
	var survival = 1.0; var proof_survival = 1.0; var reach = 1.0
	var certain = false
	for opponent in rank_context.opponents:
		var proof = 0.0
		for count in range(opponent.distribution.size()):
			if count + opponent.known >= threshold: proof += opponent.distribution[count]
		if opponent.known >= threshold: certain = true
		# Unknown-dead cards remain in the distribution pool. We never assume
		# everybody knows the bot's private dead cards or its old hidden plays.
		var ordinary_call = 0.20 + clampf(opponent.call_rate - 0.25, -0.12, 0.35)
		ordinary_call += clampf(rank_context.reputation - 0.4, -0.10, 0.20)
		ordinary_call += 0.085 * (amount - 1) / int(view.decks)
		ordinary_call += 0.30 if finish else 0.0
		ordinary_call -= minf(0.14, float(view.pile_count + amount) / maxi(1, opponent.size) * 0.07)
		ordinary_call = clampf(ordinary_call, 0.04, 0.90)
		survival *= 1.0 - reach * (proof + (1.0 - proof) * ordinary_call)
		proof_survival *= 1.0 - reach * proof
		# In turn order, a follow covers this claim; only passes leave it open.
		# Free challenge exposes it to every seat. Consent is deliberately not
		# presumed to be denied: that would encourage visibly absurd lies.
		if view.get("config", {}).get("challenge", "turn") != "any": reach *= 0.45
	return {"call": clampf(1.0 - survival, 0, 1), "proof": clampf(1.0 - proof_survival, 0, 1), "certain": certain}

static func _add(plays: Array, seen: Dictionary, cards: Array, rank: int) -> void:
	if cards.is_empty(): return
	var ids = cards.duplicate(); ids.sort()
	var key = str(rank) + ":" + str(ids)
	if seen.has(key): return
	seen[key] = true
	plays.append({"type": "play", "cards": ids, "rank": rank})

static func candidates(view: Dictionary) -> Array:
	var plays: Array = []; var seen = {}
	var hand: Array = view.hand
	var counts = Knowledge.counts(hand)
	var ordinary = hand.filter(func(id): return Cards.rank(id) < 16)
	# Keep same-rank cards together when shedding small groups.
	ordinary.sort_custom(func(a, b):
		var ar = Cards.rank(a); var br = Cards.rank(b)
		if counts[ar] != counts[br]: return counts[ar] < counts[br]
		return ar < br if ar != br else a < b)
	var wild = hand.filter(func(id): return Cards.rank(id) >= 16)
	var ranks = Cards.DECLARATIONS if view.last.is_empty() else [int(view.rank)]
	for rank in ranks:
		var natural = ordinary.filter(func(id): return Cards.rank(id) == rank)
		for size in range(natural.size() + 1):
			for jokers in range(wild.size() + 1):
				_add(plays, seen, natural.slice(0, size) + wild.slice(0, jokers), rank)
		var wrong = ordinary.filter(func(id): return Cards.rank(id) != rank)
		if wrong.is_empty(): continue
		# Larger lies are legal for humans, but everyone can disprove >6/12.
		for size in range(1, mini(ordinary.size(), int(view.decks) * 6) + 1):
			var shed: Array = [wrong[0]]
			for id in ordinary:
				if shed.size() >= size: break
				if id not in shed: shed.append(id)
			_add(plays, seen, shed, rank)
			var mixed: Array = [wrong[0]]
			for id in natural + wrong:
				if mixed.size() >= size: break
				if id not in mixed: mixed.append(id)
			_add(plays, seen, mixed, rank)
	return plays

static func rank_actions(view: Dictionary) -> Array:
	var ranked: Array = []; var contexts = {}; var risks = {}
	var own = Knowledge.counts(view.hand)
	var before_groups = groups(own)
	for play in candidates(view):
		var rank = int(play.rank); var amount = play.cards.size()
		var removed = Knowledge.counts(play.cards)
		var truthful = matching(removed, rank) == amount
		var after = own.duplicate()
		for value in removed: after[value] -= removed[value]
		var left = view.hand.size() - amount
		var shape_gain = SHAPE_WEIGHT * (before_groups - groups(after))
		var reserve_cost = WILD_RESERVE * (removed[16] + removed[17]) if left > 0 else 0.0
		var gain = amount + shape_gain - reserve_cost
		var risk = {"call": 0.0, "proof": 0.0, "certain": false}
		var score = gain
		if not truthful:
			if not contexts.has(rank): contexts[rank] = context(view, rank)
			var risk_key = str(rank) + ":" + str(amount)
			if not risks.has(risk_key): risks[risk_key] = exposure(view, contexts[rank], amount, left == 0)
			risk = risks[risk_key]
			# Do not knowingly bluff into a hand that disproves it, or a likely
			# immediate counting proof. Uncertain, modest bluffs remain candidates.
			if risk.certain or risk.proof >= 0.50: continue
			# A caught play returns these cards AND the existing pile. A tempo
			# cost also matters on an empty table, where net card loss is zero.
			score = (1.0 - risk.call) * gain - risk.call * (view.pile_count + 1.8)
		if left == 0: score += 1000.0 if truthful else (1.0 - risk.call) * 5.0
		# A surviving one-rank hand can finish on its next truthful lead.
		elif groups(after) <= 1: score += (1.0 - risk.call) * 0.8
		play["revision"] = view.revision
		play["analysis"] = {"score": score, "truthful": truthful, "call_risk": risk.call,
			"proof_risk": risk.proof, "groups_left": groups(after), "cards_left": left}
		ranked.append(play)
	if not view.last.is_empty():
		# Passing is preferable to a negative-value bluff into a large pile.
		ranked.append({"revision": view.revision, "type": "pass", "analysis": {"score": 0.0}})
	# A candidate's identity supplies stable tie order; randomness is used only
	# among close scores by choose(), never before evaluating the alternatives.
	for index in range(ranked.size()): ranked[index].analysis["order"] = index
	ranked.sort_custom(func(a, b):
		return a.analysis.score > b.analysis.score if a.analysis.score != b.analysis.score else a.analysis.order < b.analysis.order)
	return ranked

static func choose(view: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var ranked = rank_actions(view)
	if ranked.is_empty(): return {}
	var best = float(ranked[0].analysis.score)
	var choices = ranked.filter(func(play): return play.analysis.score >= best - CLOSE_SCORE)
	var selected: Dictionary = choices[rng.randi_range(0, choices.size() - 1)].duplicate(true)
	selected.erase("analysis")
	return selected
