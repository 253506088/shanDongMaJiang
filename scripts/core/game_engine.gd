class_name GameEngine
extends RefCounted
## Authoritative, synchronous state machine. One accepted command = one revision.
## Local play uses this directly; a future LAN host can expose the same contract.

const VERSION = 1
var state: Dictionary = {}
var journal: Array = []
var opening: Dictionary = {}
var rng = RandomNumberGenerator.new()

func start(settings: Dictionary = {}, game_seed: int = 0, round_number: int = 1, scores: Array = [], initial_wall: Array = []) -> void:
	rng.seed = game_seed if game_seed != 0 else int(Time.get_unix_time_from_system())
	var config = {"jiang": "258", "chi": true, "ai": "efficiency", "rounds": 4, "takeover": false}
	config.merge(settings, true)
	if config.jiang not in ["258", "luan"]: config.jiang = "258"
	if config.ai not in ["classic", "efficiency"]: config.ai = "efficiency"
	config.rounds = int(config.rounds)
	scores = scores.map(func(n): return int(n))
	# JSON decodes numbers as floats; normalize at the protocol boundary.
	var wall = initial_wall.map(func(t): return int(t)) if not initial_wall.is_empty() else Tiles.wall()
	if initial_wall.is_empty():
		for i in range(wall.size() - 1, 0, -1):
			var j = rng.randi_range(0, i)
			var t = wall[i]; wall[i] = wall[j]; wall[j] = t
	Tiles.ensure_tail(wall)
	opening = {"settings": config.duplicate(true), "wall": wall.duplicate(), "round": round_number, "scores": scores.duplicate(), "seed": str(rng.seed)}
	journal = []
	state = {"version": VERSION, "revision": 0, "settings": config, "round": round_number, "dealer": (round_number - 1) % 4, "phase": "turn", "current": (round_number - 1) % 4, "wall": wall, "players": [], "pending": [], "last_discard": {}, "first_discard": true, "last_normal": -1, "result": {}, "event": {"kind": "opening", "seat": 0}, "claim_stage": "", "claim_from": -1, "claim_tile": -1, "claim_seat": -1, "claim_queue": [], "added_index": -1, "dice": [rng.randi_range(1, 6), rng.randi_range(1, 6)]}
	opening.dice = state.dice.duplicate()
	# Public physical slots parallel the private wall. The tail's top tile is the
	# exposed kong head; identities remain stable after head/tail/flower draws.
	state.wall_slots=range(144)
	state.wall_slots[142]=143;state.wall_slots[143]=142
	for seat in range(4):
		var player = {"seat": seat, "name": ["我", "听松", "观澜", "知秋"][seat], "score": scores[seat] if scores.size() == 4 else 2000, "hand": [], "melds": [], "discards": [], "bao": false, "ming": false, "passed_hu": false, "passed_peng": [], "drawn": -1}
		var count = 14 if seat == state.dealer else 13
		for _i in range(count):
			player.hand.append(wall.pop_front());state.wall_slots.pop_front()
		state.players.append(player)
	for p in state.players:
		while true:
			var flower_index = -1
			for i in range(p.hand.size()):
				if p.hand[i] >= 34: flower_index = i; break
			if flower_index < 0: break
			var tile = p.hand.pop_at(flower_index)
			p.melds.append({"type": "flower", "tile": tile, "tiles": [tile]})
			if not wall.is_empty():
				p.hand.append(wall.pop_back());state.wall_slots.pop_back()
				_expose_wall_tail()
		p.hand.sort()
	Tiles.ensure_tail(wall)
	state.gang_head = wall.back() if not wall.is_empty() else -1
	var dealer = state.players[state.dealer]
	dealer.drawn = dealer.hand.size() - 1
	for p in state.players:
		if Rules.flower_count(p.melds) == 8:
			_settle(p.seat, {"self_draw": true, "tile": p.melds.back().tile})
			return
	if Rules.winning(dealer.hand, dealer.melds, _luan()):
		_settle(state.dealer, {"self_draw": true, "tianhu": true, "tile": dealer.hand.back()})
	else: _turn_options()

func _luan() -> bool:
	return state.settings.jiang == "luan"

func _expose_wall_tail() -> void:
	var slots=state.wall_slots
	if slots.size()<2: return
	var last=int(slots[-1]);var previous=int(slots[-2])
	if last%2==1 and last/2==previous/2:
		slots[-1]=previous;slots[-2]=last

func _option(kind: String, extra: Dictionary = {}) -> Dictionary:
	var move = {"kind": kind}
	move.merge(extra)
	move.id = str(state.pending.size())
	state.pending.append(move)
	return move

