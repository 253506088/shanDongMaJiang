extends Control
## Presentation receives a private seat view, never the engine or other hands.
const Kit = preload("res://scripts/ui/ui_kit.gd")
const Card = preload("res://scripts/poker/ui/card.gd")
const Themes = preload("res://scripts/poker/ui/card_themes.gd")
const Cards = preload("res://scripts/bluff/core/cards.gd")
const Rules = preload("res://scripts/bluff/core/engine.gd")
const Recorder = preload("res://scripts/bluff/ui/recorder.gd")
const NAMES = ["我", "听松", "观澜", "知秋", "望舒", "怀竹"]
const GESTURES = ["石头", "剪刀", "布"]
const ROW_SIZE = 27
signal action_requested(action: Dictionary)
signal start_requested(config: Dictionary)
signal exit_requested
signal pause_changed(value: bool)
signal settings_changed(settings: Dictionary)
var view: Dictionary = {}
var settings = {"players": 3, "challenge": "turn", "theme": "traditional", "pace": 2.8, "voice": "male", "muted": false}
var selected: Array = []
var declared = 14
var hand_cards: Array = []
var rank_buttons: Array = []
var content: Control
var hand_layer: Control
var action_layer: Control
var modal_layer: Control
var modal_kind = ""
var paused = false
var submitted = -1
var selection_label: Label
var play_button: Button
var challenge_button: Button
var pass_button: Button
var review_label: Label
var round_history: Control
var round_rows: Array = []
var recorder: Control
var notice = ""
var drag_active = false
var drag_seen: Dictionary = {}
var drag_regions: Array = []
var drag_last = Vector2.ZERO
var touch_until = 0
var touch_position = Vector2.INF
var built = false

func _ready() -> void:
	size = Vector2(1600, 900)
	mouse_filter = MOUSE_FILTER_STOP
	var courtyard = Kit.texture(self, Rect2(0, 0, 1600, 900), load("res://assets/backgrounds/courtyard_day.jpg"))
	courtyard.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	panel(self, Rect2(0, 0, 1600, 900), Color("061916df"), Color.TRANSPARENT, 0)
	panel(self, Rect2(28, 105, 1544, 778), Color("493f2b"), Color("aa8f5b70"), 44)
	panel(self, Rect2(39, 116, 1522, 756), Color("102e29"), Color("d4b97b80"), 35)
	var cloth = Kit.texture(self, Rect2(48, 125, 1504, 738), load("res://assets/textures/felt_delivered.png"))
	cloth.stretch_mode = TextureRect.STRETCH_SCALE
	cloth.modulate = Color("bbcfc5")
	panel(self, Rect2(48, 125, 1504, 738), Color("06242148"), Color.TRANSPARENT, 30)
	for layer_name in ["content", "hand_layer", "action_layer", "modal_layer"]:
		var layer = Control.new(); layer.size = size; layer.mouse_filter = MOUSE_FILTER_IGNORE
		set(layer_name, layer); add_child(layer)
	built = true
	render()

func clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child); child.queue_free()

func panel(parent: Node, rect: Rect2, fill: Color, border: Color = Color.TRANSPARENT, radius: int = 14) -> Panel:
	var node = Kit.panel(parent, rect, fill, border, radius)
	node.mouse_filter = MOUSE_FILTER_IGNORE
	return node

func label(parent: Node, rect: Rect2, text: String, font_size: int = 22, color: Color = Kit.TEXT, center: bool = false) -> Label:
	var node = Kit.label(parent, rect, text, font_size, color)
	if center: node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return node

func button(parent: Node, rect: Rect2, text: String, callback: Callable, primary: bool = false) -> Button:
	var node = Kit.table_button(parent, rect, text, callback, primary)
	node.add_theme_font_size_override("font_size", 22)
	return node

func face(parent: Node, id: int, rect: Rect2, back: bool = false) -> Control:
	var card = Card.new(); card.card_id = id; card.face_down = back
	card.theme_id = Themes.normalize(settings.get("theme", "traditional"))
	card.position = rect.position; card.size = rect.size
	parent.add_child(card)
	return card

func set_view(next: Dictionary) -> void:
	if next.get("revision", -1) != view.get("revision", -1) or next.get("round_id", -1) != view.get("round_id", -1):
		selected.clear(); submitted = -1; notice = ""; cancel_drag()
		if not modal_kind.is_empty(): close_modal()
	view = next.duplicate(true)
	if not view.get("last", {}).is_empty(): declared = view.rank
	if built: render()

