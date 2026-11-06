class_name DdzThemePreview
extends Control
## Preview uses the same textures and sampler as the playable cards.
const Card = preload("res://scripts/doudizhu/ui/card.gd")
const SAMPLE = [28, 32, 37, 40, 52, 53, -1]
var theme_id = "traditional"

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for id in SAMPLE:
		var card = Card.new()
		card.theme_id = theme_id
		card.card_id = maxi(0, id)
		card.face_down = id < 0
		add_child(card)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	var width = minf((size.x - 6 * 13) / 7.0, size.y * 112.0 / 164.0)
	var height = width * 164.0 / 112.0
	var start = (size.x - (width * 7 + 6 * 13)) * 0.5
	for index in range(get_child_count()):
		var card = get_child(index)
		card.size = Vector2(width, height)
		card.position = Vector2(start + index * (width + 13), (size.y - height) * 0.5)
