extends RefCounted
## Receives one seat's knowledge, never the authority's hidden state.
const Cards = preload("res://scripts/bluff/core/cards.gd")
const Knowledge = preload("res://scripts/bluff/core/knowledge.gd")
const Strategy = preload("res://scripts/bluff/core/strategy.gd")

static func matching(counts: Dictionary, rank: int) -> float:
	return float(counts.get(rank, 0)) + float(counts.get(16, 0)) + float(counts.get(17, 0))

static func assessment(view: Dictionary) -> Dictionary:
	if view.last.is_empty(): return {"false_chance": 0.0, "certain": false, "reason": "no_claim"}
	var actor = int(view.last.seat); var rank = int(view.rank); var claimed = int(view.last.count)
	var memory: Dictionary = view.get("memory", {})
	var available = 6.0 * view.decks - matching(Knowledge.counts(view.hand), rank)
	var known_dead: Dictionary = memory.get("dead", view.get("recorder", {}).get("counts", {}))
	available -= matching(known_dead, rank)
	var known_hands: Array = memory.get("hands", [])
	for seat in range(known_hands.size()):
		if seat != actor and seat != int(view.seat): available -= matching(known_hands[seat], rank)
	var pile: Array = memory.get("pile", [])
	for entry in pile.slice(0, maxi(0, pile.size() - 1)):
		available -= matching(entry.known, rank)
	var previous_size = int(view.hand_counts[actor]) + claimed
	var before: Dictionary = {}; var expected: Dictionary = {}; var placed: Dictionary = {}
	if not pile.is_empty():
		before = pile.back().before; expected = pile.back().expected; placed = pile.back().known
	var known_matches = matching(before, rank)
	var known_other = float(before.values().reduce(func(a, b): return a + b, 0)) - known_matches
	var possible = minf(available, previous_size - known_other)
	var proved_other = float(placed.values().reduce(func(a, b): return a + b, 0)) - matching(placed, rank)
	if claimed > possible or proved_other > 0:
		return {"false_chance": 1.0, "certain": true, "reason": "impossible", "possible": possible}
	if matching(placed, rank) >= claimed:
		return {"false_chance": 0.0, "certain": true, "reason": "known_true", "possible": possible}
	var profiles: Array = memory.get("profiles", [])
	var profile: Dictionary = profiles[actor] if not profiles.is_empty() else {}
	# Revealed samples have selection bias, so their influence is bounded.
	var habit = (2.0 + profile.get("lies", 0)) / (5.0 + profile.get("revealed", 0))
	var doubt = 0.38 + clampf(habit - 0.4, -0.16, 0.22)
	var outside = maxi(previous_size, int(view.hand_counts.reduce(func(a, b): return a + b, 0)) - view.hand.size() + claimed)
	var expected_capacity = maxf(known_matches, available * previous_size / float(outside))
	doubt += clampf((claimed - expected_capacity) / maxf(1, expected_capacity), -0.5, 1.5) * 0.20
	doubt -= 0.22 * minf(1, known_matches / claimed)
	# Keep a softer trace after unknown cards could have spent a remembered K.
	doubt -= 0.10 * minf(1, maxf(0, matching(expected, rank) - known_matches) / claimed)
	var earlier_claims = maxi(0, int(view.pile_count) - claimed)
	doubt += minf(0.12, earlier_claims / (60.0 * view.decks))
	return {"false_chance": clampf(doubt, 0.05, 0.90), "certain": false, "reason": "inference", "possible": possible}

static func wants_challenge(view: Dictionary, rng: RandomNumberGenerator) -> bool:
	if view.last.is_empty() or not (view.get("can_challenge", true) or view.get("can_request_challenge", false)): return false
	var evidence = assessment(view)
	# Following an empty hand concedes immediately. Otherwise a truthful
	# finish on our turn wins even if challenged; do not gamble it on a call.
	if view.hand_counts[view.last.seat] > 0 and int(view.get("turn", -1)) == int(view.seat) and view.hand.all(func(id): return Cards.matches(id, view.rank)): return false
	if evidence.certain: return evidence.false_chance > 0.5
	if view.hand_counts[view.last.seat] == 0: return true
	var chance = float(evidence.false_chance)
	# Collecting a large pile is costly; a proof still overrides this caution.
	chance -= minf(0.20, float(view.pile_count) / maxi(1, view.hand.size()) * 0.08)
	return rng.randf() < clampf(chance, 0.04, 0.94)

static func choose(view: Dictionary, rng: RandomNumberGenerator, check_call: bool = true) -> Dictionary:
	if view.phase == "permission": return permission_response(view)
	if check_call and wants_challenge(view, rng): return challenge_action(view)
	return Strategy.choose(view, rng)

static func challenge_action(view: Dictionary) -> Dictionary:
	return {"revision": view.revision, "type": "challenge" if view.can_challenge else "request_challenge"}

static func permission_response(view: Dictionary) -> Dictionary:
	# The protected seat decides from its own information. A likely genuine
	# claim may leave a path to follow and finish; clear evidence can justify opening.
	var evidence = assessment(view)
	var can_finish = view.hand.all(func(id): return Cards.matches(id, view.rank))
	var allow = evidence.false_chance >= (0.85 if can_finish else 0.60)
	return {"type": "challenge_permission", "allow": allow, "revision": view.revision}