func render() -> void:
	cancel_drag()
	clear(content); clear(hand_layer); clear(action_layer)
	hand_cards.clear(); rank_buttons.clear()
	play_button = null; pass_button = null; challenge_button = null; selection_label = null
	review_label = null; round_history = null; round_rows.clear()
	recorder = null
	button(content, Rect2(53, 31, 124, 51), "返回" if view.is_empty() else "暂停", func(): exit_requested.emit() if view.is_empty() else pause_menu())
	button(content, Rect2(189, 31, 124, 51), "玩法", show_rules)
	button(content, Rect2(325, 31, 175, 51), "国风青玉" if settings.theme == "guofeng" else "传统牌面", toggle_theme)
	label(content, Rect2(610, 25, 380, 61), "唬  牌", 36, Kit.ACCENT, true)
	button(content, Rect2(1150, 31, 214, 51), "女声宣言" if settings.voice == "female" else "男声宣言", func(): settings.voice = "female" if settings.voice == "male" else "male"; settings_changed.emit(settings.duplicate()); render())
	button(content, Rect2(1376, 31, 168, 51), "声音关" if settings.muted else "声音开", func(): settings.muted = not settings.muted; settings_changed.emit(settings.duplicate()); render())
	if view.is_empty():
		draw_setup(); return
	if compact_hand():
		draw_compact_table()
	else:
		draw_seats()
		if view.phase == "rps": draw_rps()
		elif view.phase == "review" or view.phase == "finished": draw_review()
		else: draw_center()
		if view.phase != "rps": draw_recorder()
	draw_hand()
	draw_actions()
	if compact_hand():
		# Move action/header controls together, preserving their normal targets.
		action_layer.position.y = -204
	else: action_layer.position.y = 0
	if view.phase == "finished" and not compact_hand(): button(content, Rect2(1240, 561, 270, 50), "本局记录", show_history)

func compact_hand() -> bool:
	return view.get("hand", []).size() > 30

func hand_header_y() -> float:
	return 445.0 if compact_hand() else 651.0

func draw_compact_table() -> void:
	# Large collected hands use several persistent rows. Keep every player's
	# count and round contributions visible above them, without a page switch.
	for seat in range(view.config.players):
		var x = 74 + seat * (1450.0 / view.config.players)
		var width = 1450.0 / view.config.players - 12
		var active = view.phase == "playing" and view.turn == seat
		panel(content, Rect2(x, 133, width, 98), Color("102c28ed"), Kit.ACCENT if active else Kit.LINE, 16)
		label(content, Rect2(x + 12, 140, width - 24, 36), "%s · %d 张%s" % [NAMES[seat], view.hand_counts[seat], " · 行动" if active else ""], 23, Kit.ACCENT if active else Kit.TEXT)
		var counts: Array = []
		for play in view.get("trick", []):
			if play.seat == seat: counts.append(str(play.count))
		var row = label(content, Rect2(x + 12, 185, width - 24, 32), NAMES[seat] + "  " + ("未出牌" if counts.is_empty() else " + ".join(counts) + " 张"), 20, Kit.MUTED)
		row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; row.tooltip_text = row.text
		round_rows.append(row)
	draw_recorder(); recorder.position.y = 251
	label(content, Rect2(370, 243, 820, 33), "中央 %d 张  ·  死牌 %d 张" % [view.pile_count, view.dead_count], 22, Kit.MUTED, true)
	var summary = "新一轮 · %s领出" % NAMES[maxi(0, view.turn)]
	if not view.last.is_empty(): summary = "%s：%d 张 %s   ·   %d 家已过" % [NAMES[view.last.seat], view.last.count, Cards.label(view.rank), view.passed.size()]
	if view.phase == "review" or view.phase == "finished":
		summary = event_text(view.event)
		if view.phase == "finished": summary = "%s获胜 · %s" % [NAMES[view.winner], summary]
		if view.event.get("type", "") == "challenge":
			button(content, Rect2(1235, 296, 275, 43), "查看翻开的 %d 张" % view.event.cards.size(), show_reveal)
			var shown = mini(8, view.event.cards.size())
			for index in range(shown):
				var id = view.event.cards[index]
				var x = 790 - shown * 40 + index * 80
				face(content, id, Rect2(x, 326, 44, 64))
				label(content, Rect2(x + 46, 344, 32, 29), "王" if Cards.rank(id) >= 16 else ("真" if Cards.matches(id, view.event.rank) else "假"), 18, Kit.ACCENT if Cards.matches(id, view.event.rank) else Kit.CORAL)
	label(content, Rect2(370, 277, 820, 47), summary, 25, Kit.ACCENT, true)
	button(content, Rect2(1235, 246, 275, 43), "本轮出牌 · 详情", show_round_history)
	button(content, Rect2(1235, 346, 275, 43), "牌局记录", show_history)

