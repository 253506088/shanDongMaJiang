class_name PokerCardThemes
extends RefCounted
## Availability is an explicit release decision. Dropping unfinished artwork
## into the project must not make a preview selectable in a saved preference.
const DEFAULT = "traditional"
const CATALOG = [
	{
		"id": "traditional", "name": "传统扑克牌", "available": true,
		"status": "已可使用", "preview_only": false,
		"description": "标准花色点阵与双头 J / Q / K 人物。",
		"art_root": "res://assets/doudizhu/cards/"
	},
	{
		"id": "guofeng", "name": "国风青玉", "available": true,
		"status": "已可使用", "preview_only": false,
		"description": "青玉双头人物、黑红 JOKER 与回纹牌背。",
		"art_root": "res://assets/doudizhu/guofeng/"
	}
]

static func options() -> Array:
	return CATALOG.duplicate(true)

static func available(id: String) -> bool:
	for theme in CATALOG:
		if theme.id == id: return bool(theme.available)
	return false

static func normalize(value: Variant) -> String:
	if value is String and available(value): return value
	return DEFAULT

static func info(id: String) -> Dictionary:
	for theme in CATALOG:
		if theme.id == id: return theme.duplicate(true)
	return CATALOG[0].duplicate(true)

static func art_root(id: String) -> String:
	return str(info(normalize(id)).art_root)
