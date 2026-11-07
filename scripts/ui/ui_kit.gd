class_name UI
extends RefCounted
const INK = Color("f3eddf")
const ACCENT = Color("dec18b")
# One warm, readable palette connects the lobby, table and reading panels.
const GOLD = ACCENT
const TEXT = INK
const MUTED = Color("b6c5bc")
const PAPER = Color("132e2bfA")
const SURFACE = Color("183a34ed")
const LINE = Color("b7c7af38")
const SOFT = Color("23443c")
const CORAL = Color("d77763")
# The playing surface uses translucent panels over the courtyard.
const TABLE_TEXT = Color("f3eddf")
const TABLE_MUTED = Color("a8bab2")
const TABLE_GOLD = Color("dec18b")
const TABLE_SURFACE = Color("102e2cdb")
const TABLE_LINE = Color("b7c7af30")

static func font(emphasis: bool = false) -> Font:
	# Static SemiBold/Bold outlines stay substantial at the small HUD sizes;
	# a single sans family also keeps headings, buttons and numbers consistent.
	return load("res://assets/fonts/NotoSansSC-Bold.ttf" if emphasis else "res://assets/fonts/NotoSansSC.ttf")

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
	b.add_theme_stylebox_override("hover",style(Color("ebd2a2") if primary else Color("2e5149f2"),ACCENT,12))
	b.add_theme_stylebox_override("pressed",style(Color("b99a65") if primary else Color("0c2825f2"),ACCENT,12))
	b.add_theme_stylebox_override("focus",style(Color.TRANSPARENT,ACCENT,12,2))
	b.add_theme_stylebox_override("disabled",style(Color("12302a80"),Color("b7c7af16"),12))
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: b.add_theme_color_override(state,Color("342e21") if primary else TEXT)
	b.add_theme_color_override("font_disabled_color",Color("71877d"))
	b.pressed.connect(callback); parent.add_child(b)
	return b

static func texture(parent: Node, rect: Rect2, image: Texture2D) -> TextureRect:
	var node = TextureRect.new(); node.position = rect.position; node.size = rect.size
	node.texture = image; node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE; parent.add_child(node)
	return node

static func portrait(parent: Node, position: Vector2, diameter: float, seat: int, character_id: String = "", border: Color = Characters.NORMAL_BORDER) -> TextureRect:
	var ring=panel(parent,Rect2(position,Vector2.ONE*diameter),Color("193e38"),border,int(diameter/2))
	ring.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ring.get_theme_stylebox("panel").set_border_width_all(3)
	var node=texture(parent,Rect2(position+Vector2.ONE*3,Vector2.ONE*(diameter-6)),null)
	node.name="CharacterPortrait";node.set_meta("portrait_ring",weakref(ring))
	configure_portrait(node,Characters.default_for_seat(seat) if character_id.is_empty() else character_id,border)
	return node

static func configure_portrait(node: TextureRect, id: String, border: Color = Characters.NORMAL_BORDER) -> void:
	var character=Characters.info(id)
	node.texture=load(character.avatar) if ResourceLoader.exists(character.avatar) else null
	node.set_meta("character_id",character.id);node.set_meta("border_color",border)
	node.tooltip_text=character.name+" · "+("女" if character.gender=="female" else "男")
	var ring=node.get_meta("portrait_ring").get_ref()
	if is_instance_valid(ring):ring.get_theme_stylebox("panel").border_color=border

static func table_style(active: bool = false, radius: int = 14) -> StyleBoxFlat:
	var box = style(Color("25483fec") if active else TABLE_SURFACE,TABLE_GOLD if active else TABLE_LINE,radius)
	box.set_border_width_all(2 if active else 1)
	box.set_content_margin_all(0)
	box.shadow_color=Color("030e1038");box.shadow_size=9;box.shadow_offset=Vector2(0,4)
	return box

static func table_panel(parent: Node, rect: Rect2, active: bool = false, radius: int = 14) -> Panel:
	var p=Panel.new();p.position=rect.position;p.size=rect.size
	p.add_theme_stylebox_override("panel",table_style(active,radius));parent.add_child(p)
	return p

static func table_button(parent: Node, rect: Rect2, text: String, callback: Callable, primary: bool = false, icon_name: String = "") -> Button:
	var b=button(parent,rect,text,callback)
	b.add_theme_font_size_override("font_size",20 if primary else 18)
	var normal=style(Color("d9bb83") if primary else Color("123330dc"),Color("f0d6a3") if primary else TABLE_LINE,12)
	normal.content_margin_left=12;normal.content_margin_right=12
	normal.shadow_color=Color("051a1940");normal.shadow_size=7;normal.shadow_offset=Vector2(0,4)
	b.add_theme_stylebox_override("normal",normal)
	b.add_theme_stylebox_override("hover",style(Color("ebd2a2") if primary else Color("2e5149f2"),TABLE_GOLD,12))
	b.add_theme_stylebox_override("pressed",style(Color("b99a65") if primary else Color("0c2825f2"),TABLE_GOLD,12))
	b.add_theme_stylebox_override("focus",style(Color.TRANSPARENT,TABLE_GOLD,12,2))
	b.add_theme_stylebox_override("disabled",style(Color("12302a80"),Color("b7c7af16"),12))
	for state in ["normal","hover","pressed","focus","disabled"]:
		var box=b.get_theme_stylebox(state)
		box.content_margin_left=12;box.content_margin_right=12
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		b.add_theme_color_override(state,Color("342e21") if primary else TABLE_TEXT)
	b.add_theme_color_override("font_disabled_color",Color("71877d"))
	if not icon_name.is_empty():
		b.icon=load("res://assets/icons/"+icon_name+".svg")
		b.add_theme_constant_override("icon_max_width",21)
		b.add_theme_constant_override("h_separation",10)
		b.add_theme_color_override("icon_normal_color",TABLE_MUTED)
		b.add_theme_color_override("icon_hover_color",TABLE_TEXT)
		b.add_theme_color_override("icon_disabled_color",Color("71877d"))
	return b
