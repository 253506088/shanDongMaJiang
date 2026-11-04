extends "res://tests/ui_smoke.gd"

## Renderer regression: real frames and production geometry, isolated QA state.
## Timings describe this machine; draw-call counts are the portable regression.
func run() -> void:
	create_timer(120).timeout.connect(func():printerr("RENDER UI watchdog");quit(1))
	app=load("res://scenes/main.tscn").instantiate();app.qa_mode=true;root.add_child(app)
	app.session.storage_root="user://qa-render/";app.muted=true;app.session.set_process(false)
	app._build_hud();app.table.quality(false)
	var e=GameEngine.new();e.start({},93000)
	app.session.engine=e;app._changed(e.view(0))
	await create_timer(2.1).timeout
	# Routine correctness checks use a small, capped sample. More timing samples
	# require an explicit request and still retain a 60 FPS ceiling.
	var benchmark="--benchmark" in OS.get_cmdline_user_args()
	app.desktop_window.set_frame_limit(60 if benchmark else 30)
	if benchmark:DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var results={"resolution":str(DisplayServer.window_get_size()),"renderer":RenderingServer.get_video_adapter_name(),"scenes":[]}
	results.scenes.append(await _measure("opening"))
	var bot=MahjongAI.new()
	for i in range(35):
		if e.state.phase=="settled":break
		var seat=e.decision_seat();e.submit(seat,e.state.revision,bot.choose(e.view(seat),seat,0.8).id)
	app._changed(e.view(0));await create_timer(0.6).timeout
	results.scenes.append(await _measure("midgame"))
	await capture("render-midgame")
	await _verify_animation_and_reset()
	var args=OS.get_cmdline_user_args();var index=args.find("--capture-dir")
	var directory=args[index+1] if index>=0 and index+1<args.size() else "res://tmp"
	var output=FileAccess.open(directory.path_join("render-metrics.json"),FileAccess.WRITE)
	if output:output.store_string(JSON.stringify(results,"\t"))
	print("RENDER_METRICS: ",JSON.stringify(results))
	print("RENDER_UI_RESULT: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)

func _measure(scene_name: String) -> Dictionary:
	for i in range(10):
		await process_frame;RenderingServer.force_draw(false)
	var times: Array=[]
	var sample_count=30 if "--benchmark" in OS.get_cmdline_user_args() else 6
	for i in range(sample_count):
		await process_frame
		var start=Time.get_ticks_usec();RenderingServer.force_draw(false)
		times.append((Time.get_ticks_usec()-start)/1000.0)
	times.sort()
	var scene=app.table.get_viewport()
	var draw_calls=scene.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	check(draw_calls>0 and draw_calls<200,"%s stays below 200 actual draw calls (got %d)"%[scene_name,draw_calls])
	_verify_batches()
	return {"scene":scene_name,"pieces":app.table.pieces.size(),
		"visible_draw_calls":draw_calls,
		"shadow_draw_calls":scene.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"samples":sample_count,"render_submit_ms_median":times[sample_count/2],"render_submit_ms_p95":times[mini(sample_count-1,int(ceil(sample_count*0.95))-1)]}

func _verify_batches() -> void:
	var table=app.table;var faces=0
	for key in table.tile_batches:
		var batch=table.tile_batches[key].multimesh
		if key.begins_with("face_"):faces+=batch.visible_instance_count
		else:check(batch.visible_instance_count==table.pieces.size(),"all live tiles have a "+key)
	check(faces==table.pieces.size(),"face batches contain exactly the current tiles, without stale instances")
	for key in table.pieces:
		var piece=table.pieces[key];var index=int(piece.get_meta("batch_index"))
		var rendered=table.tile_batches.cap.multimesh.get_instance_transform(index)
		var model=piece.transform*piece.get_node("Model").transform
		check(rendered.origin.is_equal_approx(model*Vector3(0,0.055,0)),"rendered body tracks pickable tile: "+key)
		var face=table.tile_batches[piece.get_meta("face_batch")]
		if piece.get_meta("tile")<0:check(face.material_override==table.body_material,"hidden hand never uploads a private face: "+key)

func _verify_animation_and_reset() -> void:
	# Reuse batches across a new round, then sample the real discard tween. A
	# renderer that uploads only on revision changes leaves this tile floating.
	var e=GameEngine.new();e.start({},93000);app.session.engine=e
	app.table.last_round=-1;app._changed(e.view(0));_verify_batches()
	var action=e.state.pending.filter(func(move):return move.kind=="discard")[0]
	check(e.submit(0,e.state.revision,action.id),"animation fixture submits a legal discard")
	app._changed(e.view(0))
	var piece=app.table.pieces["d0-0"];var start=piece.position
	var tween=app.table.tile_tweens["d0-0"]
	tween.pause();tween.custom_step(0.12)
	check(piece.position.y<start.y and piece.position.y>TableLayout.river(0,0).y,"discard advances smoothly before landing")
	_verify_batches()
	await capture("render-discard-motion")
	tween.custom_step(0.25)
	check(piece.position.is_equal_approx(TableLayout.river(0,0)),"discard lands at the pickable river position")
	_verify_batches()
	var fresh=GameEngine.new();fresh.start({},93001);app.session.engine=fresh
	app.table.last_round=-1;app._changed(fresh.view(0));_verify_batches()
	check(not app.table.pieces.has("d0-0"),"new round removes old discard and its animation")
