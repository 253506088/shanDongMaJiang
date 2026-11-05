class_name DdzCards
extends RefCounted
## Physical cards are independent of the Mahjong tile encoding.
## 0..51 = 3..2 in spade/heart/club/diamond order; 52/53 = jokers.

const SUITS = ["♠", "♥", "♣", "♦"]
const RANKS = ["3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A", "2", "小王", "大王"]

static func rank(card: int) -> int:
	return 16 + card - 52 if card >= 52 else 3 + int(card / 4)

static func suit(card: int) -> int:
	return -1 if card >= 52 else card % 4

static func rank_label(value: int) -> String:
	return RANKS[value - 3] if value >= 3 and value <= 17 else "?"

static func label(card: int) -> String:
	if card < 0 or card > 53: return "?"
	return rank_label(rank(card)) if card >= 52 else SUITS[suit(card)] + rank_label(rank(card))

static func sort_cards(cards: Array) -> Array:
	var result = cards.duplicate()
	result.sort_custom(func(a, b): return a > b)
	return result

static func deck() -> Array:
	return range(54)

static func valid_cards(cards: Array) -> bool:
	var seen = {}
	for card in cards:
		if typeof(card) != TYPE_INT or card < 0 or card > 53 or seen.has(card): return false
		seen[card] = true
	return true

static func groups(cards: Array) -> Dictionary:
	var result = {}
	for card in sort_cards(cards):
		var value = rank(card)
		if not result.has(value): result[value] = []
		result[value].append(card)
	return result
