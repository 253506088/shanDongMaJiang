class_name GameEngine
extends RefCounted
## Authoritative, synchronous state machine. One accepted command = one revision.
## Local play uses this directly; a future LAN host can expose the same contract.

const VERSION = 1
const LEGACY_FIELD_VERSION = 2
const FIELD_VERSION = 3
var state: Dictionary = {}
var journal: Array = []
var opening: Dictionary = {}
var rng = RandomNumberGenerator.new()

func start(settings: Dictionary = {}, game_seed: int = 0, round_number: int = 1, scores: Array = [], initial_wall: Array = [], field_override: String = "", replay_version: int = 0) -> void:
	rng.seed = game_seed if game_seed != 0 else int(Time.get_unix_time_from_system())
	var config = {"jiang": "258", "chi": true, "ai": "efficiency", "rounds": 4, "takeover": false}
	config.merge(settings, true)
	if config.jiang not in ["258", "luan"]: config.jiang = "258"
	if config.ai not in ["classic", "efficiency"]: config.ai = "efficiency"
	config.rounds = int(config.rounds) if config.rounds is int or config.rounds is float else 4
	if config.has("field_rules"): config.field_rules = config.field_rules is bool and config.field_rules
	if config.has("field_selection"): config.field_selection = FieldRules.selection(config)
	var field_rng = RandomNumberGenerator.new()
	field_rng.seed = rng.seed ^ (round_number * 104729)
	var field_id = ""
	if config.get("field_rules", false):
		field_id = FieldRules.IDS[field_rng.randi_range(0, FieldRules.IDS.size() - 1)]
		var selected_field = FieldRules.selection(config)
		if selected_field in FieldRules.IDS: field_id = selected_field
		if field_override in FieldRules.IDS: field_id = field_override
	scores = scores.map(func(n): return int(n))
	# JSON decodes numbers as floats; normalize at the protocol boundary.
	var wall = initial_wall.map(func(t): return int(t)) if not initial_wall.is_empty() else Tiles.wall()
	if field_id == "no_honors":
		for i in range(144):
			# Consume the same deterministic random stream on replay.
			if i >= 108 and i < 136:
				var replacement = field_rng.randi_range(0, 26)
				if initial_wall.is_empty(): wall[i] = replacement
	if initial_wall.is_empty():
		for i in range(wall.size() - 1, 0, -1):
			var j = rng.randi_range(0, i)
			var t = wall[i]; wall[i] = wall[j]; wall[j] = t
	Tiles.ensure_tail(wall)
	opening = {"settings": config.duplicate(true), "wall": wall.duplicate(), "round": round_number, "scores": scores.duplicate(), "seed": str(rng.seed)}
	journal = []
	state = {"version": VERSION, "revision": 0, "settings": config, "round": round_number, "dealer": (round_number - 1) % 4, "phase": "turn", "current": (round_number - 1) % 4, "wall": wall, "players": [], "pending": [], "last_discard": {}, "first_discard": true, "last_normal": -1, "result": {}, "event": {"kind": "opening", "seat": 0}, "claim_stage": "", "claim_from": -1, "claim_tile": -1, "claim_seat": -1, "claim_queue": [], "added_index": -1, "dice": [rng.randi_range(1, 6), rng.randi_range(1, 6)]}
	if not field_id.is_empty():
		state.version = LEGACY_FIELD_VERSION if replay_version == LEGACY_FIELD_VERSION else FIELD_VERSION
		state.field = {"id": field_id, "tile_totals": Tiles.counts(wall)}
		opening.field_id = field_id
		if field_id == "chosen":
			var choices = range(27)
			state.field.chosen_tiles = []
			for _i in range(3): state.field.chosen_tiles.append(choices.pop_at(field_rng.randi_range(0, choices.size() - 1)))
		if field_id == "transparent":
			state.wall_hidden = []
			state.wall_hidden.resize(wall.size()); state.wall_hidden.fill(false)
			for tile in range(34):
				var indices = []
				for i in range(wall.size()):
					if wall[i] == tile: indices.append(i)
				state.wall_hidden[indices[field_rng.randi_range(0, indices.size() - 1)]] = true
	opening.dice = state.dice.duplicate()
	# Public physical slots parallel the private wall. The tail's top tile is the
	# exposed kong head; identities remain stable after head/tail/flower draws.
	state.wall_slots=range(144)
	state.wall_slots[142]=143;state.wall_slots[143]=142
	for seat in range(4):
		var player = {"seat": seat, "name": ["我", "听松", "观澜", "知秋"][seat], "score": scores[seat] if scores.size() == 4 else 2000, "hand": [], "melds": [], "discards": [], "bao": false, "ming": false, "passed_hu": false, "passed_peng": [], "drawn": -1}
		if not field_id.is_empty():
			player.merge({"field_used": false, "field_private": {}, "revealed_hand": false, "last_draw_head": -1})
		if field_id == "angels_gift" and state.version >= FIELD_VERSION:
			player.gift_ready = false
			player.gift_draw_slot = -1
		if field_id == "transparent": player.hidden = []
		var count = 14 if seat == state.dealer else 13
		for _i in range(count):
			var hidden = state.wall_hidden.pop_front() if state.has("wall_hidden") else false
			_hand_add(player, wall.pop_front(), hidden); state.wall_slots.pop_front()
		state.players.append(player)
	for p in state.players:
		while true:
			var flower_index = -1
			for i in range(p.hand.size()):
				if p.hand[i] >= 34: flower_index = i; break
			if flower_index < 0: break
			var tile = _hand_remove(p, flower_index)
			p.melds.append({"type": "flower", "tile": tile, "tiles": [tile]})
			if not wall.is_empty():
				var hidden = state.wall_hidden.pop_back() if state.has("wall_hidden") else false
				_hand_add(p, wall.pop_back(), hidden); state.wall_slots.pop_back()
				_expose_wall_tail()
		_sort_hand(p)
	_ensure_tail()
	state.gang_head = wall.back() if not wall.is_empty() else -1
	var dealer = state.players[state.dealer]
	dealer.drawn = dealer.hand.size() - 1
	if field_id == "exchange":
		state.exchange_seat = state.dealer
		state.exchange_picks = {}
		_exchange_options()
		return
	_opening_options()

