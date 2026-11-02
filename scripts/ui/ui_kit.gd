class_name UI
extends RefCounted
const INK = Color("102f2c")
const GOLD = Color("d8bb7b")
const TEXT = Color("f2ecd8")
const MUTED = Color("a0b7a6")

static func font(serif: bool = false) -> Font:
	return load("res://assets/fonts/NotoSerifSC.ttf" if serif else "res://assets/fonts/NotoSansSC.ttf")

static func style(color: Color, border: Color = Color.TRANSPARENT, radius: int = 12, width: int = 1) -> StyleBoxFlat:
	var box = StyleBoxFlat.new(); box.bg_color = color
	box.border_color = border; box.set_border_width_all(width); box.set_corner_radius_all(radius)
	box.content_margin_left = 18; box.content_margin_right = 18; box.content_margin_top = 10; box.content_margin_bottom = 10
	return box

static func panel(parent: Node, rect: Rect2, color: Color = Color("102f2cf0"), border: Color = Color("73836566"), radius: int = 14) -> Panel:
	var p = Panel.new(); p.position = rect.position; p.size = rect.size
	p.add_theme_stylebox_override("panel",style(color,border,radius)); parent.add_child(p)
	return p

static func label(parent: Node, rect: Rect2, text: String, size: int = 22, color: Color = TEXT, serif: bool = false) -> Label:
	var l = Label.new(); l.position = rect.position; l.size = rect.size; l.text = text
	l.add_theme_font_override("font",font(serif))
	l.add_theme_font_size_override("font_size",size); l.add_theme_color_override("font_color",color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE; parent.add_child(l)
	return l

static func button(parent: Node, rect: Rect2, text: String, callback: Callable, primary: bool = false) -> Button:
	var b = Button.new(); b.position = rect.position; b.size = rect.size; b.text = text
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font",font()); b.add_theme_font_size_override("font_size",20)
	b.add_theme_stylebox_override("normal",style(Color("d7bc81") if primary else Color("163f38"),Color("c8b377") if primary else Color("6a826366"),10))
	b.add_theme_stylebox_override("hover",style(Color("efdaa9") if primary else Color("28594b"),GOLD,10))
	b.add_theme_stylebox_override("pressed",style(Color("b49b65") if primary else Color("0c2c26"),GOLD,10))
	b.add_theme_stylebox_override("focus",style(Color.TRANSPARENT,GOLD,10,2))
	b.add_theme_stylebox_override("disabled",style(Color("263e37"),Color("52634a"),10))
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: b.add_theme_color_override(state,INK if primary else TEXT)
	b.add_theme_color_override("font_disabled_color",Color("738778"))
	b.pressed.connect(callback); parent.add_child(b)
	return b

static func texture(parent: Node, rect: Rect2, image: Texture2D) -> TextureRect:
	var node = TextureRect.new(); node.position = rect.position; node.size = rect.size
	node.texture = image; node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE; parent.add_child(node)
	return node
