extends SceneTree
## Sends input into this test's viewport, never to the desktop mouse/keyboard.
const TableScript = preload("res://scripts/doudizhu/ui/table.gd")
const Rules = preload("res://scripts/doudizhu/core/rules.gd")
const Surface = preload("res://scripts/ui/scene_surface.gd")
var table
var surface
var failures: Array = []
var assertions: int = 0
var actions: Array = []
var pause_events: Array = []
var hints: int = 0
var nexts: int = 0
var exits: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		printerr("DDZ UI FAIL: ", message)

func frames(count: int = 2) -> void:
	for index in range(count): await process_frame

func fixture(phase: String = "playing", revision: int = 10) -> Dictionary:
	return {"phase": phase, "revision": revision, "seat": 0, "turn": 0,
		"hand": [0, 1, 2, 3, 4, 5, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 49, 52, 53],
		"hand_counts": [20, 17, 17], "landlord": 0, "bottom": [1, 12, 53],
		"highest_bid": 3, "bids": [3, -1, -1], "bid_starter": 0,
		"target": {}, "target_seat": -1, "passes": 0, "last_actions": [{}, {}, {}],
		"event": {"type": "landlord", "seat": 0}, "multiplier": 1, "bomb_count": 0,
		"result": {}, "play_counts": [0, 0, 0]}

func click(control: Control) -> void:
	check(is_instance_valid(control), "input target exists")
	if not is_instance_valid(control): return
	var at = control.get_global_rect().get_center()
	# The visible left strip of an overlapped card is its hit target.
	if control.get_script() == preload("res://scripts/doudizhu/ui/card.gd"):
		at = control.global_position + Vector2(20, 84)
	var motion = InputEventMouseMotion.new(); motion.position = at
	root.push_input(motion, true)
	await frames()
	for pressed in [true, false]:
		var event = InputEventMouseButton.new()
		event.position = at; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)
		await frames()

func find_button(parent: Node, text: String) -> Button:
	if parent is Button and parent.text == text and parent.is_visible_in_tree(): return parent
	var children = parent.get_children()
	children.reverse()
	for child in children:
		var result = find_button(child, text)
		if result: return result
	return null

func touch_at(at: Vector2) -> void:
	var motion = InputEventMouseMotion.new(); motion.position = at
	root.push_input(motion, true)
	for pressed in [true, false]:
		var touch = InputEventScreenTouch.new(); touch.position = at; touch.index = 0; touch.pressed = pressed
		root.push_input(touch, true)
		# push_input bypasses Input's mouse emulation; supply the paired event
		# emitted by this project's real touch controls, without touching the OS.
		var mouse = InputEventMouseButton.new(); mouse.position = at
		mouse.button_index = MOUSE_BUTTON_LEFT; mouse.pressed = pressed
		mouse.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(mouse, true)
		await frames()

func find_card(id: int):
	for card in table.hand_cards:
		if card.card_id == id: return card
	return null

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var args = OS.get_cmdline_user_args()
	var index = args.find("--capture-dir")
	if index < 0 or index + 1 >= args.size(): return
	var directory = args[index + 1]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	await frames(3)
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(directory.path_join(name + ".png")) == OK, "capture " + name)