func _opening_options() -> void:
	var dealer = state.players[state.dealer]
	for p in state.players:
		if Rules.flower_count(p.melds) == 8:
			_settle(p.seat, {"self_draw": true, "tile": p.melds.back().tile})
			return
	if _winning(dealer.hand, dealer.melds):
		_settle(state.dealer, {"self_draw": true, "tianhu": true, "tile": dealer.hand.back()})
	else: _turn_options()

func _luan() -> bool:
	return state.settings.jiang == "luan"

func _field_id() -> String:
	return state.get("field", {}).get("id", "")

func _winning(hand: Array, melds: Array) -> bool:
	return Rules.winning(hand, melds, _luan(), _field_id())

func _waits(hand: Array, melds: Array) -> Array:
	return Rules.waits(hand, melds, _luan(), _field_id())

func _hand_add(p: Dictionary, tile: int, hidden: bool = false) -> void:
	p.hand.append(tile)
	if p.has("hidden"): p.hidden.append(hidden)

func _hand_remove(p: Dictionary, index: int) -> int:
	if p.has("hidden"): p.hidden.remove_at(index)
	return p.hand.pop_at(index)

func _hand_erase(p: Dictionary, tile: int) -> void:
	var index = p.hand.find(tile)
	if index >= 0: _hand_remove(p, index)

func _sort_hand(p: Dictionary) -> void:
	if not p.has("hidden"):
		p.hand.sort(); return
	var pairs = []
	for i in range(p.hand.size()): pairs.append([p.hand[i], p.hidden[i]])
	pairs.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and not a[1] and b[1]))
	p.hand = pairs.map(func(pair): return pair[0])
	p.hidden = pairs.map(func(pair): return pair[1])

