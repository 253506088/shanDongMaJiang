class_name DdzTable
extends Control
## An independent three-seat surface. It only receives a seat-cropped view;
## gameplay, AI timing and persistence belong to the Doudizhu session.
const Kit = preload("res://scripts/ui/ui_kit.gd")
const Cards = preload("res://scripts/doudizhu/core/cards.gd")
const Rules = preload("res://scripts/doudizhu/core/rules.gd")
const CardFace = preload("res://scripts/doudizhu/ui/card.gd")
signal action_requested(action: Dictionary)
signal hint_requested
signal next_requested
signal exit_requested
signal pause_changed(paused: bool)
signal mute_requested

const NAMES = ["我", "听松", "观澜"]
const HAND_Y = 695.0
const TARGET_RECT = Rect2(418, 306, 764, 178)
var view: Dictionary = {}
var selected_cards: Array = []
var hand_cards: Array = []
var target_cards: Array = []
var bid_buttons: Array = []
var play_button: Button
var pass_button: Button
var hint_button: Button
var clear_button: Button
var selection_label: Label
var status_label: Label
var mute_button: Button
var content: Control
var hand_layer: Control
var action_layer: Control
var modal_layer: Control
var modal: Control
var muted: bool = false
var _built: bool = false
var _paused: bool = false
var _modal_kind: String = ""
var _rules_return: String = ""
var _submitted_revision: int = -1
var _notice: String = ""
var _result_hidden: bool = false

func _ready() -> void:
	name = "DoudizhuTable"
	size = Vector2(1600, 900)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_background()
	content = _layer()
	hand_layer = _layer()
	action_layer = _layer()
	modal_layer = _layer()
	_built = true
	_render()

func _layer() -> Control:
	var layer = Control.new()
	layer.size = Vector2(1600, 900)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	return layer

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _passive_panel(parent: Node, rect: Rect2, color: Color, border: Color = Color.TRANSPARENT, radius: int = 14) -> Panel:
	var panel = Kit.panel(parent, rect, color, border, radius)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel

func _label(parent: Node, rect: Rect2, text: String, font_size: int = 22, color: Color = Kit.TEXT, center: bool = false) -> Label:
	var label = Kit.label(parent, rect, text, font_size, color)
	if center: label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

func _button(parent: Node, rect: Rect2, text: String, callback: Callable, primary: bool = false) -> Button:
	var button = Kit.table_button(parent, rect, text, callback, primary)
	button.add_theme_font_size_override("font_size", 23)
	return button

func _build_background() -> void:
	var courtyard = Kit.texture(self, Rect2(0, 0, 1600, 900), load("res://assets/backgrounds/courtyard_day.jpg"))
	courtyard.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_passive_panel(self, Rect2(0, 0, 1600, 900), Color("071d1bcb"), Color.TRANSPARENT, 0)
	_passive_panel(self, Rect2(31, 103, 1538, 780), Color("413c2d"), Color("aa8f5b70"), 46)
	_passive_panel(self, Rect2(43, 115, 1514, 756), Color("0d2c2b"), Color("c2a87770"), 37)
	var cloth = Kit.texture(self, Rect2(49, 121, 1502, 744), load("res://assets/textures/felt_delivered.png"))
	cloth.stretch_mode = TextureRect.STRETCH_SCALE
	cloth.modulate = Color("d3ddd2")
	_passive_panel(self, Rect2(49, 121, 1502, 744), Color("08282630"), Color("dece991c"), 31)
	# A restrained rail beneath the cards, never a white hand tray.
	_passive_panel(self, Rect2(64, 662, 1472, 1), Color("dcc79235"), Color.TRANSPARENT, 0)

func set_view(next_view: Dictionary) -> void:
	var previous_revision = int(view.get("revision", -1))
	var previous_phase = str(view.get("phase", ""))
	view = next_view.duplicate(true)
	if int(view.get("revision", -1)) != previous_revision or str(view.get("phase", "")) != previous_phase:
		selected_cards.clear()
		_submitted_revision = -1
		_notice = ""
	if str(view.get("phase", "")) != previous_phase: _result_hidden = false
	if previous_phase == "finished" and str(view.get("phase", "")) != "finished":
		_close_modal()
	if _built: _render()

