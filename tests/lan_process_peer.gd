extends SceneTree
## One real process per seat. Used by tools/test_lan_process.ps1 against the
## exported Windows package; no scene or model is shared between processes.
var session: LanSession
var role = "host"
var directory = ""
var port = 0
var player_index = 0
var last_action = ""
var settled_at = -1
var sent_result = false

func _initialize() -> void:
	Engine.max_fps = 60
	var args = OS.get_cmdline_user_args()
	if args.size() != 4: printerr("Expected role, port, output directory, player index"); quit(1); return
	role = args[0]; port = int(args[1]); directory = args[2]; player_index = int(args[3])
	call_deferred("run")

func fail(reason: String) -> void:
	printerr("LAN_PROCESS_FAIL: ", role, " ", reason)
	quit(1)

func report(name: String, data: Dictionary) -> void:
	var file = FileAccess.open(directory.path_join(name + ".json"), FileAccess.WRITE)
	if file == null: fail("cannot write result"); return
	file.store_string(JSON.stringify(data)); file.close()

func run() -> void:
	create_timer(45).timeout.connect(func(): fail("timeout"))
	session = LanSession.new(); root.add_child(session)
	session.connection_closed.connect(func(reason):
		if not sent_result: fail(reason))
	if role == "host":
		if session.host_room({"jiang":"luan", "chi":false, "ai":"classic"}, "Windows 房主", port) != OK:
			fail("bind"); return
		report("listening", {"port":port})
	else:
		if session.join_room("127.0.0.1", "跨进程牌友%d" % player_index, port) != OK:
			fail("connect"); return
	while true:
		await process_frame
		if not session.connected: continue
		if not session.room.started:
			if role == "host":
				if session.room.seats.all(func(seat): return seat.occupied) and session.room.can_start: session.start_room()
			elif not session.room.seats[session.local_seat].ready: session.set_ready(true)
			continue
		var state = session.current_view
		if state.is_empty(): continue
		if state.round >= 2:
			var scores = [0,0,0,0]
			for relative in range(4): scores[(relative+session.local_seat)%4] = state.players[relative].score
			if not sent_result:
				report(role+str(player_index), {"seat":session.local_seat, "round":state.round, "scores":scores, "version":ProjectSettings.get_setting("application/config/version")})
				sent_result = true
			if role != "host":
				# Remain connected until the host records all confirmations.
				if FileAccess.file_exists(directory.path_join("complete.json")):
					session.leave_room(); await create_timer(0.2).timeout; quit(); return
			else:
				var finished = true
				for index in range(1,4): finished = finished and FileAccess.file_exists(directory.path_join("client%d.json" % index))
				if finished:
					report("complete", {"round":state.round, "scores":scores})
					await create_timer(0.5).timeout
					session.leave_room(); await create_timer(0.2).timeout
					print("LAN_PROCESS_RESULT: four processes completed a round and entered round 2")
					quit(); return
			continue
		if state.phase == "settled":
			if role == "host":
				if settled_at < 0: settled_at = Time.get_ticks_msec()
				elif Time.get_ticks_msec() - settled_at > 500: session.next_round()
			continue
		if state.decision_seat != 0 or state.pending.is_empty(): continue
		var key = "%d:%d" % [state.round,state.revision]
		if key == last_action: continue
		var choices = state.pending.filter(func(move): return move.kind == "win")
		if choices.is_empty(): choices = state.pending.filter(func(move): return move.kind in ["discard","pass"])
		if choices.is_empty(): choices = state.pending
		if session.play(str(choices[0].id), state.revision): last_action = key