func _ensure_tail() -> void:
	if state.has("wall_hidden") and not state.wall.is_empty() and state.wall.back() >= 34:
		for i in range(state.wall.size()):
			if state.wall[i] < 34:
				var hidden = state.wall_hidden[-1]
				state.wall_hidden[-1] = state.wall_hidden[i]; state.wall_hidden[i] = hidden
				break
	Tiles.ensure_tail(state.wall)

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
	if locked and _winning(p.hand, p.melds): _option("win")
	var c = Tiles.counts(p.hand)
	if not locked:
		for tile in range(34):
			if c[tile] >= 4: _option("angang", {"tile": tile})
		for i in range(p.melds.size()):
			if _can_extend(p.melds[i]) and c[p.melds[i].tile] > 0: _option("bugang", {"meld_index": i, "tile": p.melds[i].tile})
	var waits_by_tile = {}
	for i in range(p.hand.size()):
		if locked and i != p.drawn: continue
		_option("discard", {"index": i, "tile": p.hand[i]})
		if not locked:
			var tile = p.hand[i]
			if not waits_by_tile.has(tile):
				var after = p.hand.duplicate(); after.remove_at(i)
				waits_by_tile[tile] = _waits(after, p.melds)
			if not waits_by_tile[tile].is_empty():
				if not p.get("revealed_hand", false): _option("bao", {"index": i, "tile": tile, "waits": waits_by_tile[tile]})
				_option("ming", {"index": i, "tile": tile, "waits": waits_by_tile[tile]})
	if p.bao and not p.ming: _option("upgrade_ming")
	# Append new locked-hand options so pre-existing replay action IDs stay stable.
	if locked and not state.wall.is_empty() and p.drawn >= 0:
		for tile in range(34):
			if c[tile] >= 4 and _locked_kong_preserves_waits(p, tile):
				_option("angang", {"tile": tile})
		for i in range(p.melds.size()):
			if _can_extend(p.melds[i]) and c[p.melds[i].tile] > 0 and _locked_kong_preserves_waits(p, p.melds[i].tile, i):
				_option("bugang", {"meld_index": i, "tile": p.melds[i].tile})
	_field_options(p)

func _can_extend(meld: Dictionary) -> bool:
	return meld.type == "peng" or (_field_id() in ["diamond_finger", "no_honors"] and meld.type in ["gang", "angang"])

func _locked_kong_preserves_waits(p: Dictionary, tile: int, meld_index: int = -1) -> bool:
	if p.drawn < 0 or p.drawn >= p.hand.size() or p.hand[p.drawn] != tile: return false
	var before = p.hand.duplicate(); before.remove_at(p.drawn)
	var waits_before = _waits(before, p.melds)
	if waits_before.is_empty(): return false
	var after = p.hand.duplicate()
	var melds = p.melds.duplicate(true)
	if meld_index >= 0:
		after.erase(tile)
		melds[meld_index].type = "gang"; melds[meld_index].tiles.append(tile)
	else:
		for _i in range(4): after.erase(tile)
		melds.append({"type":"angang", "tile":tile, "tiles":[tile,tile,tile,tile]})
	return waits_before == _waits(after, melds)

func _external_kong_preserves_waits(p: Dictionary, meld_index: int) -> bool:
	if not p.bao and not p.ming: return true
	var before = _waits(p.hand, p.melds)
	if before.is_empty(): return false
	var melds = p.melds.duplicate(true)
	melds[meld_index].type = "gang"
	melds[meld_index].tiles.append(melds[meld_index].tile)
	return before == _waits(p.hand, melds)