func set_muted(value: bool) -> void:
	muted = value
	if is_instance_valid(mute_button): mute_button.text = "声音关" if muted else "声音开"

func set_hint(cards: Array) -> void:
	if not _can_act() or str(view.get("phase", "")) != "playing": return
	selected_cards.clear()
	for id in cards:
		if id in view.get("hand", []) and id not in selected_cards: selected_cards.append(id)
	_notice = ""
	if selected_cards.is_empty():
		var target: Dictionary = view.get("target", {})
		var can_beat = not Rules.legal_plays(view.get("hand", []), target).is_empty()
		if not can_beat:
			_notice = "没有能压过的牌，可以选择不要。"
		elif int(view.get("landlord", -1)) != int(view.get("seat", 0)) and int(view.get("target_seat", -1)) != int(view.get("landlord", -1)):
			_notice = "建议不要，把出牌权留给队友；也可自行选牌。"
		else:
			_notice = "建议这一手不要；也可自行选牌。"
	_refresh_selection()

func action_rejected(message: String) -> void:
	_submitted_revision = -1
	_notice = message
	if _built: _refresh_selection()

func show_notice(message: String) -> void:
	_notice = message
	if _built: _refresh_selection()

func _render() -> void:
	_clear(content)
	_clear(hand_layer)
	_clear(action_layer)
	hand_cards.clear()
	target_cards.clear()
	bid_buttons.clear()
	play_button = null; pass_button = null; hint_button = null; clear_button = null
	_button(content, Rect2(53, 31, 126, 51), "暂停", pause_menu)
	_button(content, Rect2(191, 31, 126, 51), "玩法", show_rules)
	_label(content, Rect2(631, 28, 338, 57), "斗 地 主", 30, Kit.ACCENT, true)
	mute_button = _button(content, Rect2(1385, 31, 163, 51), "声音关" if muted else "声音开", func(): mute_requested.emit())
	if view.is_empty(): return
	_draw_bottom()
	_draw_opponent(2, true)
	_draw_opponent(1, false)
	_draw_target()
	_draw_self()
	_draw_hand()
	_draw_actions()
	if str(view.get("phase", "")) == "finished" and _modal_kind != "result" and not _result_hidden: _show_result()

func _draw_bottom() -> void:
	var bottom: Array = view.get("bottom", [])
	_label(content, Rect2(595, 163, 90, 39), "底牌", 24, Kit.MUTED, true)
	for index in range(3):
		var card = _card(content, int(bottom[index]) if bottom.size() == 3 else 0, Vector2(698 + index * 69, 136), Vector2(61, 89))
		card.face_down = bottom.size() != 3
		if card.face_down: card.tooltip_text = "底牌尚未公开"
	var base = int(view.get("highest_bid", 0))
	_label(content, Rect2(930, 146, 313, 35), "等待叫分" if base == 0 else ("当前叫分 %d" % base if str(view.get("phase", "")) == "bidding" else "底分 %d" % base), 24, Kit.ACCENT)
	_label(content, Rect2(930, 185, 313, 31), "本局 ×%d" % int(view.get("multiplier", 1)), 23, Kit.MUTED)

func _role(seat: int) -> String:
	var landlord = int(view.get("landlord", -1))
	if str(view.get("phase", "")) == "bidding": return "叫分领先" if landlord == seat else "等待叫分"
	if landlord < 0: return "等待叫分"
	if landlord == seat: return "地主"
	return "农民 · 队友" if int(view.get("seat", 0)) != landlord and seat != int(view.get("seat", 0)) else "农民"

func _seat_name(seat: int) -> String:
	return NAMES[seat] if seat >= 0 and seat < NAMES.size() else "牌友"

