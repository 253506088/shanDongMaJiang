extends SceneTree
## One bounded, manually driven window for final native resize/layout review.
## Can be passed by absolute --script path to the exported Windows executable.
var app: Node
var output_dir = "res://tmp"
var native_size_events = 0
var initial_targets = 0
var done = false

class ReviewKeys extends Node:
	func _input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode==KEY_F8:
			get_viewport().set_input_as_handled()
			get_tree().call_deferred("_finish")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args=OS.get_cmdline_user_args();var idx=args.find("--capture-dir")
	if idx>=0 and idx+1<args.size():output_dir=args[idx+1]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	app=load("res://scenes/main.tscn").instantiate();app.qa_mode=true;root.add_child(app)
	app.session.storage_root="user://qa-desktop-review/";app.session.set_process(false)
	app._build_hud()
	var engine=GameEngine.new();engine.start({},93000)
	for seat in range(1,4):
		var player=engine.state.players[seat]
		player.hand=[0,1,2,9,10,11,18,19,20,13,13,26+seat,26+seat]
		player.melds=[];player.discards=[];player.drawn=-1;player.ming=true;player.bao=true
	app.session.engine=engine;app.session.paused=true;app._changed(engine.view(0))
	app.desktop_window.set_frame_limit(30)
	root.title="山东麻将 · 窗口与明搂验收"
	root.add_child(ReviewKeys.new())
	await create_timer(1.0).timeout
	initial_targets=app.scene_surface.target_changes
	root.size_changed.connect(func():native_size_events+=1)
	_snapshot("native-start")
	print("DESKTOP_REVIEW_READY: one capped window; F8 finishes; automatic exit in 120 seconds")
	create_timer(120).timeout.connect(_finish)

func _snapshot(name: String) -> void:
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(output_dir.path_join(name+".png"))

func _finish() -> void:
	if done:return
	done=true
	_snapshot("native-final")
	var report={"native_size_events":native_size_events,
		"native_extension_loaded":GDExtensionManager.is_extension_loaded("res://native/windows/motion_gate.gdextension"),
		"scene_target_updates":app.scene_surface.target_changes-initial_targets,
		"window_size":str(root.size),"scene_size":str(app.scene_surface.scene_viewport.size),
		"logical_size":str(app.scene_surface.scene_viewport.get_visible_rect().size),
		"opponent_wait_cards":app.opponent_waits_panels.size(),
		"outer_3d_disabled":root.disable_3d,"separate_world":app.scene_surface.scene_viewport.own_world_3d}
	var file=FileAccess.open(output_dir.path_join("native-review.json"),FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(report,"\t"))
	print("DESKTOP_REVIEW_RESULT: ",JSON.stringify(report))
	app.queue_free();await process_frame;await process_frame
	quit()
