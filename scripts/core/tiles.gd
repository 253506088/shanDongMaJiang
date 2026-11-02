class_name Tiles
extends RefCounted

const HONOR_NAMES = ["东", "南", "西", "北", "中", "發", "白"]
const FLOWER_NAMES = ["春", "夏", "秋", "冬", "梅", "兰", "竹", "菊"]
const NUMERALS = ["一", "二", "三", "四", "五", "六", "七", "八", "九"]
const ORPHANS = [0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33]

static func title(tile: int) -> String:
	if tile < 0: return "暗牌"
	if tile < 27: return NUMERALS[tile % 9] + ["万", "筒", "条"][tile / 9]
	if tile < 34: return HONOR_NAMES[tile - 27]
	return FLOWER_NAMES[tile - 34]

static func code(tile: int) -> String:
	if tile < 27: return ["m", "p", "s"][tile / 9] + str(tile % 9 + 1)
	if tile < 34: return ["east", "south", "west", "north", "red", "green", "white"][tile - 27]
	return "f" + str(tile - 33)

static func from_code(value: String) -> int:
	for tile in range(42):
		if code(tile) == value: return tile
	return -1

static func eye(tile: int) -> bool:
	return tile >= 0 and tile < 27 and tile % 9 in [1, 4, 7]

static func wall() -> Array:
	var result: Array = []
	for tile in range(34):
		for copy in range(4): result.append(tile)
	result.append_array(range(34, 42))
	return result

static func counts(hand: Array) -> Array:
	var result: Array = []
	result.resize(42)
	result.fill(0)
	for tile in hand:
		if tile >= 0 and tile < 42: result[int(tile)] += 1
	return result

static func ensure_tail(wall_tiles: Array) -> void:
	if wall_tiles.is_empty() or wall_tiles.back() < 34: return
	for i in range(wall_tiles.size()):
		if wall_tiles[i] < 34:
			var flower = wall_tiles.back()
			wall_tiles[-1] = wall_tiles[i]
			wall_tiles[i] = flower
			return
