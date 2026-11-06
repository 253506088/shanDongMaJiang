extends RefCounted
## Pure deterministic rules. No scene, IO, Mahjong or Dou Dizhu dependency.
const Cards = preload("res://scripts/bluff/core/cards.gd")
const Recorder = preload("res://scripts/bluff/core/recorder.gd")
const Knowledge = preload("res://scripts/bluff/core/knowledge.gd")
var state: Dictionary = {}
var rng = RandomNumberGenerator.new()

static func options(raw: Dictionary = {}) -> Dictionary:
	return {"players": clampi(int(raw.get("players", 3)), 3, 6),
		"challenge": "any" if raw.get("challenge", "turn") == "any" else "turn"}

func start(seed_value: int, settings: Dictionary = {}) -> void:
	rng.seed = seed_value
	var config = options(settings)
	var count = config.players
	var decks = 1 if count == 3 else 2
	var deck: Array = range(decks * 54)
	for i in range(deck.size() - 1, 0, -1):
		var other = rng.randi_range(0, i)
		var temp = deck[i]; deck[i] = deck[other]; deck[other] = temp
	var hands: Array = []
	var stats: Array = []
	for seat in range(count):
		hands.append([])
		stats.append({"plays": 0, "caught": 0, "calls": 0, "collected": 0})
	# Random dealing origin avoids always giving seat zero the extra card.
	var origin = rng.randi_range(0, count - 1)
	for i in range(deck.size()): hands[(i + origin) % count].append(deck[i])
	state = {"config": config, "decks": decks, "hands": hands, "stats": stats,
		"phase": "rps", "revision": 0, "turn": -1, "contenders": range(count),
		"rps_round": 0, "pile": [], "dead": [], "last": {}, "passed": [],
		"rank": 0, "event": {}, "history": [], "trick": [], "winner": -1, "next_leader": -1}
	state["recorder"] = Recorder.create(count)
	state["knowledge"] = Knowledge.create(count)

func act(seat: int, action: Dictionary) -> bool:
	if state.is_empty() or action.get("revision", -1) != state.revision: return false
	var type = action.get("type", "")
	if state.phase == "rps":
		if type != "rps" or seat != 0 or typeof(action.get("gesture")) != TYPE_INT or action.gesture not in [0, 1, 2]: return false
		_rps(action.gesture)
	elif state.phase == "review":
		if type != "continue" or seat != 0: return false
		state.phase = "playing"; state.turn = state.next_leader
		state.event = {"type": "lead", "seat": state.turn}
	elif state.phase == "playing":
		if seat < 0 or seat >= state.config.players: return false
		if type == "challenge":
			if not can_challenge(seat): return false
			_challenge(seat)
		else:
			if seat != state.turn: return false
			if type == "play":
				var cards = action.get("cards", [])
				var declared = action.get("rank", state.rank)
				if not cards is Array or cards.is_empty() or not Cards.valid(cards, state.decks): return false
				if not cards.all(func(id): return id in state.hands[seat]): return false
				if typeof(declared) != TYPE_INT or declared not in Cards.DECLARATIONS: return false
				# Any nonempty owned selection can be declared, even an obviously
				# impossible claim. Truth is checked only when another player calls.
				if not state.last.is_empty() and declared != state.rank: return false
				# A new declaration accepts the previous player's final hand.
				if not state.last.is_empty() and state.hands[state.last.seat].is_empty():
					_finish(state.last.seat, "accepted")
				else: _play(seat, cards, declared)
			elif type == "pass":
				if state.last.is_empty(): return false
				_pass(seat)
			else: return false
	else: return false
	state.revision += 1
	return true

func can_challenge(seat: int) -> bool:
	return not state.is_empty() and state.phase == "playing" and not state.last.is_empty() and seat >= 0 and seat < state.config.players and seat != state.last.seat and (state.config.challenge == "any" or seat == state.turn)

func _rps(human: int) -> void:
	var gestures: Array = []
	var used: Array = []
	for seat in range(state.config.players):
		var gesture = (human if seat == 0 else rng.randi_range(0, 2)) if seat in state.contenders else -1
		gestures.append(gesture)
		if gesture >= 0 and gesture not in used: used.append(gesture)
	state.rps_round += 1
	# 0 rock, 1 scissors, 2 paper. Three kinds or one kind is a tie.
	if used.size() == 2:
		var winning = used[0] if (used[0] + 1) % 3 == used[1] else used[1]
		state.contenders = state.contenders.filter(func(seat): return gestures[seat] == winning)
	state.event = {"type": "rps", "gestures": gestures, "remaining": state.contenders.duplicate(), "round": state.rps_round}
	if state.contenders.size() == 1:
		state.phase = "review"; state.next_leader = state.contenders[0]
		state.event["leader"] = state.next_leader
	_record(state.event)

