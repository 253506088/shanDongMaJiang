extends RefCounted
## Per-observer memory. Inputs are public moves/reveals and that observer's own
## cards only. Bounds are facts; likely counts are deliberately uncertain.
const Cards = preload("res://scripts/bluff/core/cards.gd")
const Recorder = preload("res://scripts/bluff/core/recorder.gd")

static func counts(cards: Array) -> Dictionary:
	var result = Recorder.empty_counts()
	for id in cards: result[Cards.rank(id)] += 1
	return result

static func create(players: int) -> Array:
	var observers: Array = []
	for observer in range(players):
		var hands: Array = []; var likely: Array = []; var profiles: Array = []
		for seat in range(players):
			hands.append(Recorder.empty_counts()); likely.append(Recorder.empty_counts())
			profiles.append({"revealed": 0, "lies": 0, "plays": 0, "calls": 0, "opportunities": 0})
		observers.append({"hands": hands, "likely": likely, "dead": Recorder.empty_counts(), "pile": [], "profiles": profiles})
	return observers

static func played(memory: Array, seat: int, cards: Array, rank: int, hand_size: int) -> void:
	for observer in range(memory.size()):
		var m: Dictionary = memory[observer]
		var before: Dictionary = m.hands[seat].duplicate()
		var expected: Dictionary = m.likely[seat].duplicate()
		var known = counts(cards) if observer == seat else Recorder.empty_counts()
		for value in before:
			if observer != seat:
				known[value] = maxi(0, before[value] - (hand_size - cards.size()))
			m.hands[seat][value] = maxi(0, before[value] - (known[value] if observer == seat else cards.size()))
			# A hidden play can contain ANY rank. A matching declaration makes
			# that rank likelier to have left, but never certifies its identity.
			var weight = 1.7 if value == rank or value >= 16 else 0.8
			m.likely[seat][value] = maxf(m.hands[seat][value], expected[value] * maxf(0, 1.0 - weight * cards.size() / float(hand_size)))
		m.pile.append({"seat": seat, "known": known, "before": before, "expected": expected, "hand_size": hand_size})
		m.profiles[seat].plays += 1

static func responded(memory: Array, seat: int, called: bool) -> void:
	for m in memory:
		m.profiles[seat].opportunities += 1
		if called: m.profiles[seat].calls += 1

static func revealed(memory: Array, actor: int, loser: int, cards: Array, truthful: bool) -> void:
	var actual = counts(cards)
	for m in memory:
		var last: Dictionary = m.pile.back()
		last.known = actual.duplicate()
		for rank in actual:
			# Restore bounds lost to uncertainty about this specific hidden play.
			m.hands[actor][rank] = maxi(0, last.before[rank] - actual[rank])
			m.likely[actor][rank] = maxf(m.hands[actor][rank], last.expected[rank] - actual[rank])
		for play in m.pile:
			for rank in play.known:
				m.hands[loser][rank] += play.known[rank]
				m.likely[loser][rank] += play.known[rank]
		m.profiles[actor].revealed += 1
		if not truthful: m.profiles[actor].lies += 1
		m.pile.clear()

static func cleared(memory: Array) -> void:
	for m in memory:
		for play in m.pile:
			for rank in play.known: m.dead[rank] += play.known[rank]
		m.pile.clear()

static func sync_own(memory: Array, seat: int, hand: Array) -> void:
	memory[seat].hands[seat] = counts(hand)
	memory[seat].likely[seat] = counts(hand)

static func view(memory: Array, seat: int, hand: Array) -> Dictionary:
	var result: Dictionary = memory[seat].duplicate(true)
	result.hands[seat] = counts(hand)
	result.likely[seat] = counts(hand)
	return result