func _draw_opponent(seat: int, left: bool) -> void:
	var x = 82.0 if left else 1303.0
	var active = int(view.get("turn", -1)) == seat and str(view.get("phase", "")) != "finished"
	var player = _passive_panel(content, Rect2(x, 253, 214, 149), Color("102d2ddf"), Kit.ACCENT if active else Kit.TABLE_LINE, 17)
	Kit.portrait(player, Vector2(16, 16), 68, seat)
	_label(player, Rect2(99, 13, 106, 41), _seat_name(seat), 26)
	var counts: Array = view.get("hand_counts", [0, 0, 0])
	_label(player, Rect2(99, 54, 106, 30), "%d 张" % int(counts[seat]), 24, Kit.CORAL if int(counts[seat]) <= 2 else Kit.ACCENT)
	_label(player, Rect2(16, 100, 190, 30), _role(seat), 22, Kit.ACCENT if int(view.get("landlord", -1)) == seat else Kit.MUTED)
	if active: _label(content, Rect2(x, 216, 214, 32), "正在叫分…" if str(view.get("phase", "")) == "bidding" else "正在出牌…", 23, Kit.ACCENT, true)
	var latest: Array = view.get("last_actions", [{}, {}, {}])
	var action: Dictionary = latest[seat] if latest.size() > seat else {}
	var kind = str(action.get("type", ""))
	if str(view.get("phase", "")) == "bidding":
		var bids: Array = view.get("bids", [-1, -1, -1])
		if int(bids[seat]) >= 0: _label(content, Rect2(x - 7, 422, 229, 47), "不叫" if int(bids[seat]) == 0 else "%d 分" % int(bids[seat]), 29, Kit.MUTED, true)
	elif kind == "pass":
		_label(content, Rect2(x - 7, 432, 229, 47), "不要", 31, Kit.MUTED, true)
	elif kind == "play":
		var played: Array = action.get("cards", [])
		var rect = Rect2(71 if left else 1211, 440, 318, 100)
		if played.size() <= 8:
			_draw_group(content, played, rect, 58, 34)
		else:
			_button(content, Rect2(rect.position.x + 27, 447, 264, 63), "查看上手 · %d 张" % played.size(), _show_last_play.bind(seat))
		_label(content, Rect2(rect.position.x, 541, rect.size.x, 31), "上一手 · " + str(action.get("combo", {}).get("name", "出牌")), 18, Kit.MUTED, true)

func _draw_target() -> void:
	var phase = str(view.get("phase", ""))
	var target: Dictionary = view.get("target", {})
	if phase == "bidding":
		_label(content, Rect2(407, 292, 786, 71), "先叫分，定地主", 42, Kit.TEXT, true)
		_label(content, Rect2(426, 379, 748, 44), "最高叫分者拿底牌 · 叫到 3 分立即开始", 23, Kit.MUTED, true)
	elif target.is_empty():
		_label(content, Rect2(418, 330, 764, 79), "新一轮领出", 39, Kit.TEXT, true)
		_label(content, Rect2(418, 419, 764, 39), "可以打出任意合法牌型", 24, Kit.MUTED, true)
	else:
		var source = _seat_name(int(view.get("target_seat", -1)))
		_label(content, Rect2(418, 261, 764, 38), source + " 出牌 · " + str(target.get("name", "")), 25, Kit.ACCENT, true)
		target_cards = _draw_group(content, target.get("cards", []), TARGET_RECT, 97, 60)
		_label(content, Rect2(418, 486, 764, 31), "本局最后一手" if phase == "finished" else "当前要压的牌", 20, Kit.MUTED, true)
	var turn = int(view.get("turn", -1))
	var my_turn = turn == int(view.get("seat", 0))
	var status = "轮到你叫分" if phase == "bidding" else "轮到你出牌"
	if not my_turn: status = "等待%s%s" % [_seat_name(turn), "叫分" if phase == "bidding" else "出牌"]
	if phase == "finished": status = "本局结束"
	status_label = _label(content, Rect2(413, 528, 774, 39), status, 29, Kit.ACCENT if my_turn else Kit.TEXT, true)

