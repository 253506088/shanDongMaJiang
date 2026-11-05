class_name DdzCard
extends Button
## Vector card face: the exposed left edge always carries both rank and suit.
## No dependency on the Mahjong tile renderer or on system symbol fonts.
const Kit = preload("res://scripts/ui/ui_kit.gd")
const FACE_FONT = preload("res://assets/fonts/NotoSansSC-Bold.ttf")
var card_id: int = 0
var face_down: bool = false
var chosen: bool = false
var interactive: bool = false
var _hovered: bool = false

func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if interactive else Control.CURSOR_ARROW
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	mouse_entered.connect(func(): _hovered = true; queue_redraw())
	mouse_exited.connect(func(): _hovered = false; queue_redraw())
	resized.connect(queue_redraw)

func set_chosen(value: bool) -> void:
	chosen = value
	queue_redraw()

func _box(rect: Rect2, fill: Color, line: Color, radius: int, width: int = 1) -> void:
	var box = Kit.style(fill, line, radius, width)
	draw_style_box(box, rect)

func _draw() -> void:
	if size.x <= 0 or size.y <= 0: return
	draw_set_transform(Vector2.ZERO, 0, size / Vector2(112, 164))
	_box(Rect2(2, 5, 109, 158), Color("04161369"), Color.TRANSPARENT, 8)
	_box(Rect2(0, 0, 109, 158), Color("eee9dc"), Color("e5c982") if chosen else Color("8a8b7a"), 8, 3 if chosen else 1)
	if face_down:
		_box(Rect2(7, 7, 95, 144), Color("153e3d"), Color("c8ae7280"), 5)
		for y in range(18, 146, 12):
			draw_line(Vector2(13, y), Vector2(96, y - 7), Color("a6baa018"), 1, true)
		draw_circle(Vector2(54.5, 79), 25, Color("cdb47928"))
		draw_arc(Vector2(54.5, 79), 26, 0, TAU, 40, Color("d9c18c"), 1.5, true)
		draw_polyline(PackedVector2Array([Vector2(54.5, 58), Vector2(70, 79), Vector2(54.5, 100), Vector2(39, 79), Vector2(54.5, 58)]), Color("d9c18c"), 1.5, true)
		return
	var joker = card_id >= 52
	var suit = card_id % 4
	var red = card_id == 53 or (not joker and suit in [1, 3])
	var ink = Color("a73e36") if red else Color("203432")
	var rank_value = 3 + card_id / 4
	var rank_text = str(rank_value)
	if rank_value >= 11: rank_text = ["J", "Q", "K", "A", "2"][rank_value - 11] if rank_value <= 15 else ""
	if joker:
		draw_string(FACE_FONT, Vector2(10, 29), "大" if red else "小", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, ink)
		draw_string(FACE_FONT, Vector2(10, 57), "王", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, ink)
		_crown(Vector2(64, 85), 23, ink)
		draw_string(FACE_FONT, Vector2(22, 132), "JOKER", HORIZONTAL_ALIGNMENT_CENTER, 80, 16, ink)
	else:
		draw_string(FACE_FONT, Vector2(8, 34), rank_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 32 if rank_text != "10" else 29, ink)
		_suit(Vector2(22, 54), 11, suit, ink)
		if rank_value in [11, 12, 13]:
			_crown(Vector2(69, 88), 20, Color(ink, 0.85))
			draw_string(FACE_FONT, Vector2(48, 133), rank_text, HORIZONTAL_ALIGNMENT_CENTER, 47, 34, ink)
		else:
			_suit(Vector2(68, 99), 27, suit, Color(ink, 0.94))
		# Opposite corner makes a fully exposed card familiar without weakening
		# the much larger index at the left edge of an overlapped hand.
		draw_set_transform(Vector2(109, 158) * size / Vector2(112, 164), PI, size / Vector2(112, 164))
		draw_string(FACE_FONT, Vector2(7, 25), rank_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, ink)
		_suit(Vector2(16, 38), 7, suit, ink)
		draw_set_transform(Vector2.ZERO, 0, size / Vector2(112, 164))
	if interactive and _hovered and not disabled:
		_box(Rect2(0, 0, 109, 158), Color("ffffff08"), Color("e2c994"), 8, 2)

func _suit(center: Vector2, radius: float, kind: int, color: Color) -> void:
	if kind == 3:
		draw_colored_polygon(PackedVector2Array([center + Vector2(0, -radius), center + Vector2(radius * 0.7, 0), center + Vector2(0, radius), center + Vector2(-radius * 0.7, 0)]), color)
	elif kind == 1:
		draw_circle(center + Vector2(-radius * 0.38, -radius * 0.30), radius * 0.52, color)
		draw_circle(center + Vector2(radius * 0.38, -radius * 0.30), radius * 0.52, color)
		draw_colored_polygon(PackedVector2Array([center + Vector2(-radius * 0.86, -radius * 0.10), center + Vector2(radius * 0.86, -radius * 0.10), center + Vector2(0, radius)]), color)
	elif kind == 0:
		draw_circle(center + Vector2(-radius * 0.34, radius * 0.23), radius * 0.47, color)
		draw_circle(center + Vector2(radius * 0.34, radius * 0.23), radius * 0.47, color)
		draw_colored_polygon(PackedVector2Array([center + Vector2(-radius * 0.78, radius * 0.2), center + Vector2(radius * 0.78, radius * 0.2), center + Vector2(0, -radius)]), color)
		draw_colored_polygon(PackedVector2Array([center + Vector2(0, radius * 0.15), center + Vector2(-radius * 0.32, radius), center + Vector2(radius * 0.32, radius)]), color)
	else:
		for offset in [Vector2(0, -0.43), Vector2(-0.46, 0.23), Vector2(0.46, 0.23)]:
			draw_circle(center + offset * radius, radius * 0.5, color)
		draw_colored_polygon(PackedVector2Array([center + Vector2(0, radius * 0.15), center + Vector2(-radius * 0.32, radius), center + Vector2(radius * 0.32, radius)]), color)

func _crown(center: Vector2, radius: float, color: Color) -> void:
	var points = PackedVector2Array([center + Vector2(-radius, -radius * 0.45), center + Vector2(-radius * 0.6, radius * 0.48), center + Vector2(radius * 0.6, radius * 0.48), center + Vector2(radius, -radius * 0.45), center + Vector2(radius * 0.4, -radius * 0.1), center + Vector2(0, -radius * 0.8), center + Vector2(-radius * 0.4, -radius * 0.1)])
	draw_colored_polygon(points, color)
	draw_line(center + Vector2(-radius * 0.57, radius * 0.7), center + Vector2(radius * 0.57, radius * 0.7), color, 3, true)
