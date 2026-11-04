extends "res://tests/ui_smoke.gd"

func run() -> void:
	create_timer(120).timeout.connect(func():printerr("UX UI watchdog");quit(1))
	app=load("res://scenes/main.tscn").instantiate();app.qa_mode=true;root.add_child(app)
	app.session.storage_root="user://qa-ux/";app.muted=true;app.session.set_process(false)
	app._build_hud()
	var e=load("res://tests/ux_regressions.gd").screenshot_engine()
	app.session.engine=e;app.session.paused=false;app._changed(e.view(0))
	await create_timer(2).timeout
	check(find_button(app.root,"补杠 四万")!=null,"screenshot Four Characters kong button visible")
	await capture("ux-four-wan-before")
	check(is_instance_valid(app.waits_panel) and not is_instance_valid(app.modal),"locked waits remain on table without a modal")
	await capture("ux-locked-waits")
	await click_control(find_button(app.root,"收起听牌"))
	await click_control(find_button(app.root,"听牌一览"))
	check(not app.session.paused,"locked waits do not pause the game")
	await click_control(find_button(app.root,"补杠 四万"))
	check(e.state.players[0].melds[1].tiles.size()==4,"kong button commits physical fourth tile")
	await create_timer(0.5).timeout
	await capture("ux-four-wan-after")
	# Pending pung shows actor, readable face and target-labelled button.
	e.start({},481);var p=e.state.players[0]
	p.hand=[0,2,3,3,6,8,9,11,13,18,20,23,25];p.melds=[];p.bao=false;p.drawn=-1
	e.state.players[3].discards=[3];e.state.revision+=1;e._begin_claims(3,3)
	app._changed(e.view(0));await pause_frames(8)
	check(app.last_tile_label.text=="四万","pending target face caption")
	check("知秋" in app.last_actor_label.text,"pending source actor")
	check(find_button(app.root,"碰 四万")!=null,"target-labelled pung button")
	await create_timer(1.4).timeout;await capture("ux-claim")
	var position=app.table.camera.unproject_position(app.table.pieces["d3-0"].global_position+Vector3(0,0.12,0))
	for pressed in [true,false]:
		var event=InputEventMouseButton.new();event.position=position;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
		root.push_input(event,true);await pause_frames(2)
	check(app.inspect_layer.get_child_count()>0,"clicking a real 3D discard opens face inspection")
	app._clear(app.inspect_layer);await pause_frames(2)
	await click_control(find_button(app.root,"碰 四万"))
	check(p.melds[0].type=="peng" and p.melds[0].tile==3,"pung button claims correct tile")
	# Three chi options must remain a visual choice, not cramped long button labels.
	e.start({},481);p=e.state.players[0]
	p.hand=[1,2,4,5,7,9,11,13,18,20,23,25,27];p.melds=[];p.drawn=-1
	e.state.players[3].discards=[3];e.state.revision+=3;e._begin_claims(3,3)
	app._changed(e.view(0));await pause_frames(5)
	await click_control(find_button(app.root,"吃牌组合"))
	check(is_instance_valid(app.modal) and app.session.paused,"chi picker pauses and shows choices")
	await capture("ux-chi-picker")
	await click_control(find_button(app.root,"吃这组"))
	check(p.melds[0].tiles==[1,2,3],"visual chi choice resolves selected sequence")
	await click_control(find_button(app.root,"听牌一览"))
	check(app.session.paused,"waits panel pauses game")
	await capture("ux-waits")
	await click_control(find_button(app.root,"×"))
	await click_control(find_button(app.root,"查看桌面牌"))
	await capture("ux-public-tiles")
	await click_control(find_button(app.root,"×"))
	# Four seats, long discard rivers and all meld types exercise rendering clearances.
	e=load("res://tests/ux_regressions.gd").screenshot_engine();app.session.engine=e
	for player in e.state.players:
		player.discards=range(24)
		if player.seat!=0:
			player.hand=[1,2,4,5];player.melds=[{"type":"peng","tile":27,"tiles":[27,27,27],"from":(player.seat+1)%4},{"type":"chi","tile":18,"tiles":[18,19,20],"from":(player.seat+3)%4},{"type":"gang","tile":8,"tiles":[8,8,8,8],"from":(player.seat+2)%4,"added":true}]
	e.state.revision=60;e.state.last_discard={"seat":3,"tile":23,"revision":60}
	app._changed(e.view(0));await create_timer(0.6).timeout
	var keys=app.table.pieces.keys()
	for i in range(keys.size()):
		var a=app.table.pieces[keys[i]]
		var bounds_a=app.table.tile_bounds(keys[i])
		for j in range(i+1,keys.size()):
			var b=app.table.pieces[keys[j]]
			var bounds_b=app.table.tile_bounds(keys[j])
			check(not bounds_a.intersects(bounds_b),"rendered tile clearance "+keys[i]+" / "+keys[j])
	await create_timer(1.4).timeout
	await capture("ux-table-stress")
	# Every supplied voice clip is loaded and a new event is deduplicated.
	check(app.voice.clips.size()==39,"34 tile voices plus five action voices loaded")
	for tile in range(34): check(app.voice.clips[str(tile)].get_length()>0,"voice decodes %d"%tile)
	var audio_view=e.view(0);audio_view.revision=999;audio_view.event={"kind":"discard","seat":0,"tile":27}
	check(app.voice.announce(audio_view,false)>0,"East discard schedules East audio")
	check(app.voice.announce(audio_view,false)==0,"same revision does not announce twice")
	app.voice.stop_all()
	print("UX_UI_RESULT: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