func _draw_self() -> void:
	Kit.portrait(content, Vector2(81, 699), 82, int(view.get("seat", 0)))
	_label(content, Rect2(63, 788, 118, 31), "我", 25, Kit.TEXT, true)
	_label(content, Rect2(51, 823, 143, 29), _role(int(view.get("seat", 0))).replace(" · 队友", ""), 22, Kit.ACCENT, true)

func _card(parent: Node, id: int, at: Vector2, dimensions: Vector2, interactive: bool = false) -> CardFace:
	var card = CardFace.new()
	card.card_id = id
	card.position = at
	card.size = dimensions
	card.interactive = interactive
	card.tooltip_text = Cards.label(id) if not card.face_down else "底牌"
	parent.add_child(card)
	return card

func _draw_group(parent: Node, ids: Array, rect: Rect2, width: float, preferred_step: float) -> Array:
	var result: Array = []
	if ids.is_empty(): return result
	if ids.size() > 12: width = minf(width, 84.0)
	var cards = Cards.sort_cards(ids)
	var step = minf(preferred_step, (rect.size.x - width) / maxf(1, cards.size() - 1))
	var total = width + step * (cards.size() - 1)
	var x = rect.position.x + (rect.size.x - total) * 0.5
	for id in cards:
		result.append(_card(parent, int(id), Vector2(x, rect.position.y), Vector2(width, width * 164.0 / 112.0)))
		x += step
	return result

func _draw_hand() -> void:
	var cards = Cards.sort_cards(view.get("hand", []))
	var step = minf(65, 1200.0 / maxf(1, cards.size() - 1))
	var width = 115.0
	var total = width + step * (cards.size() - 1)
	var x = 227 + (1268 - total) * 0.5
	for id in cards:
		var card = _card(hand_layer, int(id), Vector2(x, HAND_Y), Vector2(width, 168.4), true)
		card.name = "Card_%d" % int(id)
		card.pressed.connect(_toggle_card.bind(int(id)))
		hand_cards.append(card)
		x += step
	_refresh_hand_cards()

func _draw_actions() -> void:
	if str(view.get("phase", "")) == "bidding":
		for amount in range(4):
			var button = _button(action_layer, Rect2(466 + amount * 173, 578, 158, 58), "不叫" if amount == 0 else "%d 分" % amount, _send_bid.bind(amount), amount == 3)
			button.disabled = not _can_act() or (amount != 0 and amount <= int(view.get("highest_bid", 0)))
			bid_buttons.append(button)
	elif str(view.get("phase", "")) == "finished":
		_button(action_layer, Rect2(468, 578, 194, 58), "返回大厅", func(): exit_requested.emit())
		_button(action_layer, Rect2(678, 578, 194, 58), "本局分数", _show_result)
		_button(action_layer, Rect2(888, 578, 244, 58), "再来一局", _next_round, true)
	else:
		pass_button = _button(action_layer, Rect2(468, 578, 142, 58), "不要", _send_pass)
		hint_button = _button(action_layer, Rect2(625, 578, 142, 58), "提示", func(): hint_requested.emit())
		clear_button = _button(action_layer, Rect2(782, 578, 142, 58), "取消选牌", _clear_selection)
		play_button = _button(action_layer, Rect2(943, 578, 188, 58), "出 牌", _send_play, true)
	selection_label = _label(action_layer, Rect2(223, 640, 1280, 28), "", 21, Kit.MUTED, true)
	_refresh_selection()

func _can_act() -> bool:
	return not view.is_empty() and not _paused and int(view.get("turn", -1)) == int(view.get("seat", 0)) and str(view.get("phase", "")) in ["bidding", "playing"] and _submitted_revision != int(view.get("revision", -1))

func _selected_combo() -> Dictionary:
	return Rules.classify(selected_cards)

func _play_is_valid() -> bool:
	if selected_cards.is_empty(): return false
	var combo = _selected_combo()
	if not combo.get("valid", false): return false
	var target: Dictionary = view.get("target", {})
	return target.is_empty() or Rules.beats(combo, target)

