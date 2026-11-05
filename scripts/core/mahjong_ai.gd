class_name MahjongAI
extends RefCounted
## Public-seat information only. Port of upstream classic / efficiency policies.
var cache: Dictionary = {}
var _best = 9
var _exposed = 0
var _luan = false
var _field_sequences: Array = []
var _field_pairs: Dictionary = {}
var _sequence_cache: Dictionary = {}

func shanten(hand: Array, melds: Array, luan: bool, field_id: String = "") -> int:
	var c = Tiles.counts(hand)
	var exposed = Rules.active(melds).size()
	var key = field_id + str(exposed) + str(luan) + str(c)
	if cache.has(key): return cache[key]
	_best = 9; _exposed = exposed; _luan = luan
	_prepare_field_sequences(field_id)
	if exposed == 0:
		var pairs = 0; var has_eye = luan; var single = luan
		for tile in range(34):
			pairs += int(c[tile]) / 2
			if Tiles.eye(tile) and c[tile] >= 2: has_eye = true
			if Tiles.eye(tile) and c[tile] > 0: single = true
		var seven_distance = 6 - pairs if has_eye else maxi(0 if single else 1, 6 - pairs + (0 if single else 1))
		_best = mini(_best, seven_distance)
		var unique_orphans = 0; var orphan_pair = false
		for t in Tiles.ORPHANS:
			if c[t] > 0: unique_orphans += 1
			if c[t] >= 2: orphan_pair = true
		_best = mini(_best, 13 - unique_orphans - int(orphan_pair))
		for a in range(3):
			for b in range(3):
				if a == b: continue
				var patterns = [a, b, 3 - a - b]
				var unique = 0
				for t in range(27, 34):
					if c[t] > 0: unique += 1
				for suit in range(3):
					for rank in range(patterns[suit], 9, 3):
						if c[suit * 9 + rank] > 0: unique += 1
				_best = mini(_best, 13 - unique)
	_dfs(c, 0, 0, 0, 0, false)
	# This is a bounded discard heuristic, not the win authority. Actual field
	# waits are always checked below, including every possible red-dragon use.
	var result = maxi(-1, _best - (c[31] if field_id == "wildcard" else 0))
	if cache.size() >= 12000: cache.clear()
	cache[key] = result
	return result

func _prepare_field_sequences(field_id: String) -> void:
	_field_sequences = []; _field_pairs = {}
	if field_id not in ["ouroboros", "honor_sequences"]: return
	if _sequence_cache.has(field_id):
		_field_sequences = _sequence_cache[field_id].sequences
		_field_pairs = _sequence_cache[field_id].pairs
		return
	for original in FieldRules.sequences(field_id):
		var sequence: Array = original.duplicate(); sequence.sort()
		if sequence[0] < 27 and sequence[2] - sequence[0] == 2: continue
		_field_sequences.append(sequence)
		for tile in sequence:
			if not _field_pairs.has(tile): _field_pairs[tile] = []
			for other in sequence:
				if other > tile and other not in _field_pairs[tile]: _field_pairs[tile].append(other)
	_sequence_cache[field_id] = {"sequences": _field_sequences, "pairs": _field_pairs}

func _dfs(c: Array, start: int, groups: int, partials: int, pair: int, eye_single: bool) -> void:
	if groups + _exposed > 4 or partials > 4 or _best == -1: return
	while start < 34 and c[start] == 0: start += 1
	if start == 34:
		var complete = groups + _exposed
		_best = mini(_best, 8 - complete * 2 - mini(partials, 4 - complete) - pair + int(pair == 0 and not eye_single))
		return
	var count = c[start]
	var eligible = _luan or Tiles.eye(start)
	if count >= 3:
		c[start] -= 3; _dfs(c, start, groups + 1, partials, pair, eye_single); c[start] += 3
	var rank = start % 9
	if start < 27 and rank <= 6 and c[start + 1] > 0 and c[start + 2] > 0:
		for t in range(start, start + 3): c[t] -= 1
		_dfs(c, start, groups + 1, partials, pair, eye_single)
		for t in range(start, start + 3): c[t] += 1
	for sequence in _field_sequences:
		if start not in sequence or not sequence.all(func(tile): return c[tile] > 0): continue
		for tile in sequence: c[tile] -= 1
		_dfs(c, start, groups + 1, partials, pair, eye_single)
		for tile in sequence: c[tile] += 1
	if count >= 2:
		c[start] -= 2
		if pair == 0 and eligible: _dfs(c, start, groups, partials, 1, eye_single)
		_dfs(c, start, groups, partials + 1, pair, eye_single)
		c[start] += 2
	if start < 27:
		for gap in [1, 2]:
			if rank + gap > 8 or c[start + gap] == 0: continue
			c[start] -= 1; c[start + gap] -= 1
			_dfs(c, start, groups, partials + 1, pair, eye_single)
			c[start] += 1; c[start + gap] += 1
	for other in _field_pairs.get(start, []):
		if c[other] == 0: continue
		c[start] -= 1; c[other] -= 1
		_dfs(c, start, groups, partials + 1, pair, eye_single)
		c[start] += 1; c[other] += 1
	c[start] = 0
	_dfs(c, start + 1, groups, partials, pair, eye_single or eligible)
	c[start] = count

