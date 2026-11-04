extends "res://tests/ui_smoke.gd"

## Real desktop window lifecycle and input; never read/write player settings.
func run() -> void:
	create_timer(120).timeout.connect(func():printerr("WINDOW UI watchdog");quit(1))
	app=load("res://scenes/main.tscn").instantiate();app.qa_mode=true;root.add_child(app)
	app.session.storage_root="user://qa-window/";app.session.set_process(false)
	var display=app.desktop_window
	check(display.supported,"test requires a real desktop display")
	if not display.supported:quit(1);return
	await pause_frames(5)
	var initial_size=root.size
	var initial_position=root.position
	var initial_vsync=DisplayServer.window_get_vsync_mode()
	app._show_settings();await pause_frames(3)
	check(is_instance_valid(find_button(app.root,"窗口模式")),"settings exposes windowed mode")
	await capture("window-settings")
	await click_control(find_button(app.root,"窗口模式"))
	await pause_frames(5)
	check(root.mode==Window.MODE_FULLSCREEN,"settings selects borderless, non-exclusive fullscreen")
	check(root.size==DisplayServer.screen_get_size(root.current_screen),"fullscreen fills current monitor")
	check(app.session.paused,"fullscreen preserves settings pause")
	check(is_instance_valid(find_button(app.root,"无边框全屏")),"settings reflects fullscreen immediately")
	await capture("window-fullscreen")
	await _key(KEY_F11)
	await create_timer(0.55).timeout
	check(root.mode==Window.MODE_WINDOWED,"F11 exits fullscreen even with a modal")
	check(root.size==initial_size and root.position==initial_position,"fullscreen restores window geometry")
	await _key(KEY_ENTER,true)
	check(root.mode==Window.MODE_FULLSCREEN,"Alt+Enter enters fullscreen")
	await _key(KEY_F11,false,true)
	check(root.mode==Window.MODE_FULLSCREEN,"holding F11 does not repeatedly toggle")
	await _key(KEY_ENTER,true)
	await create_timer(0.55).timeout
	app._close_modal();app._build_hud()
	var engine=GameEngine.new();engine.start({},93000)
	app.session.engine=engine;app.session.paused=false;app._changed(engine.view(0))
	await create_timer(2.1).timeout
	var revision=app.view.revision
	await _key(KEY_ENTER,true)
	check(root.mode==Window.MODE_FULLSCREEN and app.view.revision==revision,"Alt+Enter never discards a tile")
	await _key(KEY_F11)
	await create_timer(0.55).timeout
	if OS.get_name()=="Windows":
		root.position=initial_position+Vector2i(24,24)
		await pause_frames(2)
		check(Engine.max_fps==60 and DisplayServer.window_get_vsync_mode()==initial_vsync,"moving does not raise FPS or switch VSync")
		check(root.content_scale_mode==Window.CONTENT_SCALE_MODE_CANVAS_ITEMS,"moving keeps native-resolution rendering")
		await create_timer(0.55).timeout
		check(Engine.max_fps==60,"movement retains normal frame pacing")
		var sizes=[Vector2i(960,540),Vector2i(1120,710),Vector2i(1320,740),Vector2i(1440,900),Vector2i(1010,610)]
		var scene_size=app.scene_surface.scene_viewport.size
		var target_changes=app.scene_surface.target_changes
		for size in sizes:
			root.size=size;await pause_frames(2)
			check(app.scene_surface.resize_pending,"resize queued at "+str(size))
			check(app.scene_surface.scene_viewport.size==scene_size,"resize keeps scene render target stable")
			check(root.content_scale_mode==Window.CONTENT_SCALE_MODE_CANVAS_ITEMS,"outer canvas never switches modes")
			check(root.get_visible_rect().size==Vector2(1600,900),"resize preserves logical input coordinates")
			RenderingServer.force_draw(false)
		await create_timer(0.55).timeout
		check(app.scene_surface.target_changes==target_changes+1,"all live sizes produce one final scene target update")
		check(not app.scene_surface.resize_pending and root.content_scale_mode==Window.CONTENT_SCALE_MODE_CANVAS_ITEMS,"resize restores crisp native scene")
		check(DisplayServer.window_get_vsync_mode()==initial_vsync,"resize restores VSync")
		check(app.view.revision==revision,"window operations leave match state unchanged")
		await capture("window-resized-table")
		# Quality changes during adjustment must survive restoration.
		root.position+=Vector2i(8,0);await pause_frames(2)
		display.set_frame_limit(30)
		await create_timer(0.55).timeout
		check(Engine.max_fps==30,"adjustment retains new frame limit")
		display.set_frame_limit(60)
	root.mode=Window.MODE_MAXIMIZED;await create_timer(0.55).timeout
	await _key(KEY_F11);await _key(KEY_F11)
	check(root.mode==Window.MODE_MAXIMIZED,"fullscreen restores maximized state")
	root.mode=Window.MODE_WINDOWED;root.size=initial_size;root.position=initial_position
	await create_timer(0.55).timeout
	# Input mapping still reaches the same real hand button after every resize.
	var card: TextureButton
	for child in app.hand_layer.get_children():
		if child is TextureButton:card=child;break
	await click_control(card)
	check(app.view.revision>revision,"hand click still discards after window transitions")
	print("WINDOW_UI_RESULT: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)

func _key(code: Key, alt: bool=false, echo: bool=false) -> void:
	for pressed in [true,false]:
		var event=InputEventKey.new();event.keycode=code;event.pressed=pressed;event.alt_pressed=alt;event.echo=echo
		root.push_input(event,true)
		await pause_frames(2)
