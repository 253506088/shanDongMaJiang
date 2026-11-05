class_name DdzRecorder
extends RefCounted
## Public-information card counter: cards outside the viewer's hand that have
## not been played. Before bidding finishes, this includes the three bottom cards.
const Cards = preload("res://scripts/doudizhu/core/cards.gd")

static func remaining(view: Dictionary) -> Array:
	# Missing history must not silently masquerade as a fresh deck. The table
	# can show unavailable marks for incomplete debug/legacy fixture views.
	if not view.get("hand") is Array or not view.get("played_cards") is Array: return []
	var accounted: Array = view.hand + view.played_cards
	if not Cards.valid_cards(accounted): return []
	var counts: Array = [4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 1, 1]
	for card in accounted: counts[Cards.rank(card) - 3] -= 1
	return counts