func utility(tile: int, hand: Array, luan: bool, field_id: String = "") -> int:
	var c = Tiles.counts(hand)
	if field_id == "wildcard" and tile == 31: return 140
	if c[tile] >= 3: return 80
	if c[tile] == 2: return 75 if luan or Tiles.eye(tile) else 55
	if tile >= 27:
		if field_id == "honor_sequences" and tile <= 31:
			var connections = 0
			for other in range(27, 32):
				if other != tile and c[other] > 0: connections += 1
			return 10 + connections * 20
		return 10
	var value = 20 + (8 if not luan and Tiles.eye(tile) else 0)
	for gap in [-2, -1, 1, 2]:
		var other = tile + gap
		if field_id == "ouroboros": other = int(tile / 9) * 9 + posmod(tile % 9 + gap, 9)
		if other >= 0 and other < 27 and other / 9 == tile / 9 and c[other] > 0: value += 20 if absi(gap) == 1 else 10
	return value

func rank(hand: Array, melds: Array, luan: bool, visible: Array, classic: bool = false, field_id: String = "", tile_totals: Array = []) -> Array:
	var c = Tiles.counts(visible)
	var own = Tiles.counts(hand)
	var candidates = []; var seen = []
	for index in range(hand.size()):
		var tile = hand[index]
		if tile in seen: continue
		seen.append(tile)
		var after = hand.duplicate(); after.remove_at(index)
		var distance = 1 if classic else shanten(after, melds, luan, field_id)
		var waits = Rules.waits(after, melds, luan, field_id) if classic or distance <= 0 or field_id in ["ouroboros", "honor_sequences", "wildcard"] or after.all(func(t): return t >= 27) else []
		var live = 0
		for t in waits: live += maxi(0, _tile_total(t, tile_totals) - maxi(c[t], own[t]))
		candidates.append({"index": index, "tile": tile, "waits": waits, "remaining": live, "shanten": 0 if not waits.is_empty() else maxi(1, distance), "ukeire": live, "utility": utility(tile, hand, luan, field_id)})
	if classic:
		var ready = candidates.filter(func(a): return not a.waits.is_empty())
		if not ready.is_empty():
			ready.sort_custom(func(a, b): return a.waits.size() > b.waits.size() if a.waits.size() != b.waits.size() else a.index < b.index)
			return ready
		candidates.sort_custom(func(a, b): return a.utility < b.utility if a.utility != b.utility else a.index < b.index)
		return candidates
	var live_ready = candidates.filter(func(a): return a.remaining > 0)
	if not live_ready.is_empty(): candidates = live_ready
	else:
		var best_distance = 9
		for item in candidates:
			item.shanten = maxi(1, item.shanten)
			best_distance = mini(best_distance, item.shanten)
		for item in candidates:
			if item.shanten != best_distance: continue
			var after = hand.duplicate(); after.remove_at(item.index)
			for tile in range(34):
				var live = maxi(0, _tile_total(tile, tile_totals) - maxi(c[tile], own[tile]))
				if live > 0 and shanten(after + [tile], melds, luan, field_id) < item.shanten: item.ukeire += live
	candidates.sort_custom(func(a, b):
		if a.shanten != b.shanten: return a.shanten < b.shanten
		if a.ukeire != b.ukeire: return a.ukeire > b.ukeire
		if a.waits.size() != b.waits.size(): return a.waits.size() > b.waits.size()
		if a.utility != b.utility: return a.utility < b.utility
		return a.index < b.index)
	return candidates

static func _tile_total(tile: int, totals: Array) -> int:
	return int(totals[tile]) if tile < totals.size() else 4

func _visible_tiles(view: Dictionary, seat: int) -> Array:
	var visible: Array = view.players[seat].hand.duplicate()
	for other in view.players:
		visible.append_array(other.discards)
		for meld in other.melds: visible.append_array(meld.tiles)
		# The authority already strips concealed tiles. Transparent and reborn
		# hands can be visible without the locked-hand ming declaration.
		if other.seat != seat: visible.append_array(other.hand.filter(func(tile): return tile >= 0))
	if view.gang_head >= 0: visible.append(view.gang_head)
	return visible

