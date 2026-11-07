extends SceneTree
## Also runnable against an exported EXE with an absolute --script path.
var app
var engine
var failures: Array = []
var checks = 0
var directory = ""
var finishing = false

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("TOUCH INSPECTION FAIL: ",message)

func frames(count: int = 3) -> void:
	for frame in range(count): await process_frame

func labels(node: Node) -> Array:
	var result: Array = []
	if not is_instance_valid(node) or node.is_queued_for_deletion(): return result
	if node is Label: result.append(node.text)
	for child in node.get_children(): result.append_array(labels(child))
	return result

func inspection() -> Control:
	for child in app.inspect_layer.get_children():
		if child is Control and not child.is_queued_for_deletion(): return child
	return null

func tile(index: int) -> Control:
	for child in app.hand_layer.get_children():
		if child is TextureButton and not child.is_queued_for_deletion() and child.get_meta("hand_index")==index: return child
	return null

func motion(position: Vector2, emulated: bool = true) -> void:
	var event=InputEventMouseMotion.new();event.position=position
	event.device=InputEvent.DEVICE_ID_EMULATION if emulated else 0
	root.push_input(event,true)

func tap(position: Vector2) -> void:
	motion(position)
	for pressed in [true,false]:
		var touch=InputEventScreenTouch.new();touch.position=position;touch.index=0;touch.pressed=pressed
		root.push_input(touch,true)
		var mouse=InputEventMouseButton.new();mouse.position=position;mouse.button_index=MOUSE_BUTTON_LEFT
		mouse.pressed=pressed;mouse.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
		mouse.device=InputEvent.DEVICE_ID_EMULATION;root.push_input(mouse,true)
		await frames(2)

func tap_tile(index: int) -> void:
	check(is_instance_valid(tile(index)),"hand tile exists")
	if is_instance_valid(tile(index)): await tap(tile(index).get_global_rect().get_center())

func fixture() -> void:
	# Load after the real app has registered its classes, matching game startup.
	engine=load("res://scripts/core/game_engine.gd").new();engine.start({},481)
	for player in engine.state.players:
		player.melds=[];player.discards=[];player.bao=false;player.ming=false
	engine.state.players[0].hand=[0,1,2,3,4,5,9,10,11,18,19,20,22,27]
	engine.state.players[0].drawn=13
	# Hidden triplets must not affect the viewer's unseen counts.
	engine.state.players[1].hand=[2,2,2,3,3,3,4,4,4,12,13,14,31]
	engine.state.gang_head=31;engine._turn_options()
	app.session.engine=engine;app.session.paused=false
	app.suppress_click_until=-1;app.last_touch_ms=-1000;app.touch_index=-1
	app._build_hud();app._changed(engine.view(0));await frames()

func capture(name: String) -> void:
	var args=OS.get_cmdline_user_args();var index=args.find("--capture-dir")
	if DisplayServer.get_name()=="headless" or index<0: return
	await frames(4);RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(args[index+1].path_join(name+".png"))==OK,"save rendered inspection screenshot")

func test_about() -> void:
	app._about()
	check(labels(app.modal).has("署名：股神墨菲特"),"about displays requested credit")
	var link: LinkButton
	for child in app.modal.get_children():
		if child is LinkButton: link=child
	check(link!=null,"about includes a project link")
	if link!=null:
		check(link.text=="GitHub：https://github.com/253506088/shanDongMaJiang","complete requested URL is visible")
		check(link.get_meta("url","")=="https://github.com/253506088/shanDongMaJiang" and link.pressed.get_connections().size()==1,"link targets project without opening external apps during QA")
	check(labels(app.modal).any(func(text):return text.contains("莲花麻将（MIT）") and text.contains("LGPL-2.1")),"upstream attribution remains visible")
	await capture("about-credit")
	app._close_modal()

