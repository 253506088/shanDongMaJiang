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
	check(table.play_button.disabled and actions.is_empty(), "five-card lead blocked without auto-play")
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
	table.set_view(view)
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
	view.revision = 6; view.hand = range(108); table.set_view(view)
	check(table.hand_cards.size() == 30 and is_instance_valid(find_button(table, "›")), "large hand paginated at readable widths")
	table.toggle_card(0)
	await click(find_button(table, "›"))
	check(table.page == 1 and table.selected.has(0) and table.hand_cards[0].card_id == 30, "paging preserves off-page choices")
	table.toggle_card(30)
	check(table.selected.size() == 2, "cross-page selections retained")
	await capture("07-large-hand")
	table.show_hand(); await capture("08-expanded-large-hand"); table.close_modal()
	view = fixture(6); view.revision = 7; view.phase = "review"; view.turn = -1; view.next_leader = 2
	view.event = {"type": "challenge", "caller": 2, "seat": 1, "rank": 3, "cards": [0, 54, 4, 52, 106], "truthful": false, "loser": 1, "count": 29, "leader": 2}
	table.set_view(view)
	await capture("09-caught")
	check(is_instance_valid(find_button(table, "看清了，继续   →")), "open reveal requires human acknowledgment")
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
	table.queue_free(); surface.queue_free(); await frames(3)
	print("BLUFF_UI_RESULT: %d failures; %d checks" % [failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