func draw_setup() -> void:
	label(content, Rect2(130, 197, 820, 80), "敢不敢，开这一手？", 54, Kit.TEXT)
	label(content, Rect2(135, 288, 750, 76), "扣下真牌，也可以虚张声势。\n留下判断的时间，把胜负交给这一声「开」。", 26, Kit.MUTED)
	for index in range(5):
		var card = face(content, [44, 40, 36, 52, 53][index], Rect2(1030 + index * 56, 255 + abs(index - 2) * 14, 145, 214), index == 2)
		card.rotation = (index - 2) * 0.08
	label(content, Rect2(135, 400, 270, 40), "同桌人数", 25, Kit.ACCENT)
	for count in range(3, 7):
		button(content, Rect2(135 + (count - 3) * 175, 452, 158, 59), "%d 人" % count, func(): settings.players = count; settings_changed.emit(settings.duplicate()); render(), settings.players == count)
	label(content, Rect2(135, 518, 850, 36), "你 + %d 位机器人   ·   %d 副牌（含大小王）   ·   顺时针行动" % [settings.players - 1, 1 if settings.players == 3 else 2], 22, Kit.MUTED)
	label(content, Rect2(135, 580, 235, 40), "质疑约定", 25, Kit.ACCENT)
	button(content, Rect2(135, 632, 300, 56), "轮到我时开", func(): settings.challenge = "turn"; settings_changed.emit(settings.duplicate()); render(), settings.challenge == "turn")
	button(content, Rect2(450, 632, 300, 56), "任何人可抢开", func(): settings.challenge = "any"; settings_changed.emit(settings.duplicate()); render(), settings.challenge == "any")
	button(content, Rect2(1030, 598, 370, 56), "节奏 · 舒缓" if settings.pace >= 2.8 else "节奏 · 标准", func(): settings.pace = 2.0 if settings.pace >= 2.8 else 2.8; settings_changed.emit(settings.duplicate()); render())
	label(content, Rect2(1030, 663, 420, 70), "领出、跟牌均不限张数\n大小王万能 · 最后一手仍可质疑", 22, Kit.MUTED)
	button(content, Rect2(135, 750, 615, 68), "入 座 猜 拳   →", func(): start_requested.emit(Rules.options(settings)), true)
	label(content, Rect2(1030, 771, 410, 43), "单局胜负 · 随时续局", 23, Kit.ACCENT)

func draw_seats() -> void:
	var positions = {
		3: [Vector2(87, 282), Vector2(1277, 282)],
		4: [Vector2(87, 292), Vector2(680, 135), Vector2(1277, 292)],
		5: [Vector2(87, 407), Vector2(87, 193), Vector2(1277, 193), Vector2(1277, 407)],
		6: [Vector2(87, 417), Vector2(87, 213), Vector2(680, 135), Vector2(1277, 213), Vector2(1277, 417)]}
	for seat in range(1, view.config.players):
		var at: Vector2 = positions[view.config.players][seat - 1]
		var active = view.phase == "playing" and view.turn == seat
		panel(content, Rect2(at, Vector2(236, 106)), Color("102c28ed"), Kit.ACCENT if active else Kit.LINE, 22)
		if seat <= 3: Kit.portrait(content, at + Vector2(13, 17), 58, seat)
		else:
			panel(content, Rect2(at + Vector2(13, 17), Vector2(58, 58)), Color("36574b"), Kit.LINE, 29)
			label(content, Rect2(at + Vector2(13, 17), Vector2(58, 58)), NAMES[seat].left(1), 30, Kit.ACCENT, true)
		label(content, Rect2(at + Vector2(84, 7), Vector2(140, 39)), NAMES[seat] + (" · 行动" if active else ""), 22, Kit.ACCENT if active else Kit.TEXT)
		label(content, Rect2(at + Vector2(84, 44), Vector2(140, 37)), "%d 张" % view.hand_counts[seat], 27)
		var status = "顺时针 %d" % seat
		if seat in view.passed: status = "已过牌"
		elif not view.last.is_empty() and view.last.seat == seat: status = "刚扣下 %d 张" % view.last.count
		if view.hand_counts[seat] == 0: status = "已出完 · 待确认" if view.phase != "finished" else "已出完"
		label(content, Rect2(at + Vector2(13, 79), Vector2(208, 25)), status, 17, Kit.MUTED, true)
	label(content, Rect2(74, 134, 430, 36), "%d 人 · %d 副牌  /  %s" % [view.config.players, view.decks, "自由抢开" if view.config.challenge == "any" else "顺位质疑"], 19, Kit.MUTED)
	button(content, Rect2(1370, 132, 160, 43), "牌局记录", show_history)

