extends "res://tests/ui_smoke.gd"

func run() -> void:
	create_timer(180).timeout.connect(func():printerr("ART UI watchdog");quit(1))
	app=load("res://scenes/main.tscn").instantiate();app.qa_mode=true;root.add_child(app)
	app.session.storage_root="user://qa-art/";app.muted=true;app.session.set_process(false)
	app._build_hud();app.table.quality("--low-quality" in OS.get_cmdline_user_args())
	var e=GameEngine.new();e.start({},93000)
	app.session.engine=e;app.session.paused=false;app._changed(e.view(0))
	await create_timer(1.05).timeout
	for die in app.table.dice_nodes:
		check(die.visible,"fresh opening rolls visible dice")
		var bounds=die.global_transform*AABB(Vector3.ONE*-0.215,Vector3.ONE*0.43)
		check(absf(bounds.position.y-TableLayout.SURFACE_Y)<0.02,"dice settle on the cloth")
		check(not bounds.intersects(AABB(Vector3(-1.1,0,-1.1),Vector3(2.2,2,2.2))),"dice never obscure the central dial")
		for key in app.table.pieces:
			check(not bounds.intersects(app.table.tile_bounds(key)),"opening dice clear tiles: "+key)
	await capture("art-dice")
	await create_timer(1.05).timeout
	check(app.table.dice_nodes.all(func(die):return not die.visible),"dice clear after the opening beat")
	check(rad_to_deg(-app.table.camera.rotation.x)>52,"camera provides high tabletop view")
	check(app.table.camera.projection==Camera3D.PROJECTION_PERSPECTIVE,"table uses perspective")
	_verify_tile_geometry()
	_verify_wall(e)
	_verify_flower_lanes()
	for seat in range(1,4):
		var piece=app.table.pieces["h%d-0"%seat]
		check(piece.get_meta("pose")=="standing","concealed opponent hand stands %d"%seat)
		check(piece.get_meta("tile")==-1,"standing hand does not disclose private face")
		var bounds=app.table.tile_bounds("h%d-0"%seat)
		check(bounds.size.y>0.70 and absf(bounds.position.y-TableLayout.SURFACE_Y)<0.02,"standing tile rests on its short edge")
	await capture("art-opening")
	# Real deterministic midgame; no fabricated wall or duplicated tile display.
	var bot=MahjongAI.new()
	for i in range(35):
		if e.state.phase=="settled":break
		var seat=e.decision_seat();var move=bot.choose(e.view(seat),seat,0.8)
		e.submit(seat,e.state.revision,move.id)
	app._changed(e.view(0));await create_timer(1.5).timeout
	_verify_wall(e)
	_verify_clearance()
	await capture("art-midgame")
	app.table.last_round=-1
	app.table.update_view(e.view(0))
	check(app.table.dice_time==0 and app.table.dice_nodes.all(func(die):return not die.visible),"resuming midgame never rolls over existing rivers")
	if "--preview" in OS.get_cmdline_user_args(): quit();return
	var tail=int(e.state.wall_slots.back());var tail_key="w%d"%tail
	var point=app.table.camera.unproject_position(app.table.pieces[tail_key].global_position+Vector3(0,0.18,0))
	for pressed in [true,false]:
		var input=InputEventMouseButton.new();input.position=point;input.button_index=MOUSE_BUTTON_LEFT;input.pressed=pressed
		root.push_input(input,true);await pause_frames(2)
	check(app.inspect_layer.get_child_count()>0,"wall kong head can be inspected")
	app._clear(app.inspect_layer)
	# Exercise every successive tail layer, including a sole upper tile dropping.
	var wall_before=e.state.wall_slots.duplicate()
	e._draw(0,"normal")
	check(e.state.wall_slots.back()==wall_before.back(),"ordinary draw does not move the kong head")
	for i in range(5):
		var previous=e.state.wall_slots.back()
		e._draw(0,"kong")
		check(previous not in e.state.wall_slots,"kong removes that exact physical tail")
		app._changed(e.view(0));await pause_frames(3)
		_verify_wall(e)
	await capture("art-kong-tail")
	# The existing bug fixture still fits the taller bodies and new camera.
	e=load("res://tests/ux_regressions.gd").screenshot_engine();app.session.engine=e
	app._changed(e.view(0));await create_timer(0.6).timeout
	await click_control(find_button(app.root,"补杠 四万"));await create_timer(0.5).timeout
	_verify_wall(e);_verify_clearance();await capture("art-added-kong")
	# Continue another legal game to settlement and verify public hand presentation.
	e.start({},93000)
	for i in range(200):
		if e.state.phase=="settled": break
		var seat=e.decision_seat();e.submit(seat,e.state.revision,bot.choose(e.view(seat),seat,0.8).id)
	check(e.state.phase=="settled","real match reaches settlement")
	app._changed(e.view(0));await create_timer(1.8).timeout;app._close_modal();await pause_frames(5)
	_verify_wall(e);_verify_clearance();await capture("art-settled")
	print("ART_UI_RESULT: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)

func _verify_wall(e: GameEngine) -> void:
	var state=e.state
	var slots: Array=state.wall_slots
	check(slots.size()==state.wall.size(),"rendered wall has the actual remaining count")
	var visible=0
	for key in app.table.pieces:
		if key.begins_with("w") and app.table.pieces[key].get_meta("tile")>=0: visible+=1
	check(visible==1 if not slots.is_empty() else visible==0,"only the actual tail is face up")
	if slots.is_empty():return
	var tail=int(slots.back())
	var piece=app.table.pieces["w%d"%tail]
	check(piece.get_meta("tile")==state.gang_head and piece.get_meta("pose")=="face","physical tail matches public head")
	if tail%2==1: check(tail-1 not in slots,"head is never obscured by an upper tile")
	for slot in slots:
		var pos=TableLayout.wall(slot,slots)
		if slot%2==0 and slot+1 not in slots: check(absf(pos.y-TableLayout.TILE_Y)<0.001,"unsupported upper tile settles to felt")

func _verify_clearance() -> void:
	var keys=app.table.pieces.keys()
	for i in range(keys.size()):
		var a=app.table.tile_bounds(keys[i])
		for j in range(i+1,keys.size()):
			check(not a.intersects(app.table.tile_bounds(keys[j])),"tile clearance "+keys[i]+" / "+keys[j])

func _verify_flower_lanes() -> void:
	# Eight flowers are possible on one seat. Their physical corners must fit
	# the cloth and their projected near-edge lane must clear the player's hand.
	var hand_top=INF
	for child in app.hand_layer.get_children():
		if child is TextureButton: hand_top=minf(hand_top,child.position.y)
	for seat in range(4):
		var boxes: Array=[]
		for index in range(8):
			var size=TableLayout.TILE*0.65
			if seat%2: size=Vector3(size.z,size.y,size.x)
			var bounds=AABB(TableLayout.flower(seat,index)-size/2,size)
			check(absf(bounds.position.x)<8.02 and bounds.end.x<8.02 and absf(bounds.position.z)<7.35 and bounds.end.z<7.35,"all flowers fit cloth %d/%d"%[seat,index])
			for previous in boxes: check(not bounds.intersects(previous),"flower lane does not overlap")
			boxes.append(bounds)
			for corner in range(8):
				if seat in [0,3]: check(app.table.camera.unproject_position(bounds.get_endpoint(corner)).y<hand_top-2,"near flowers clear screen-space hand")
			for other in range(4):
				var meld_size=TableLayout.TILE
				if other%2: meld_size=Vector3(meld_size.z,meld_size.y,meld_size.x)
				check(not bounds.intersects(AABB(TableLayout.meld(other,0)-meld_size/2,meld_size)),"flower lane clears neighbour's first meld")

func _verify_tile_geometry() -> void:
	# Godot culls counterclockwise exterior triangles. Opposite winding makes
	# even correct smooth normals show the inside of a tile instead of its cap.
	for mesh in [app.table.cap_mesh,app.table.base_mesh]:
		var arrays=mesh.surface_get_arrays(0)
		var vertices=arrays[Mesh.ARRAY_VERTEX];var normals=arrays[Mesh.ARRAY_NORMAL];var indices=arrays[Mesh.ARRAY_INDEX]
		var reversed_faces=0
		for triangle in range(0,indices.size(),3):
			var a=indices[triangle];var b=indices[triangle+1];var c=indices[triangle+2]
			var cross=(vertices[b]-vertices[a]).cross(vertices[c]-vertices[a])
			if cross.dot(normals[a]+normals[b]+normals[c])>0.000001: reversed_faces+=1
		check(reversed_faces==0,"rounded tile exterior has Godot clockwise winding")
