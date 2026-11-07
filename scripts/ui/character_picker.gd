extends Control
signal selected(id: String)
signal dismissed
var current_id = Characters.DEFAULT

func _ready() -> void:
	name = "CharacterPicker"; size = Vector2(1600, 900); mouse_filter = MOUSE_FILTER_STOP
	var shade = ColorRect.new(); shade.size = size; shade.color = Color("031815dc"); add_child(shade)
	var panel = UI.panel(self, Rect2(240, 90, 1120, 720), Color("12372ffb"), UI.GOLD, 24)
	UI.label(panel, Rect2(38, 25, 940, 52), "选择角色", 34, UI.GOLD)
	UI.button(panel, Rect2(1014, 27, 67, 48), "×", func():dismissed.emit())
	UI.label(panel, Rect2(38, 85, 1044, 42), "麻将沿用莲花原声 · 斗地主、唬牌按角色性别播报 · 选择自动保存", 22, UI.TEXT)
	for index in range(8):
		var id = Characters.IDS[index]; var character = Characters.info(id)
		var x = 38 + (index % 4) * 263; var y = 149 + (index / 4) * 229
		var card = UI.button(panel, Rect2(x, y, 250, 213), "", func(): selected.emit(id), id == current_id)
		card.set_meta("character_id", id)
		UI.portrait(card, Vector2(78, 15), 94, index, id)
		var ink = Color("342e21") if id == current_id else UI.TEXT
		var title = UI.label(card, Rect2(10, 115, 230, 35), character.name + (" · 已选" if id == current_id else ""), 23, ink, true)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var subtitle = ("女角色" if character.gender == "female" else "男角色") + (" · 头像待交付" if not ResourceLoader.exists(character.avatar) else (" · 临时头像" if character.temporary else ""))
		var detail = UI.label(card, Rect2(9, 158, 232, 35), subtitle, 17, ink)
		detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.label(panel, Rect2(38, 640, 1044, 42), "角色不影响打牌。同桌可选相同角色，以边框颜色区分。", 20, UI.MUTED)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed: accept_event()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		dismissed.emit(); get_viewport().set_input_as_handled()
