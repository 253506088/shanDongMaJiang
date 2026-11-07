extends "res://tests/ui_smoke.gd"
var checks=0
var save_directory=""

func expect(ok: bool, message: String) -> void:
	checks+=1;check(ok,message)

func tagged(node: Node, key: String, value: Variant) -> Node:
	if node.is_queued_for_deletion():return null
	if node.has_meta(key) and node.get_meta(key)==value:return node
	for child in node.get_children():
		var found=tagged(child,key,value)
		if found:return found
	return null

func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await super.capture(name)

func choose(id: String) -> void:
	await click_control(tagged(app.character_picker,"character_id",id))
	await pause_frames(3)

func run() -> void:
	create_timer(100).timeout.connect(func():printerr("CHARACTER UI watchdog");quit(1))
	print("Character UI: loading app")
	app=load("res://scenes/main.tscn").instantiate();app.qa_mode=true
	print("Character UI: entering app")
	root.add_child(app)
	print("Character UI: app ready")
	app.muted=true;app.session.set_process(false)
	save_directory="user://qa-characters-ui-%d-%d/"%[OS.get_process_id(),Time.get_ticks_msec()]
	app.session.storage_root=save_directory;app.preferences_path=save_directory+"preferences.json"
	await pause_frames(4)
	expect(app.character_id==Characters.DEFAULT and Characters.info(app.character_id).gender=="male","first start defaults to male role")
	await click_control(app.character_button);await pause_frames(3)
	expect(is_instance_valid(app.character_picker),"lobby opens role picker")
	for id in Characters.IDS:expect(tagged(app.character_picker,"character_id",id)!=null,"all eight roles selectable")
	await capture("01-eight-roles")
	await choose("female_02")
	expect(app.character_id=="female_02" and app.character_button.text=="角色 · 观澜","choosing female updates lobby")
	expect(not FileAccess.file_exists(app.preferences_path),"QA never writes preferences")
	app._open_doudizhu();app.doudizhu.session.set_process(false);await pause_frames(3)
	expect(app.doudizhu.session.current_view().characters[0]=="female_02","selected role carries into DDZ")
	app.doudizhu.session.engine.state.phase="playing";app.doudizhu.session.engine.state.turn=0;app.doudizhu.session.engine.state.landlord=0
	app.doudizhu.session._publish()
	var card=app.doudizhu.table.view.hand[0]
	app.doudizhu.table._toggle_card(card)
	var before=app.doudizhu.session.engine.state.duplicate(true)
	await click_control(app.doudizhu.table.character_button);await pause_frames(2)
	expect(app.doudizhu.session.paused,"role picker pauses local DDZ")
	await choose("male_03")
	expect(app.doudizhu.table.selected_cards==[card] and app.doudizhu.session.engine.state==before,"DDZ role change preserves chosen cards and all game state")
	expect(not app.doudizhu.session.paused and app.doudizhu.table.character_button.text=="角色 · 怀竹","closing picker restores play and updates role")
	expect(find_button(app.doudizhu,"男声报牌")==null and find_button(app.doudizhu,"女声报牌")==null,"manual voice choices removed from DDZ")
	await capture("02-ddz-role")
	app._show_lobby();await pause_frames(3)
	app._open_bluff();app.bluff.session.set_process(false)
	app.bluff.table.start_requested.emit({"players":6});await pause_frames(3)
	var engine=app.bluff.session.engine
	engine.state.phase="playing";engine.state.turn=0;app.bluff.session._publish()
	card=app.bluff.table.view.hand[0];app.bluff.table.toggle_card(card)
	before=engine.state.duplicate(true)
	await click_control(find_button(app.bluff,"角色 · 怀竹"));await pause_frames(2)
	expect(app.bluff.session.paused,"role picker pauses local bluff")
	await choose("female_03")
	expect(app.bluff.table.selected==[card] and engine.state==before,"bluff selection and round state survive role change")
	expect(not app.bluff.table.settings.has("voice") and find_button(app.bluff,"男声宣言")==null,"bluff no longer stores a voice choice")
	await capture("03-bluff-role")
	app._show_lobby();await pause_frames(3)
	app._start_game(false);app.session.set_process(false);await pause_frames(3)
	var snapshot=JSON.stringify(app.session.engine.snapshot())
	await click_control(app.character_button);await pause_frames(2)
	await choose("female_04")
	expect(JSON.stringify(app.session.engine.snapshot())==snapshot,"Mahjong role choice cannot change saved rules or moves")
	expect(app.players_ui[0].portrait.get_meta("character_id")=="female_04","Mahjong avatar follows chosen role")
	await capture("04-mahjong-role")
	app._set_character("male_01")
	var view=Characters.decorate(app.session.engine.view(0),["male_01","male_01","male_01","male_01"])
	app._changed(view);await pause_frames(3)
	var colors: Array=[]
	for seat in range(4):
		var portrait=app.players_ui[seat].portrait
		expect(portrait.get_meta("character_id")=="male_01" and portrait.get_meta("border_color") not in colors,"same-role seats have different visible border colors")
		colors.append(portrait.get_meta("border_color"))
	await capture("05-duplicate-borders")
	app._show_lobby();app._show_lan_browser();await pause_frames(3)
	app.lan_lobby.nickname="保留昵称";app.lan_lobby.address="192.168.1.10"
	await click_control(app.lan_lobby.character_button);await pause_frames(2)
	await choose("male_02")
	expect(app.lan_lobby.nickname=="保留昵称" and app.lan_lobby.address=="192.168.1.10","changing role preserves room form entries")
	await capture("06-lan-role-entry")
	var room={"name":"同角色测试","settings":{"jiang":"258","chi":true,"ai":"efficiency","field_rules":false},"host_addresses":["127.0.0.1"],"port":32141,"started":false,"can_start":true,"seats":[]}
	for seat in range(4):room.seats.append({"name":"玩家%d"%(seat+1),"occupied":true,"connected":true,"ready":true,"character_id":"male_02"})
	app.lan_lobby.show_room(room,true,0);await pause_frames(3)
	var portraits=app.lan_lobby.find_children("*","Control",true,false).filter(func(node):return node.has_meta("character_id"))
	expect(portraits.size()==4,"room shows four instances of repeated character")
	colors.clear()
	for portrait in portraits:
		expect(portrait.get_meta("border_color") not in colors,"room also assigns distinct duplicate borders")
		colors.append(portrait.get_meta("border_color"))
	await capture("07-lan-duplicate-room")
	app.discovery.stop()
	print("CHARACTERS_UI_RESULT: %d failures; %d checks"%[failures.size(),checks])
	call_deferred("finish",0 if failures.is_empty() else 1)

func finish(code: int) -> void:
	app._close_character_picker();app.queue_free();app=null
	await pause_frames(4)
	RenderingServer.force_draw(false)
	await create_timer(.2).timeout
	for file in ["preferences.json","current_match.json","current_match.json.bak","current_match.json.tmp"]:
		var path=ProjectSettings.globalize_path(save_directory+file)
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_directory))
	quit(code)