func _field_choice(view: Dictionary, seat: int, visible: Array) -> Dictionary:
	var moves: Array = view.pending
	var p: Dictionary = view.players[seat]
	var field: Dictionary = view.get("field", {})
	var field_id = str(field.get("id", ""))
	var luan = view.settings.jiang == "luan"
	var totals: Array = field.get("tile_totals", [])
	if view.phase == "exchange":
		# Select from authority-provided sets, so the honor fallback and exact
		# three-tile restriction never depend on a second implementation in AI.
		var selected: Dictionary = {}
		var lowest = 100000
		for move in moves:
			if move.kind != "field_exchange": continue
			var value = 0
			for tile in move.tiles: value += utility(tile, p.hand, luan, field_id)
			if value < lowest: selected = move; lowest = value
		return selected
	if view.phase == "draw_choice":
		for move in moves:
			if move.kind == "field_gift": return move
		return moves[0]
	if view.phase == "gift_choice":
		var selected: Dictionary = {}
		var best_value = -INF
		for move in moves:
			if move.kind != "field_gift_pick": continue
			var candidate: Array = p.hand + [move.tile]
			var ranking = rank(candidate, p.melds, luan, visible + [move.tile], true, field_id, totals)
			if ranking.is_empty(): continue
			var result: Dictionary = ranking[0]
			var value = result.remaining * 100 + result.waits.size() * 20 + utility(move.tile, candidate, luan, field_id)
			if value > best_value: selected = move; best_value = value
		return selected
	if view.phase != "turn": return {}
	for move in moves:
		if move.kind == "field_peek_wall": return move
	var peeks = moves.filter(func(move): return move.kind == "field_peek_waits")
	if not peeks.is_empty():
		# Prefer an opponent who has declared and whose waits are still hidden.
		for move in peeks:
			var target: Dictionary = view.players[int(move.target)]
			if target.bao and not target.ming: return move
		return peeks[0]
	if field_id == "rebirth" and moves.any(func(move): return move.kind == "field_rebirth"):
		var base: Array = p.hand.duplicate()
		if p.drawn >= 0 and p.drawn < base.size(): base.remove_at(p.drawn)
		var visible_counts = Tiles.counts(visible)
		var live = 0
		for tile in Rules.waits(base, p.melds, luan, field_id): live += maxi(0, _tile_total(tile, totals) - visible_counts[tile])
		if live == 0:
			for move in moves:
				if move.kind == "field_rebirth": return move
	if (p.bao or p.ming) or field_id not in ["diamond_finger", "reclaim"]: return {}
	var baseline = rank(p.hand, p.melds, luan, visible, true, field_id, totals)
	if baseline.is_empty(): return {}
	var best: Dictionary = baseline[0]
	var value = best.remaining * 100 + best.waits.size() * 20 - shanten(p.hand, p.melds, luan, field_id) * 10
	var selected: Dictionary = {}
	for move in moves:
		if move.kind not in ["field_transform", "field_reclaim"]: continue
		var hand: Array = p.hand.duplicate()
		var melds: Array = p.melds.duplicate(true)
		if move.kind == "field_transform": hand[int(move.index)] = 33
		else:
			hand.append_array(melds[int(move.meld_index)].tiles)
			melds.remove_at(int(move.meld_index))
		var ranking = rank(hand, melds, luan, visible, true, field_id, totals)
		if ranking.is_empty(): continue
		var candidate: Dictionary = ranking[0]
		var candidate_value = candidate.remaining * 100 + candidate.waits.size() * 20 - shanten(hand, melds, luan, field_id) * 10
		# A limited ability should improve the hand, not merely consume a turn.
		if candidate_value > value:
			selected = move; value = candidate_value
	return selected

func choose(view: Dictionary, seat: int, random_value: float = 1.0) -> Dictionary:
	var moves: Array = view.pending
	if moves.is_empty(): return {}
	for move in moves:
		if move.kind == "win": return move
	var p: Dictionary = view.players[seat]
	var field: Dictionary = view.get("field", {})
	var field_id = str(field.get("id", ""))
	var visible = _visible_tiles(view, seat)
	if not field_id.is_empty():
		var field_move = _field_choice(view, seat, visible)
		if not field_move.is_empty(): return field_move
	for kind in ["angang", "bugang", "gang", "tolerance_gang", "peng", "chi"]:
		for move in moves:
			if move.kind == kind: return move
	if view.phase == "claim": return moves.back()
	if p.bao or p.ming:
		for move in moves:
			if move.kind == "discard": return move
	# Unusual phases must always progress via a legal action, including when
	# future field rules introduce a choice this policy does not yet optimise.
	if view.phase != "turn": return moves[0]
	var classic = view.settings.ai == "classic"
	var candidates = rank(p.hand, p.melds, view.settings.jiang == "luan", visible, classic, field_id, field.get("tile_totals", []))
	if candidates.is_empty(): return moves[0]
	var best: Dictionary = candidates[0]
	var private_field: Dictionary = p.get("field_private", {})
	if private_field.has("peek_waits"):
		# Astrology information is supplied only in this seat's private view.
		# Avoid a known dangerous discard when an equally close alternative exists.
		for candidate in candidates:
			if candidate.shanten == best.shanten and candidate.tile not in private_field.peek_waits:
				best = candidate; break
	var kind = "discard"
	if not best.waits.is_empty() and (classic or best.remaining > 0):
		kind = "ming" if p.get("revealed_hand", false) or (view.wall_count > 30 and random_value < 0.15) else "bao"
	for move in moves:
		if move.kind == kind and move.get("index", -1) == best.index:
			var answer = move.duplicate(true)
			answer.analysis = best
			return answer
	# A declaration can be unavailable under a field constraint. Prefer the
	# ranked legal discard instead of falling into an unrelated ability.
	for move in moves:
		if move.kind == "discard" and move.get("index", -1) == best.index: return move
	return moves.back()