func _turn_options() -> void:
	state.phase = "turn"
	state.pending = []
	var p = state.players[state.current]
	var locked = p.bao or p.ming
	if locked and Rules.winning(p.hand, p.melds, _luan()): _option("win")
	var c = Tiles.counts(p.hand)
	if not locked:
		for tile in range(34):
			if c[tile] == 4: _option("angang", {"tile": tile})
		for i in range(p.melds.size()):
			if p.melds[i].type == "peng" and c[p.melds[i].tile] > 0: _option("bugang", {"meld_index": i, "tile": p.melds[i].tile})
	var waits_by_tile = {}
	for i in range(p.hand.size()):
		if locked and i != p.drawn: continue
		_option("discard", {"index": i, "tile": p.hand[i]})
		if not locked:
			var tile = p.hand[i]
			if not waits_by_tile.has(tile):
				var after = p.hand.duplicate(); after.remove_at(i)
				waits_by_tile[tile] = Rules.waits(after, p.melds, _luan())
			if not waits_by_tile[tile].is_empty():
				_option("bao", {"index": i, "tile": tile, "waits": waits_by_tile[tile]})
				_option("ming", {"index": i, "tile": tile, "waits": waits_by_tile[tile]})
	if p.bao and not p.ming: _option("upgrade_ming")
	# Append new locked-hand options so pre-existing replay action IDs stay stable.
	if locked and not state.wall.is_empty() and p.drawn >= 0:
		for tile in range(34):
			if c[tile] == 4 and _locked_kong_preserves_waits(p, tile):
				_option("angang", {"tile": tile})
		for i in range(p.melds.size()):
			if p.melds[i].type == "peng" and c[p.melds[i].tile] > 0 and _locked_kong_preserves_waits(p, p.melds[i].tile, i):
				_option("bugang", {"meld_index": i, "tile": p.melds[i].tile})

func _locked_kong_preserves_waits(p: Dictionary, tile: int, meld_index: int = -1) -> bool:
	if p.drawn < 0 or p.drawn >= p.hand.size() or p.hand[p.drawn] != tile: return false
	var before = p.hand.duplicate(); before.remove_at(p.drawn)
	var waits_before = Rules.waits(before, p.melds, _luan())
	if waits_before.is_empty(): return false
	var after = p.hand.duplicate()
	var melds = p.melds.duplicate(true)
	if meld_index >= 0:
		after.erase(tile)
		melds[meld_index].type = "gang"; melds[meld_index].tiles.append(tile)
	else:
		for _i in range(4): after.erase(tile)
		melds.append({"type":"angang", "tile":tile, "tiles":[tile,tile,tile,tile]})
	return waits_before == Rules.waits(after, melds, _luan())

func decision_seat() -> int:
	if state.is_empty() or state.phase == "settled": return -1
	return state.current if state.phase == "turn" else state.claim_seat

func submit(seat: int, revision: int, action_id: String) -> bool:
	if state.is_empty() or revision != state.revision or seat != decision_seat(): return false
	var selected = {}
	for move in state.pending:
		if move.id == action_id: selected = move.duplicate(true); break
	if selected.is_empty(): return false
	journal.append({"seat": seat, "revision": revision, "action": selected.duplicate(true)})
	state.revision += 1
	var p = state.players[seat]
	state.event = {"kind": selected.kind, "seat": seat, "tile": selected.get("tile", state.claim_tile)}
	if state.phase == "turn":
		match selected.kind:
			"win": _settle(seat, {"self_draw": true, "tile": p.hand[p.drawn]})
			"upgrade_ming": p.ming = true; _turn_options()
			"discard", "bao", "ming":
				if selected.kind == "bao": p.bao = true
				if selected.kind == "ming": p.ming = true
				_discard(seat, selected.index)
			"angang":
				state.first_discard = false
				for _i in range(4): p.hand.erase(selected.tile)
				p.melds.append({"type": "angang", "tile": selected.tile, "tiles": [selected.tile, selected.tile, selected.tile, selected.tile]})
				p.hand.sort()
				_draw(seat, "kong")
			"bugang":
				state.first_discard = false
				state.added_index = selected.meld_index
				_begin_claims(seat, selected.tile, true)
	else:
		if selected.kind == "win":
			_settle(seat, {"self_draw": false, "robbed": state.claim_stage == "rob", "source": state.claim_from, "tile": state.claim_tile})
		elif selected.kind == "pass":
			if state.claim_stage in ["ron", "rob"]: p.passed_hu = true
			if state.claim_stage == "meld" and state.pending.any(func(a): return a.kind == "peng") and state.claim_tile not in p.passed_peng: p.passed_peng.append(state.claim_tile)
			_offer_next_claim()
		else: _claim(seat, selected)
	return true

