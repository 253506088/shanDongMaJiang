class_name Rules
extends RefCounted
## Port of upstream shandongRules.ts (MIT). Preserve its scoring semantics.
## Pure rules: no scene tree, timers, filesystem, networking or UI state.

static func active(melds: Array) -> Array:
	return melds.filter(func(m): return m.type != "flower")

static func flower_count(melds: Array) -> int:
	return melds.size() - active(melds).size()

static func all_tiles(hand: Array, melds: Array) -> Array:
	var result = hand.duplicate()
	for meld in active(melds): result.append_array(meld.tiles)
	return result

static func groups(counts: Array, needed: int, field_id: String = "") -> bool:
	var start = -1
	for i in range(34):
		if counts[i] > 0:
			start = i
			break
	if needed == 0: return start == -1
	if start == -1: return false
	if counts[start] >= 3:
		counts[start] -= 3
		var ok = groups(counts, needed - 1, field_id)
		counts[start] += 3
		if ok: return true
	if field_id in ["ouroboros", "honor_sequences"]:
		for sequence in FieldRules.sequences(field_id):
			if start not in sequence or sequence.any(func(t): return counts[t] < 1): continue
			for tile in sequence: counts[tile] -= 1
			var ok = groups(counts, needed - 1, field_id)
			for tile in sequence: counts[tile] += 1
			if ok: return true
		return false
	if start < 27 and start % 9 <= 6 and counts[start + 1] > 0 and counts[start + 2] > 0:
		for t in range(start, start + 3): counts[t] -= 1
		var ok = groups(counts, needed - 1, field_id)
		for t in range(start, start + 3): counts[t] += 1
		if ok: return true
	return false

static func pinghu(hand: Array, melds: Array = [], luan: bool = false, field_id: String = "") -> bool:
	var needed = 4 - active(melds).size()
	if hand.size() != needed * 3 + 2: return false
	var c = Tiles.counts(hand)
	for t in range(34):
		if c[t] >= 2 and (luan or Tiles.eye(t)):
			c[t] -= 2
			var ok = groups(c, needed, field_id)
			c[t] += 2
			if ok: return true
	return false

static func triplets(hand: Array, melds: Array = [], luan: bool = false) -> bool:
	var exposed = active(melds)
	if exposed.any(func(m): return m.type == "chi"): return false
	if hand.size() != (4 - exposed.size()) * 3 + 2: return false
	var c = Tiles.counts(hand)
	for tile in range(34):
		if c[tile] < 2 or not (luan or Tiles.eye(tile)): continue
		c[tile] -= 2
		var ok = true
		for n in c:
			if int(n) % 3 != 0: ok = false
		c[tile] += 2
		if ok: return true
	return false

static func seven(hand: Array, melds: Array = [], luan: bool = false, field_id: String = "") -> int:
	if not active(melds).is_empty() or hand.size() != 14: return -1
	var c = Tiles.counts(hand)
	var luxury = 0
	var has_eye = luan
	for t in range(42):
		if c[t] == 0: continue
		if field_id in ["diamond_finger", "no_honors"]:
			if c[t] % 2 != 0: return -1
			luxury += int(c[t]) / 4
		else:
			if c[t] not in [2, 4]: return -1
			if c[t] == 4: luxury += 1
		if Tiles.eye(t): has_eye = true
	return luxury if has_eye else -1

static func orphans(hand: Array, melds: Array = []) -> bool:
	if not active(melds).is_empty() or hand.size() != 14: return false
	var c = Tiles.counts(hand)
	var pairs = 0
	for tile in Tiles.ORPHANS:
		if c[tile] == 0 or c[tile] > 2: return false
		if c[tile] == 2: pairs += 1
	return pairs == 1

static func bukao(hand: Array, melds: Array = []) -> bool:
	if not active(melds).is_empty() or hand.size() != 14: return false
	var c = Tiles.counts(hand)
	var patterns = [-1, -1, -1]
	for tile in hand:
		if tile >= 34 or c[tile] != 1: return false
		if tile >= 27: continue
		var suit = int(tile) / 9
		var p = int(tile) % 3
		if patterns[suit] != -1 and patterns[suit] != p: return false
		patterns[suit] = p
	var used = []
	for p in patterns:
		if p < 0: continue
		if p in used: return false
		used.append(p)
	return true

static func special_color(hand: Array, melds: Array, honors: bool, field_id: String = "") -> bool:
	var all = all_tiles(hand, melds)
	if all.size() != 14: return false
	for tile in all:
		if honors and (tile < 27 or tile >= 34): return false
		if not honors and not Tiles.eye(tile): return false
	if field_id == "honor_sequences" and honors: return pinghu(hand, melds, true, field_id) or seven(hand, melds, true, field_id) >= 0
	# Preserve upstream: the special color check itself accepts triplet groups.
	return triplets(hand, [], true) if active(melds).is_empty() and seven(hand, [], true, field_id) < 0 else _special_complete(hand, melds, field_id)