func decision_seat() -> int:
	if state.is_empty() or state.phase == "settled": return -1
	if state.phase == "exchange": return state.exchange_seat
	if state.phase in ["draw_choice", "gift_choice"]: return state.current
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
	if selected.kind.begins_with("field_"):
		_field_submit(seat, selected)
		return true
	if selected.kind == "draw_normal":
		_draw(seat, "normal", true)
		return true
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
				for _i in range(4): _hand_erase(p, selected.tile)
				p.melds.append({"type": "angang", "tile": selected.tile, "tiles": [selected.tile, selected.tile, selected.tile, selected.tile]})
				_sort_hand(p)
				_draw(seat, "kong")
			"bugang":
				state.first_discard = false
				state.added_index = selected.meld_index
				if p.melds[selected.meld_index].type == "angang":
					_hand_erase(p, selected.tile); _sort_hand(p)
					p.melds[selected.meld_index].tiles.append(selected.tile)
					state.event.concealed = true
					_draw(seat, "kong")
				else: _begin_claims(seat, selected.tile, true)
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
	var tile = _hand_remove(p, index)
	_sort_hand(p); p.drawn = -1
	if p.has("gift_ready"): p.gift_ready = false; p.gift_draw_slot = -1
	if p.has("last_draw_head"): p.last_draw_head = -1
	p.discards.append(tile)
	state.last_discard = {"tile": tile, "seat": seat, "revision": state.revision}
	state.event.tile = tile
	var first = state.first_discard and seat == state.dealer
	state.first_discard = false
	if first:
		for distance in range(1, 4):
			var candidate = (seat + distance) % 4
			var other = state.players[candidate]
			if not other.ming and not other.get("revealed_hand", false) and not other.passed_hu and _winning(other.hand + [tile], other.melds) and (_field_id() != "single_wait" or _waits(other.hand, other.melds).size() == 1):
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
		if p.bao and not p.ming and not p.get("revealed_hand", false) and not p.passed_hu and _winning(p.hand + [tile], p.melds): state.claim_queue.append(seat)
	_offer_next_claim()

func _offer_next_claim() -> void:
	state.pending = []
	while not state.claim_queue.is_empty():
		var seat = state.claim_queue.pop_front()
		var p = state.players[seat]
		state.claim_seat = seat
		if state.claim_stage in ["ron", "rob"]: _option("win", {"tile": state.claim_tile})
		elif state.claim_stage == "meld":
			if _field_id() == "tolerance" and not state.wall.is_empty():
				for i in range(p.melds.size()):
					if p.melds[i].type == "peng" and p.melds[i].tile == state.claim_tile and _external_kong_preserves_waits(p, i):
						_option("tolerance_gang", {"tile": state.claim_tile, "meld_index": i})
			if p.bao or p.ming:
				if not state.pending.is_empty():
					_option("pass"); return
				continue
			var count = p.hand.count(state.claim_tile)
			if count >= 3: _option("gang", {"tile": state.claim_tile})
			if count >= 2 and state.claim_tile not in p.passed_peng: _option("peng", {"tile": state.claim_tile})
		elif state.claim_stage == "chi":
			if p.bao or p.ming or not state.settings.chi: continue
			for tiles in Rules.chi(p.hand, state.claim_tile, _field_id()): _option("chi", {"tile": state.claim_tile, "tiles": tiles})
		if not state.pending.is_empty():
			_option("pass")
			return
	match state.claim_stage:
		"rob":
			var p = state.players[state.claim_from]
			_hand_erase(p, state.claim_tile)
			_sort_hand(p)
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
	if move.kind == "tolerance_gang":
		var meld = p.melds[move.meld_index]
		meld.type = "gang"; meld.added = true; meld.tiles.append(move.tile)
		state.current = seat
		_draw(seat, "kong")
		return
	var tiles = move.tiles.duplicate() if move.kind == "chi" else [move.tile, move.tile, move.tile]
	if move.kind == "gang": tiles.append(move.tile)
	var needed = tiles.duplicate(); needed.erase(move.tile)
	for t in needed: _hand_erase(p, t)
	_sort_hand(p); p.drawn = -1
	p.melds.append({"type": move.kind, "tile": move.tile, "tiles": tiles, "from": state.claim_from})
	state.current = seat
	if move.kind == "gang": _draw(seat, "kong")
	else: _turn_options()