func _discard(seat: int, index: int) -> void:
	var p = state.players[seat]
	var tile = p.hand.pop_at(index)
	p.hand.sort(); p.drawn = -1
	p.discards.append(tile)
	state.last_discard = {"tile": tile, "seat": seat, "revision": state.revision}
	state.event.tile = tile
	var first = state.first_discard and seat == state.dealer
	state.first_discard = false
	if first:
		for distance in range(1, 4):
			var candidate = (seat + distance) % 4
			var other = state.players[candidate]
			if not other.ming and not other.passed_hu and Rules.winning(other.hand + [tile], other.melds, _luan()):
				_settle(candidate, {"dihu": true, "source": seat, "tile": tile})
				return
	_begin_claims(seat, tile)

func _begin_claims(from: int, tile: int, robbed: bool = false) -> void:
	state.phase = "claim"
	state.claim_from = from; state.claim_tile = tile
	state.claim_stage = "rob" if robbed else "ron"
	state.claim_queue = []
	for distance in range(1, 4):
		var seat = (from + distance) % 4
		var p = state.players[seat]
		if p.bao and not p.ming and not p.passed_hu and Rules.winning(p.hand + [tile], p.melds, _luan()): state.claim_queue.append(seat)
	_offer_next_claim()

func _offer_next_claim() -> void:
	state.pending = []
	while not state.claim_queue.is_empty():
		var seat = state.claim_queue.pop_front()
		var p = state.players[seat]
		state.claim_seat = seat
		if state.claim_stage in ["ron", "rob"]: _option("win", {"tile": state.claim_tile})
		elif state.claim_stage == "meld":
			if p.bao or p.ming: continue
			var count = p.hand.count(state.claim_tile)
			if count >= 3: _option("gang", {"tile": state.claim_tile})
			if count >= 2 and state.claim_tile not in p.passed_peng: _option("peng", {"tile": state.claim_tile})
		elif state.claim_stage == "chi":
			if p.bao or p.ming or not state.settings.chi: continue
			for tiles in Rules.chi(p.hand, state.claim_tile): _option("chi", {"tile": state.claim_tile, "tiles": tiles})
		if not state.pending.is_empty():
			_option("pass")
			return
	match state.claim_stage:
		"rob":
			var p = state.players[state.claim_from]
			p.hand.erase(state.claim_tile)
			p.hand.sort()
			var meld = p.melds[state.added_index]
			meld.type = "gang"; meld.added = true; meld.tiles.append(state.claim_tile)
			_draw(state.claim_from, "kong")
		"ron":
			state.claim_stage = "meld"
			# Existing implementation offers peng/gang in absolute seat order.
			state.claim_queue = [0, 1, 2, 3]; state.claim_queue.erase(state.claim_from)
			_offer_next_claim()
		"meld":
			state.claim_stage = "chi"; state.claim_queue = [(state.claim_from + 1) % 4]
			_offer_next_claim()
		"chi": _draw((state.claim_from + 1) % 4)

func _claim(seat: int, move: Dictionary) -> void:
	var p = state.players[seat]
	var source = state.players[state.claim_from]
	source.discards.pop_back()
	state.last_discard = {}
	var tiles = move.tiles.duplicate() if move.kind == "chi" else [move.tile, move.tile, move.tile]
	if move.kind == "gang": tiles.append(move.tile)
	var needed = tiles.duplicate(); needed.erase(move.tile)
	for t in needed: p.hand.erase(t)
	p.hand.sort(); p.drawn = -1
	p.melds.append({"type": move.kind, "tile": move.tile, "tiles": tiles, "from": state.claim_from})
	state.current = seat
	if move.kind == "gang": _draw(seat, "kong")
	else: _turn_options()

func _draw(seat: int, reason: String = "normal") -> void:
	state.last_normal = -1
	var normal_draw = reason == "normal"
	while true:
		var wall = state.wall
		if wall.is_empty() or (reason != "kong" and wall.size() < 2): _draw_result(); return
		var tile: int
		if reason == "normal":
			tile = wall.pop_front();state.wall_slots.pop_front()
		elif reason == "flower":
			state.wall_slots.pop_at(wall.size()-2);tile = wall.pop_at(wall.size() - 2)
		else:
			tile = wall.pop_back();state.wall_slots.pop_back()
			_expose_wall_tail()
			Tiles.ensure_tail(wall)
			state.gang_head = wall.back() if not wall.is_empty() else -1
		var p = state.players[seat]
		if tile >= 34:
			p.melds.append({"type": "flower", "tile": tile, "tiles": [tile]})
			if Rules.flower_count(p.melds) == 8: _settle(seat, {"self_draw": true, "tile": tile}); return
			reason = "flower"
			continue
		p.hand.append(tile); p.drawn = p.hand.size() - 1
		p.passed_hu = false; p.passed_peng = []
		if normal_draw and wall.size() <= 1: state.last_normal = seat
		state.current = seat
		_turn_options()
		return

