class_name MahjongAI
extends RefCounted
## Public-seat information only. Port of upstream classic / efficiency policies.
var cache: Dictionary = {}
var _best = 9
var _exposed = 0
var _luan = false

func shanten(hand: Array, melds: Array, luan: bool) -> int:
	var c = Tiles.counts(hand)
	var exposed = Rules.active(melds).size()
	var key = str(exposed) + str(luan) + str(c)
	if cache.has(key): return cache[key]
	_best = 9; _exposed = exposed; _luan = luan
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
	var result = maxi(-1, _best)
	if cache.size() >= 12000: cache.clear()
	cache[key] = result
	return result

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
	c[start] = 0
	_dfs(c, start + 1, groups, partials, pair, eye_single or eligible)
	c[start] = count

func utility(tile: int, hand: Array, luan: bool) -> int:
	var c = Tiles.counts(hand)
	if c[tile] >= 3: return 80
	if c[tile] == 2: return 75 if luan or Tiles.eye(tile) else 55
	if tile >= 27: return 10
	var value = 20 + (8 if not luan and Tiles.eye(tile) else 0)
	for gap in [-2, -1, 1, 2]:
		var other = tile + gap
		if other >= 0 and other < 27 and other / 9 == tile / 9 and c[other] > 0: value += 20 if absi(gap) == 1 else 10
	return value

func rank(hand: Array, melds: Array, luan: bool, visible: Array, classic: bool = false) -> Array:
	var c = Tiles.counts(visible)
	var own = Tiles.counts(hand)
	var candidates = []; var seen = []
	for index in range(hand.size()):
		var tile = hand[index]
		if tile in seen: continue
		seen.append(tile)
		var after = hand.duplicate(); after.remove_at(index)
		var distance = 1 if classic else shanten(after, melds, luan)
		var waits = Rules.waits(after, melds, luan) if classic or distance <= 0 or after.all(func(t): return t >= 27) else []
		var live = 0
		for t in waits: live += maxi(0, 4 - maxi(c[t], own[t]))
		candidates.append({"index": index, "tile": tile, "waits": waits, "remaining": live, "shanten": 0 if not waits.is_empty() else maxi(1, distance), "ukeire": live, "utility": utility(tile, hand, luan)})
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
				var live = maxi(0, 4 - maxi(c[tile], own[tile]))
				if live > 0 and shanten(after + [tile], melds, luan) < item.shanten: item.ukeire += live
	candidates.sort_custom(func(a, b):
		if a.shanten != b.shanten: return a.shanten < b.shanten
		if a.ukeire != b.ukeire: return a.ukeire > b.ukeire
		if a.waits.size() != b.waits.size(): return a.waits.size() > b.waits.size()
		if a.utility != b.utility: return a.utility < b.utility
		return a.index < b.index)
	return candidates

func choose(view: Dictionary, seat: int, random_value: float = 1.0) -> Dictionary:
	var moves = view.pending
	if moves.is_empty(): return {}
	for kind in ["win", "angang", "bugang", "gang", "peng", "chi"]:
		for move in moves:
			if move.kind == kind: return move
	if view.phase == "claim": return moves.back()
	var p = view.players[seat]
	if p.bao or p.ming:
		for move in moves:
			if move.kind == "discard": return move
	var visible = p.hand.duplicate()
	for other in view.players:
		visible.append_array(other.discards)
		for meld in other.melds: visible.append_array(meld.tiles)
		if other.seat != seat and other.ming: visible.append_array(other.hand)
	if view.gang_head >= 0: visible.append(view.gang_head)
	var classic = view.settings.ai == "classic"
	var best = rank(p.hand, p.melds, view.settings.jiang == "luan", visible, classic)[0]
	var kind = "discard"
	if not best.waits.is_empty() and (classic or best.remaining > 0): kind = "ming" if view.wall_count > 30 and random_value < 0.15 else "bao"
	for move in moves:
		if move.kind == kind and move.get("index", -1) == best.index:
			var answer = move.duplicate(true)
			answer.analysis = best
			return answer
	return moves.back()