func _draw(seat: int, reason: String = "normal", skip_gift: bool = false) -> void:
	state.last_normal = -1
	var owner = state.players[seat]
	if owner.has("gift_ready"): owner.gift_ready = false; owner.gift_draw_slot = -1
	if owner.has("last_draw_head"): owner.last_draw_head = state.gang_head if reason == "kong" else -1
	# v2 logs keep their original decision IDs and before-draw choice. New games
	# draw normally and offer the ability only after the player sees that tile.
	if state.version == LEGACY_FIELD_VERSION and reason == "normal" and not skip_gift and _field_id() == "angels_gift" and not owner.field_used and not owner.bao and not owner.ming and state.wall.size() >= 4:
		state.current = seat; state.phase = "draw_choice"; state.pending = []
		_option("draw_normal"); _option("field_gift")
		return
	var normal_draw = reason == "normal"
	while true:
		var wall = state.wall
		if wall.is_empty() or (reason != "kong" and wall.size() < 2): _draw_result(); return
		var tile: int
		var hidden = false
		var drawn_slot = -1
		if reason == "normal":
			if state.has("wall_hidden"): hidden = state.wall_hidden.pop_front()
			tile = wall.pop_front(); drawn_slot = state.wall_slots.pop_front()
		elif reason == "flower":
			if state.has("wall_hidden"): hidden = state.wall_hidden.pop_at(wall.size()-2)
			drawn_slot = state.wall_slots.pop_at(wall.size()-2); tile = wall.pop_at(wall.size() - 2)
		else:
			if state.has("wall_hidden"): hidden = state.wall_hidden.pop_back()
			tile = wall.pop_back(); drawn_slot = state.wall_slots.pop_back()
			_expose_wall_tail()
			_ensure_tail()
			state.gang_head = wall.back() if not wall.is_empty() else -1
		var p = state.players[seat]
		if tile >= 34:
			p.melds.append({"type": "flower", "tile": tile, "tiles": [tile]})
			if Rules.flower_count(p.melds) == 8: _settle(seat, {"self_draw": true, "tile": tile}); return
			reason = "flower"
			continue
		_hand_add(p, tile, hidden); p.drawn = p.hand.size() - 1
		if p.has("gift_ready"):
			p.gift_ready = normal_draw and not p.field_used and not p.bao and not p.ming and wall.size() >= 3
			p.gift_draw_slot = drawn_slot if p.gift_ready else -1
		p.passed_hu = false; p.passed_peng = []
		if normal_draw and wall.size() <= 1: state.last_normal = seat
		state.current = seat
		_turn_options()
		return

func _field_options(p: Dictionary) -> void:
	if _field_id().is_empty() or p.get("field_used", false): return
	var locked = p.bao or p.ming
	match _field_id():
		"angels_gift":
			if not locked and p.get("gift_ready", false) and p.drawn >= 0 and p.drawn < p.hand.size() and state.wall.size() >= 3:
				_option("field_gift")
		"diamond_finger":
			if not locked:
				for i in range(p.hand.size()):
					if p.hand[i] != 33: _option("field_transform", {"index": i, "tile": p.hand[i]})
		"rebirth":
			if locked: _option("field_rebirth")
		"reclaim":
			if not locked:
				for i in range(p.melds.size()):
					if p.melds[i].type in ["chi", "peng"]:
						_option("field_reclaim", {"meld_index": i, "tiles": p.melds[i].tiles.duplicate()})
		"astrology_wall":
			if state.wall.size() > 1: _option("field_peek_wall")
		"astrology_waits":
			for other in state.players:
				if other.seat != p.seat and (other.bao or other.ming): _option("field_peek_waits", {"target": other.seat})

