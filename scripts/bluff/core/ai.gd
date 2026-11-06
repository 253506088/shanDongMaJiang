extends RefCounted
## Receives only a cropped seat view and its own random stream.
const Cards = preload("res://scripts/bluff/core/cards.gd")

static func choose(view: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var result = {"revision": view.revision}
	var hand: Array = view.hand
	var last: Dictionary = view.last
	if not last.is_empty():
		var matching = hand.filter(func(id): return Cards.matches(id, view.rank))
		var supply = 6 * view.decks # Four of each rank plus two wildcards per deck.
		var claimed = int(last.count)
		var impossible = claimed > supply - matching.size()
		# Public declaration volume is evidence, not knowledge of hidden cards.
		var volume = 0
		for play in view.trick: volume += int(play.count)
		var doubt = 0.12 + minf(0.42, float(volume) / (supply * 4.0))
		if view.hand_counts[last.seat] == 0: doubt += 0.28
		if view.pile_count > hand.size(): doubt -= 0.12
		if impossible or rng.randf() < doubt:
			result["type"] = "challenge"; return result
		if matching.is_empty() and rng.randf() < 0.58:
			result["type"] = "pass"; return result
		var cards = matching.slice(0, rng.randi_range(1, maxi(1, matching.size())))
		if cards.is_empty() or (rng.randf() < 0.22 and cards.size() < 4):
			var others = hand.filter(func(id): return id not in cards)
			if not others.is_empty(): cards.append(others[rng.randi_range(0, others.size() - 1)])
		result.merge({"type": "play", "cards": cards, "rank": view.rank})
	else:
		var best_rank = 3; var best: Array = []
		for rank in Cards.DECLARATIONS:
			var group = hand.filter(func(id): return Cards.matches(id, rank))
			if group.size() > best.size(): best = group; best_rank = rank
		var cards = best.slice(0, 4)
		if rng.randf() < 0.22:
			best_rank = Cards.DECLARATIONS[rng.randi_range(0, 12)]
			cards = hand.slice(0, mini(3, hand.size()))
		result.merge({"type": "play", "cards": cards, "rank": best_rank})
	return result
