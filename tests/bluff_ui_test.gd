extends SceneTree
## Test viewport input only; never system mouse, keyboard, focus or other windows.
const Table = preload("res://scripts/bluff/ui/table.gd")
const Game = preload("res://scripts/bluff/core/engine.gd")
const Surface = preload("res://scripts/ui/scene_surface.gd")
var table
var surface
var failures: Array = []
var checks = 0
var actions: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("BLUFF UI FAIL: ", message)

func frames(count: int = 2) -> void:
	for i in range(count): await process_frame

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var args = OS.get_cmdline_user_args(); var index = args.find("--capture-dir")
	if index < 0: return
	await frames(3); RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(args[index + 1].path_join(name + ".png")) == OK, "capture " + name)

func fixture(count: int = 3) -> Dictionary:
	var game = Game.new(); game.start(765, {"players": count})
	game.state.phase = "playing"; game.state.turn = 0
	var view = game.view(0); view["round_id"] = 1
	return view

func find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text and node.is_visible_in_tree(): return node
	for child in node.get_children():
		var found = find_button(child, text)
		if found: return found
	return null

func mouse(at: Vector2, down: bool, device: int = 0) -> void:
	var event = InputEventMouseButton.new(); event.position = at; event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down; event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0; event.device = device
	root.push_input(event, true); await frames()

func click(button: Control) -> void:
	check(is_instance_valid(button), "click target exists")
	if not is_instance_valid(button): return
	var at = button.get_global_rect().get_center()
	await mouse(at, true); await mouse(at, false)

func motion(at: Vector2) -> void:
	var event = InputEventMouseMotion.new(); event.position = at; event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true); await frames()