func _field_submit(seat: int, move: Dictionary) -> void:
	var p = state.players[seat]
	# Public events never include selected hand indices, missing tile faces,
	# astrology targets, the unchosen draws, or the exchanged packet.
	state.event = {"kind": move.kind, "seat": seat, "tile": -1}
	match move.kind:
		"field_transform":
			p.hand[move.index] = 33; p.field_used = true
			state.field.tile_totals[33] += 1
			state.first_discard = false
			_turn_options()
		"field_rebirth":
			p.bao = false; p.ming = false; p.revealed_hand = true; p.field_used = true
			_turn_options()
		"field_reclaim":
			var meld = p.melds.pop_at(move.meld_index)
			p.hand.append_array(meld.tiles); _sort_hand(p); p.drawn = -1
			p.field_used = true; state.first_discard = false
			_turn_options()
		"field_peek_wall":
			p.field_private.peek_wall = state.wall.slice(0, mini(4, state.wall.size() - 1))
			p.field_used = true; _turn_options()
		"field_peek_waits":
			var target = state.players[move.target]
			var hand = target.hand.duplicate()
			if target.drawn >= 0 and hand.size() % 3 == 2: hand.remove_at(target.drawn)
			p.field_private.peek_target = move.target
			p.field_private.peek_waits = _waits(hand, target.melds)
			p.field_used = true; _turn_options()
		"field_gift":
			p.field_used = true
			if state.version >= FIELD_VERSION:
				var first_tile = _hand_remove(p, p.drawn)
				p.drawn = -1
				p.field_private.gift_tiles = [first_tile]
				p.field_private.gift_after_draw = true
				state.gift_slots = [p.gift_draw_slot]
				for _i in range(2):
					p.field_private.gift_tiles.append(state.wall.pop_front())
					state.gift_slots.append(state.wall_slots.pop_front())
				p.gift_ready = false; p.gift_draw_slot = -1
			else: p.field_private.gift_tiles = state.wall.slice(0, 3)
			state.phase = "gift_choice"; state.pending = []
			for i in range(3): _option("field_gift_pick", {"index": i, "tile": p.field_private.gift_tiles[i]})
		"field_gift_pick":
			var tile: int
			if state.version >= FIELD_VERSION:
				var candidates: Array = p.field_private.gift_tiles
				tile = candidates[move.index]
				# Restore the unchosen physical copies in candidate order. A kept
				# original tile therefore leaves the future wall exactly as it was.
				for i in range(2, -1, -1):
					if i == move.index: continue
					state.wall.push_front(candidates[i])
					state.wall_slots.push_front(state.gift_slots[i])
				state.erase("gift_slots")
				p.field_private.erase("gift_after_draw")
			else:
				tile = state.wall.pop_at(move.index); state.wall_slots.remove_at(move.index)
			p.field_private.erase("gift_tiles")
			p.passed_hu = false; p.passed_peng = []
			if tile >= 34:
				p.melds.append({"type": "flower", "tile": tile, "tiles": [tile]})
				if Rules.flower_count(p.melds) == 8: _settle(seat, {"self_draw": true, "tile": tile})
				else: _draw(seat, "flower", true)
			else:
				_hand_add(p, tile); p.drawn = p.hand.size() - 1
				_turn_options()
		"field_exchange":
			# Collect every choice before transferring, so later seats cannot
			# choose from an incoming packet or infer it from early hand changes.
			state.exchange_picks[str(seat)] = move.indices.duplicate()
			p.field_used = true
			if state.exchange_picks.size() < 4:
				state.exchange_seat = (seat + 1) % 4; _exchange_options()
			else:
				var packets = []
				for owner in state.players:
					var packet = []
					var indices = state.exchange_picks[str(owner.seat)].duplicate()
					indices.sort(); indices.reverse()
					for index in indices: packet.append(_hand_remove(owner, index))
					packets.append(packet)
				for owner in state.players:
					owner.hand.append_array(packets[(owner.seat + 3) % 4]); _sort_hand(owner)
					owner.drawn = owner.hand.size() - 1 if owner.seat == state.dealer else -1
				state.erase("exchange_picks"); state.erase("exchange_seat")
				state.current = state.dealer
				_opening_options()

func _exchange_options() -> void:
	state.phase = "exchange"; state.pending = []
	var p = state.players[state.exchange_seat]
	var suited = p.hand.filter(func(tile): return tile < 27).size()
	var required = mini(3, suited)
	var seen = {}
	for a in range(p.hand.size() - 2):
		for b in range(a + 1, p.hand.size() - 1):
			for c in range(b + 1, p.hand.size()):
				var tiles = [p.hand[a], p.hand[b], p.hand[c]]
				if tiles.filter(func(tile): return tile < 27).size() != required: continue
				var key = str(tiles)
				if seen.has(key): continue
				seen[key] = true
				_option("field_exchange", {"indices": [a, b, c], "tiles": tiles})

func _draw_result() -> void:
	state.phase = "settled"; state.pending = []
	state.result = {"draw": true, "deltas": [0, 0, 0, 0], "winner": -1, "round": state.round}

