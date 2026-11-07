extends "res://tests/ui_smoke.gd"
var engine
var save_directory = ""

func _fixture() -> void:
	engine=load("res://scripts/core/game_engine.gd").new();engine.start({},481)
	var p=engine.state.players[0]
	# Four completed runs and a single five bamboo; discarding East can declare.
	p.hand=[0,1,2,3,4,5,9,10,11,18,19,20,22,27]
	p.melds=[];p.bao=false;p.ming=false;p.drawn=13
	engine._turn_options()
	app.session.engine=engine;app.session.paused=false;app.last_revision=-1
	app.suppress_click_until=-1;app.touch_index=-1;app.last_touch_ms=-1000
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

func _swipe_control(control: Control) -> void:
	check(is_instance_valid(control),"swipe target exists")
	if not is_instance_valid(control):return
	var start=control.get_global_rect().get_center()
	# End inside the original hit box so the paired mouse release can activate
	# the button too; the swipe must still produce only one accepted command.
	var finish=start+Vector2(0,-36)
	var motion=InputEventMouseMotion.new();motion.position=start;root.push_input(motion,true)
	var down=InputEventScreenTouch.new();down.position=start;down.index=0;down.pressed=true;root.push_input(down,true)
	var mouse_down=InputEventMouseButton.new();mouse_down.position=start;mouse_down.button_index=MOUSE_BUTTON_LEFT
	mouse_down.pressed=true;mouse_down.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(mouse_down,true)
	await pause_frames(2)
	var drag=InputEventScreenDrag.new();drag.position=finish;drag.relative=finish-start;drag.index=0;root.push_input(drag,true)
	motion=InputEventMouseMotion.new();motion.position=finish;motion.relative=finish-start
	motion.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(motion,true)
	var up=InputEventScreenTouch.new();up.position=finish;up.index=0;up.pressed=false;root.push_input(up,true)
	var mouse_up=InputEventMouseButton.new();mouse_up.position=finish;mouse_up.button_index=MOUSE_BUTTON_LEFT
	mouse_up.pressed=false;root.push_input(mouse_up,true)
	await pause_frames(3)

func _check_discard(tile: int, message: String) -> void:
	check(engine.state.revision==1 and engine.journal.size()==1 and engine.state.players[0].discards==[tile],message)

func _test_selection() -> void:
	await _fixture()
	var resting_y=_hand_tile(13).get_global_rect().position.y
	await _touch_control(_hand_tile(13))
	check(app.selected==13 and engine.state.revision==0,"first touch selects East without discarding")
	check(_hand_tile(13).get_global_rect().position.y<resting_y,"first touch visibly raises the selected tile")
	# This exceeds both the former 360 ms double-tap window and 500 ms touch
	# classification interval. Selection must survive until the next touch.
	await create_timer(0.6).timeout
	check(app.selected==13 and engine.state.revision==0,"selected East remains selected after a long pause")
	await _touch_control(_hand_tile(13))
	_check_discard(27,"slow second touch confirms selected East exactly once")

	await _fixture()
	await _touch_control(_hand_tile(13))
	await _touch_control(_hand_tile(13))
	_check_discard(27,"rapid two touches with paired mouse events submit exactly once")

	await _fixture()
	var first_resting_y=_hand_tile(0).get_global_rect().position.y
	var second_resting_y=_hand_tile(13).get_global_rect().position.y
	await _touch_control(_hand_tile(0))
	await _touch_control(_hand_tile(13))
	check(app.selected==13 and engine.state.revision==0,"touching another tile changes selection without discarding")
	check(is_equal_approx(_hand_tile(0).get_global_rect().position.y,first_resting_y),"previously selected tile returns to its resting position")
	check(_hand_tile(13).get_global_rect().position.y<second_resting_y,"newly selected tile rises")
	await _touch_control(_hand_tile(13))
	_check_discard(27,"touching the new selection again discards it exactly once")

	await _fixture()
	await _touch_control(_hand_tile(13))
	await _touch_control(_hand_tile(0))
	await _touch_control(_hand_tile(13))
	check(app.selected==13 and engine.state.revision==0,"returning to an earlier tile only selects it again")
	await _touch_control(_hand_tile(13))
	_check_discard(27,"reselected earlier tile needs one more touch to discard")

	await _fixture()
	await _touch_control(_hand_tile(13))
	await _touch_at(Vector2(800,600))
	check(app.selected==-1 and engine.state.revision==0,"touching table space cancels the selected tile")
	await _touch_control(_hand_tile(13))
	check(app.selected==13 and engine.state.revision==0,"reselecting East after a blank tap does not accidentally discard")
	await _touch_control(_hand_tile(13))
	_check_discard(27,"selection after a blank tap is confirmed by the following touch")

	await _fixture()
	var hint=engine.state.pending.filter(func(move):return move.kind=="discard" and move.index==13)[0]
	app._hint(hint);await pause_frames()
	check(app.selected==13 and engine.state.revision==0,"a discard hint selects East without submitting")
	await create_timer(0.6).timeout
	await _touch_control(_hand_tile(13))
	_check_discard(27,"one touch confirms the tile already selected by a hint")

	await _fixture()
	await _touch_control(_hand_tile(13))
	await _touch_control(find_button(app.root,"打出 东"))
	_check_discard(27,"touching the selected discard action plays East exactly once")

