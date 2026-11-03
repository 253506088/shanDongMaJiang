extends SceneTree
var app: Node
var failures: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); printerr("UI FAIL: ",message)

func pause_frames(count: int = 3) -> void:
	for i in range(count): await process_frame

func find_button(node: Node, text: String) -> BaseButton:
	if node is Button and node.text==text and node.is_visible_in_tree(): return node
	for child in node.get_children():
		var found=find_button(child,text)
		if found:return found
	return null

func click_control(control: Control) -> void:
	check(is_instance_valid(control),"click target exists")
	if not is_instance_valid(control):return
	var position=control.get_global_rect().get_center()
	var motion=InputEventMouseMotion.new();motion.position=position;root.push_input(motion,true)
	await pause_frames(2)
	for pressed in [true,false]:
		var event=InputEventMouseButton.new();event.position=position;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
		event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event,true);await pause_frames(2)

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/"+name+".png")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tmp"))
	create_timer(240).timeout.connect(func():printerr("UI watchdog timeout");quit(1))
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	app.session.storage_root="user://qa/"
	app.muted=true
	app.config={"jiang":"258","chi":true,"ai":"efficiency","rounds":4}
	app._show_lobby()
	await pause_frames(20)
	await capture("qa-lobby")
	await click_control(find_button(app.root,"入 座 开 局   →"))
	await pause_frames()
	var confirm=find_button(app.root,"开始新牌局")
	if confirm:await click_control(confirm)
	await pause_frames(25)
	check(app.current_screen=="table","new game opens table")
	if app.current_screen!="table":await capture("qa-failed");quit(1);return
	check(app.view.players[0].hand.size()==14,"initial dealer has 14 tiles")
	await capture("qa-table")
	var card: Control
	for child in app.hand_layer.get_children():
		if child is TextureButton:card=child;break
	await click_control(card)
	check(app.session.engine.state.revision==1,"Lotus desktop single click submits one discard")
	await click_control(find_button(app.root,"暂停  II"))
	check(app.session.paused,"pause suspends game")
	var revision=app.session.engine.state.revision
	await create_timer(1.2).timeout
	check(app.session.engine.state.revision==revision,"pause does not advance AI")
	await capture("qa-pause")
	await click_control(find_button(app.root,"保存并返回大厅"))
	check(app.current_screen=="lobby","return to lobby")
	await click_control(find_button(app.root,"继续上次牌局"))
	check(app.current_screen=="table","resume opens table")
	check(app.session.engine.state.revision==revision,"resume retains revision")
	await click_control(find_button(app.root,"玩法"))
	check(is_instance_valid(app.modal),"rules panel opens")
	await capture("qa-rules")
	await click_control(find_button(app.root,"×"))
	await click_control(find_button(app.root,"交给 AI"))
	check(app.session.autopilot,"autopilot toggle works")
	app.session.speed=25
	var deadline=Time.get_ticks_msec()+180000
	while app.session.engine.state.phase!="settled" and Time.get_ticks_msec()<deadline:await process_frame
	check(app.session.engine.state.phase=="settled","autopilot completes real game")
	await create_timer(1.7).timeout
	await pause_frames(10)
	await capture("qa-settlement")
	var previous_round=app.session.engine.state.round
	await click_control(find_button(app.root,"继续下一局 →"))
	check(app.session.engine.state.round==previous_round+1,"next round rotates")
	check(app.session.engine.state.dealer==1,"dealer rotates")
	print("UI_RESULT: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