func _settle(seat: int, flags: Dictionary) -> void:
	var p = state.players[seat]
	var self_draw = flags.get("self_draw", false) or flags.get("tianhu", false)
	var hand = p.hand.duplicate()
	if not self_draw: hand.append(flags.tile)
	flags.merge({"luan": _luan(), "bao": p.bao, "ming": p.ming or p.get("revealed_hand", false), "haidi": self_draw and state.last_normal == seat})
	if not _field_id().is_empty():
		flags.field_id = _field_id()
		flags.field_bonus = _field_bonuses(seat, hand, flags)
	var result = Rules.evaluate(hand, p.melds, flags)
	assert(not result.is_empty(), "Invalid authoritative win")
	var deltas = [0, 0, 0, 0]
	var source = flags.get("source", -1)
	if flags.get("robbed", false): deltas[source] = -result.points * 3 * (2 if _scores_as_ming(state.players[source]) else 1)
	elif self_draw or flags.get("dihu", false):
		for i in range(4):
			if i != seat: deltas[i] = -result.points * (2 if _scores_as_ming(state.players[i]) else 1)
	else: deltas[source] = -result.points * (2 if _scores_as_ming(state.players[source]) else 1)
	for i in range(4):
		if i != seat: deltas[seat] -= deltas[i]
	for i in range(4): state.players[i].score += deltas[i]
	result.merge({"draw": false, "winner": seat, "source": source, "win_tile": flags.tile, "win_hand": hand, "deltas": deltas, "round": state.round})
	state.result = result; state.phase = "settled"; state.pending = []
	state.event = {"kind": "win", "seat": seat, "tile": flags.tile}

func _scores_as_ming(p: Dictionary) -> bool:
	return p.ming or p.get("revealed_hand", false)

func _field_bonuses(seat: int, hand: Array, flags: Dictionary) -> Array:
	var bonuses = []
	match _field_id():
		"single_wait": bonuses.append("听单张")
		"chosen":
			var targets = state.field.chosen_tiles
			if flags.tile in targets or (flags.get("tianhu", false) and hand.any(func(tile): return tile in targets)): bonuses.append("天选")
		"chosen_head":
			var target = state.gang_head
			var player = state.players[seat]
			if flags.get("self_draw", false) and player.get("last_draw_head", -1) >= 0: target = player.last_draw_head
			if flags.tile == target or (flags.get("tianhu", false) and target in hand): bonuses.append("天选·杠头")
		"astrology_waits":
			var source = flags.get("source", -1)
			if source >= 0 and state.players[source].field_private.get("peek_target", -1) == seat: bonuses.append("占星·点炮")
	return bonuses

func view(seat: int) -> Dictionary:
	if state.is_empty(): return {}
	var result = state.duplicate(true)
	result.erase("wall"); result.erase("claim_queue"); result.erase("added_index")
	result.erase("wall_hidden"); result.erase("exchange_picks")
	result.erase("gift_slots")
	result.wall_count = state.wall.size()
	if _field_id() == "transparent": result.gang_head = -1
	result.decision_seat = decision_seat()
	if seat != decision_seat(): result.pending = []
	for p in result.players:
		p.hand_count = p.hand.size()
		p.erase("gift_draw_slot")
		if p.seat != seat: p.erase("gift_ready")
		if _field_id() == "transparent": p.last_draw_head = -1
		if p.has("hidden"):
			p.hand_public = p.hidden.map(func(hidden): return not hidden or p.ming or state.phase == "settled")
		if p.seat != seat:
			p.erase("field_private")
			if not p.ming and not p.get("revealed_hand", false) and state.phase != "settled":
				if _field_id() == "transparent":
					var visible = []
					var opaque = 0
					var drawn_face = -1
					for i in range(p.hand.size()):
						if i == p.drawn:
							drawn_face = -1 if p.hidden[i] else p.hand[i]
							continue
						if p.hidden[i]: opaque += 1
						else: visible.append(p.hand[i])
					visible.sort()
					for _i in range(opaque): visible.append(-1)
					if p.drawn >= 0:
						visible.append(drawn_face); p.drawn = visible.size() - 1
					p.hand = visible
					p.hand_public = visible.map(func(tile): return tile >= 0)
				else: p.hand = []
		if p.seat != seat and state.phase != "settled":
			for meld in p.melds:
				if meld.type == "angang":
					meld.tile = -1
					meld.tiles.fill(-1)
		p.erase("hidden")
		p.erase("passed_hu"); p.erase("passed_peng")
	if state.phase != "settled" and result.event.get("seat", -1) != seat and (result.event.kind == "angang" or result.event.get("concealed", false)):
		result.event.tile = -1
	return result