static func _special_complete(hand: Array, melds: Array, field_id: String = "") -> bool:
	var c = Tiles.counts(hand)
	for tile in range(34):
		if c[tile] < 2: continue
		c[tile] -= 2
		var count = 0
		var ok = true
		for n in c:
			if int(n) % 3 != 0: ok = false
			count += int(n) / 3
		c[tile] += 2
		if ok and count == 4 - active(melds).size(): return true
	return seven(hand, melds, true, field_id) >= 0

static func suit_color(hand: Array, melds: Array, mixed: bool, luan: bool, field_id: String = "") -> bool:
	var all = all_tiles(hand, melds)
	if all.size() != 14: return false
	var suit = -1
	var has_honor = false
	for tile in all:
		# Upstream's /^([mps])/ color classifier treats "south" as suit s.
		# Kept for exact migration; documented in the compatibility baseline.
		if tile >= 27 and tile != 28:
			has_honor = true
			continue
		var s = 2 if tile == 28 else int(tile) / 9
		if suit != -1 and suit != s: return false
		suit = s
	if suit == -1 or has_honor != mixed: return false
	return pinghu(hand, melds, luan, field_id) or seven(hand, melds, luan, field_id) >= 0 or triplets(hand, melds, luan)

static func dragon(hand: Array, melds: Array, luan: bool, field_id: String = "") -> bool:
	if not pinghu(hand, melds, luan, field_id): return false
	var c = Tiles.counts(all_tiles(hand, melds))
	for suit in range(3):
		var ok = true
		for r in range(9):
			if c[suit * 9 + r] == 0: ok = false
		if ok: return true
	return false

static func winning(hand: Array, melds: Array = [], luan: bool = false, field_id: String = "") -> bool:
	if field_id == "wildcard": return FieldRules.wildcard_winning(hand, melds, luan)
	if flower_count(melds) >= 8: return true
	if orphans(hand, melds) or bukao(hand, melds): return true
	if special_color(hand, melds, true, field_id) or special_color(hand, melds, false, field_id): return true
	return seven(hand, melds, luan, field_id) >= 0 or pinghu(hand, melds, luan, field_id)

static func waits(hand: Array, melds: Array = [], luan: bool = false, field_id: String = "") -> Array:
	var result = []
	for t in range(34):
		if field_id == "no_honors" and t >= 27: continue
		if winning(hand + [t], melds, luan, field_id): result.append(t)
	if field_id == "single_wait" and result.size() != 1: return []
	return result

static func chi(hand: Array, tile: int, field_id: String = "") -> Array:
	var result = []
	if field_id in ["ouroboros", "honor_sequences"]:
		for sequence in FieldRules.sequences(field_id):
			if tile not in sequence: continue
			var needed = sequence.duplicate(); needed.erase(tile)
			if needed.all(func(t): return t in hand): result.append(sequence)
		return result
	if tile >= 27: return result
	var c = Tiles.counts(hand)
	for start in range(tile - 2, tile + 1):
		if start < 0 or start / 9 != tile / 9 or start % 9 > 6: continue
		var needed = [start, start + 1, start + 2]
		needed.erase(tile)
		if c[needed[0]] > 0 and c[needed[1]] > 0: result.append([start, start + 1, start + 2])
	return result