func draw_rps() -> void:
	label(content, Rect2(390, 246, 820, 55), "猜拳 · 胜者先手", 33, Kit.ACCENT, true)
	var event: Dictionary = view.event
	if event.get("type", "") == "rps":
		var lines: Array = []
		for seat in range(view.config.players):
			if event.gestures[seat] >= 0: lines.append(NAMES[seat] + " " + GESTURES[event.gestures[seat]])
		label(content, Rect2(355, 306, 890, 56), "  ·  ".join(lines), 22, Kit.TEXT, true)
		label(content, Rect2(395, 363, 810, 42), "平局，再来一次" if event.remaining.size() == lines.size() else "胜出的玩家继续猜拳", 24, Kit.MUTED, true)
	else:
		label(content, Rect2(395, 316, 810, 58), "同时出拳；平局重猜，多位胜者继续决胜。", 24, Kit.MUTED, true)
	if 0 in view.contenders:
		for gesture in range(3):
			button(content, Rect2(430 + gesture * 252, 440, 236, 79), GESTURES[gesture], func(): send({"type": "rps", "gesture": gesture}), true)
	else:
		button(content, Rect2(540, 437, 520, 72), "观看下一轮猜拳", func(): send({"type": "rps", "gesture": 0}), true)
	label(content, Rect2(480, 548, 640, 36), "第 %d 轮  ·  %d 人参与" % [view.rps_round + 1, view.contenders.size()], 21, Kit.MUTED, true)

func draw_center() -> void:
	var last: Dictionary = view.last
	label(content, Rect2(386, 250, 828, 32), "中央 %d 张   ·   死牌 %d 张" % [view.pile_count, view.dead_count], 22, Kit.MUTED, true)
	if last.is_empty():
		label(content, Rect2(405, 294, 790, 73), "新一轮 · %s领出" % NAMES[view.turn], 40, Kit.ACCENT, true)
		label(content, Rect2(400, 381, 800, 67), "任意指定点数\n选任意张牌，也可整手扣下", 26, Kit.MUTED, true)
	else:
		var fan_count = mini(5, last.count)
		for index in range(fan_count):
			face(content, 0, Rect2(645 - (112 + (fan_count - 1) * 27) / 2.0 + index * 27, 287, 112, 164), true)
		label(content, Rect2(365, 454, 560, 62), "%s：%d 张 %s" % [NAMES[last.seat], last.count, Cards.label(view.rank)], 36, Kit.ACCENT, true)
		var text = "只翻这一手 · 历史扣牌不翻"
		if view.hand_counts[last.seat] == 0: text = "最后一手仍可开 · 跟牌即认可其出完"
		label(content, Rect2(365, 518, 560, 39), text, 21, Kit.MUTED, true)
		label(content, Rect2(365, 558, 560, 33), "%d / %d 家已过牌" % [view.passed.size(), view.config.players - 1], 20, Kit.MUTED, true)
		draw_round_history()
	if last.is_empty() and view.event.get("type", "") == "dead":
		label(content, Rect2(395, 469, 810, 42), "上一轮 %d 张已清理" % view.event.count, 23, Kit.MUTED, true)

func draw_round_history() -> void:
	round_history = panel(content, Rect2(945, 285, 286, 288), Color("102c28dd"), Kit.LINE, 16)
	button(round_history, Rect2(12, 8, 262, 39), "本轮出牌 · 详情", show_round_history).add_theme_font_size_override("font_size", 20)
	var scroll = ScrollContainer.new(); scroll.position = Vector2(16, 57); scroll.size = Vector2(255, 217)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	round_history.add_child(scroll)
	var rows = VBoxContainer.new(); rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 2); scroll.add_child(rows)
	for seat in range(view.config.players):
		var counts: Array = []
		var total = 0
		for play in view.get("trick", []):
			if play.seat == seat: counts.append(str(play.count)); total += int(play.count)
		var text = NAMES[seat] + "  " + ("未出牌" if counts.is_empty() else " + ".join(counts) + " 张")
		var row = label(rows, Rect2(), text, 21, Kit.ACCENT if seat == view.last.seat else Kit.TEXT)
		row.custom_minimum_size = Vector2(235, 28); row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.tooltip_text = "%s本轮累计 %d 张；依次显示每手张数。" % [NAMES[seat], total]
		round_rows.append(row)

func show_round_history() -> void:
	var window = open_modal("round_history")
	label(window, Rect2(55, 30, 960, 62), "本轮出牌 · 按出牌先后", 31, Kit.ACCENT)
	var scroll = ScrollContainer.new(); scroll.position = Vector2(55, 110); scroll.size = Vector2(1090, 522)
	window.add_child(scroll)
	var lines = VBoxContainer.new(); scroll.add_child(lines)
	var index = 0
	for play in view.get("trick", []):
		index += 1
		var row = label(lines, Rect2(), "%02d   %s  ·  %d 张 %s" % [index, NAMES[play.seat], play.count, Cards.label(play.rank)], 25)
		row.custom_minimum_size = Vector2(1035, 50)

func draw_recorder() -> void:
	recorder = Recorder.new(); recorder.position = Vector2(74, 532)
	content.add_child(recorder)
	recorder.configure(view.get("recorder", {}))
	recorder.inspect_requested.connect(show_recorder)