func _test_declarations() -> void:
	await _fixture()
	await _touch_control(find_button(app.root,"报听"))
	check(app.declare_mode=="bao","touching declare enters the discard-selection mode")
	await _touch_control(find_button(app.root,"取消报听"))
	check(app.declare_mode.is_empty() and engine.state.revision==0,"touching cancel declaration exits without re-entering or playing")

	await _fixture()
	await _touch_control(find_button(app.root,"报听"))
	await _touch_control(_hand_tile(13))
	check(app.selected==13 and engine.state.revision==0 and not engine.state.players[0].bao,"first declaration touch selects its discard without declaring")
	await create_timer(0.6).timeout
	await _touch_control(_hand_tile(13))
	_check_discard(27,"second declaration touch plays its legal discard exactly once")
	check(engine.state.players[0].bao and engine.journal[0].action.kind=="bao","legal second touch keeps the requested declaration")

	await _fixture()
	check(not engine.state.pending.any(func(move):return move.kind=="bao" and move.index==0),"One Character cannot be used to declare in this fixture")
	await _touch_control(find_button(app.root,"报听"))
	await _touch_control(_hand_tile(0))
	await _touch_control(_hand_tile(0))
	check(engine.state.revision==0 and not engine.state.players[0].bao and app.declare_mode=="bao","confirming an invalid declaration tile neither discards nor declares")
	await _touch_control(_hand_tile(13))
	check(app.selected==13 and engine.state.revision==0,"switching from invalid to legal declaration tile only selects it")
	await _touch_control(_hand_tile(13))
	_check_discard(27,"legal declaration remains usable after an invalid confirmation")
	check(engine.state.players[0].bao,"valid retry declares ready")

func _test_gestures_and_guards() -> void:
	await _fixture()
	await _swipe_control(_hand_tile(13))
	_check_discard(27,"upward swipe and its paired mouse release submit exactly once")

	await _fixture()
	await click_control(_hand_tile(13))
	_check_discard(27,"desktop mouse single click still discards immediately")

	await _fixture()
	await _touch_control(_hand_tile(13))
	app.session.paused=true
	await _touch_control(_hand_tile(13))
	check(engine.state.revision==0 and engine.journal.is_empty(),"touching the selection while paused cannot submit")

	await _fixture()
	await _touch_control(_hand_tile(13))
	engine.state.current=1;engine._turn_options();app._changed(engine.view(0));await pause_frames()
	await _touch_control(_hand_tile(13))
	check(engine.state.revision==0 and engine.journal.is_empty(),"touching a tile outside the local turn cannot submit")

func _finish(code: int) -> void:
	# Every invocation gets its own save directory; delete only files this test
	# can create, preserving other QA runs and all real-player preferences.
	if not save_directory.is_empty():
		for name in ["current_match.json","current_match.json.bak","current_match.json.tmp"]:
			var path=ProjectSettings.globalize_path(save_directory+name)
			if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_directory))
	if is_instance_valid(app):app.queue_free()
	app=null;engine=null
	await pause_frames(2)
	quit(code)

func run() -> void:
	create_timer(120).timeout.connect(func():printerr("TOUCH UI watchdog timeout");await _finish(1))
	app=load("res://scenes/main.tscn").instantiate();app.qa_mode=true;root.add_child(app)
	save_directory="user://qa-touch-%d-%d/"%[OS.get_process_id(),Time.get_ticks_msec()]
	app.session.storage_root=save_directory;app.muted=true;app.session.set_process(false)
	app._build_hud()
	await _test_selection()
	await _test_declarations()
	await _test_gestures_and_guards()
	print("TOUCH_UI_RESULT: ",failures.size()," failures")
	await _finish(0 if failures.is_empty() else 1)