func _draw_result() -> void:
	state.phase = "settled"; state.pending = []
	state.result = {"draw": true, "deltas": [0, 0, 0, 0], "winner": -1, "round": state.round}

func _settle(seat: int, flags: Dictionary) -> void:
	var p = state.players[seat]
	var self_draw = flags.get("self_draw", false) or flags.get("tianhu", false)
	var hand = p.hand.duplicate()
	if not self_draw: hand.append(flags.tile)
	flags.merge({"luan": _luan(), "bao": p.bao, "ming": p.ming, "haidi": self_draw and state.last_normal == seat})
	var result = Rules.evaluate(hand, p.melds, flags)
	assert(not result.is_empty(), "Invalid authoritative win")
	var deltas = [0, 0, 0, 0]
	var source = flags.get("source", -1)
	if flags.get("robbed", false): deltas[source] = -result.points * 3 * (2 if state.players[source].ming else 1)
	elif self_draw or flags.get("dihu", false):
		for i in range(4):
			if i != seat: deltas[i] = -result.points * (2 if state.players[i].ming else 1)
	else: deltas[source] = -result.points * (2 if state.players[source].ming else 1)
	for i in range(4):
		if i != seat: deltas[seat] -= deltas[i]
	for i in range(4): state.players[i].score += deltas[i]
	result.merge({"draw": false, "winner": seat, "source": source, "win_tile": flags.tile, "win_hand": hand, "deltas": deltas, "round": state.round})
	state.result = result; state.phase = "settled"; state.pending = []
	state.event = {"kind": "win", "seat": seat, "tile": flags.tile}

func view(seat: int) -> Dictionary:
	if state.is_empty(): return {}
	var result = state.duplicate(true)
	result.erase("wall"); result.erase("claim_queue"); result.erase("added_index")
	result.wall_count = state.wall.size()
	result.decision_seat = decision_seat()
	if seat != decision_seat(): result.pending = []
	for p in result.players:
		p.hand_count = p.hand.size()
		if p.seat != seat and not p.ming and state.phase != "settled": p.hand = []
		if p.seat != seat and state.phase != "settled":
			for meld in p.melds:
				if meld.type == "angang":
					meld.tile = -1
					meld.tiles = [-1, -1, -1, -1]
		p.erase("passed_hu"); p.erase("passed_peng")
	return result

func snapshot() -> Dictionary:
	return {"version": VERSION, "state": state.duplicate(true), "opening": opening.duplicate(true), "journal": journal.duplicate(true), "rng_state": str(rng.state)}

func restore(data: Dictionary) -> bool:
	if data.get("version", 0) != VERSION or not data.get("state", {}) is Dictionary: return false
	var candidate = data.get("state", {})
	if candidate.get("players", []).size() != 4 or candidate.get("phase", "") not in ["turn", "claim", "settled"]: return false
	# Replay the accepted journal instead of trusting serialized scores / moves.
	var initial = data.get("opening", {})
	if not initial is Dictionary or not initial.get("wall", []) is Array: return false
	if initial.get("wall", []).size() != 144: return false
	for tile in initial.wall:
		if not (tile is int or tile is float) or tile != int(tile) or tile < 0 or tile >= 42: return false
	var amounts = Tiles.counts(initial.wall)
	for tile in range(42):
		if amounts[tile] != (4 if tile < 34 else 1): return false
	if not initial.get("settings", {}) is Dictionary or not initial.get("scores", []) is Array: return false
	if not data.get("journal", []) is Array: return false
	for entry in data.get("journal", []):
		if not entry is Dictionary or not entry.get("action", {}) is Dictionary: return false
		if not entry.has("seat") or not entry.has("revision") or not entry.action.has("id"): return false
	var check = GameEngine.new()
	check.start(initial.settings, int(initial.seed), int(initial.round), initial.scores, initial.wall)
	check.state.dice = initial.get("dice", [1,1]).map(func(n): return int(n))
	check.opening.dice = check.state.dice.duplicate()
	for entry in data.get("journal", []):
		if not check.submit(int(entry.seat), int(entry.revision), str(entry.action.id)): return false
	state = check.state; opening = check.opening; journal = check.journal
	rng.state = int(data.get("rng_state", "1"))
	return true