func show_recorder() -> void:
	var window = open_modal("recorder")
	var counts: Dictionary = view.get("recorder", {})
	label(window, Rect2(55, 30, 960, 62), "记牌器 · 本家已清 %d 张" % int(counts.get("total", 0)), 32, Kit.ACCENT)
	label(window, Rect2(55, 139, 1090, 68), "只记你自己实际打出、并随本轮移出游戏的牌。", 28, Kit.TEXT)
	var ranks: Array = Cards.DECLARATIONS.duplicate(); ranks.append_array([16, 17])
	for index in range(ranks.size()):
		var rank = ranks[index]; var x = 187 + index * 63
		var name = "小王" if rank == 16 else ("大王" if rank == 17 else Cards.label(rank))
		label(window, Rect2(x, 286, 59, 47), name, 23, Kit.ACCENT, true)
		label(window, Rect2(x, 360, 59, 62), str(counts.get("counts", {}).get(rank, 0)), 34, Kit.TEXT, true)
	label(window, Rect2(55, 360, 127, 62), "已清", 25, Kit.MUTED)
	label(window, Rect2(55, 511, 1090, 102), "例如：你打出的 1 张 4 成为死牌，就记「4 已清 1 张」。\n其他人的盖牌不记；质疑后被收回手里的牌不记。\n按真实牌面记，唬成别的点数也不影响；大小王单独计数。", 23, Kit.MUTED)

func draw_review() -> void:
	var event: Dictionary = view.event
	var is_over = view.phase == "finished"
	var title = ""
	var subtitle = ""
	if event.get("type", "") == "challenge":
		title = "全部为真 · 质疑失败" if event.truthful else "发现假牌 · 抓包成功"
		subtitle = "%s开%s的 %d 张 %s" % [NAMES[event.caller], NAMES[event.seat], event.cards.size(), Cards.label(event.rank)]
		label(content, Rect2(385, 247, 830, 45), title, 33, Kit.ACCENT if event.truthful else Kit.CORAL, true)
		label(content, Rect2(385, 296, 830, 32), subtitle, 23, Kit.MUTED, true)
		var count = mini(10, event.cards.size())
		var width = count * 73 + 25
		for index in range(count):
			var id = event.cards[index]
			var at = Vector2(800 - width / 2.0 + index * 73, 337)
			face(content, id, Rect2(at, Vector2(95, 139)))
			label(content, Rect2(at + Vector2(0, 144), Vector2(86, 28)), "万能" if Cards.rank(id) >= 16 else ("真" if Cards.matches(id, event.rank) else "假"), 20, Kit.ACCENT if Cards.matches(id, event.rank) else Kit.CORAL, true)
		if event.cards.size() > 10:
			button(content, Rect2(601, 518, 398, 38), "展开全部 %d 张" % event.cards.size(), show_reveal)
		else:
			label(content, Rect2(375, 516, 850, 36), "%s收回中央全部 %d 张 · 历史牌不展示" % [NAMES[event.loser], event.count], 22, Kit.TEXT, true)
	elif event.get("type", "") == "rps":
		label(content, Rect2(398, 281, 804, 73), "%s猜拳获胜" % NAMES[event.leader], 43, Kit.ACCENT, true)
		var names: Array = []
		for seat in range(view.config.players):
			if event.gestures[seat] >= 0: names.append(NAMES[seat] + " " + GESTURES[event.gestures[seat]])
		label(content, Rect2(344, 378, 912, 65), " · ".join(names), 23, Kit.TEXT, true)
	elif event.get("type", "") == "dead":
		label(content, Rect2(387, 284, 826, 79), "%d 张成为死牌" % event.count, 43, Kit.ACCENT, true)
		label(content, Rect2(385, 383, 830, 61), "其余玩家全部过牌 · 不翻面，移出本局", 25, Kit.MUTED, true)
	if is_over:
		label(content, Rect2(435, 553, 730, 51), "你赢了！" if view.winner == 0 else "%s率先出完 · 本局获胜" % NAMES[view.winner], 33, Kit.ACCENT, true)
		if event.get("type", "") not in ["challenge", "dead"]:
			label(content, Rect2(392, 299, 816, 117), "最后一手已获认可\n这局的虚实，到这里揭晓。", 33, Kit.TEXT, true)
	else:
		label(content, Rect2(435, 559, 730, 34), "下一轮由%s领出" % NAMES[view.next_leader], 27, Kit.ACCENT, true)

