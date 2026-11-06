extends RefCounted
## Physical IDs 0..107; the second deck shares artwork, never identity.
const LABELS = ["3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A", "2"]
const DECLARATIONS = [14, 15, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]

static func rank(id: int) -> int:
	var face = id % 54
	return 16 + face - 52 if face >= 52 else 3 + int(face / 4)

static func label(value: int) -> String:
	return LABELS[value - 3] if value >= 3 and value <= 15 else "王"

static func matches(id: int, declared: int) -> bool:
	return rank(id) >= 16 or rank(id) == declared

static func sorted(hand: Array) -> Array:
	var result = hand.duplicate()
	result.sort_custom(func(a, b): return rank(a) > rank(b) if rank(a) != rank(b) else a > b)
	return result

static func valid(cards: Array, decks: int) -> bool:
	var seen = {}
	for id in cards:
		if typeof(id) != TYPE_INT or id < 0 or id >= 54 * decks or seen.has(id): return false
		seen[id] = true
	return true
