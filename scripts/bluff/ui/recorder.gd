extends Control
## Always-visible totals of this player's own cards that have left the game.
const Kit = preload("res://scripts/ui/ui_kit.gd")
const Cards = preload("res://scripts/bluff/core/cards.gd")
signal inspect_requested
var data: Dictionary = {}

func configure(value: Dictionary) -> void:
	data = value.duplicate(true)
	queue_redraw()

func _ready() -> void:
	size = Vector2(274, 118)
	mouse_filter = MOUSE_FILTER_STOP
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	tooltip_text = "只记你亲自打出并已清掉的真实牌，其他人的盖牌不计入。"
	queue_redraw()

func _draw() -> void:
	draw_style_box(Kit.style(Color("102c28c9"), Kit.LINE, 12), Rect2(Vector2.ZERO, size))
	var font = Kit.font()
	draw_string(font, Vector2(11, 23), "记牌 · 本家已清 %d 张  ›" % int(data.get("total", 0)), HORIZONTAL_ALIGNMENT_LEFT, 255, 19, Kit.ACCENT)
	for column in range(1, 5): draw_line(Vector2(7 + column * 52, 31), Vector2(7 + column * 52, 113), Kit.LINE)
	for row in range(1, 3): draw_line(Vector2(7, 29 + row * 28), Vector2(266, 29 + row * 28), Kit.LINE)
	var ranks: Array = Cards.DECLARATIONS.duplicate(); ranks.append_array([16, 17])
	for index in range(ranks.size()):
		var rank = ranks[index]
		var amount = int(data.get("counts", {}).get(rank, 0))
		var point = Vector2(11 + (index % 5) * 52, 52 + int(index / 5) * 28)
		var name = "小王" if rank == 16 else ("大王" if rank == 17 else Cards.label(rank))
		draw_string(font, point, name, HORIZONTAL_ALIGNMENT_LEFT, 31, 15 if rank >= 16 else 18, Kit.MUTED)
		draw_string(font, point + Vector2(31, 0), str(amount), HORIZONTAL_ALIGNMENT_RIGHT, 15, 20, Kit.ACCENT if amount > 0 else Kit.MUTED)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		inspect_requested.emit()
		accept_event()
