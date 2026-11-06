class_name DdzCardThemes
extends RefCounted
## Availability is an explicit release decision. Dropping unfinished artwork
## into the project must not make a preview selectable in a saved preference.
const DEFAULT = "traditional"
const CATALOG = [
	{
		"id": "traditional", "name": "传统扑克牌", "available": true,
		"status": "已可使用", "preview_only": false,
		"description": "标准花色点阵与双头 J / Q / K 人物。"
	},
	{
		"id": "guofeng", "name": "国风青玉", "available": false,
		"status": "等待专属插画", "preview_only": true,
		"description": "保留标准角标，定制人物、JOKER 与牌背。"
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
