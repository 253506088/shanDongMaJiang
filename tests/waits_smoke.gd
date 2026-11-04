extends "res://tests/touch_smoke.gd"

func _click_at(position: Vector2) -> void:
	var motion=InputEventMouseMotion.new();motion.position=position;root.push_input(motion,true)
	await pause_frames(2)
	for pressed in [true,false]:
		var event=InputEventMouseButton.new();event.position=position;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
		event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event,true);await pause_frames(2)

func _wheel_at(position: Vector2, steps: int) -> void:
	var motion=InputEventMouseMotion.new();motion.position=position;root.push_input(motion,true)
	for step in range(steps):
		for pressed in [true,false]:
			var event=InputEventMouseButton.new();event.position=position;event.button_index=MOUSE_BUTTON_WHEEL_DOWN;event.pressed=pressed
			root.push_input(event,true)
		await pause_frames(2)

func _has_text(node: Node, text: String) -> bool:
	if node is Label and node.text==text:return true
	for child in node.get_children():
		if _has_text(child,text):return true
	return false

func _wait_faces() -> Array:
	if not is_instance_valid(app.waits_panel):return []
	var body=app.waits_panel.get_node("WaitsScroll").get_child(0)
	return body.get_children().filter(func(node):return node is TextureRect and node.has_meta("wait_tile"))

