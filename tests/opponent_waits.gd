extends "res://tests/ui_smoke.gd"

var engine: GameEngine
const ORPHANS=[0,8,9,17,18,26,27,28,29,30,31,32,33]

func _publish() -> void:
	engine.state.revision+=1;app._changed(engine.view(0));await pause_frames(4)

func _tiles(seat: int) -> Array:
	return app._opponent_waits(seat).map(func(entry):return entry.tile)

func _has_text(node: Node, expected: String) -> bool:
	if node is Label and node.text==expected:return true
	for child in node.get_children():
		if _has_text(child,expected):return true
	return false

func _verify_clearance() -> void:
	var rectangles: Array=[]
	for panel in app.opponent_waits_panels.values():
		var rect=panel.get_global_rect()
		check(Rect2(0,0,1600,900).encloses(rect),"opponent wait card fits the canvas")
		for previous in rectangles:check(not rect.intersects(previous),"three wait cards do not overlap")
		rectangles.append(rect)
		for info in app.players_ui:check(not rect.intersects(info.panel.get_global_rect()),"wait card clears every portrait")
		for button in [app.public_tiles_button,app.waits_button,app.hint_button,app.auto_button]:
			check(not rect.intersects(button.get_global_rect()),"wait card clears action controls")
		if is_instance_valid(app.waits_panel):check(not rect.intersects(app.waits_panel.get_global_rect()),"opponent waits clear the local locked waits")
		var covers_tile=false
		for key in app.table.pieces:
			var bounds=app.table.tile_bounds(key)
			var tile_rect=Rect2(app.table.camera.unproject_position(bounds.get_endpoint(0)),Vector2.ZERO)
			for corner in range(1,8):tile_rect=tile_rect.expand(app.table.camera.unproject_position(bounds.get_endpoint(corner)))
			if rect.intersects(tile_rect):covers_tile=true;break
		check(not covers_tile,"opponent wait card clears projected physical tiles")

func _capture_if_rendered(name: String) -> void:
	if DisplayServer.get_name()!="headless":await capture(name)

func run() -> void:
	create_timer(60).timeout.connect(func():printerr("OPPONENT WAITS watchdog");quit(1))
	app=load("res://scenes/main.tscn").instantiate();app.qa_mode=true;root.add_child(app)
	app.session.storage_root="user://qa-opponent-waits/";app.muted=true;app.session.set_process(false)
	app._build_hud()
	engine=load("res://tests/ux_regressions.gd").screenshot_engine()
	engine.state.current=1;engine.state.pending=[]
	for seat in range(1,4):
		var p=engine.state.players[seat]
		p.hand=[0,1,2,9,10,11,18,19,20,13,13,26+seat,26+seat]
		p.melds=[];p.discards=[];p.drawn=-1;p.ming=true;p.bao=true
	app.session.engine=engine;app.session.paused=false;app.last_revision=-1
	await _publish()
	check(app.opponent_waits_panels.size()==3,"all three ming opponents display persistent waits")
	check(not app.session.paused and not is_instance_valid(app.modal),"opponent waits do not pause play or open a modal")
	for seat in range(1,4):
		check(_tiles(seat)==[26+seat],"declared opponent has the correct stable wait: %d"%seat)
		check(app._opponent_waits(seat)[0].remaining==2,"unseen count includes the target player's exposed pair")
		check(_has_text(app.opponent_waits_panels[seat],"未见2张"),"card displays the known-information count")
	_verify_clearance()
	await _capture_if_rendered("opponent-waits-three")
	var first_panel=app.opponent_waits_panels[1]
	await _publish()
	check(app.opponent_waits_panels[1]==first_panel,"unchanged waits reuse the panel during another turn")
	var p=engine.state.players[1]
	p.hand.insert(0,33);p.drawn=0
	var original=p.hand.duplicate()
	await _publish()
	check(_tiles(1)==[27] and p.hand==original,"new draw at index zero is excluded without mutating the exposed hand")
	p.hand[0]=27
	await _publish()
	check(_tiles(1)==[27] and app._opponent_waits(1)[0].remaining==1,"drawn winning tile reduces unseen count without changing the wait")
	p.hand.remove_at(0);p.drawn=-1
	engine.state.players[2].ming=false;engine.state.players[2].hand=[27,27]
	await _publish()
	check(not app.opponent_waits_panels.has(2) and app._opponent_waits(2).is_empty(),"bao-only opponent never reveals a wait")
	check(app._opponent_waits(1)[0].remaining==2,"other concealed hand cannot affect the known-information count")
	engine.state.players[2].ming=true;engine.state.players[2].hand=[27]
	await _publish()
	check(app._opponent_waits(1)[0].remaining==1,"another ming hand counts as public knowledge")
	engine.state.players[3].discards=[27]
	await _publish()
	check(app._opponent_waits(1)[0].remaining==0 and _has_text(app.opponent_waits_panels[1],"未见0张"),"exhausted wait remains listed at zero")
	var body=app.opponent_waits_panels[1].get_node("WaitsScroll").get_child(0)
	check(body.get_child(0).modulate.a<0.5,"exhausted face is visually subdued")
	await _capture_if_rendered("opponent-waits-exhausted")
	for seat in range(1,4):
		var other=engine.state.players[seat]
		other.hand=ORPHANS.duplicate();other.melds=[];other.discards=[];other.ming=true;other.drawn=-1
	await _publish()
	for seat in range(1,4):
		check(_tiles(seat).size()==13,"all thirteen waits are retained for opponent %d"%seat)
		var scroll: ScrollContainer=app.opponent_waits_panels[seat].get_node("WaitsScroll")
		check(scroll.get_v_scroll_bar().visible,"each long list has a scrollbar")
		scroll.scroll_vertical=120
	await pause_frames(3)
	var old_scroll=app.opponent_waits_panels[1].get_node("WaitsScroll").scroll_vertical
	engine.state.players[0].hand.append(27)
	await _publish()
	check(app.opponent_waits_panels[1].get_node("WaitsScroll").scroll_vertical==old_scroll,"public count refresh preserves scroll position")
	_verify_clearance()
	await _capture_if_rendered("opponent-waits-multi")
	engine.start({},93001,2)
	await _publish()
	check(app.opponent_waits_panels.is_empty() and app.opponent_waits_cache.is_empty(),"new round removes all opponent cards and cached hands")
	check(app.public_tiles_button.position.y==500,"new round restores the public-tiles button")
	print("OPPONENT_WAITS_UI_RESULT: ",failures.size()," failures")
	app.queue_free();await pause_frames(2)
	quit(0 if failures.is_empty() else 1)
