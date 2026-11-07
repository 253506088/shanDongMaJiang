extends SceneTree
var checks=0
var failures: Array=[]

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message);printerr("CHARACTER SESSION FAIL: ",message)

func wait_for(predicate: Callable, message: String) -> bool:
	var deadline=Time.get_ticks_msec()+5000
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
	var ok=predicate.call();check(ok,message);return ok

func preferences() -> void:
	var directory="user://qa-character-prefs-%d/"%Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path=directory+"preferences.json"
	var file=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"doudizhu_voice":"female","bluff_settings":{"voice":"female","players":5,"theme":"guofeng"},"muted":true,"config":{"jiang":"luan","chi":false,"field_rules":true,"field_selection":"mutation"}}));file.close()
	var app=load("res://scenes/main.tscn").instantiate();app.qa_mode=false;app.preferences_path=path;root.add_child(app)
	check(app.character_id==Characters.DEFAULT,"legacy female voice preference does not choose a female role by itself")
	check(app.config.jiang=="luan" and not app.config.chi and app.config.field_selection=="mutation","loading role preference preserves unrelated game settings")
	check(app._set_character("female_03"),"temporary-avatar female role can be selected normally")
	var saved=JSON.parse_string(FileAccess.get_file_as_string(path))
	check(saved.character_id=="female_03" and not saved.has("doudizhu_voice") and not saved.bluff_settings.has("voice"),"only character ID persists; manual voice preferences removed")
	check(saved.bluff_settings.players==5 and saved.bluff_settings.theme=="guofeng" and saved.muted,"existing non-voice preferences retained")
	app.free();await process_frame
	app=load("res://scenes/main.tscn").instantiate();app.qa_mode=false;app.preferences_path=path;root.add_child(app)
	check(app.character_id=="female_03" and app.session.character_id=="female_03","a fresh app restores selected role")
	app._open_doudizhu();app.doudizhu.session.set_process(false)
	check(app.doudizhu.session.current_view().characters[0]=="female_03" and Characters.voice_for(app.doudizhu.session.current_view(),0)=="female","DDZ receives cached gender role")
	app._show_lobby();await process_frame
	app._open_bluff()
	check(app.bluff.character_id=="female_03" and app.bluff.table.character_id=="female_03","bluff setup receives same cached role")
	app.free();await process_frame
	saved.character_id="invalid";file=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(saved));file.close()
	app=load("res://scenes/main.tscn").instantiate();app.qa_mode=false;app.preferences_path=path;root.add_child(app)
	check(app.character_id==Characters.DEFAULT,"corrupt role ID recovers to male default")
	app.free();await process_frame
	var before=FileAccess.get_file_as_bytes(path)
	app=load("res://scenes/main.tscn").instantiate();app.qa_mode=true;app.preferences_path=path;root.add_child(app)
	app._set_character("female_04")
	check(FileAccess.get_file_as_bytes(path)==before,"QA role selection never writes real or isolated preferences")
	app.free();await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path));DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))

