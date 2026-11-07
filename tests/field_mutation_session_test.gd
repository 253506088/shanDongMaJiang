extends SceneTree
var checks = 0
var failures: Array = []

class MemorySession extends LocalSession:
	func _save() -> void: pass

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("MUTATION SESSION FAIL: ",message)

func wait_for(predicate: Callable, message: String) -> bool:
	var deadline=Time.get_ticks_msec()+5000
	while not predicate.call() and Time.get_ticks_msec()<deadline: await process_frame
	var ok=predicate.call();check(ok,message);return ok

func test_local_and_rotation() -> void:
	var ids=["angels_gift","ouroboros","chosen","astrology_waits"]
	var engine=GameEngine.new();engine.start({"field_rules":true,"field_selection":"mutation"},81503,1,[],[],"",0,ids)
	for local in range(4):
		var view=SeatView.for_seat(engine.view(local),local)
		check(FieldRules.for_seat(view.field,0)==ids[local],"local player's rule follows seat rotation")
		for relative in range(4):
			check(FieldRules.for_seat(view.field,relative)==ids[(relative+local)%4],"each relative seat retains the correct assignment")
		check(view.players[0].hand==engine.state.players[local].hand,"rotation retains own hand")
		check(view.players.slice(1).all(func(p):return p.hand.is_empty() and not p.has("field_private")),"public assignments do not expose concealed hands or powers' private results")
	check(engine.state.field.seat_rules==ids,"rotation does not mutate authoritative assignment")
	var local=MemorySession.new();root.add_child(local);local.set_process(false)
	local.start_match({"field_rules":true,"field_selection":"mutation"})
	var previous=local.engine.state.field.seat_rules.duplicate()
	local.engine._draw_result();local.next_round()
	check(local.engine.state.round==2 and local.engine.state.field.id=="mutation" and FieldRules.valid_assignment(local.engine.state.field.seat_rules),"local continuation keeps mutation and allocates four distinct rules again")
	check(local.engine.state.players.all(func(p):return not p.field_used),"new round resets all personal uses")
	local.free()
	var wire=LanSession.new()
	check(LanSession.PROTOCOL==4 and LanDiscovery.PROTOCOL==4,"discovery and game protocol upgraded together")
	for malformed in [null, [], ["chosen","chosen","rebirth","reclaim"], ["no_honors","chosen","rebirth","reclaim"]]:
		var view=engine.view(0);view.field.seat_rules=malformed
		check(not wire._valid_view(view),"invalid assignment rejected before rotating received view")
	wire.free()
	var room={"id":"mutation-qa","name":"突变房间","port":32141,"players":4,"started":false,"settings":{"jiang":"258","chi":true,"ai":"classic","field_rules":true,"field_selection":"mutation"}}
	check(LanDiscovery._validate_room(room,"127.0.0.1").get("settings",{}).get("field_selection","")=="mutation","discovery accepts host's mutation selection")