func snapshot() -> Dictionary:
	return {"version": state.get("version", VERSION), "state": state.duplicate(true), "opening": opening.duplicate(true), "journal": journal.duplicate(true), "rng_state": str(rng.state)}

func restore(data: Dictionary) -> bool:
	var version = data.get("version", 0)
	if not (version is int or version is float) or version != int(version) or int(version) not in [VERSION, LEGACY_FIELD_VERSION, FIELD_VERSION] or not data.get("state", {}) is Dictionary: return false
	var saved_rng = data.get("rng_state", "1")
	if not saved_rng is String or not saved_rng.is_valid_int(): return false
	var candidate = data.get("state", {})
	var players = candidate.get("players", [])
	if not players is Array or players.size() != 4 or candidate.get("phase", "") not in ["turn", "claim", "settled", "exchange", "draw_choice", "gift_choice"]: return false
	# Replay the accepted journal instead of trusting serialized scores / moves.
	var initial = data.get("opening", {})
	if not initial is Dictionary or not initial.get("wall", []) is Array: return false
	for key in ["settings", "scores", "seed", "round"]:
		if not initial.has(key): return false
	if not initial.get("settings", {}) is Dictionary or not initial.get("scores", []) is Array: return false
	if initial.settings.has("field_rules") and not initial.settings.field_rules is bool: return false
	if initial.settings.has("field_selection"):
		var selection = initial.settings.field_selection
		if not selection is String or (selection != "random" and selection not in FieldRules.IDS): return false
	if not initial.get("dice", [1, 1]) is Array or initial.get("dice", [1, 1]).size() != 2: return false
	for die in initial.get("dice", [1, 1]):
		if not (die is int or die is float) or die != int(die) or die < 1 or die > 6: return false
	if not (initial.get("round") is int or initial.get("round") is float) or initial.round != int(initial.round) or initial.round < 1: return false
	if not initial.get("seed", "") is String or not initial.seed.is_valid_int(): return false
	if initial.scores.size() not in [0, 4]: return false
	for score in initial.scores:
		if not (score is int or score is float) or score != int(score): return false
	if initial.get("wall", []).size() != 144: return false
	for tile in initial.wall:
		if not (tile is int or tile is float) or tile != int(tile) or tile < 0 or tile >= 42: return false
	var amounts = Tiles.counts(initial.wall)
	var field_id = str(initial.get("field_id", ""))
	if int(data.version) in [LEGACY_FIELD_VERSION, FIELD_VERSION]:
		if field_id not in FieldRules.IDS or initial.get("settings", {}).get("field_rules", false) != true: return false
	elif not field_id.is_empty() or initial.get("settings", {}).get("field_rules", false): return false
	if int(version) >= FIELD_VERSION:
		var configured_field = FieldRules.selection(initial.settings)
		if configured_field != "random" and configured_field != field_id: return false
	for tile in range(42):
		if field_id == "no_honors":
			if tile < 27 and amounts[tile] < 4: return false
			if tile >= 27 and amounts[tile] != (0 if tile < 34 else 1): return false
		elif amounts[tile] != (4 if tile < 34 else 1): return false
	if not data.get("journal", []) is Array: return false
	for entry in data.get("journal", []):
		if not entry is Dictionary or not entry.get("action") is Dictionary: return false
		if not entry.has("seat") or not entry.has("revision") or not entry.action.has("id"): return false
		for key in ["seat", "revision"]:
			if not (entry[key] is int or entry[key] is float) or entry[key] != int(entry[key]): return false
	var check = GameEngine.new()
	check.start(initial.settings, int(initial.seed), int(initial.round), initial.scores, initial.wall, field_id, int(version))
	check.state.dice = initial.get("dice", [1,1]).map(func(n): return int(n))
	check.opening.dice = check.state.dice.duplicate()
	for entry in data.get("journal", []):
		if not check.submit(int(entry.seat), int(entry.revision), str(entry.action.id)): return false
	state = check.state; opening = check.opening; journal = check.journal
	rng.state = int(saved_rng)
	return true