func _publish() -> void:
	engine.state.revision+=1
	app._changed(engine.view(0))
	await pause_frames(5)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tmp"))
	create_timer(90).timeout.connect(func():printerr("WAITS UI watchdog timeout");quit(1))
	app=load("res://scenes/main.tscn").instantiate();app.qa_mode=true;root.add_child(app)
	app.session.storage_root="user://qa-waits/";app.muted=true;app.session.set_process(false)
	app._build_hud()
	await _fixture()
	await click_control(find_button(app.root,"听牌一览"))
	check(is_instance_valid(app.modal) and app.session.paused,"unlocked waits opens a paused modal")
	if not is_instance_valid(app.modal):quit(1);return
	await _click_at(app.modal.global_position+Vector2(65,65))
	check(is_instance_valid(app.modal),"clicking inside waits modal keeps it open")
	await capture("waits-normal")
	var tile_rect=_hand_tile(0).get_global_rect()
	var outside=Vector2(tile_rect.get_center().x,tile_rect.end.y-4)
	check(not app.modal.get_global_rect().has_point(outside),"discardable tile is outside waits modal")
	await _click_at(outside)
	check(not is_instance_valid(app.modal) and not app.session.paused,"mouse release outside closes waits modal")
	check(engine.state.revision==0 and app.selected==-1,"outside mouse click does not select or discard underlying tile")
	await pause_frames(8)
	check(engine.state.revision==0,"closing mouse release does not queue a later discard")
	await _fixture()
	await _touch_control(find_button(app.root,"听牌一览"))
	check(is_instance_valid(app.modal),"touch opens unlocked waits modal")
	if not is_instance_valid(app.modal):quit(1);return
	await _touch_at(app.modal.global_position+Vector2(65,65))
	check(is_instance_valid(app.modal),"touching inside waits modal keeps it open")
	tile_rect=_hand_tile(0).get_global_rect()
	await _touch_at(Vector2(tile_rect.get_center().x,tile_rect.end.y-4))
	check(not is_instance_valid(app.modal) and not app.session.paused,"touch release outside closes waits modal")
	check(engine.state.revision==0 and app.selected==-1,"outside touch and its emulated mouse do not play underlying tile")

	engine=load("res://tests/ux_regressions.gd").screenshot_engine()
	for seat in range(1,4):
		engine.state.players[seat].discards=[];engine.state.players[seat].melds=[]
	app.session.engine=engine;app.last_revision=-1;app._changed(engine.view(0));await pause_frames(6)
	check(is_instance_valid(app.waits_panel) and app.waits_panel.visible,"declared ready hand automatically shows permanent waits")
	check(not is_instance_valid(app.modal) and not app.session.paused,"permanent waits does not open a modal or pause play")
	var entries: Array=app._locked_waits()
	check(entries.size()==1 and entries[0].tile==16,"locked screenshot hand waits only for eight dots")
	check(_has_text(app.waits_panel,"八筒") and _has_text(app.waits_panel,"未见3张"),"permanent panel renders tile name and publicly unseen count")
	var first_fan=int(entries[0].fan)
	await create_timer(2).timeout
	await capture("waits-locked")
	await click_control(find_button(app.root,"收起听牌"))
	check(not is_instance_valid(app.waits_panel) and not app.session.paused,"permanent waits can fold without pausing")
	await _publish()
	check(not is_instance_valid(app.waits_panel),"folded preference survives a state update")
	await click_control(find_button(app.root,"听牌一览"))
	check(is_instance_valid(app.waits_panel) and not is_instance_valid(app.modal) and not app.session.paused,"ready waits button reopens the permanent panel")
	await _publish()
	check(is_instance_valid(app.waits_panel),"expanded permanent waits survives a state update")
	var p=engine.state.players[0]
	p.hand.remove_at(p.drawn);p.drawn=-1
	engine.state.current=1;engine.state.pending=[]
	await _publish()
	check(app._locked_waits().map(func(item):return item.tile)==[16],"waiting through an opponent turn keeps the same locked waits")
	p.hand.insert(0,27);p.drawn=0;engine.state.current=0;engine._turn_options()
	await _publish()
	check(app._locked_waits().map(func(item):return item.tile)==[16],"newly drawn tile at index zero is excluded from locked waits")
	check(is_instance_valid(app.waits_panel) and not app.session.paused,"new draw keeps permanent waits open and play active")
	engine.state.players[1].hand=[16,16,16]
	await _publish()
	check(app._locked_waits()[0].remaining==3,"opponent concealed tiles do not leak into unseen count")
	engine.state.players[1].discards=[16]
	await _publish()
	check(app._locked_waits()[0].remaining==2 and _has_text(app.waits_panel,"未见2张"),"public discard reduces displayed unseen count")
	engine.state.players[2].ming=true;engine.state.players[2].hand=[16]
	await _publish()
	check(app._locked_waits()[0].remaining==1,"opponent revealed hand reduces unseen count")
	engine.state.players[3].discards=[16]
	p.ming=true
	await _publish()
	check(app._locked_waits()[0].remaining==0 and _has_text(app.waits_panel,"未见0张"),"exhausted wait remains listed with zero unseen copies")
	check(app._locked_waits()[0].fan==first_fan*2 and _has_text(app.waits_panel,"%d番"%(first_fan*2)),"ming declaration refreshes displayed fan multiplier")
	var faces=_wait_faces()
	check(faces.size()==1 and is_equal_approx(faces[0].modulate.a,0.45),"exhausted wait face is visibly subdued")
	await capture("waits-exhausted")

	# Thirteen unique terminals/honors wait on all thirteen and exceed the side panel.
	p.hand=[0,8,9,17,18,26,27,28,29,30,31,32,33];p.drawn=-1;p.melds=[];p.bao=true;p.ming=false
	for seat in range(1,4):
		engine.state.players[seat].discards=[];engine.state.players[seat].melds=[];engine.state.players[seat].ming=false
	engine.state.current=1;engine.state.pending=[];engine.state.gang_head=1
	await _publish()
	check(app._locked_waits().size()==13 and _wait_faces().size()==13,"all thirteen orphan waits are present without truncation")
	var scroll: ScrollContainer=app.waits_panel.get_node("WaitsScroll")
	check(scroll.get_v_scroll_bar().visible,"many waits expose a vertical scrollbar")
	await capture("waits-multi")
	await _wheel_at(scroll.get_global_rect().get_center(),5)
	check(scroll.scroll_vertical>0,"mouse wheel scrolls through permanent waits")
	var old_scroll=scroll.scroll_vertical
	await _publish()
	scroll=app.waits_panel.get_node("WaitsScroll")
	check(scroll.scroll_vertical==old_scroll,"state refresh preserves permanent wait scroll position")
	await capture("waits-multi-scrolled")
	engine.start({},482,2)
	await _publish()
	check(not is_instance_valid(app.waits_panel) and app.waits_expanded,"next round clears old waits and resets folded preference")
	check(find_button(app.root,"听牌一览")!=null,"next round restores the ordinary waits button")
	print("WAITS_UI_RESULT: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