func network() -> void:
	var host=LanSession.new();root.add_child(host);host.set_character("male_01")
	var port=56000+OS.get_process_id()%2000
	check(host.host_room({},"角色房主",port)==OK,"host creates room with male role")
	var guests: Array=[]
	for id in ["female_01","male_01","female_01"]:
		var guest=LanSession.new();root.add_child(guest);guest.set_character(id);guests.append(guest)
		check(guest.join_room("127.0.0.1","同桌",port)==OK,"guest joins with possibly repeated role")
		if not await wait_for(func():return guest.connected,"role handshake assigns seat"):
			await cleanup(host,guests);return
		guest.set_ready(true)
	if not await wait_for(func():return host.room.can_start,"repeated roles do not block readiness"):
		await cleanup(host,guests);return
	check(host.room.seats.map(func(member):return member.character_id)==["male_01","female_01","male_01","female_01"],"room retains duplicate choices exactly")
	check(host.start_room(),"four people can start with two duplicated role pairs")
	host.hold_presentation(600)
	if not await wait_for(func():return guests.all(func(guest):return not guest.current_view.is_empty()),"all clients receive characters"):
		await cleanup(host,guests);return
	var host_view=host.current_view
	for guest in guests:
		var local=guest.local_seat
		check(Characters.at(guest.current_view,0)==guest.character_id,"guest sees own chosen character at bottom")
		for relative in range(4):
			var absolute=(relative+local)%4
			check(Characters.at(guest.current_view,relative)==Characters.at(host_view,absolute),"all clients agree on role identities")
			check(Characters.border(guest.current_view,relative)==Characters.border(host_view,absolute),"all clients agree on duplicate border colors")
	var snapshot=JSON.stringify(host.engine.snapshot())
	var revision=host.engine.state.revision
	var appearance=host.current_view.character_revision
	var old_packet=host._seat_view(1).duplicate(true)
	check(guests[0].set_character("male_01"),"guest can change character during current turn")
	if await wait_for(func():return guests.all(func(guest):return guest.current_view.character_revision>appearance),"same-turn appearance update reaches all clients"):
		check(host.engine.state.revision==revision and JSON.stringify(host.engine.snapshot())==snapshot,"live character change does not alter game or replay")
		check(host.current_view.characters.slice(0,3)==["male_01","male_01","male_01"],"three identical roles allowed")
		var colors=[Characters.border(host.current_view,0),Characters.border(host.current_view,1),Characters.border(host.current_view,2)]
		check(colors[0]!=colors[1] and colors[0]!=colors[2] and colors[1]!=colors[2],"three equal avatars remain distinguishable")
		var latest=guests[0].current_view.duplicate(true)
		guests[0]._receive_client({"kind":"view","view":old_packet})
		check(guests[0].current_view==latest,"stale same-turn cosmetic packet cannot undo selected role")
	check(not guests[0].set_character("../bad.png"),"invalid avatar path cannot be selected or sent")
	guests[0]._send(1,{"kind":"character","character_id":"male_02","seat":0,"gender":"female"})
	if await wait_for(func():return host.room.seats[1].character_id=="male_02","server accepts canonical role change"):
		check(host.room.seats[0].character_id=="male_01","client cannot change another seat using a forged seat field")
		check(Characters.info(host.room.seats[1].character_id).gender=="male","forged gender never overrides catalog")
	guests[0]._close_peer()
	await wait_for(func():return not host.room.seats[1].connected,"disconnect preserves original seat")
	guests[0].set_character("female_04")
	check(guests[0].reconnect_room()==OK,"guest reconnects with same role")
	if await wait_for(func():return guests[0].connected and Characters.at(guests[0].current_view,0)=="female_04","reconnected view retains selected character"):
		check(guests[0].local_seat==1 and JSON.stringify(host.engine.snapshot())==snapshot,"reconnect preserves seat and gameplay")
		await wait_for(func():return guests.all(func(guest):return Characters.at(guest.current_view,SeatView.relative(1,guest.local_seat))=="female_04"),"reconnecting role refresh reaches the other clients too")
	await cleanup(host,guests)

func cleanup(host: LanSession, guests: Array) -> void:
	var port=host._port
	for guest in guests:guest.leave_room();guest.queue_free()
	host.leave_room();host.queue_free()
	var deadline=Time.get_ticks_msec()+2500
	while root.get_child_count()>0 and Time.get_ticks_msec()<deadline:await process_frame
	check(root.get_child_count()==0,"network drains finish before shutdown")
	LanSession._host_drains.erase(port)
	for child in root.get_children():child.queue_free()
	await process_frame

func run() -> void:
	Engine.max_fps=60
	await preferences()
	await network()
	print("CHARACTERS_SESSION_RESULT: %d failures; %d checks"%[failures.size(),checks])
	call_deferred("quit",0 if failures.is_empty() else 1)
