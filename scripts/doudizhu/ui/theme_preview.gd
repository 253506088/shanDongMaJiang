class_name DdzThemePreview
extends Control
## A layout study, never a playable card theme. The reserved illustration
## slots remain explicitly labelled until user-supplied artwork is accepted.
const DESIGN_SIZE = Vector2(760, 260)
const FONT = preload("res://assets/fonts/NotoSansSC.ttf")
const BOLD = preload("res://assets/fonts/NotoSansSC-Bold.ttf")
const PAPER = Color("f0e9d8")
const JADE = Color("19483e")
const RED = Color("ab3e34")
const GOLD = Color("b59a62")
const SLOT = Color("dce1d4")
const MUTED = Color("637b69")

func _ready() -> void:
	if size == Vector2.ZERO: size = DESIGN_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	if size.x <= 0 or size.y <= 0: return
	var zoom = minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	var offset = (size - DESIGN_SIZE * zoom) * 0.5
	draw_set_transform(offset, 0.0, Vector2.ONE * zoom)
	for index in range(4):
		_draw_card(Vector2(23 + index * 186, 16), ["J", "Q", "K", "JOKER"][index], index)

func _box(rect: Rect2, fill: Color, outline: Color, radius: int, width: int = 1) -> void:
	var box = StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = outline
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	box.anti_aliasing = true
	draw_style_box(box, rect)

func _text(at: Vector2, text: String, font_size: int, color: Color, width: float = -1.0, bold: bool = false) -> void:
	draw_string(BOLD if bold else FONT, at, text, HORIZONTAL_ALIGNMENT_CENTER if width > 0 else HORIZONTAL_ALIGNMENT_LEFT, width, font_size, color)

func _draw_card(at: Vector2, rank: String, suit: int) -> void:
	var ink = RED if suit in [1, 3] else JADE
	_box(Rect2(at + Vector2(3, 5), Vector2(150, 228)), Color("051c1b50"), Color.TRANSPARENT, 12)
	_box(Rect2(at, Vector2(150, 228)), PAPER, GOLD, 10)
	_box(Rect2(at + Vector2(5, 5), Vector2(140, 218)), Color.TRANSPARENT, Color("b59a6255"), 7)
	if rank != "JOKER":
		_text(at + Vector2(13, 39), rank, 33, ink, -1, true)
		_suit(at + Vector2(23, 60), 9.0, suit, ink)
		_text(at + Vector2(116, 213), rank, 22, ink, -1, true)
		_suit(at + Vector2(126, 176), 6.0, suit, ink)
	else:
		_text(at + Vector2(11, 35), "JOKER", 27, ink, 128, true)
		_text(at + Vector2(35, 216), "JOKER", 18, ink, 101, true)
	# A fine illustration window and corner ornament communicate the intended
	# treatment without borrowing existing avatars or pretending it is finished.
	var art = Rect2(at + Vector2(45, 47), Vector2(85, 133)) if rank != "JOKER" else Rect2(at + Vector2(20, 51), Vector2(110, 133))
	_box(art, SLOT, Color("66847066"), 7)
	_corner(art.position + Vector2(7, 7), false)
	_corner(art.end - Vector2(7, 7), true)
	var center = art.get_center() + Vector2(0, -19)
	draw_circle(center, 27, Color("d1daca"))
	draw_arc(center, 28, 0, TAU, 48, Color("a68d594f"), 1.0, true)
	_fan(center + Vector2(0, 5), 20)
	_text(Vector2(art.position.x, art.position.y + 104), "插画待制作", 14, JADE, art.size.x, true)
	_text(Vector2(art.position.x, art.position.y + 123), "版式预览", 12, MUTED, art.size.x)
	# Restrained cloud strokes leave the artwork area quiet and unobstructed.
	_cloud(at + Vector2(21, 195), 0.6)
	if rank != "JOKER": _cloud(at + Vector2(97, 22), 0.55)

func _corner(at: Vector2, reverse: bool) -> void:
	var sign_value = -1.0 if reverse else 1.0
	var points = PackedVector2Array([
		at + Vector2(0, 12) * sign_value, at,
		at + Vector2(12, 0) * sign_value
	])
	draw_polyline(points, GOLD, 1.1, true)

func _fan(center: Vector2, radius: float) -> void:
	var start = deg_to_rad(205)
	var finish = deg_to_rad(335)
	draw_arc(center, radius, start, finish, 30, JADE, 1.25, true)
	for index in range(5):
		var angle = lerpf(start, finish, index / 4.0)
		draw_line(center, center + Vector2(cos(angle), sin(angle)) * radius, Color("527760"), 1.0, true)
	draw_line(center + Vector2(-3, 5), center + Vector2(3, 5), GOLD, 2.0, true)

func _cloud(at: Vector2, scale_value: float) -> void:
	var points = PackedVector2Array([
		Vector2(0, 9), Vector2(8, 9), Vector2(8, 4), Vector2(15, 4),
		Vector2(15, 0), Vector2(24, 0), Vector2(24, 4), Vector2(31, 4),
		Vector2(31, 9), Vector2(39, 9)
	])
	for index in range(points.size()): points[index] = at + points[index] * scale_value
	draw_polyline(points, Color("9b854d8c"), 1.2, true)

func _suit(center: Vector2, radius: float, kind: int, color: Color) -> void:
	if kind == 1:
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