func draw_hand() -> void:
	var hand: Array = view.hand
	var rows = ceili(hand.size() / float(ROW_SIZE)) if compact_hand() else 1
	var columns = ceili(hand.size() / float(maxi(1, rows)))
	var height = 164.0 if rows <= 2 else 140.0
	var row_step = 176.0 if rows == 2 else (110.0 if rows == 3 else 74.0)
	var top = 715.0 if rows == 1 else (516.0 if rows == 2 else 504.0)
	label(hand_layer, Rect2(74, hand_header_y(), 460, 38), "我的手牌 · %d 张%s" % [hand.size(), " · %d 行" % rows if rows > 1 else ""], 23, Kit.TEXT)
	if not hand.is_empty():
		var inspect = button(hand_layer, Rect2(1235, hand_header_y() - 2, 275, 40), "放大查看手牌", show_hand)
		for style_name in ["normal", "hover", "pressed", "focus", "disabled"]:
			var style = inspect.get_theme_stylebox(style_name)
			style.content_margin_top = 4; style.content_margin_bottom = 4
		inspect.size.y = 40
	for row in range(rows):
		var row_hand = hand.slice(row * columns, (row + 1) * columns)
		var width = height * 112.0 / 164.0
		var stride = minf(83, 1330.0 / maxi(1, row_hand.size() - 1))
		var start_x = (1600 - ((row_hand.size() - 1) * stride + width)) / 2.0
		for index in range(row_hand.size()):
			var y = top + row * row_step
			var card = face(hand_layer, row_hand[index], Rect2(start_x + stride * index, y, width, height))
			card.set_meta("rest_y", y); card.set_meta("row", row)
			card.set_meta("hit_width", stride if index + 1 < row_hand.size() else width)
			card.set_meta("hit_height", minf(height + 16, row_step) if row + 1 < rows else height + 16)
			hand_cards.append(card)
	refresh_selection()

func draw_actions() -> void:
	if view.phase == "playing":
		if view.turn == 0:
			if view.last.is_empty():
				label(action_layer, Rect2(360, 536, 130, 36), "宣称点数", 20, Kit.MUTED)
				for index in range(Cards.DECLARATIONS.size()):
					var rank = Cards.DECLARATIONS[index]
					var b = button(action_layer, Rect2(490 + index * 55, 535, 50, 42), Cards.label(rank), func(): declared = rank; render(), declared == rank)
					b.add_theme_font_size_override("font_size", 20)
					rank_buttons.append(b)
			play_button = button(action_layer, Rect2(885, 591, 315, 56), "扣牌", send_play, true)
			pass_button = button(action_layer, Rect2(725, 591, 148, 56), "过牌", func(): send({"type": "pass"}))
			button(action_layer, Rect2(360, 591, 168, 56), "清空选择", func(): selected.clear(); refresh_selection())
		else:
			label(action_layer, Rect2(399, 597, 480, 45), "等待%s表态…" % NAMES[view.turn], 25, Kit.MUTED, true)
		if view.can_challenge:
			challenge_button = button(action_layer, Rect2(540 if view.turn == 0 else 887, 591, 173 if view.turn == 0 else 313, 56), "开！质疑", func(): send({"type": "challenge"}))
			challenge_button.add_theme_stylebox_override("normal", Kit.style(Color("573c30"), Kit.CORAL))
		selection_label = label(hand_layer, Rect2(542, hand_header_y(), 658, 39), "", 20, Kit.ACCENT, true)
	elif view.phase == "review":
		review_label = label(action_layer, Rect2(452, 602, 696, 43), "", 23, Kit.MUTED, true)
		set_review_remaining(float(view.get("review_remaining", 4.0)))
	elif view.phase == "finished":
		button(action_layer, Rect2(525, 606, 265, 41), "返回入座", reset_setup)
		button(action_layer, Rect2(808, 606, 265, 41), "再来一局", func(): start_requested.emit(Rules.options(settings)), true)
	refresh_selection()

func set_review_remaining(seconds: float) -> void:
	if is_instance_valid(review_label):
		review_label.text = "%d 秒后自动开始下一轮" % maxi(1, ceili(seconds))

func can_select() -> bool:
	return not view.is_empty() and view.phase == "playing" and view.turn == 0 and not paused and submitted != int(view.revision)

func refresh_selection() -> void:
	for card in hand_cards:
		card.set_chosen(card.card_id in selected)
		card.position.y = float(card.get_meta("rest_y")) - (16 if card.chosen else 0)
	var can = can_select()
	var valid = can and not selected.is_empty()
	if is_instance_valid(play_button):
		play_button.disabled = not valid
		play_button.text = "扣下 %d 张 %s" % [selected.size(), Cards.label(declared)] if not selected.is_empty() else "选牌后扣下"
	if is_instance_valid(pass_button): pass_button.disabled = not can or view.last.is_empty()
	if is_instance_valid(challenge_button): challenge_button.disabled = paused or submitted == int(view.revision)
	if is_instance_valid(selection_label):
		selection_label.text = notice if not notice.is_empty() else ("已选 %d 张 · 以宣称点数为准" % selected.size() if not selected.is_empty() else "点选／划选后确认 · 可真可假")

func toggle_card(id: int) -> void:
	if not can_select() or id not in view.hand: return
	if id in selected: selected.erase(id)
	else: selected.append(id)
	refresh_selection()

func send_play() -> void:
	if not can_select() or selected.is_empty(): return
	send({"type": "play", "cards": selected.duplicate(), "rank": declared})

func send(action: Dictionary) -> void:
	if view.is_empty() or paused or submitted == int(view.revision): return
	action["revision"] = view.revision; action["round_id"] = view.round_id
	submitted = view.revision
	cancel_drag(); refresh_selection()
	action_requested.emit(action)

