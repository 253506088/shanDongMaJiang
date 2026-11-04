extends "res://tests/ui_smoke.gd"

## CPU/headless contract checks before the single desktop interaction review.
func run() -> void:
	create_timer(30).timeout.connect(func():printerr("SCENE SURFACE watchdog");quit(1))
	app=load("res://scenes/main.tscn").instantiate();app.qa_mode=true;root.add_child(app)
	app.session.set_process(false)
	var surface=app.scene_surface
	var scene=surface.scene_viewport
	check(scene.own_world_3d and scene.find_world_3d()!=root.find_world_3d(),"scene owns a separate 3D world")
	check(root.disable_3d and root.msaa_3d==Viewport.MSAA_DISABLED,"outer window has no 3D or multisampling")
	check(scene.oversampling_override==2.0 and root.oversampling_override==2.0,"font sampling is stable in both viewports")
	check(scene.get_visible_rect().size==Vector2(1600,900),"scene retains original logical coordinates")
	check(SceneSurface.fit_resolution(Vector2i(960,540))==Vector2i(960,540),"small window uses matching scene pixels")
	check(SceneSurface.fit_resolution(Vector2i(1280,800))==Vector2i(1280,720),"non-16:9 window preserves the playing aspect")
	var original=root.size
	var target=scene.size
	var changes=surface.target_changes
	for i in range(40):
		root.size=Vector2i(960+i*4,540+i*3)
		check(scene.size==target and surface.target_changes==changes,"native size burst cannot reallocate scene targets")
	var deadline=Time.get_ticks_msec()+2000
	while surface.resize_pending and Time.get_ticks_msec()<deadline:
		await create_timer(0.05).timeout
	check(scene.size==SceneSurface.fit_resolution(root.size),"stable window updates to native scene pixels")
	check(surface.target_changes==changes+1,"burst produces exactly one scene allocation after settling")
	app._show_settings();await pause_frames(2)
	await click_control(find_button(app.root,"已静音"))
	check(not app.muted,"container forwards pointer input into resized logical UI")
	app._close_modal();app._build_hud()
	var engine=GameEngine.new();engine.start({},93000)
	app.session.engine=engine;app.session.paused=false;app._changed(engine.view(0))
	await pause_frames(2)
	var card:TextureButton
	for child in app.hand_layer.get_children():
		if child is TextureButton:card=child;break
	await click_control(card)
	check(app.view.revision>0,"hand input still follows the existing discard path")
	root.size=original
	print("SCENE_SURFACE_RESULT: ",failures.size()," failures")
	app.queue_free();await pause_frames(2)
	quit(0 if failures.is_empty() else 1)
