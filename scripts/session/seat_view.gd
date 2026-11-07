class_name SeatView
extends RefCounted
## Presentation-only rotation. Always call GameEngine.view(seat) before this.

static func relative(seat: int, local_seat: int) -> int:
	return (seat - local_seat + 4) % 4 if seat >= 0 and seat < 4 else seat

static func for_seat(source: Dictionary, local_seat: int) -> Dictionary:
	if source.is_empty() or local_seat < 0 or local_seat > 3: return {}
	var result = source.duplicate(true)
	result.local_seat = local_seat
	for key in ["dealer", "current", "decision_seat", "claim_from", "claim_seat", "last_normal"]:
		if result.has(key): result[key] = relative(int(result[key]), local_seat)
	var players: Array = []
	for relative_seat in range(4):
		var absolute_seat = (relative_seat + local_seat) % 4
		var player: Dictionary = result.players[absolute_seat]
		player.seat = relative_seat
		player.absolute_seat = absolute_seat
		for meld in player.melds:
			if meld.has("from"): meld.from = relative(int(meld.from), local_seat)
		var private_field: Dictionary = player.get("field_private", {})
		if private_field.has("peek_target"):
			private_field.peek_target = relative(int(private_field.peek_target), local_seat)
		players.append(player)
	result.players = players
	if result.get("characters", []).size() == 4:
		var ids: Array = result.characters.duplicate()
		for seat in range(4): result.characters[seat] = ids[(seat + local_seat) % 4]
	if result.get("field", {}).get("id", "") == "mutation":
		if not FieldRules.valid_assignment(result.field.get("seat_rules")): return {}
		var assigned: Array = result.field.seat_rules.duplicate()
		for seat in range(4): result.field.seat_rules[seat] = assigned[(seat + local_seat) % 4]
	for move in result.get("pending", []):
		if move.has("target"): move.target = relative(int(move.target), local_seat)
	for key in ["event", "last_discard"]:
		if result.get(key, {}).has("seat"):
			result[key].seat = relative(int(result[key].seat), local_seat)
		if result.get(key, {}).has("target"):
			result[key].target = relative(int(result[key].target), local_seat)
	var settlement: Dictionary = result.get("result", {})
	for key in ["winner", "source"]:
		if settlement.has(key): settlement[key] = relative(int(settlement[key]), local_seat)
	if settlement.get("deltas", []).size() == 4:
		var original: Array = settlement.deltas.duplicate()
		for seat in range(4): settlement.deltas[seat] = original[(seat + local_seat) % 4]
	# Physical wall slots are public positions, not tile identities. Rotate their
	# stable identities together with the players so the exposed tail stays put.
	if result.has("wall_slots"):
		# TableLayout.wall enumerates sides in the opposite direction to seats.
		result.wall_slots = result.wall_slots.map(func(slot): return (int(slot) + local_seat * 36) % 144)
	return result