func action_rejected() -> void:
	submitted = -1; notice = "牌局已变化，请重新选择。"; refresh_selection()

func toggle_theme() -> void:
	settings.theme = "guofeng" if settings.theme == "traditional" else "traditional"
	settings_changed.emit(settings.duplicate())
	render()

func reset_setup() -> void:
	close_modal(); view = {}; selected.clear(); render()

func open_modal(kind: String) -> Control:
	cancel_drag(); clear(modal_layer)
	modal_kind = kind; paused = true; pause_changed.emit(true)
	var shade = ColorRect.new(); shade.color = Color("031a17dd"); shade.size = size
	modal_layer.add_child(shade)
	var window = Kit.panel(modal_layer, Rect2(200, 100, 1200, 700), Color("102f29fc"), Color("c9b57c80"), 25)
	button(window, Rect2(1063, 28, 90, 51), "返回", close_modal)
	refresh_selection()
	return window

func close_modal() -> void:
	if not built: return
	clear(modal_layer); modal_kind = ""; paused = false; pause_changed.emit(false)
	refresh_selection()

func pause_menu() -> void:
	if not modal_kind.is_empty(): close_modal(); return
	var window = open_modal("pause")
	label(window, Rect2(65, 43, 950, 68), "牌局已暂停", 39, Kit.ACCENT)
	label(window, Rect2(65, 150, 1050, 82), "慢慢想，这一手等你回来。\n返回大厅将结束当前牌局。", 26, Kit.MUTED)
	button(window, Rect2(65, 325, 1050, 73), "继续牌局", close_modal, true)
	button(window, Rect2(65, 430, 510, 66), "本桌玩法", show_rules)
	button(window, Rect2(595, 430, 520, 66), "牌局记录", show_history)
	button(window, Rect2(65, 543, 1050, 66), "结束本局，返回大厅", func(): exit_requested.emit())

func show_rules() -> void:
	var window = open_modal("rules")
	label(window, Rect2(55, 32, 960, 55), "唬牌 · 本桌玩法", 35, Kit.ACCENT)
	var text = "01  入座与领出\n3 人一副牌，4–6 人两副牌，含大小王。猜拳决出先手；领出可选任意张牌，指定 A–K 任一点数。\n\n02  顺时针表态\n跟牌可选任意张数，必须沿用本轮点数；也可过牌或喊「开」。真假由你决定。\n\n03  只开最后一手，输家收走整堆\n有一张不符即为假，出牌者全收；全部符合则质疑者全收。大小王替代任意点数。\n质疑成功者领出；质疑失败则原出牌者领出。开牌停留约4秒后自动继续。\n\n04  全员过牌与最后一手\n出牌后其他所有人均过牌，整堆不翻面成为死牌，出牌者重新领出。\n最后一手仍可被质疑；有人跟牌、其余全过或开牌证实为真，才算出完获胜。"
	label(window, Rect2(55, 112, 1090, 469), text, 23, Kit.TEXT)
	label(window, Rect2(55, 607, 1090, 46), "本桌：" + ("任何人可抢开，以率先受理的有效操作为准。" if settings.challenge == "any" else "仅轮到的玩家可以质疑最近一手；过牌后由下一家决定。"), 23, Kit.ACCENT)

func show_history() -> void:
	var window = open_modal("history")
	label(window, Rect2(55, 30, 960, 62), "牌局记录 · 只记录公开信息", 31, Kit.ACCENT)
	var scroll = ScrollContainer.new(); scroll.position = Vector2(55, 112); scroll.size = Vector2(1090, 520)
	window.add_child(scroll)
	var lines = VBoxContainer.new(); lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(lines)
	var history: Array = view.get("history", []).duplicate(); history.reverse()
	for event in history:
		var text = event_text(event)
		var row = label(lines, Rect2(0, 0, 1020, 53), text, 23, Kit.TEXT)
		row.custom_minimum_size = Vector2(1020, 53)
	if history.is_empty(): label(lines, Rect2(0, 0, 1000, 50), "还没有行动记录。", 24, Kit.MUTED)

func event_text(event: Dictionary) -> String:
	match event.type:
		"play": return "%s  宣称 %d 张 %s%s" % [NAMES[event.seat], event.count, Cards.label(event.rank), " · 最后一手" if event.empty else ""]
		"pass": return NAMES[event.seat] + "  过牌"
		"challenge": return "%s 开 %s · %s · %s收回 %d 张" % [NAMES[event.caller], NAMES[event.seat], "全部为真" if event.truthful else "含有假牌", NAMES[event.loser], event.count]
		"dead": return "%d 张成为死牌 · %s重新领出" % [event.count, NAMES[event.seat]]
		"win": return NAMES[event.seat] + "  获胜"
		"rps": return "第 %d 轮猜拳 · %s" % [event.round, NAMES[event.leader] + "先手" if event.has("leader") else "继续决胜"]
	return ""

