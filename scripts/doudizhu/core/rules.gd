class_name DdzRules
extends RefCounted
## Common three-player, one-pack Dou Dizhu. See docs/doudizhu-rules.md
## for the deliberately fixed wing variants. No scene-tree dependencies.

const Cards = preload("res://scripts/doudizhu/core/cards.gd")
const NAMES = {
	"single": "单张", "pair": "对子", "triple": "三张", "triple_single": "三带一",
	"triple_pair": "三带一对", "straight": "顺子", "pair_chain": "连对", "airplane": "飞机",
	"airplane_single": "飞机带单", "airplane_pair": "飞机带对", "four_two_single": "四带二",
	"four_two_pair": "四带两对", "bomb": "炸弹", "rocket": "王炸"
}

static func classify(cards: Array) -> Dictionary:
	var invalid = {"valid": false, "kind": "", "name": "请选择合法牌型", "main": -1, "length": cards.size(), "chain": 0, "cards": []}
	if cards.is_empty() or cards.size() > 20 or not Cards.valid_cards(cards): return invalid
	var groups = Cards.groups(cards)
	var ranks = groups.keys(); ranks.sort()
	var n = cards.size()
	if n == 1: return _combo("single", ranks[0], cards)
	if n == 2 and groups.has(16) and groups.has(17): return _combo("rocket", 17, cards)
	if ranks.size() == 1:
		if n == 2: return _combo("pair", ranks[0], cards)
		if n == 3: return _combo("triple", ranks[0], cards)
		if n == 4: return _combo("bomb", ranks[0], cards)
	if n == 4 or n == 5:
		for value in ranks:
			if groups[value].size() == 3:
				if n == 4: return _combo("triple_single", value, cards)
				if ranks.size() == 2: return _combo("triple_pair", value, cards)
	if n >= 5 and ranks.size() == n and _consecutive(ranks):
		return _combo("straight", ranks.back(), cards, n)
	if n >= 6 and n % 2 == 0 and ranks.size() == int(n / 2) and _all_count(groups, 2) and _consecutive(ranks):
		return _combo("pair_chain", ranks.back(), cards, ranks.size())
	if n >= 6 and n % 3 == 0 and ranks.size() == int(n / 3) and _all_count(groups, 3) and _consecutive(ranks):
		return _combo("airplane", ranks.back(), cards, ranks.size())
	for wing_size in [1, 2]:
		var unit = 3 + wing_size
		if n < unit * 2 or n % unit != 0: continue
		var chain = int(n / unit)
		for low in range(3, 15 - chain + 1):
			var body = range(low, low + chain)
			if not body.all(func(value): return groups.has(value) and groups[value].size() == 3): continue
			var wings = groups.duplicate()
			for value in body: wings.erase(value)
			if wing_size == 1 and _single_wings(wings):
				return _combo("airplane_single", body.back(), cards, chain)
			if wing_size == 2 and wings.size() == chain and _all_count(wings, 2):
				return _combo("airplane_pair", body.back(), cards, chain)
	if n == 6 or n == 8:
		for value in ranks:
			if groups[value].size() != 4: continue
			var wings = groups.duplicate(); wings.erase(value)
			if n == 6 and _single_wings(wings): return _combo("four_two_single", value, cards)
			if n == 8 and wings.size() == 2 and _all_count(wings, 2): return _combo("four_two_pair", value, cards)
	return invalid

static func beats(candidate, target) -> bool:
	var move = classify(candidate) if candidate is Array else candidate
	var previous = classify(target) if target is Array else target
	if not move is Dictionary or not move.get("valid", false): return false
	if previous == null or (previous is Dictionary and previous.is_empty()): return true
	if not previous is Dictionary or not previous.get("valid", false): return false
	if previous.kind == "rocket": return false
	if move.kind == "rocket": return true
	if move.kind == "bomb" and previous.kind != "bomb": return true
	return move.kind == previous.kind and move.length == previous.length and move.main > previous.main