func _play(seat: int, cards: Array, declared: int) -> void:
	if not state.last.is_empty(): Knowledge.responded(state.knowledge, seat, false)
	Knowledge.sync_own(state.knowledge, seat, state.hands[seat])
	Knowledge.played(state.knowledge, seat, cards, declared, state.hands[seat].size())
	for id in cards: state.hands[seat].erase(id)
	state.pile.append_array(cards)
	state.last = {"seat": seat, "cards": cards.duplicate(), "rank": declared, "count": cards.size(), "revision": state.revision + 1}
	state.rank = declared; state.passed.clear()
	state.turn = (seat + 1) % state.config.players
	state.stats[seat].plays += 1
	state.event = {"type": "play", "seat": seat, "rank": declared, "count": cards.size(), "empty": state.hands[seat].is_empty()}
	state.trick.append(state.event.duplicate(true))
	_record(state.event)

func _pass(seat: int) -> void:
	Knowledge.responded(state.knowledge, seat, false)
	state.passed.append(seat)
	state.event = {"type": "pass", "seat": seat}
	_record(state.event)
	if state.passed.size() == state.config.players - 1:
		var leader = state.last.seat
		state.event = {"type": "dead", "count": state.pile.size(), "seat": leader}
		Recorder.clear_pile(state.recorder, state.trick, state.pile)
		Knowledge.cleared(state.knowledge)
		state.dead.append_array(state.pile)
		_reset_trick(leader)
		# A unanimous pass starts the next trick in this same accepted action.
		# Keep the dead event for the log/recorder, without a review interstitial.
		state.phase = "playing"; state.turn = leader
		_record(state.event)
		if state.hands[leader].is_empty(): _finish(leader, "passed")
	else: state.turn = (seat + 1) % state.config.players

func _challenge(seat: int) -> void:
	var last = state.last
	var truthful = last.cards.all(func(id): return Cards.matches(id, last.rank))
	var loser = seat if truthful else last.seat
	var leader = last.seat if truthful else seat
	state.stats[seat].calls += 1
	if not truthful: state.stats[seat].caught += 1
	state.stats[loser].collected += state.pile.size()
	state.event = {"type": "challenge", "caller": seat, "seat": last.seat, "rank": last.rank,
		"cards": last.cards.duplicate(), "truthful": truthful, "loser": loser, "count": state.pile.size(), "leader": leader}
	Knowledge.responded(state.knowledge, seat, true)
	Knowledge.revealed(state.knowledge, last.seat, loser, last.cards, truthful)
	state.hands[loser].append_array(state.pile)
	Knowledge.sync_own(state.knowledge, loser, state.hands[loser])
	_reset_trick(leader)
	_record(state.event)
	if truthful and state.hands[last.seat].is_empty(): _finish(last.seat, "proved")

func _reset_trick(leader: int) -> void:
	state.pile = []; state.last = {}; state.passed = []; state.trick = []; state.rank = 0
	state.phase = "review"; state.turn = -1; state.next_leader = leader

func _finish(seat: int, reason: String) -> void:
	state.winner = seat; state.phase = "finished"; state.turn = -1
	state["finish_reason"] = reason
	_record({"type": "win", "seat": seat, "reason": reason})

func _record(event: Dictionary) -> void:
	state.history.append(event.duplicate(true))
	if state.history.size() > 80: state.history.pop_front()

func view(seat: int) -> Dictionary:
	if state.is_empty() or seat < 0 or seat >= state.config.players: return {}
	var result = {}
	for key in ["config", "decks", "phase", "revision", "turn", "contenders", "rps_round", "rank", "passed", "event", "winner", "next_leader", "stats", "history", "trick"]:
		result[key] = state[key]
	result = result.duplicate(true)
	result["seat"] = seat
	result["hand"] = Cards.sorted(state.hands[seat])
	result["hand_counts"] = state.hands.map(func(hand): return hand.size())
	result["pile_count"] = state.pile.size(); result["dead_count"] = state.dead.size()
	result["last"] = {} if state.last.is_empty() else {"seat": state.last.seat, "rank": state.last.rank, "count": state.last.count, "revision": state.last.revision}
	result["can_challenge"] = can_challenge(seat)
	result["finish_reason"] = state.get("finish_reason", "")
	result["recorder"] = Recorder.view(state.recorder, seat)
	result["memory"] = Knowledge.view(state.knowledge, seat, state.hands[seat])
	return result