func _refresh_hand_cards() -> void:
	for card in hand_cards:
		var selected = card.card_id in selected_cards
		card.set_chosen(selected)
		card.position.y = HAND_Y - (24 if selected else 0)
		card.disabled = not _can_act() or str(view.get("phase", "")) != "playing"

func _refresh_selection() -> void:
	_refresh_hand_cards()
	var can = _can_act() and str(view.get("phase", "")) == "playing"
	if is_instance_valid(play_button): play_button.disabled = not can or not _play_is_valid()
	if is_instance_valid(pass_button): pass_button.disabled = not can or view.get("target", {}).is_empty() or int(view.get("target_seat", -1)) == int(view.get("seat", 0))
	if is_instance_valid(hint_button): hint_button.disabled = not can
	if is_instance_valid(clear_button): clear_button.disabled = not can or selected_cards.is_empty()
	for amount in range(bid_buttons.size()):
		bid_buttons[amount].disabled = not _can_act() or (amount != 0 and amount <= int(view.get("highest_bid", 0)))
	if not is_instance_valid(selection_label): return
	var message = ""
	if not _notice.is_empty(): message = _notice
	elif not selected_cards.is_empty():
		var combo = _selected_combo()
		if not combo.get("valid", false): message = "这组牌不能一起出，请调整选牌。"
		elif not _play_is_valid(): message = str(combo.get("name", "")) + " · 压不过当前牌，请换一组。"
		else: message = "已选 %d 张 · %s" % [selected_cards.size(), str(combo.get("name", ""))]
	elif _can_act() and str(view.get("phase", "")) == "playing": message = "点选手牌，再按出牌"
	selection_label.text = message

func _toggle_card(id: int) -> void:
	if not _can_act() or str(view.get("phase", "")) != "playing" or id not in view.get("hand", []): return
	if id in selected_cards: selected_cards.erase(id)
	else: selected_cards.append(id)
	_notice = ""
	_refresh_selection()

func _clear_selection() -> void:
	selected_cards.clear()
	_notice = ""
	_refresh_selection()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not _paused:
		_clear_selection()

func _send_bid(amount: int) -> void:
	if str(view.get("phase", "")) != "bidding" or amount < 0 or amount > 3 or (amount > 0 and amount <= int(view.get("highest_bid", 0))): return
	_send({"type": "bid", "value": amount})

func _send_play() -> void:
	if str(view.get("phase", "")) != "playing" or not _play_is_valid(): return
	_send({"type": "play", "cards": selected_cards.duplicate()})

func _send_pass() -> void:
	if str(view.get("phase", "")) != "playing" or view.get("target", {}).is_empty() or int(view.get("target_seat", -1)) == int(view.get("seat", 0)): return
	_send({"type": "pass"})

func _send(action: Dictionary) -> void:
	if not _can_act(): return
	action["revision"] = int(view.revision)
	_submitted_revision = int(view.revision)
	_refresh_selection()
	action_requested.emit(action)

func _open_modal(kind: String, dimensions: Vector2) -> Control:
	_clear(modal_layer)
	_modal_kind = kind
	var shade = ColorRect.new()
	shade.color = Color("031b19ce")
	shade.size = Vector2(1600, 900)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_layer.add_child(shade)
	modal = Kit.panel(modal_layer, Rect2((Vector2(1600, 900) - dimensions) * 0.5, dimensions), Color("102e2dfc"), Color("d1bb8280"), 23)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	if not _paused:
		_paused = true
		pause_changed.emit(true)
	_refresh_selection()
	return modal

func _close_modal() -> void:
	if not _built: return
	_clear(modal_layer)
	modal = null
	_modal_kind = ""
	_rules_return = ""
	if _paused:
		_paused = false
		pause_changed.emit(false)
	_refresh_selection()

func pause_menu() -> void:
	if _modal_kind in ["rules", "inspect"]:
		_finish_rules()
	elif _modal_kind == "result":
		_hide_result()
	elif _modal_kind == "pause":
		_close_modal()
	else:
		_show_pause()

func ensure_paused() -> void:
	if not _paused: _show_pause()

