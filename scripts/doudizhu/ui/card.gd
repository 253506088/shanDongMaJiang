class_name DdzCard
extends Button
## Traditional Bellot/de Beer card artwork, imported with source and LGPL-2.1.
## Input/selection remain owned by the table; this class only draws the face.
const Kit = preload("res://scripts/ui/ui_kit.gd")
const ART_ROOT = "res://assets/doudizhu/cards/"
static var _art: Dictionary = {}
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
	# Face art is downscaled 3–8 times at the table. Mip filtering preserves
	# the average of the fine court-art lines instead of aliasing them.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	mouse_entered.connect(func(): _hovered = true; queue_redraw())
	mouse_exited.connect(func(): _hovered = false; queue_redraw())
	resized.connect(queue_redraw)

func set_chosen(value: bool) -> void:
	chosen = value
	queue_redraw()

func _box(rect: Rect2, fill: Color, line: Color, radius: int, width: int = 1) -> void:
	draw_style_box(Kit.style(fill, line, radius, width), rect)

func _face() -> Texture2D:
	var key = "back" if face_down else "%02d" % clampi(card_id, 0, 53)
	if not _art.has(key): _art[key] = load(ART_ROOT + key + ".png")
	return _art[key]

func _draw() -> void:
	if size.x <= 0 or size.y <= 0: return
	draw_set_transform(Vector2.ZERO, 0, size / Vector2(112, 164))
	_box(Rect2(2, 5, 109, 158), Color("04161369"), Color.TRANSPARENT, 8)
	var texture = _face()
	if texture: draw_texture_rect(texture, Rect2(0, 0, 109, 158), false)
	# Keep the original black/red JOKER lettering visible; do not paint over
	# it with translated labels or a replacement corner background.
	if chosen:
		_box(Rect2(0, 0, 109, 158), Color.TRANSPARENT, Color("e5c982"), 6, 3)
	elif interactive and _hovered and not disabled:
		_box(Rect2(0, 0, 109, 158), Color("ffffff05"), Color("d8c299"), 6, 2)
