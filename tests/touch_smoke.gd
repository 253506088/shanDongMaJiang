extends "res://tests/ui_smoke.gd"
var engine: GameEngine

func _fixture() -> void:
	engine=GameEngine.new();engine.start({},481)
	var p=engine.state.players[0]
	# Four completed runs and a single five bamboo; discarding East can declare.
	p.hand=[0,1,2,3,4,5,9,10,11,18,19,20,22,27]
	p.melds=[];p.bao=false;p.ming=false;p.drawn=13
	engine._turn_options()
	app.session.engine=engine;app.session.paused=false;app.last_revision=-1
	app.suppress_click_until=-1;app.touch_index=-1
	app._changed(engine.view(0));await pause_frames()
	check(engine.state.pending.any(func(a):return a.kind=="bao" and a.index==13),"touch fixture has a real East declaration option")

func _hand_tile(index: int) -> Control:
	for child in app.hand_layer.get_children():
		if child is TextureButton and not child.is_queued_for_deletion() and child.get_meta("hand_index")==index:return child
	return null

func _touch_at(position: Vector2) -> void:
	var motion=InputEventMouseMotion.new();motion.position=position;root.push_input(motion,true)
	for pressed in [true,false]:
		var touch=InputEventScreenTouch.new();touch.position=position;touch.index=0;touch.pressed=pressed
		root.push_input(touch,true)
		# Viewport.push_input bypasses Input's mouse-from-touch emulation. Supply
		# the paired mouse event used by this project's real touch controls.
		var mouse=InputEventMouseButton.new();mouse.position=position;mouse.button_index=MOUSE_BUTTON_LEFT;mouse.pressed=pressed
		mouse.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(mouse,true);await pause_frames(2)

func _touch_control(control: Control) -> void:
	check(is_instance_valid(control),"touch target exists")
	if is_instance_valid(control):await _touch_at(control.get_global_rect().get_center())

func run() -> void:
	create_timer(60).timeout.connect(func():printerr("TOUCH UI watchdog timeout");quit(1))
	app=load("res://scenes/main.tscn").instantiate();app.qa_mode=true;root.add_child(app)
	app.session.storage_root="user://qa-touch/";app.muted=true;app.session.set_process(false)
	app._build_hud()
	await _fixture()
	await _touch_control(_hand_tile(13))
	check(app.selected==13 and engine.state.revision==0,"first touch selects East without discarding")
	await _touch_control(find_button(app.root,"打出 东"))
	check(engine.state.revision==1 and engine.state.players[0].discards.has(27),"touching the selected discard action plays East exactly once")
	await _fixture()
	await _touch_control(find_button(app.root,"报听"))
	check(app.declare_mode=="bao","touching declare enters the discard-selection mode")
	await _touch_control(find_button(app.root,"取消报听"))
	check(app.declare_mode.is_empty() and engine.state.revision==0,"touching cancel declaration exits without re-entering or playing")
	await _fixture()
	await _touch_control(_hand_tile(13))
	await _touch_at(Vector2(800,600))
	check(app.selected==-1 and engine.state.revision==0,"touching table space cancels the selected tile")
	# Keep this inside the original 360 ms double-tap interval: deselection
	# must break that gesture even when the user immediately reselects the tile.
	app.last_tap_ms=Time.get_ticks_msec()
	await _touch_control(_hand_tile(13))
	check(app.selected==13 and engine.state.revision==0,"reselecting East after a blank tap does not accidentally discard")
	print("TOUCH_UI_RESULT: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
