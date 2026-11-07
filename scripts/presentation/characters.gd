class_name Characters
extends RefCounted
## Presentation metadata only. Never part of rules, shuffle, scoring or replay.
const DEFAULT = "male_01"
const IDS = ["male_01", "male_02", "male_03", "male_04", "female_01", "female_02", "female_03", "female_04"]
const NAMES = ["听松", "知秋", "怀竹", "行舟", "清和", "观澜", "望舒", "映雪"]
const DEFAULT_SEATS = ["male_01", "male_02", "female_02", "male_03", "female_03", "female_04"]
const COLORS = [Color("e8bd6a"), Color("69c6ed"), Color("de8aca"), Color("8cd59a"), Color("e99572"), Color("aaa0ef")]
const NORMAL_BORDER = Color("dbc596")

static func valid(id) -> bool:
	return id is String and id in IDS

static func normalize(id) -> String:
	return id if valid(id) else DEFAULT

static func info(id) -> Dictionary:
	var normalized = normalize(id)
	return {"id": normalized, "name": NAMES[IDS.find(normalized)], "gender": "female" if normalized.begins_with("female_") else "male", "avatar": "res://assets/ui/characters/%s.png" % normalized, "temporary": normalized in ["female_03", "male_04"]}

static func default_for_seat(seat: int) -> String:
	return DEFAULT_SEATS[posmod(seat, DEFAULT_SEATS.size())]

static func roster(selected, count: int) -> Array:
	var result: Array = []
	for seat in range(count): result.append(normalize(selected) if seat == 0 else default_for_seat(seat))
	return result

static func at(view: Dictionary, seat: int) -> String:
	if seat < 0: return DEFAULT
	var ids = view.get("characters", [])
	if ids is Array and seat >= 0 and seat < ids.size(): return normalize(ids[seat])
	var players = view.get("players", [])
	if players is Array and seat >= 0 and seat < players.size() and players[seat].has("character_id"):
		return normalize(players[seat].character_id)
	return default_for_seat(seat)

static func voice_for(view: Dictionary, seat: int, fallback: String = "male") -> String:
	# Legacy audio fixtures have no cosmetic roster; live sessions always add it.
	if not view.has("characters") and not view.get("players", []).any(func(p):return p.has("character_id")): return fallback
	return info(at(view, seat)).gender

static func border(view: Dictionary, seat: int) -> Color:
	var ids: Array = view.get("characters", [])
	if ids.count(at(view, seat)) < 2: return NORMAL_BORDER
	var absolute = seat
	if view.get("players", []).size() > seat: absolute = int(view.players[seat].get("absolute_seat", seat))
	return COLORS[posmod(absolute, COLORS.size())]

static func decorate(view: Dictionary, ids: Array) -> Dictionary:
	# Call with a fresh engine view, never with authority state.
	view["characters"] = ids.map(normalize)
	for seat in range(view.get("players", []).size()):
		view.players[seat]["character_id"] = view.characters[seat]
	return view