func _show_last_play(seat: int) -> void:
	var latest: Array = view.get("last_actions", [{}, {}, {}])
	if latest.size() <= seat: return
	var action: Dictionary = latest[seat]
	var cards: Array = action.get("cards", [])
	if cards.is_empty(): return
	_rules_return = _modal_kind if _modal_kind in ["pause", "result"] else ""
	var panel = _open_modal("inspect", Vector2(1120, 454))
	_label(panel, Rect2(44, 33, 1032, 52), _seat_name(seat) + " 上一手 · " + str(action.get("combo", {}).get("name", "出牌")), 31, Kit.ACCENT, true)
	_draw_group(panel, cards, Rect2(41, 128, 1038, 176), 105, 60)
	_button(panel, Rect2(44, 353, 1032, 58), "回到牌桌", _finish_rules, true)

func _show_pause() -> void:
	var panel = _open_modal("pause", Vector2(622, 438))
	_label(panel, Rect2(42, 32, 536, 55), "歇一会儿", 35, Kit.TEXT, true)
	_label(panel, Rect2(42, 99, 536, 49), "牌局已暂停，回来接着打。", 23, Kit.MUTED, true)
	_button(panel, Rect2(54, 171, 514, 62), "继续打牌", _resume_from_pause, true)
	_button(panel, Rect2(54, 247, 248, 59), "玩法说明", show_rules)
	_button(panel, Rect2(320, 247, 248, 59), "退出本局", _confirm_exit)
	_label(panel, Rect2(43, 348, 536, 40), "每局独立计分 · 没有局外积分", 21, Kit.MUTED, true)

func _resume_from_pause() -> void:
	_close_modal()
	if str(view.get("phase", "")) == "finished" and not _result_hidden: _show_result()

func _confirm_exit() -> void:
	var panel = _open_modal("exit", Vector2(688, 366))
	_label(panel, Rect2(45, 36, 598, 52), "退出斗地主？", 32, Kit.TEXT, true)
	_label(panel, Rect2(45, 109, 598, 75), "退出后本局结束，下次从新的一局开始。\n不保留或累计任何局外分数。", 24, Kit.MUTED, true)
	_button(panel, Rect2(46, 244, 282, 62), "继续打牌", _resume_from_pause)
	_button(panel, Rect2(347, 244, 294, 62), "退出到大厅", func(): exit_requested.emit(), true)

func show_rules() -> void:
	_rules_return = _modal_kind if _modal_kind in ["pause", "result"] else ""
	var panel = _open_modal("rules", Vector2(964, 722))
	_label(panel, Rect2(44, 28, 876, 53), "斗地主 · 本桌玩法", 34, Kit.TEXT)
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(44, 98); scroll.size = Vector2(876, 514)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	scroll.add_child(body)
	var sections = [
		["一副牌，三个人", "54 张牌，每人先拿 17 张，留下 3 张底牌。依次叫 1、2、3 分或不叫，后叫必须高于前者；叫 3 分立即当地主。全不叫则重新发牌。"],
		["地主先出，农民合作", "地主拿到底牌后共 20 张，先出牌。轮到自己可压过上手或不要；连续两人不要，由最后出牌者重新领出。地主先出完获胜，任一农民先出完则两位农民共同获胜。"],
		["牌型与大小", "单张、对子、三张、三带一、三带一对、顺子（至少 5 张）、连对（至少 3 对）、飞机及带翅膀、四带二、炸弹和王炸。通常须同牌型、同张数才能比较，按主体点数比较。3 最小，依次到 A、2、小王、大王；顺子、连对和飞机主体不含 2 与王。"],
		["本桌采用的带牌约定", "飞机单翅每种点数最多两张，不能同时带双王；翅膀不能与飞机主体同点。飞机双翅须为不同点数的对子。四带二单可带一对，但不能带双王；四带二对须带两个不同点数的对子。"],
		["炸弹、春天与本局分", "四张同点为炸弹，双王为王炸；每次炸弹或王炸使本局翻倍。地主获胜且农民都未出过牌为春天；农民获胜且地主只出过一手为反春天，均再翻倍。每名农民输赢为底分 × 倍率，地主为其两倍，三人合计为零。"],
		["想玩就继续", "每局独立计分，没有金币、段位、局外结算或固定场数。打完可再来一局，也可随时退出。点选一张或多张手牌，再按出牌；提示只会帮你选牌，不会自动打出。"]
	]
	for section in sections:
		var title = Label.new(); title.text = section[0]
		title.add_theme_font_override("font", Kit.font(true)); title.add_theme_font_size_override("font_size", 25)
		title.add_theme_color_override("font_color", Kit.ACCENT); body.add_child(title)
		var text = Label.new(); text.text = section[1]; text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_font_override("font", Kit.font()); text.add_theme_font_size_override("font_size", 23)
		text.add_theme_color_override("font_color", Kit.TEXT); body.add_child(text)
	_button(panel, Rect2(44, 633, 876, 57), "知道了", _finish_rules, true)