func test_network() -> void:
	var host=LanSession.new();root.add_child(host)
	var guests: Array=[]
	var port=52000+OS.get_process_id()%3000
	check(host.host_room({"field_rules":true,"field_selection":"mutation","ai":"classic"},"突变房主",port)==OK,"mutation host binds ENet")
	for index in range(3):
		var guest=LanSession.new();root.add_child(guest);guests.append(guest)
		check(guest.join_room("127.0.0.1","测试客人%d"%(index+1),port)==OK,"guest joins local test room")
		if not await wait_for(func():return guest.connected,"guest receives a seat"):
			await cleanup(host,guests);return
		guest.set_ready(true)
	if not await wait_for(func():return host.room.can_start,"all three guests ready"):
		await cleanup(host,guests);return
	check(host.start_room(),"host starts mutation")
	host.hold_presentation(600)
	if not await wait_for(func():return guests.all(func(guest):return not guest.current_view.is_empty()),"all guests receive initial assignment"):
		await cleanup(host,guests);return
	for guest in guests:
		check(guest.room.settings.field_selection=="mutation","room configuration agrees with mutation game")
		check(FieldRules.for_seat(guest.current_view.field,0)==FieldRules.for_seat(host.engine.state.field,guest.local_seat),"ENet delivers each guest's own rule after rotation")
	# Advance a real journal to guest 1's first ordinary draw. No forged state
	# or private draw is inserted, so the in-progress gift can also be replayed.
	var ids=["diamond_finger","angels_gift","ouroboros","astrology_waits"]
	host.engine.start(host.room.settings,82101,5,[],[],"",0,ids)
	var ai=MahjongAI.new();var steps=0
	while not (host.engine.decision_seat()==1 and host.engine.state.pending.any(func(move):return move.kind=="field_gift")) and host.engine.state.phase!="settled" and steps<80:
		var seat=host.engine.decision_seat();var choice=ai.choose(host.engine.view(seat),seat,0.5)
		check(host.engine.submit(seat,host.engine.state.revision,str(choice.id)),"journal reaches recipient's normal draw")
		steps+=1
	check(host.engine.decision_seat()==1 and host.engine.state.phase=="turn","gift recipient reaches ordinary turn")
	host._publish()
	if not await wait_for(func():return guests.all(func(guest):return guest.current_view.get("round")==5),"new mutation distribution reaches every seat"):
		await cleanup(host,guests);return
	var owner=guests[0]
	check(owner.local_seat==1 and FieldRules.for_seat(owner.current_view.field,0)=="angels_gift","gift owned only by first guest")
	var gifts=owner.current_view.pending.filter(func(move):return move.kind=="field_gift")
	var uses_before=host.engine.state.players.map(func(p):return p.field_used)
	check(gifts.size()==1,"recipient receives usable gift action")
	if gifts.is_empty():await cleanup(host,guests);return
	check(not host.play(str(gifts[0].id)) and not guests[1].play(str(gifts[0].id)) and not guests[2].play(str(gifts[0].id)),"other three humans cannot use recipient's action ID")
	check(owner.play(str(gifts[0].id)),"recipient activates gift through ENet")
	if await wait_for(func():return guests.all(func(guest):return guest.current_view.get("phase")=="gift_choice"),"private choice phase delivered"):
		check(owner.current_view.pending.size()==3 and owner.current_view.players[0].field_private.gift_tiles.size()==3,"only owner receives three candidates")
		for guest in [host,guests[1],guests[2]]:
			var recipient=SeatView.relative(1,guest.local_seat)
			check(guest.current_view.pending.is_empty() and not guest.current_view.players[recipient].has("field_private"),"other clients cannot inspect candidates")
		var restored=GameEngine.new();var snapshot=JSON.parse_string(JSON.stringify(host.engine.snapshot()))
		check(restored.restore(snapshot) and JSON.parse_string(JSON.stringify(restored.state))==snapshot.state,"v4 saves exact in-progress gift and original assignments")
		var revision=host.engine.state.revision
		check(owner.play(str(owner.current_view.pending[0].id)),"owner confirms original drawn tile")
		await wait_for(func():return host.engine.state.revision==revision+1 and host.engine.state.phase=="turn","gift completes via host authority")
		check(host.engine.state.players[1].field_used,"recipient's gift is consumed")
		for seat in [0,2,3]:check(host.engine.state.players[seat].field_used==uses_before[seat],"recipient's use does not consume anyone else's")
	host.engine._draw_result();host.next_round();host.hold_presentation(600)
	if await wait_for(func():return guests.all(func(guest):return guest.current_view.get("round")==6),"next mutation round reaches guests"):
		check(host.engine.state.field.id=="mutation" and FieldRules.valid_assignment(host.engine.state.field.seat_rules),"LAN continuation retains mode and new distinct assignment")
		for guest in guests:check(FieldRules.for_seat(guest.current_view.field,0)==FieldRules.for_seat(host.engine.state.field,guest.local_seat),"new assignments rotate correctly too")
	await cleanup(host,guests)

func cleanup(host: LanSession, guests: Array) -> void:
	var port=host._port
	for guest in guests:guest.leave_room();guest.queue_free()
	host.leave_room();host.queue_free()
	var deadline=Time.get_ticks_msec()+2500
	while root.get_child_count()>0 and Time.get_ticks_msec()<deadline:await process_frame
	check(root.get_child_count()==0,"all ENet peers and delayed drains retired")
	LanSession._host_drains.erase(port)
	for child in root.get_children():child.queue_free()
	await process_frame

func run() -> void:
	Engine.max_fps=60
	test_local_and_rotation()
	await test_network()
	print("FIELD_MUTATION_SESSION_RESULT: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
