extends RefCounted
## Remember only the physical cards this seat personally played into dead piles.
const Cards = preload("res://scripts/bluff/core/cards.gd")

static func empty_counts() -> Dictionary:
	var counts = {}
	for rank in range(3, 18): counts[rank] = 0
	return counts

static func create(players: int) -> Dictionary:
	var own: Array = []
	for seat in range(players): own.append(empty_counts())
	return {"own": own}

static func clear_pile(recorder: Dictionary, plays: Array, pile: Array) -> void:
	var offset = 0
	for play in plays:
		for index in range(offset, offset + int(play.count)):
			recorder.own[play.seat][Cards.rank(pile[index])] += 1
		offset += int(play.count)

static func view(recorder: Dictionary, seat: int) -> Dictionary:
	var known: Dictionary = recorder.own[seat].duplicate()
	return {"counts": known, "total": known.values().reduce(func(a, b): return a + b, 0)}