static func legal_plays(hand: Array, target: Dictionary = {}) -> Array:
	if not Cards.valid_cards(hand): return []
	var groups = Cards.groups(hand)
	var ranks = groups.keys(); ranks.sort()
	var output: Array = []
	var seen = {}
	var wanted = str(target.get("kind", ""))
	for value in ranks:
		for count in range(1, mini(groups[value].size(), 4) + 1):
			var kind = ["", "single", "pair", "triple", "bomb"][count]
			if wanted.is_empty() or wanted == kind or kind == "bomb":
				_add(output, seen, groups[value].slice(0, count), target)
	if groups.has(16) and groups.has(17): _add(output, seen, [52, 53], target)
	for value in ranks:
		if groups[value].size() < 3: continue
		var body = groups[value].slice(0, 3)
		for wing in ranks:
			if wing == value: continue
			if wanted.is_empty() or wanted == "triple_single": _add(output, seen, body + groups[wing].slice(0, 1), target)
			if groups[wing].size() >= 2 and (wanted.is_empty() or wanted == "triple_pair"):
				_add(output, seen, body + groups[wing].slice(0, 2), target)
	for count in [1, 2, 3]:
		var minimum = 5 if count == 1 else (3 if count == 2 else 2)
		for low in range(3, 15):
			var body: Array = []
			for high in range(low, 15):
				if not groups.has(high) or groups[high].size() < count: break
				body.append_array(groups[high].slice(0, count))
				var chain = high - low + 1
				if chain < minimum: continue
				var kind = ["", "straight", "pair_chain", "airplane"][count]
				if wanted.is_empty() or wanted == kind: _add(output, seen, body, target)
				if count != 3: continue
				var remaining = groups.duplicate()
				for body_rank in range(low, high + 1): remaining.erase(body_rank)
				if (wanted.is_empty() or wanted == "airplane_single") and (target.is_empty() or target.length == chain * 4):
					for wings in _wing_choices(remaining, chain, 1): _add(output, seen, body + wings, target)
				if (wanted.is_empty() or wanted == "airplane_pair") and (target.is_empty() or target.length == chain * 5):
					for wings in _wing_choices(remaining, chain, 2): _add(output, seen, body + wings, target)
	if wanted.is_empty() or wanted in ["four_two_single", "four_two_pair"]:
		for value in ranks:
			if groups[value].size() < 4: continue
			var remaining = groups.duplicate(); remaining.erase(value)
			for wing_size in [1, 2]:
				if not wanted.is_empty() and wanted != ("four_two_single" if wing_size == 1 else "four_two_pair"): continue
				for wings in _wing_choices(remaining, 2, wing_size): _add(output, seen, groups[value] + wings, target)
	output.sort_custom(func(a, b):
		var ca = classify(a); var cb = classify(b)
		var pa = 2 if ca.kind == "rocket" else (1 if ca.kind == "bomb" else 0)
		var pb = 2 if cb.kind == "rocket" else (1 if cb.kind == "bomb" else 0)
		if pa != pb: return pa < pb
		if a.size() != b.size(): return a.size() > b.size()
		if ca.main != cb.main: return ca.main < cb.main
		return str(a) < str(b))
	return output

static func _combo(kind: String, main: int, cards: Array, chain: int = 1) -> Dictionary:
	return {"valid": true, "kind": kind, "name": NAMES[kind], "main": main, "length": cards.size(), "chain": chain, "cards": Cards.sort_cards(cards)}

static func _consecutive(ranks: Array) -> bool:
	return ranks.back() <= 14 and ranks.back() - ranks.front() + 1 == ranks.size()

static func _all_count(groups: Dictionary, count: int) -> bool:
	return groups.values().all(func(cards): return cards.size() == count)

static func _single_wings(groups: Dictionary) -> bool:
	return not (groups.has(16) and groups.has(17)) and groups.values().all(func(cards): return cards.size() <= 2)

static func _add(output: Array, seen: Dictionary, cards: Array, target: Dictionary) -> void:
	var combo = classify(cards)
	if not beats(combo, target): return
	var key = str(combo.cards)
	if seen.has(key): return
	seen[key] = true; output.append(combo.cards)

static func _wing_choices(groups: Dictionary, needed: int, wing_size: int) -> Array:
	var ranks = groups.keys(); ranks.sort()
	var output: Array = []
	_collect_wings(groups, ranks, 0, needed, wing_size, [], output)
	return output

static func _collect_wings(groups: Dictionary, ranks: Array, index: int, needed: int, wing_size: int, chosen: Array, output: Array) -> void:
	# A representative for every body/wing type suffices for hints and AI.
	# Bounding rank combinations keeps a pathological 20-card hand responsive.
	if output.size() >= 128: return
	if needed == 0:
		if not (chosen.has(52) and chosen.has(53)): output.append(chosen)
		return
	if index >= ranks.size(): return
	var available = groups[ranks[index]]
	var maximum = mini(needed, mini(available.size(), 2)) if wing_size == 1 else (1 if available.size() >= 2 else 0)
	for amount in range(maximum, -1, -1):
		_collect_wings(groups, ranks, index + 1, needed - amount, wing_size, chosen + available.slice(0, amount * wing_size), output)
