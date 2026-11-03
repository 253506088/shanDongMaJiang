class_name UI
extends RefCounted
const INK = Color("234047")
const ACCENT = Color("187f80")
# Keep the existing semantic name for callers: emphasis now uses sea-glass teal.
const GOLD = ACCENT
const TEXT = INK
const MUTED = Color("647b80")
const PAPER = Color("f8fbfa")
const SURFACE = Color("f8fbfaf2")
const LINE = Color("d4e3e2")
const SOFT = Color("e5f0ed")
const CORAL = Color("d77763")

static func font(_serif: bool = false) -> Font:
	return load("res://assets/fonts/NotoSansSC.ttf")

static func style(color: Color, border: Color = Color.TRANSPARENT, radius: int = 12, width: int = 1) -> StyleBoxFlat:
	var box = StyleBoxFlat.new(); box.bg_color = color
	box.border_color = border; box.set_border_width_all(width); box.set_corner_radius_all(radius)
	box.anti_aliasing = true
	box.content_margin_left = 18; box.content_margin_right = 18; box.content_margin_top = 10; box.content_margin_bottom = 10
	return box

static func panel(parent: Node, rect: Rect2, color: Color = SURFACE, border: Color = LINE, radius: int = 14) -> Panel:
	var p = Panel.new(); p.position = rect.position; p.size = rect.size
	var box = style(color,border,radius)
	# Panels place their children explicitly; button padding must not impose a
	# 36x20 minimum on the tiny turn indicator and the tile logo's colored edge.
	box.content_margin_left=0;box.content_margin_right=0;box.content_margin_top=0;box.content_margin_bottom=0
	box.shadow_color = Color("284a4e0d"); box.shadow_size = 6; box.shadow_offset = Vector2(0,3)
	p.add_theme_stylebox_override("panel",box); parent.add_child(p)
	return p

static func label(parent: Node, rect: Rect2, text: String, size: int = 22, color: Color = TEXT, serif: bool = false) -> Label:
	var l = Label.new(); l.position = rect.position; l.size = rect.size; l.text = text
	l.add_theme_font_override("font",font(serif))
	l.add_theme_font_size_override("font_size",size); l.add_theme_color_override("font_color",color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE; parent.add_child(l)
	return l

static func button(parent: Node, rect: Rect2, text: String, callback: Callable, primary: bool = false) -> Button:
	var b = Button.new(); b.position = rect.position; b.size = rect.size; b.text = text
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font",font()); b.add_theme_font_size_override("font_size",18)
	b.add_theme_stylebox_override("normal",style(ACCENT if primary else SURFACE,ACCENT if primary else LINE,12))
	b.add_theme_stylebox_override("hover",style(Color("259697") if primary else Color("e8f5f1"),Color("72b7b2"),12))
	b.add_theme_stylebox_override("pressed",style(Color("116467") if primary else Color("d5e9e4"),ACCENT,12))
	b.add_theme_stylebox_override("focus",style(Color.TRANSPARENT,ACCENT,12,2))
	b.add_theme_stylebox_override("disabled",style(Color("e2ebe8cc"),Color("d8e3e080"),12))
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: b.add_theme_color_override(state,Color.WHITE if primary else TEXT)
	b.add_theme_color_override("font_disabled_color",Color("8b9e9e"))
	b.pressed.connect(callback); parent.add_child(b)
	return b

static func texture(parent: Node, rect: Rect2, image: Texture2D) -> TextureRect:
	var node = TextureRect.new(); node.position = rect.position; node.size = rect.size
	node.texture = image; node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE; parent.add_child(node)
	return node