func _finish_rules() -> void:
	var previous = _rules_return
	_close_modal()
	if previous == "pause": _show_pause()
	elif previous == "result" or str(view.get("phase", "")) == "finished": _show_result()

func _show_result() -> void:
	var result: Dictionary = view.get("result", {})
	if result.is_empty(): return
	_result_hidden = false
	var panel = _open_modal("result", Vector2(908, 680))
	var scores: Array = result.get("scores", [0, 0, 0])
	var won = int(scores[int(view.get("seat", 0))]) > 0
	_label(panel, Rect2(44, 25, 820, 65), "这局赢了" if won else "这局惜败", 45, Kit.ACCENT if won else Kit.TEXT, true)
	_button(panel, Rect2(679, 37, 182, 47), "查看牌桌", _hide_result)
	var spring = str(result.get("spring", ""))
	var spring_text = " · 春天" if spring == "spring" else (" · 反春天" if spring == "counter_spring" else "")
	_label(panel, Rect2(44, 99, 820, 39), ("地主胜" if result.get("landlord_won", false) else "农民胜") + spring_text, 26, Kit.MUTED, true)
	for seat in range(3):
		var x = 46 + seat * 277
		_passive_panel(panel, Rect2(x, 163, 263, 205), Color("1b3b35"), Color("c7b17e32"), 15)
		Kit.portrait(panel, Vector2(x + 22, 183), 61, seat)
		_label(panel, Rect2(x + 99, 180, 145, 35), _seat_name(seat), 25)
		_label(panel, Rect2(x + 99, 215, 145, 29), "地主" if seat == int(view.get("landlord", -1)) else "农民", 20, Kit.MUTED)
		_label(panel, Rect2(x + 16, 270, 231, 73), "%+d 分" % int(scores[seat]), 36, Kit.ACCENT if int(scores[seat]) > 0 else Kit.MUTED, true)
	var base = int(result.get("base", view.get("highest_bid", 1)))
	var multiple = int(result.get("multiplier", view.get("multiplier", 1)))
	_label(panel, Rect2(46, 395, 816, 39), "底分 %d × 本局倍率 %d = 每位农民 %d 分" % [base, multiple, base * multiple], 24, Kit.TEXT, true)
	_label(panel, Rect2(46, 442, 816, 35), "地主按两位农民的合计结算 · 炸弹/王炸 %d 次%s" % [int(view.get("bomb_count", 0)), " · 春天再翻倍" if not spring.is_empty() else ""], 20, Kit.MUTED, true)
	_label(panel, Rect2(46, 490, 816, 31), "本局到此结清，下一局重新计分。", 21, Kit.MUTED, true)
	_button(panel, Rect2(46, 560, 290, 66), "返回大厅", func(): exit_requested.emit())
	_button(panel, Rect2(354, 560, 508, 66), "再来一局", _next_round, true)

func _hide_result() -> void:
	_result_hidden = true
	_close_modal()

func _next_round() -> void:
	if str(view.get("phase", "")) != "finished": return
	_close_modal()
	next_requested.emit()