func run() -> void:
	create_timer(100).timeout.connect(func(): printerr("BLUFF UI watchdog"); quit(1))
	Engine.max_fps = 60
	surface = Surface.new(); root.add_child(surface)
	table = Table.new(); surface.scene_viewport.add_child(table)
	table.action_requested.connect(func(action): actions.append(action.duplicate(true)))
	await frames(4)
	check(table.settings.players == 3, "default three players")
	await capture("01-setup")
	await click(find_button(table, "6 人"))
	check(table.settings.players == 6, "six-player configuration selectable")
	await click(find_button(table, "任何人可抢开"))
	check(table.settings.challenge == "any", "free-call option selectable")
	var game = Game.new(); game.start(783, {"players": 6})
	var view = game.view(0); view["round_id"] = 1
	table.set_view(view)
	await capture("02-rps-six")
	await click(find_button(table, "石头"))
	check(actions.size() == 1 and actions.back().type == "rps", "human chooses gesture")
	view = fixture(6); view.revision = 2
	view.hand = [0, 54, 4, 58, 8, 62, 12, 66, 16, 70, 20, 74, 24, 78, 28, 82, 52, 106]
	table.set_view(view); actions.clear()
	check(table.hand_cards.size() == 18 and table.pass_button.disabled, "hand shown and no passing lead")
	await click(table.rank_buttons[7])
	check(table.declared == 8, "declare rank chosen independently of real cards")
	var points: Array = []
	for card in table.hand_cards.slice(0, 5): points.append(card.global_position + Vector2(20, 85))
	await mouse(points[0], true); await motion(points[4]); await motion(points[0]); await mouse(points[0], false)
	check(table.selected.size() == 5 and table.selected.has(0) and table.selected.has(54), "drag chooses both physical copies and each card once")
	check(not table.play_button.disabled and actions.is_empty(), "five-card lead allowed but still requires confirmation")
	await click(find_button(table, "清空选择"))
	await mouse(points[0], true); await mouse(points[0], false)
	check(table.selected == [0], "single click only selects")
	table.toggle_theme()
	check(table.selected == [0] and table.hand_cards.all(func(card): return card.theme_id == "guofeng"), "theme switch preserves selected physical hand")
	await capture("03-six-lead-guofeng")
	table.show_hand(); await frames()
	check(table.paused and table.modal_kind == "hand", "full hand inspection pauses bots")
	await capture("04-full-hand")
	table.close_modal()
	await click(table.play_button)
	check(actions.size() == 1 and actions[0].cards == [0] and actions[0].rank == 8, "explicit bluff declaration emitted")
	table.send_play(); check(actions.size() == 1, "same revision cannot submit twice")
	view = fixture(6); view.revision = 3; view.hand = range(27)
	view.last = {"seat": 5, "rank": 8, "count": 4}; view.rank = 8; view.pile_count = 19; view.can_challenge = true
	view.trick = [{"seat": 0, "count": 1, "rank": 8}, {"seat": 1, "count": 3, "rank": 8},
		{"seat": 2, "count": 2, "rank": 8}, {"seat": 3, "count": 1, "rank": 8},
		{"seat": 4, "count": 1, "rank": 8}, {"seat": 5, "count": 4, "rank": 8},
		{"seat": 1, "count": 3, "rank": 8}, {"seat": 5, "count": 4, "rank": 8}]
	view.recorder.counts[4] = 1; view.recorder.counts[8] = 2; view.recorder.counts[16] = 1; view.recorder.total = 4
	table.set_view(view)
	check(table.round_rows.size() == 6 and table.round_rows[1].text == "听松  3 + 3 张", "every seat's full trick play sequence is visible")
	check(table.round_rows[0].text == "我  1 张" and table.round_rows[5].text == "怀竹  4 + 4 张", "history includes human and repeated opponent plays")
	await frames()
	check(table.round_rows.back().get_global_rect().end.y <= table.round_history.get_global_rect().end.y - 12, "normal six-seat history fits without hiding the final player")
	check(table.recorder.data.counts[4] == 1 and table.recorder.data.total == 4, "recorder shows only this seat's cleared physical cards")
	await click(table.recorder)
	check(table.modal_kind == "recorder" and table.paused, "recorder can be inspected while bots pause")
	await capture("15-recorder"); table.close_modal()
	await click(find_button(table, "本轮出牌 · 详情"))
	check(table.modal_kind == "round_history" and table.paused, "chronological history is available without advancing game")
	await capture("16-round-history"); table.close_modal()
	for id in range(9): table.toggle_card(id)
	check(not table.play_button.disabled and table.declared == 8, "unlimited follow and fixed rank")
	await capture("05-six-follow")
	await click(table.challenge_button)
	check(actions.back().type == "challenge", "open calls current hand")
	view.revision = 4; view.turn = 1; view.config.challenge = "any"; table.set_view(view)
	check(is_instance_valid(table.challenge_button) and not table.challenge_button.disabled, "anyone-call mode works outside own turn")
	await capture("06-free-call")
	view.revision = 5; view.turn = 0; view.hand = [0, 54, 52, 106]; table.set_view(view)
	var at = table.hand_cards[0].global_position + Vector2(20, 80)
	for down in [true, false]:
		var touch = InputEventScreenTouch.new(); touch.position = at; touch.index = 0; touch.pressed = down
		root.push_input(touch, true); await frames()
		await mouse(at, down, InputEvent.DEVICE_ID_EMULATION)
	check(table.selected == [0], "touch plus emulated mouse toggles exactly once")
	# A subsequent finger tap on the recorder must still reach its control;
	# consuming all emulated mouse events would disable the touch UI buttons.
	at = table.recorder.get_global_rect().get_center()
	for down in [true, false]:
		var touch = InputEventScreenTouch.new(); touch.position = at; touch.index = 0; touch.pressed = down
		root.push_input(touch, true); await frames()
		await mouse(at, down, InputEvent.DEVICE_ID_EMULATION)
	check(table.modal_kind == "recorder", "touch opens recorder during own turn without hand-pair suppression")
	table.close_modal()
	view.revision = 6; view.hand = range(108); view.hand_counts[0] = 108; table.set_view(view)
	check(table.hand_cards.size() == 108 and not is_instance_valid(find_button(table, "›")), "all 108 physical cards displayed without pagination")
	table.toggle_card(0)
	check(table.hand_cards[0].position.y < table.hand_cards[30].position.y and table.selected.has(0), "large hand wraps into persistent rows")
	table.toggle_card(30)
	check(table.selected.size() == 2, "selection preserved across rows")
	check(table.hand_cards.all(func(card): return card.get_rect().end.y <= 880 and card.position.x >= 55 and card.get_rect().end.x <= 1545), "all rows fit inside the table")
	check(table.play_button.get_global_rect().end.y < table.hand_cards[0].global_position.y, "hand rows do not cover confirm actions")
	check(find_button(table, "放大查看手牌").get_global_rect().end.y < table.hand_cards[0].global_position.y, "raised top-row card cannot cover the hand inspection button")
	check(table.round_rows.size() == 6, "six players' contributions stay visible with a large hand")
	await click(find_button(table, "清空选择"))
	var first = table.hand_cards[27].global_position + Vector2(20, 30)
	var fifth = table.hand_cards[31].global_position + Vector2(20, 30)
	await mouse(first, true); await motion(fifth); await motion(first); await mouse(first, false)
	check(table.selected.size() == 5 and table.selected.has(27) and table.selected.has(31), "second-row drag selects each physical card once without hitting other rows")
	await capture("07-large-hand")
	table.show_hand(); await capture("08-expanded-large-hand"); table.close_modal()
	for amount in [31, 54, 81]:
		view.revision += 1; view.hand = range(amount); view.hand_counts[0] = amount; table.set_view(view)
		check(table.hand_cards.size() == amount, "every card visible at row transition %d" % amount)
		await capture("20-multirow-%d" % amount)
	view.hand = range(108); view.hand_counts[0] = 108; view.revision += 1; view.phase = "review"; view.turn = -1; view.next_leader = 2
	view.event = {"type": "challenge", "caller": 0, "seat": 1, "rank": 3, "cards": [0, 1], "truthful": true, "loser": 0, "count": 2, "leader": 1}
	table.set_view(view)
	await click(find_button(table, "查看翻开的 2 张"))
	check(table.modal_kind == "reveal" and table.paused, "large-hand result still exposes actual revealed cards and pauses inspection")
	table.close_modal(); await capture("21-large-hand-review")
	view = fixture(6); view.revision = 7; view.phase = "review"; view.turn = -1; view.next_leader = 2
	view.event = {"type": "challenge", "caller": 2, "seat": 1, "rank": 3, "cards": [0, 54, 4, 52, 106], "truthful": false, "loser": 1, "count": 29, "leader": 2}
	table.set_view(view)
	await capture("09-caught")
	check(not is_instance_valid(find_button(table, "看清了，继续   →")) and is_instance_valid(table.review_label), "reveal has countdown instead of acknowledgment button")
	table.set_review_remaining(2.3)
	check(table.review_label.text.begins_with("3 秒"), "review updates remaining seconds without rebuilding the table")
	view.revision = 8; view.event.cards = range(30); table.set_view(view)
	await click(find_button(table, "展开全部 30 张"))
	check(table.modal_kind == "reveal", "unlimited follow reveal can be inspected in full")
	await capture("10-large-reveal"); table.close_modal()
	view.revision = 9; view.phase = "finished"; view.winner = 0
	view.event = {"type": "challenge", "caller": 2, "seat": 0, "rank": 3, "cards": [0, 54, 52], "truthful": true, "loser": 2, "count": 18, "leader": 0}
	view.hand = []; view.hand_counts[0] = 0; table.set_view(view)
	check(is_instance_valid(find_button(table, "再来一局")), "unlimited new rounds available after win")
	await capture("11-win")
	table.show_rules(); await capture("12-rules"); table.close_modal()
	table.pause_menu(); check(table.paused, "pause freezes actions"); await capture("13-pause"); table.close_modal()
	for count in [3, 4, 5]:
		view = fixture(count); view.revision = 10 + count; table.set_view(view)
		await capture("14-seats-%d" % count)
	view = fixture(6); view.revision = 20; view.event = {"type": "dead", "count": 19, "seat": 0}
	view.recorder.total = 1; view.recorder.counts[4] = 1
	table.set_view(view)
	check(table.round_rows.is_empty() and table.review_label == null and is_instance_valid(table.play_button), "clearing resets history and offers next lead immediately")
	check(table.recorder.data.counts[4] == 1, "cleared count remains visible across tricks")
	await capture("17-cleared-next-lead")
	view = fixture(); view.revision = 21; view.hand = [53, 52, 51, 50, 49, 48, 47, 46, 45, 44]
	view.hand_counts = [10, 21, 15]; view.dead_count = 8
	table.set_view(view)
	await click(table.rank_buttons[0])
	for id in [44, 45, 46, 47, 52, 53]: table.toggle_card(id)
	check(not table.play_button.disabled and table.play_button.text == "扣下 6 张 A", "screenshot's six ace/joker lead is enabled")
	await capture("18-six-aces-lead")
	for id in [48, 49, 50, 51]: table.toggle_card(id)
	check(not table.play_button.disabled and table.play_button.text == "扣下 10 张 A", "screenshot's whole hand may claim ten aces")
	await capture("19-ten-aces-whole-hand")
	await click(table.play_button)
	check(actions.back().type == "play" and actions.back().cards.size() == 10 and actions.back().rank == 14, "whole hand reaches action boundary with declared aces")
	view.revision = 22; view.hand = range(10); table.set_view(view)
	for id in view.hand: table.toggle_card(id)
	check(not table.play_button.disabled, "ten non-aces with no joker may still lead as aces")
	await click(table.play_button)
	check(actions.back().cards == range(10) and actions.back().rank == 14, "UI does not require real aces or jokers for an ace declaration")
	# Real authority views drive the permission UI and actual viewport clicks.
	for allow in [false, true]:
		game = Game.new(); game.start(702, {"players": 3})
		game.state.phase = "playing"; game.state.turn = 1
		game.state.hands = [[0, 1, 2], [4, 5, 6, 7, 8], [9, 10, 11, 12, 13]]
		game.act(1, {"type": "play", "cards": [4], "rank": 14, "revision": 0})
		game.act(2, {"type": "request_challenge", "revision": 1})
		view = game.view(0); view["round_id"] = 50 if allow else 49; table.set_view(view)
		check(table.report_labels.size() == 1 and table.report_labels[0].text.contains("报牌三张"), "human low hand stays visibly reported during consent")
		check(table.permission_buttons.size() == 2 and not table.can_select(), "only consent actions offered while request is pending")
		await capture("22-consent-human")
		await click(find_button(table, "允许这次开牌" if allow else "不允许"))
		check(actions.back().type == "challenge_permission" and actions.back().allow == allow, "viewport click sends selected permission answer")
		check(game.act(0, actions.back()), "UI consent accepted by authority")
		view = game.view(0); view["round_id"] = 50 if allow else 49; table.set_view(view)
		check(table.permission_buttons.is_empty(), "resolved request disappears")
		await capture("23-consent-approved" if allow else "24-consent-denied")
	game = Game.new(); game.start(703, {"players": 3})
	game.state.phase = "playing"; game.state.turn = 2
	game.state.hands = [[0, 1, 2, 3, 4], [5, 6], [8, 9, 10, 11, 12]]
	game.act(2, {"type": "play", "cards": [8], "rank": 3, "revision": 0})
	view = game.view(0); view["round_id"] = 51; table.set_view(view)
	table.toggle_card(0)
	check(table.challenge_button.text == "申请开牌" and not table.play_button.disabled, "protected opponent changes only the challenge action to a request")
	await capture("25-request-button")
	await click(table.challenge_button)
	check(actions.back().type == "request_challenge" and game.act(0, actions.back()), "human asks bot before opening")
	view = game.view(0); view["round_id"] = 51; table.set_view(view)
	check(table.permission_buttons.is_empty() and table.selected == [0], "bot consent wait preserves chosen hand")
	await capture("26-consent-bot")
	game.act(1, {"type": "challenge_permission", "allow": false, "revision": game.state.revision})
	view = game.view(0); view["round_id"] = 51; table.set_view(view)
	check(table.selected == [0] and not table.play_button.disabled and not table.pass_button.disabled and not is_instance_valid(table.challenge_button), "denial preserves selection and follow/pass, without repeat request")
	await capture("27-denied-follow")
	view = fixture(6); view.revision = 80; view.hand = range(81); view.hand_counts = [81, 3, 2, 1, 8, 9]; table.set_view(view)
	check(table.report_labels.size() == 3, "multiple low opponents reported in compact multirow layout")
	await capture("28-multiple-reports")
	table.queue_free(); surface.queue_free(); await frames(3)
	print("BLUFF_UI_RESULT: %d failures; %d checks" % [failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