func show_reveal() -> void:
	show_grid(false)

func show_hand() -> void:
	if view.is_empty(): return
	show_grid(true)

func show_grid(hand: bool) -> void:
	var window = open_modal("hand" if hand else "reveal")
	var cards: Array = view.hand if hand else view.event.get("cards", [])
	var heading = "完整手牌 · %d 张" % cards.size() if hand else "本次翻开的 %d 张 %s" % [cards.size(), Cards.label(view.event.rank)]
	label(window, Rect2(55, 28, 965, 62), heading, 32, Kit.ACCENT)
	var scroll = ScrollContainer.new(); scroll.position = Vector2(55, 106); scroll.size = Vector2(1090, 494)
	window.add_child(scroll)
	var grid = GridContainer.new(); grid.columns = 10; grid.add_theme_constant_override("h_separation", 9); grid.add_theme_constant_override("v_separation", 15)
	scroll.add_child(grid)
	for id in cards:
		var cell = Control.new(); cell.custom_minimum_size = Vector2(98, 168); grid.add_child(cell)
		var card = face(cell, id, Rect2(0, 0, 98, 144)); card.set_chosen(id in selected if hand else false)
		if hand and view.phase == "playing" and view.turn == 0:
			card.mouse_filter = MOUSE_FILTER_STOP
			card.pressed.connect(func():
				if id in selected: selected.erase(id)
				else: selected.append(id)
				card.set_chosen(id in selected); refresh_selection())
		var caption = "万能" if Cards.rank(id) >= 16 else ("第 %d 副" % (int(id / 54) + 1) if hand else ("真" if Cards.matches(id, view.event.rank) else "假"))
		label(cell, Rect2(0, 143, 98, 25), caption, 18, Kit.MUTED if hand or Cards.matches(id, view.event.rank) else Kit.CORAL, true)
	var footer = "逐张选择后返回牌桌确认；已选牌会保留。" if hand else "%s收回整堆 %d 张；这里仅展示最近一手。" % [NAMES[view.event.loser], view.event.count]
	label(window, Rect2(55, 617, 1090, 44), footer, 23, Kit.MUTED)

func card_at(point: Vector2) -> int:
	for index in range(hand_cards.size() - 1, -1, -1):
		if hand_cards[index].get_rect().has_point(point): return hand_cards[index].card_id
	return -1

func cancel_drag() -> void:
	drag_active = false; drag_seen.clear(); drag_regions.clear()

func visit(id: int) -> void:
	if id < 0 or drag_seen.has(id): return
	drag_seen[id] = true; toggle_card(id)

func _input(event: InputEvent) -> void:
	if not can_select(): cancel_drag(); return
	if event is InputEventScreenTouch:
		if event.pressed:
			var at = get_global_transform_with_canvas().affine_inverse() * event.position
			var id = card_at(at)
			if id >= 0:
				touch_until = Time.get_ticks_msec() + 500; touch_position = at
				toggle_card(id); get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var at = get_global_transform_with_canvas().affine_inverse() * event.position
		# Suppress only the mouse pair of a consumed hand touch. Buttons and
		# recorder/history controls still need their emulated mouse click.
		if Time.get_ticks_msec() < touch_until and event.device == InputEvent.DEVICE_ID_EMULATION and at.distance_to(touch_position) < 12:
			get_viewport().set_input_as_handled(); return
		if event.pressed:
			cancel_drag()
			var id = card_at(at)
			if id >= 0:
				drag_active = true; drag_last = at
				for index in range(hand_cards.size()):
					var card = hand_cards[index]
					drag_regions.append({"id": card.card_id, "rect": Rect2(card.position.x, float(card.get_meta("rest_y")) - 16, float(card.get_meta("hit_width")), float(card.get_meta("hit_height")))})
				visit(id); get_viewport().set_input_as_handled()
		elif drag_active:
			cancel_drag(); get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and drag_active:
		if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT): cancel_drag(); return
		var at = get_global_transform_with_canvas().affine_inverse() * event.position
		for region in drag_regions:
			if segment_hits(drag_last, at, region.rect): visit(region.id)
		drag_last = at

func segment_hits(from: Vector2, to: Vector2, rect: Rect2) -> bool:
	var low = 0.0; var high = 1.0; var delta = to - from
	for axis in range(2):
		if absf(delta[axis]) < 0.0001:
			if from[axis] < rect.position[axis] or from[axis] >= rect.end[axis]: return false
		else:
			var a = (rect.position[axis] - from[axis]) / delta[axis]
			var b = (rect.end[axis] - 0.001 - from[axis]) / delta[axis]
			low = maxf(low, minf(a, b)); high = minf(high, maxf(a, b))
			if low > high: return false
	return true

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and can_select():
		selected.clear(); refresh_selection(); accept_event()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_MOUSE_EXIT]: cancel_drag()