func run() -> void:
	create_timer(90).timeout.connect(func(): printerr("DDZ UI watchdog"); quit(1))
	Engine.max_fps = 60
	surface = Surface.new(); root.add_child(surface)
	table = TableScript.new(); surface.scene_viewport.add_child(table)
	table.action_requested.connect(func(action): actions.append(action.duplicate(true)))
	table.pause_changed.connect(func(paused): pause_events.append(paused))
	table.hint_requested.connect(func(): hints += 1)
	table.next_requested.connect(func(): nexts += 1)
	table.exit_requested.connect(func(): exits += 1)
	table.set_muted(true)
	var state = fixture()
	table.set_view(state)
	await frames(4)
	check(table.hand_cards.size() == 20, "landlord shows all twenty physical cards")
	check(table.hand_cards[0].card_id == 53, "high cards are on left")
	check(table.pass_button.disabled, "leader cannot pass")
	check(table.play_button.disabled, "empty selection cannot play")
	check(table.hand_cards[0].global_position.x > 190 and table.hand_cards.back().get_global_rect().end.x < 1550, "twenty cards fit the table and self portrait")
	await capture("ddz-full-hand")
	await click(find_card(0))
	check(table.selected_cards == [0] and actions.is_empty(), "single click selects without playing")
	check(find_card(0).position.y < TableScript.HAND_Y, "selected card is raised")
	check(not table.play_button.disabled, "valid single can be played")
	await click(find_card(1))
	check(table.selected_cards.size() == 2 and not table.play_button.disabled, "identical ranks remain separately selectable")
	await click(find_card(0))
	check(table.selected_cards == [1], "click selected card deselects only that physical card")
	await click(table.clear_button)
	check(table.selected_cards.is_empty(), "clear button resets selection")
	await touch_at(find_card(48).global_position + Vector2(20, 84))
	check(table.selected_cards == [48] and actions.is_empty(), "touch with paired mouse event selects exactly once")
	await touch_at(find_card(49).global_position + Vector2(20, 84))
	check(table.selected_cards.size() == 2, "touch can add a second physical card")
	await touch_at(find_card(48).global_position + Vector2(20, 84))
	check(table.selected_cards == [49], "touching selected card removes only that card")
	await touch_at(Vector2(800, 494))
	check(table.selected_cards.is_empty(), "blank touch clears selected cards")
	table.set_hint([52, 53])
	check(table.selected_cards.size() == 2 and actions.is_empty(), "hint selects the rocket without submitting")
	check(not table.play_button.disabled, "rocket is playable")
	await capture("ddz-selected-rocket")
	await click(table.play_button)
	check(actions.size() == 1 and actions[0].type == "play" and actions[0].revision == 10, "play submits current revision once")
	table._send_play()
	check(actions.size() == 1 and table.play_button.disabled, "duplicate submission is blocked until a newer view")
	table.set_view(state)
	check(table.play_button.disabled, "same revision refresh cannot unlock duplicate submission")
	table.action_rejected("操作已失效")
	check(not table.play_button.disabled, "rejection unlocks the pending action")
	state.revision += 1; state.target = Rules.classify([4]); state.target_seat = 1
	state.last_actions[1] = {"type": "play", "cards": [4], "combo": state.target}
	table.set_view(state)
	check(table.selected_cards.is_empty(), "new revision clears old selection")
	table.set_hint([0])
	check(table.play_button.disabled and "压不过" in table.selection_label.text, "lower card has explanatory disabled state")
	table.set_hint([0, 8])
	check(table.play_button.disabled and "不能一起出" in table.selection_label.text, "invalid combination has explanatory disabled state")
	check(not table.pass_button.disabled, "follower may pass")
	await click(table.pass_button)
	check(actions.size() == 2 and actions.back().type == "pass", "pass submits once")
	state.revision += 1; state.turn = 2
	table.set_view(state)
	check(table.play_button.disabled and table.pass_button.disabled and table.hint_button.disabled, "opponent turn disables actions")
	table._toggle_card(48)
	check(table.selected_cards.is_empty(), "opponent turn cannot change selection")
	state = fixture("bidding", 20); state.landlord = -1; state.bottom = []; state.highest_bid = 1
	state.bids = [-1, 1, -1]; state.hand = state.hand.slice(0, 17); state.hand_counts = [17, 17, 17]
	table.set_view(state)
	check(table.bid_buttons.size() == 4, "four bidding choices exist")
	check(not table.bid_buttons[0].disabled and table.bid_buttons[1].disabled and not table.bid_buttons[2].disabled, "only higher positive bids are enabled")
	check(table.target_cards.is_empty(), "no previous trick during bidding")
	await capture("ddz-bidding")
	await click(table.bid_buttons[2])
	check(actions.size() == 3 and actions.back().value == 2, "bid uses the selected value")
	state = fixture("playing", 21)
	state.target = Rules.classify([0, 1, 2, 4, 5, 6, 8, 9, 10, 12, 13, 14, 20, 24, 28, 32])
	state.target_seat = 1
	state.last_actions[1] = {"type": "play", "cards": state.target.cards, "combo": state.target}
	table.set_view(state)
	check(table.target_cards.size() == 16, "long target displays every physical card")
	for card in table.target_cards:
		check(TableScript.TARGET_RECT.encloses(card.get_rect()), "target card remains inside the central reserved area")
	check(is_instance_valid(find_button(table, "查看上手 · 16 张")), "long opponent play offers full inspection instead of illegible overlap")
	await capture("ddz-long-target")
	await click(find_button(table, "查看上手 · 16 张"))
	check(table._paused and table._modal_kind == "inspect", "inspecting last play pauses bots")
	await capture("ddz-inspect")
	table.pause_menu()
	check(not table._paused and table._modal_kind.is_empty(), "back closes inspection")
	table.pause_menu()
	check(table._paused and table._modal_kind == "pause", "pause menu freezes actions")
	table.ensure_paused()
	check(table._paused and table._modal_kind == "pause", "background pause cannot toggle the game back on")
	table.show_rules()
	check(table._paused and table._modal_kind == "rules", "rules remain paused")
	await capture("ddz-rules")
	table.pause_menu()
	check(table._paused and table._modal_kind == "pause", "back from rules returns to pause")
	table.pause_menu()
	check(not table._paused, "back from pause resumes")
	state = fixture("finished", 30)
	state.turn = -1; state.multiplier = 8; state.bomb_count = 2
	state.hand = []; state.hand_counts = [0, 5, 4]
	state.target = Rules.classify([52, 53]); state.target_seat = 0
	state.last_actions[0] = {"type": "play", "cards": [52, 53], "combo": state.target}
	state.result = {"winner": 0, "landlord_won": true, "base": 3, "multiplier": 8, "spring": "spring", "scores": [48, -24, -24]}
	table.set_view(state)
	check(table._modal_kind == "result" and table._paused, "finished game opens the result")
	check(is_instance_valid(find_button(table, "再来一局")), "result has unlimited continuation")
	await capture("ddz-result")
	await click(find_button(table, "查看牌桌"))
	check(table._modal_kind.is_empty() and table._result_hidden and table.target_cards.size() == 2, "result can be hidden to inspect the final play")
	check(is_instance_valid(find_button(table, "本局分数")), "final table retains a result entry and continuation")
	await capture("ddz-final-table")
	await click(find_button(table, "本局分数"))
	check(table._modal_kind == "result", "result can be reopened without altering the game")
	await click(find_button(table, "再来一局"))
	check(nexts == 1, "continue emits one new-round request")
	state = fixture("bidding", 0); state.landlord = -1; state.bottom = []; state.highest_bid = 0; state.bids = [-1, -1, -1]
	table.set_view(state)
	check(not table._paused and table.selected_cards.is_empty(), "new round resets pause and card selection")
	table.pause_menu()
	await click(find_button(table, "退出本局"))
	check(table._paused and table._modal_kind == "exit", "exit asks within the game before dropping the round")
	await click(find_button(table, "退出到大厅"))
	check(exits == 1, "confirmed exit emits once")
	table.queue_free(); surface.queue_free()
	await frames(3)
	print("DDZ_UI_RESULT: ", failures.size(), " failures; ", assertions, " assertions")
	quit(0 if failures.is_empty() else 1)