static func evaluate(hand: Array, melds: Array = [], flags: Dictionary = {}) -> Dictionary:
	var luan = flags.get("luan", false)
	var field_id = str(flags.get("field_id", ""))
	if field_id == "wildcard":
		var ordinary_flags = flags.duplicate(true); ordinary_flags.field_id = ""
		var best: Dictionary = {}
		for candidate in FieldRules.wildcard_candidates(hand, melds, luan):
			var evaluated = evaluate(candidate, melds, ordinary_flags)
			_wildcard_physical_hua(evaluated, hand)
			if not evaluated.is_empty() and evaluated.get("points", 0) > best.get("points", -1):
				best = evaluated
				best.wildcard_hand = candidate
		if best.is_empty() and flower_count(melds) >= 8: best = evaluate(hand,melds,ordinary_flags)
		return best
	if not winning(hand, melds, luan, field_id) and not flags.get("tianhu", false) and not flags.get("dihu", false): return {}
	for fixed in ["tianhu", "dihu"]:
		if flags.get(fixed, false):
			var base = 30 if fixed == "tianhu" else 25
			var multiplier = base * (2 if flags.get("ming", false) else 1)
			return FieldRules.bonus({"pattern": "天胡" if fixed == "tianhu" else "地胡", "base": base, "multiplier": multiplier, "hua": 1, "points": multiplier * 10, "patterns": [{"name": "天胡" if fixed == "tianhu" else "地胡", "multiplier": base}], "hua_details": [{"name": "固定倍数不计花", "points": 1}], "win_type": fixed}, flags.get("field_bonus", []))
	var seven_count = seven(hand, melds, luan, field_id)
	var is_orphans = orphans(hand, melds)
	var is_bukao = bukao(hand, melds)
	var name = "平胡"
	var base = 1
	if is_orphans: name = "十三幺"; base = 16
	elif seven_count == 3: name = "超豪华七对"; base = 16
	elif is_bukao: name = "十三不靠"; base = 12
	elif seven_count == 2: name = "双豪华七对"; base = 8
	elif special_color(hand, melds, true, field_id): name = "风一色"; base = 6
	elif special_color(hand, melds, false, field_id): name = "将一色"; base = 6
	elif seven_count == 1: name = "豪华七对"; base = 4
	elif seven_count == 0: name = "七对"; base = 2
	elif triplets(hand, melds, luan): name = "碰碰胡"; base = 2
	var patterns = [{"name": name, "multiplier": base}]
	var additions = []
	if suit_color(hand, melds, false, luan, field_id): additions.append(["清一色", 4])
	elif suit_color(hand, melds, true, luan, field_id): additions.append(["混一色", 2])
	if dragon(hand, melds, luan, field_id): additions.append(["一条龙", 4])
	if active(melds).size() == 4 and hand.size() == 2 and hand[0] == hand[1] and (luan or Tiles.eye(hand[0])): additions.append(["大吊车", 2])
	if active(melds).all(func(m): return m.type == "angang") and seven_count < 0 and not is_orphans and not is_bukao: additions.append(["门清", 2])
	var flowers = flower_count(melds)
	if flowers > 0: additions.append(["花胡", 2])
	if flags.get("haidi", false): additions.append(["海底捞月", 2])
	if flags.get("ming", false): additions.append(["明搂", 2])
	elif flags.get("bao", false): additions.append(["报听", 1])
	var multiplier = base
	for add in additions:
		multiplier *= add[1]
		patterns.append({"name": add[0], "multiplier": add[1]})
	var details = [{"name": "底分", "points": 1}]
	if flowers: details.append({"name": "花牌（%d张）" % flowers, "points": flowers})
	for meld in active(melds):
		var honor = meld.tile >= 27 and meld.tile < 34
		var points = 0
		var label = ""
		if meld.type == "peng" and honor: points = 1; label = "字明刻"
		elif meld.type == "gang": points = 2 if honor else 1; label = "字明杠" if honor else "明杠"
		elif meld.type == "angang": points = 3 if honor else 2; label = "字暗杠" if honor else "暗杠"
		if points:
			if field_id in ["diamond_finger", "no_honors"] and meld.type in ["gang", "angang"]:
				var kongs = maxi(1, meld.tiles.size() - 3)
				points *= kongs
				if kongs > 1: label += "×%d" % kongs
			details.append({"name": label + "（" + Tiles.title(meld.tile) + "）", "points": points})
	var c = Tiles.counts(hand)
	for tile in range(27, 34):
		if c[tile] >= 3: details.append({"name": "字暗刻（" + Tiles.title(tile) + "）", "points": 1})
	var hua = 0
	for detail in details: hua += detail.points
	return FieldRules.bonus({"pattern": name, "base": base, "multiplier": multiplier, "hua": hua, "points": hua * multiplier * 10, "patterns": patterns, "hua_details": details, "win_type": "robbed-kong" if flags.get("robbed", false) else ("self-draw" if flags.get("self_draw", false) else "discard")}, flags.get("field_bonus", []))

static func _wildcard_physical_hua(result: Dictionary, original_hand: Array) -> void:
	if result.is_empty() or result.get("win_type", "") in ["tianhu", "dihu"]: return
	# Wildcards determine a valid scoring pattern, but they do not create real
	# honor copies for the separate flower ledger. Preserve actual red triplets.
	result.hua_details = result.hua_details.filter(func(detail): return not str(detail.name).begins_with("字暗刻（"))
	var actual = Tiles.counts(original_hand)
	for tile in range(27,34):
		if actual[tile] >= 3: result.hua_details.append({"name": "字暗刻（" + Tiles.title(tile) + "）", "points": 1})
	result.hua = 0
	for detail in result.hua_details: result.hua += detail.points
	result.points = result.hua * result.multiplier * 10
