extends "res://tests/ui_smoke.gd"
## Scene/control checks only. Requires headless; never changes desktop state.
var checks = 0
var save_directory = ""

func expect(ok: bool, message: String) -> void:
	checks += 1; check(ok,message)

func labels(node: Node) -> Array:
	var result: Array=[]
	if node is Label:result.append(node.text)
	for child in node.get_children():result.append_array(labels(child))
	return result

func fixture(id: String) -> GameEngine:
	app._close_modal()
	var engine=GameEngine.new()
	engine.start({"field_rules":not id.is_empty(),"jiang":"luan"},481,1,[],[],id)
	app.session.engine=engine;app.session.paused=false;app.last_revision=-1
	app._changed(engine.view(0))
	return engine

func finish(code: int) -> void:
	if is_instance_valid(app):app.queue_free();app=null
	await pause_frames(2)
	if not save_directory.is_empty():
		for name in ["current_match.json","current_match.json.bak","current_match.json.tmp"]:
			var path=ProjectSettings.globalize_path(save_directory+name)
			if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_directory))
	quit(code)

func run() -> void:
	if DisplayServer.get_name()!="headless":printerr("Field UI checks require --headless");quit(1);return
	create_timer(100).timeout.connect(func():printerr("FIELD_UI watchdog timeout");await finish(1))
	app=load("res://scenes/main.tscn").instantiate();app.qa_mode=true;root.add_child(app)
	app.session.set_process(false)
	save_directory="user://qa-field-ui-%d-%d/"%[OS.get_process_id(),Time.get_ticks_msec()]
	app.session.storage_root=save_directory
	expect(not app.config.field_rules,"field enhancement defaults off")
	find_button(app.root,"每局随机").pressed.emit();await pause_frames(2)
	expect(app.config.field_rules and app.config.jiang=="258","field toggle preserves regional rule settings")
	app._show_field_catalog();await pause_frames(2)
	for id in FieldRules.IDS:
		expect(labels(app.modal).has(FieldRules.info(id).name),"catalog includes "+id)
	app._show_field_detail("rebirth",false)
	expect(labels(app.modal).any(func(value):return str(value).contains("每人每局")),"catalog explains per-player per-round limit")
	app._close_modal();app._show_lan_browser();await pause_frames(2)
	expect(find_button(app.lan_lobby,"场地：每局随机")!=null,"LAN creation exposes the same independent modifier")
	var room={"settings":{"jiang":"luan","chi":true,"ai":"efficiency","field_rules":true},"seats":[],"started":false}
	app.lan_lobby.show_room(room,false,1)
	expect(labels(app.lan_lobby).has("场地：每局随机") and find_button(app.lan_lobby,"场地：每局随机")==null,"guest sees field setting without host-only controls")
	app.discovery.stop();app._build_hud()
	fixture("");await pause_frames(2)
	expect(not app.field_button.visible,"normal table has no field badge")
	var engine=fixture("diamond_finger");await pause_frames(2)
	expect(app.field_button.visible and app.field_button.text.contains("大力金刚指"),"table identifies active field")
	expect(find_button(app.root,"场地能力")!=null,"legal field skill has a table action")
	app._show_current_field();await pause_frames(2)
	expect(find_button(app.modal,"选择一张手牌，变为白板")!=null,"skill panel explains transformation before selection")
	app._show_field_picker("field_transform");await pause_frames(2)
	var old_revision=int(engine.state.revision)
	find_button(app.modal,"确认变白板").pressed.emit();await pause_frames(2)
	expect(engine.state.revision==old_revision+1 and engine.state.players[0].field_used,"explicit tile confirmation submits transformation once")
	app._show_current_field()
	expect(labels(app.modal).has("你的本局次数：已使用"),"used skill is visible as spent")
	app._close_modal();app._inspect_tile(0,600,763)
	expect(labels(app.inspect_layer).any(func(value):return str(value).begins_with("至多")),"secret transformation counts are presented as upper bounds beside the number")
	engine=fixture("rebirth");await pause_frames(2)
	var reborn: Dictionary=engine.state.players[0]
	reborn.hand=[0,1,2,3,4,5,9,10,11,18,19,20,22,27];reborn.melds=[]
	reborn.bao=false;reborn.ming=false;reborn.revealed_hand=true;reborn.drawn=13
	engine._turn_options();app.last_revision=-1;app._changed(engine.view(0));await pause_frames(2)
	expect(not app.view.pending.any(func(action):return action.kind=="bao") and app.view.pending.any(func(action):return action.kind=="ming"),"rebirth fixture has only legal open-ready declarations")
	app._show_waits();await pause_frames(2)
	expect(labels(app.modal).has("打出 东"),"wait overview includes open-ready-only discard choices after rebirth")
	app._close_modal();app._inspect_tile(27,600,763)
	expect(labels(app.inspect_layer).has("打出后可明搂 · 听口"),"tile inspection explains the legal post-rebirth declaration")
	engine=fixture("astrology_wall");await pause_frames(2)
	var peek: Dictionary=engine.state.pending.filter(func(action):return action.kind=="field_peek_wall")[0]
	app._submit_field(peek,int(engine.state.revision));await pause_frames(2)
	expect(is_instance_valid(app.modal) and labels(app.modal).any(func(value):return str(value).contains("你的占星记录")),"an authoritative private result opens after the updated view arrives")
	app._close_modal();app._changed(engine.view(0));await pause_frames(2)
	expect(not is_instance_valid(app.modal),"repeated snapshots do not reopen dismissed private information")
	engine=fixture("exchange");await pause_frames(2)
	app._show_exchange_picker();await pause_frames(2)
	expect(find_button(app.modal,"确认传给 "+app.view.players[1].name).disabled,"exchange requires a complete legal three-tile selection")
	var move: Dictionary=engine.state.pending[0]
	app.field_exchange_selection=move.indices.duplicate()
	app._show_exchange_picker(false);await pause_frames(2)
	var exchange=find_button(app.modal,"确认传给 "+app.view.players[1].name)
	expect(not exchange.disabled,"engine-approved exchange becomes confirmable")
	exchange.pressed.emit();await pause_frames(2)
	expect(engine.state.revision==1,"exchange confirmation passes through authoritative action")
	engine=fixture("transparent");await pause_frames(2)
	var mixed=engine.view(0)
	mixed.players[1].hand=[-1,0,1,2];mixed.players[1].hand_count=4;mixed.players[1].drawn=-1
	app._changed(mixed);await pause_frames(2)
	expect(app.table.pieces["h1-0"].get_meta("tile")==-1 and app.table.pieces["h1-0"].get_meta("pose")=="back","opaque tile keeps an unidentified back in a partially public hand")
	expect(app.table.pieces["h1-1"].get_meta("tile")==0 and app.table.pieces["h1-1"].get_meta("pose")=="face","public tile displays only the known identity")
	var before=app._visible_remaining(0)
	app.view.players[1].hand=[-1,-1,1,2]
	expect(app._visible_remaining(0)==before+1,"visible remaining count includes publicly visible opponent tiles")
	app.view.field={"id":"no_honors","tile_totals":Tiles.counts(Tiles.wall())}
	app.view.field.tile_totals[0]=9
	expect(app._visible_remaining(0)>4,"unusual decks use their actual public tile totals")
	app._show_public_tiles();await pause_frames(2)
	expect(labels(app.modal).any(func(value):return str(value).contains("公开手牌")),"public-tile viewer makes partial hands inspectable")
	engine=fixture("chosen");await pause_frames(2)
	app.view.field.chosen_tiles=[22,0,18]
	var base=[0,1,2,3,4,5,9,10,11,18,19,20,22]
	var normal=Rules.evaluate(base+[22],[],{"self_draw":true,"bao":true,"luan":true})
	app.view.players[0].melds=[]
	expect(app._wait_score(base,22).points==normal.points*2,"wait preview includes the current field bonus")
	var six=[]
	for group in Rules.chi([27,28,29,30],31,"honor_sequences"):
		six.append({"kind":"chi","tile":31,"tiles":group,"id":str(six.size())})
	app._show_move_picker(six);await pause_frames(2)
	expect(six.size()==6 and app.modal.size.y>380,"all six honor-sequence choices fit across two rows")
	app._close_modal()
	app.view.phase="turn";app.view.decision_seat=0;app.view.pending=[]
	for index in range(14):app.view.pending.append({"kind":"win","id":str(index)})
	app._draw_actions();await pause_frames(2)
	var rows: Array=[]
	for button in app.action_layer.get_children():
		if not button is Button or button.is_queued_for_deletion():continue
		var rect: Rect2=button.get_rect()
		expect(rect.position.x>=0 and rect.end.x<=1600,"long action set stays inside the logical screen")
		if rect.position.y not in rows:rows.append(rect.position.y)
	expect(rows.size()>1,"long action sets wrap instead of shrinking readable targets")
	print("FIELD_UI_RESULT: %d checks; %d failures"%[checks,failures.size()])
	engine=null
	call_deferred("finish",0 if failures.is_empty() else 1)