func test_persistence() -> void:
	await fixture();await tap_tile(3)
	check(app.selected==3 and engine.journal.is_empty(),"first tap selects Four Characters without playing")
	check(labels(inspection()).has("四万"),"first tap opens the inspection explicitly")
	motion(Vector2(800,400));tile(3).mouse_exited.emit();await frames()
	await create_timer(.7).timeout
	var text=labels(inspection())
	check(text.has("三万") and text.has("四万") and text.has("五万"),"finger release and emulated leave keep all adjacent faces visible")
	check(text.count("未见 3 张")==3,"unseen counts include own visible hand but not hidden opponent triplets")
	if inspection()!=null:
		var bounds=inspection().get_global_rect()
		check(not bounds.intersects(tile(3).get_global_rect()),"pinned panel leaves hand tile clear")
		for action in app.action_layer.get_children():
			if action is BaseButton and not action.is_queued_for_deletion():
				check(not bounds.intersects(action.get_global_rect()),"pinned panel leaves action buttons visible")
		await tap(bounds.get_center())
		check(inspection()!=null and engine.journal.is_empty(),"reading panel cannot click through and play a tile")
	await capture("touch-persistent-unseen")
	var retired=tile(3);app._draw_hand();retired.mouse_exited.emit();retired.pressed.emit();await frames()
	check(labels(inspection()).has("四万") and engine.journal.is_empty(),"retired hand controls cannot clear inspection or submit a stale click")
	app._set_character("male_01");await frames()
	check(labels(inspection()).has("四万"),"cosmetic refresh preserves inspection")
	await tap_tile(10)
	check(app.selected==10 and labels(inspection()).has("二条") and not labels(inspection()).has("四万"),"another touch updates selected tile and its inspection")
	await tap(Vector2(800,600))
	check(app.selected==-1 and inspection()==null and engine.journal.is_empty(),"blank touch dismisses inspection and selection without playing")
	motion(tile(0).get_global_rect().get_center());await frames()
	check(inspection()==null,"emulated hover does not reopen a dismissed touch panel")
	await tap_tile(0)
	check(labels(inspection()).has("一万") and labels(inspection()).has("二万") and not labels(inspection()).has("三万"),"rank one inspection stays within the suit")
	await tap_tile(13)
	check(labels(inspection()).has("东风") and not labels(inspection()).has("一万"),"honor inspection switches to that face")
	await tap_tile(13)
	check(engine.state.revision==1 and engine.journal.size()==1 and inspection()==null,"second touch still discards once and closes inspection")

func test_read_only_and_refresh() -> void:
	await fixture();engine.state.current=1;engine._turn_options();app._changed(engine.view(0));await frames()
	await tap_tile(3);await tap_tile(3)
	check(app.selected==-1 and labels(inspection()).has("四万") and engine.journal.is_empty(),"other player's turn allows inspection but never selects for discard")
	engine.state.players[2].discards.append(3);engine.state.revision+=1
	engine.state.event={"kind":"discard","seat":2,"tile":3}
	app._changed(engine.view(0));await frames()
	check(labels(inspection()).has("四万") and labels(inspection()).count("未见 2 张")==1,"public action updates counts while stable hand inspection stays open")
	await capture("touch-live-unseen")
	engine.state.players[0].hand.remove_at(0);engine.state.revision+=1
	app._changed(engine.view(0));await frames()
	check(inspection()==null,"changed physical hand invalidates the old inspection index")
	await fixture();await tap_tile(3)
	engine.state.round+=1;app._changed(engine.view(0));await frames()
	check(inspection()==null,"new round cannot retain a previous inspection")

func test_mouse() -> void:
	await fixture();motion(tile(3).get_global_rect().get_center(),false);await frames()
	check(labels(inspection()).has("四万"),"desktop hover still shows unseen counts")
	motion(Vector2(800,400),false);await frames()
	check(inspection()==null,"desktop pointer leave still hides hover-only inspection")
	await tap_tile(3);await create_timer(.7).timeout
	motion(tile(10).get_global_rect().get_center(),false);await frames()
	check(labels(inspection()).has("二条") and not labels(inspection()).has("四万"),"real mouse takes over from touch on hybrid devices")

func finish(code: int) -> void:
	if finishing:return
	finishing=true
	if is_instance_valid(app):app.queue_free()
	app=null;engine=null;await frames(4)
	if DisplayServer.get_name()!="headless": RenderingServer.force_draw(false)
	await create_timer(.2).timeout
	for name in ["current_match.json","current_match.json.bak","current_match.json.tmp"]:
		var path=ProjectSettings.globalize_path(directory+name)
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
	call_deferred("quit",code)

func run() -> void:
	Engine.max_fps=60
	create_timer(75).timeout.connect(func():printerr("Inspection watchdog");await finish(1))
	directory="user://qa-touch-inspection-%d-%d/"%[OS.get_process_id(),Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	app=load("res://scenes/main.tscn").instantiate();app.qa_mode=true;root.add_child(app)
	app.session.storage_root=directory;app.session.set_process(false);app.muted=true
	await test_about();await test_persistence();await test_read_only_and_refresh();await test_mouse()
	print("TOUCH_INSPECTION_UI_RESULT: %d failures; %d checks"%[failures.size(),checks])
	call_deferred("finish",0 if failures.is_empty() else 1)
