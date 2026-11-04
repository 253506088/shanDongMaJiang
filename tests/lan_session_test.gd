extends SceneTree

# Real UDP/ENet loopback traffic, with independent peers in one headless process.
# This does not claim Android radio, hotspot or firewall interoperability testing.
var checks = 0
var failures: Array = []
var sessions: Array = []
var port_base = 42000 + OS.get_process_id() % 10000
var port_index = 0

func _initialize() -> void:
	Engine.max_fps = 60
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("LAN FAIL: ", message)

func wait_for(predicate: Callable, message: String, timeout_ms: int = 5000) -> bool:
	var deadline = Time.get_ticks_msec() + timeout_ms
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	var ok: bool = predicate.call()
	check(ok, message)
	return ok

func tick(seconds: float = 0.15) -> void:
	await create_timer(seconds).timeout

func make_session() -> LanSession:
	var session = LanSession.new()
	session.storage_root = "user://qa-lan-%d/" % OS.get_process_id()
	root.add_child(session)
	sessions.append(session)
	return session

func new_port() -> int:
	port_index += 1
	return port_base + port_index

func cleanup() -> void:
	for session in sessions:
		if is_instance_valid(session): session.leave_room()
	await process_frame
	for session in sessions:
		if is_instance_valid(session): session.queue_free()
	sessions.clear()
	await process_frame

func run() -> void:
	var started = Time.get_ticks_msec()
	_test_seat_views()
	await _test_four_players()
	await cleanup()
	await _test_bots_and_reconnect()
	await cleanup()
	await _test_single_host()
	await cleanup()
	await _test_cancel_handshake()
	await cleanup()
	print("LAN_RESULT: %d checks, %d failures, %.2fs" % [checks, failures.size(), (Time.get_ticks_msec() - started) / 1000.0])
	quit(0 if failures.is_empty() else 1)

func _test_seat_views() -> void:
	var engine = GameEngine.new()
	engine.start({}, 71251)
	engine.state.last_discard = {"seat": 3, "tile": 13, "revision": 0}
	engine.state.event = {"kind": "peng", "seat": 2, "tile": 13}
	engine.state.current = 2
	engine.state.last_normal = 1
	engine.state.claim_from = 3
	engine.state.claim_seat = 2
	engine.state.players[2].melds = [{"type": "peng", "tile": 13, "tiles": [13,13,13], "from": 3}]
	engine.state.players[1].melds = [{"type": "angang", "tile": 5, "tiles": [5,5,5,5]}]
	engine._turn_options()
	var authoritative = engine.state.duplicate(true)
	for seat in range(4):
		var source = engine.view(seat)
		var original = source.duplicate(true)
		var view = SeatView.for_seat(source, seat)
		check(view.players[0].hand == engine.state.players[seat].hand, "seat %d has own hand at bottom" % seat)
		for relative in range(4):
			var actual = (relative + seat) % 4
			check(view.players[relative].seat == relative, "seat %d player %d uses relative seat" % [seat, relative])
			check(view.players[relative].score == engine.state.players[actual].score, "relative score belongs to player")
			if relative != 0: check(view.players[relative].hand.is_empty(), "other concealed hand is not transmitted")
		check(view.current == posmod(2-seat, 4) and view.dealer == posmod(-seat, 4), "turn and dealer rotate together")
		check(view.decision_seat == posmod(2-seat, 4), "decision rotates to correct player")
		check(view.claim_from == posmod(3-seat, 4) and view.claim_seat == posmod(2-seat, 4), "claim target seats rotate")
		check(view.last_normal == posmod(1-seat, 4), "last normal draw seat rotates")
		check(view.event.seat == posmod(2-seat, 4) and view.last_discard.seat == posmod(3-seat, 4), "animation and discard target rotate")
		check(view.players[posmod(2-seat,4)].melds[0].from == posmod(3-seat,4), "called tile direction rotates")
		var hidden_kong = view.players[posmod(1-seat,4)].melds[0]
		check(hidden_kong.tile == (5 if seat == 1 else -1), "concealed kong privacy survives rotation")
		check(view.pending.is_empty() == (seat != 2), "only decision owner sees actions")
		check(not view.has("wall") and not view.has("claim_queue") and not view.has("journal") and not view.has("opening"), "private authority state absent")
		check(source == original and engine.state == authoritative, "view conversion does not mutate authority or source")
		check(view.wall_slots.size() == source.wall_count and view.wall_slots.back() == (source.wall_slots.back()+seat*36)%144, "wall tile count and public tail move with the seat")
		var reversed = SeatView.for_seat(view, (4-seat)%4)
		check(reversed.wall_slots == source.wall_slots, "inverse seat rotation restores every physical wall slot in order")
		var slots_seen: Dictionary = {}
		for slot in view.wall_slots: slots_seen[slot] = true
		check(slots_seen.size() == view.wall_slots.size(), "rotated wall never overlaps physical slots")
	engine.state.phase = "settled"
	engine.state.result = {"draw": false, "winner": 3, "source": 1, "deltas": [-10,-20,-30,60], "win_tile": 13}
	for seat in range(4):
		var view = SeatView.for_seat(engine.view(seat), seat)
		check(view.result.winner == posmod(3-seat,4) and view.result.source == posmod(1-seat,4), "settlement winner and payer rotate")
		for relative in range(4):
			check(view.result.deltas[relative] == engine.state.result.deltas[(relative+seat)%4], "settlement payments rotate with names")
	engine.state.result = {"draw": true, "winner": -1, "source": -1, "deltas": [0,0,0,0]}
	engine.state.last_normal = -1
	engine.state.claim_from = -1
	engine.state.claim_seat = -1
	var draw_view = SeatView.for_seat(engine.view(3), 3)
	check(draw_view.result.winner == -1 and draw_view.result.source == -1 and draw_view.claim_from == -1 and draw_view.claim_seat == -1 and draw_view.last_normal == -1, "negative no-seat sentinels remain negative")

func _test_four_players() -> void:
	var host = make_session()
	var port = new_port()
	check(host.host_room({"jiang":"258", "chi":true, "ai":"classic", "rounds":4}, "房主", port) == OK, "host binds real ENet socket")
	host.ai_rng.seed = 564712
	check(host.is_host and host.local_seat == 0 and host.connected, "host takes first seat")
	var clients: Array = []
	for index in range(3):
		var client = make_session()
		clients.append(client)
		check(client.join_room("127.0.0.1", "牌友%d" % (index+1), port) == OK, "join starts real connection")
		if not await wait_for(func(): return client.local_seat == index+1 and client.connected, "client %d gets own seat" % (index+1)): return
	if not await wait_for(func(): return host.room.seats.filter(func(s): return s.occupied).size() == 4, "four human seats visible to host"): return
	check(not host.start_room(), "host cannot start before guests ready")
	for client in clients: client.set_ready(true)
	if not await wait_for(func(): return host.room.can_start, "all ready enables host start"): return
	check(not clients[0].set_room_settings({"jiang":"luan", "chi":false, "ai":"efficiency"}), "guest cannot change room settings")
	check(host.set_room_settings({"jiang":"luan", "chi":false, "ai":"efficiency"}), "host changes pregame rules")
	if not await wait_for(func(): return clients[0].room.settings.jiang == "luan" and not clients[0].room.seats[1].ready, "rule change publishes and clears guest consent"): return
	check(not host.room.can_start and not host.start_room(), "changed rules require guests to ready again")
	check(not clients[0].start_room(), "guest cannot start room")
	var outsider = make_session()
	var rejected: Array = []
	outsider.notice.connect(func(message): rejected.append(message))
	outsider.connection_closed.connect(func(message): rejected.append(message))
	check(outsider.join_room("127.0.0.1", "第五位", port) == OK, "fifth connection reaches server")
	await wait_for(func(): return not rejected.is_empty(), "full room reports rejection")
	check(outsider.local_seat < 0, "full room never allocates fifth seat")
	outsider.leave_room()
	for client in clients: client.set_ready(true)
	if not await wait_for(func(): return host.room.can_start, "all guests re-ready after changed rules"): return
	check(host.start_room(), "host starts four-player game")
	if not await wait_for(func(): return clients.all(func(c): return not c.current_view.is_empty()), "all guests receive private game views"): return
	check(host.engine.state.settings.jiang == "luan" and not host.engine.state.settings.chi and host.engine.state.settings.rounds == 0, "chosen rules locked into unlimited LAN game")
	check(not host.set_room_settings({"jiang":"258", "chi":true, "ai":"classic"}), "host cannot change rules during game")
	check(host.room.seats.all(func(s): return not s.bot), "four humans do not get robot controllers")
	check(not JSON.stringify(clients[0].room).contains("token") and not JSON.stringify(clients[0].room).contains("peer"), "public room never exposes another player's credentials or connection IDs")
	_check_private_views(host, clients)
	var original_revision: int = host.engine.state.revision
	var host_action = host.engine.state.pending[0].id
	check(not host.play("forged-action", original_revision), "invalid host action rejected")
	check(not host.play(host_action, original_revision+1), "future revision rejected")
	clients[0].play(host_action, original_revision)
	clients[0]._send(1, {"kind":"action", "seat":0, "id":host_action, "revision":original_revision, "round":host.engine.state.round})
	await tick()
	check(host.engine.state.revision == original_revision, "forged seat in actual network packet cannot play host's legal action")
	var remote_played = false
	for step in range(12):
		if host.engine.state.phase == "settled": break
		var seat: int = host.engine.decision_seat()
		var actor: LanSession = host if seat == 0 else clients[seat-1]
		if not await wait_for(func(): return actor.current_view.revision == host.engine.state.revision, "acting seat receives current revision"): return
		var moves: Array = actor.current_view.pending
		check(not moves.is_empty(), "acting human has selectable legal action")
		if moves.is_empty(): break
		var passive = moves.filter(func(m): return m.kind in ["discard", "pass"])
		var move = passive[0] if not passive.is_empty() else moves[0]
		var revision: int = host.engine.state.revision
		if seat != 0:
			actor._send(1, {"kind":"action", "id":move.id, "revision":revision, "round":host.engine.state.round-1})
			await tick(0.05)
			check(host.engine.state.revision == revision, "previous-round packet cannot reuse this round's legal ID")
		actor.play(move.id, revision)
		if not await wait_for(func(): return host.engine.state.revision > revision, "real network action reaches authority"): return
		if seat == 0: actor.play(move.id, revision)
		else: actor._send(1, {"kind":"action", "id":move.id, "revision":revision, "round":host.engine.state.round})
		await tick(0.05)
		check(host.engine.state.revision == revision+1, "duplicate stale action is applied at most once")
		remote_played = remote_played or seat != 0
		if remote_played: break
	check(remote_played, "a remote seated human completes a real game decision")
	await tick()
	_check_private_views(host, clients)
	host.engine.state.event = {"kind":"angang", "seat":1, "tile":5}
	host.engine.state.revision += 1
	host._publish()
	if not await wait_for(func(): return clients.all(func(c): return c.current_view.revision == host.engine.state.revision), "concealed kong event reaches all peers"): return
	check(host.current_view.event.tile == -1 and clients[0].current_view.event.tile == 5 and clients[1].current_view.event.tile == -1 and clients[2].current_view.event.tile == -1, "concealed kong animation reveals tile only to its owner")
	var round_before: int = host.engine.state.round
	clients[0].next_round()
	await tick()
	check(host.engine.state.round == round_before, "guest cannot advance an active round")
	# A controlled settlement isolates room lifecycle from the separately tested
	# engine scoring, while keeping names and payments attached to real seats.
	var scores = [1900,2050,2020,2030]
	host.engine.start(host.room.settings, 81521, 8, scores)
	host.engine._draw_result()
	host._publish()
	await tick()
	clients[0].next_round()
	await tick()
	check(host.engine.state.round == 8, "guest cannot start next round after settlement")
	host.next_round()
	if not await wait_for(func(): return clients[0].current_view.round == 9, "host publishes ninth round to guests"): return
	check(host.engine.state.dealer == 0 and host.engine.state.players.map(func(p): return p.score) == scores, "rounds continue past eight, dealer rotates and scores persist once")
	host.next_round()
	check(host.engine.state.round == 9, "repeated next-round request cannot skip an active round")
	check(not FileAccess.file_exists(host.storage_root+"current_match.json"), "LAN does not overwrite local match save")
	var closed: Array = []
	clients[0].connection_closed.connect(func(message): closed.append(message))
	host.leave_room()
	host.queue_free()
	var replacement = make_session()
	check(replacement.host_room({}, "马上重建", port) == OK, "host can immediately recreate room on the same port")
	await wait_for(func(): return not clients[0].connected and not closed.is_empty(), "host leaving closes guest room with a reason")

func _check_private_views(host: LanSession, clients: Array) -> void:
	for seat in range(4):
		var session: LanSession = host if seat == 0 else clients[seat-1]
		var view: Dictionary = session.current_view
		check(not view.is_empty(), "private view exists for seat %d" % seat)
		if view.is_empty(): continue
		check(view.players[0].hand == host.engine.state.players[seat].hand, "wire view contains exactly receiver's hand")
		check(view.players[0].name == host.room.seats[seat].name, "wire hand and nickname stay together")
		check(not view.has("wall") and not view.has("journal") and not view.has("opening") and not view.has("claim_queue"), "wire view contains no full authority snapshot")
		for relative in range(1,4):
			if not view.players[relative].ming and view.phase != "settled":
				check(view.players[relative].hand.is_empty(), "wire view does not expose opponent dark hand")
		check(view.decision_seat == posmod(host.engine.decision_seat()-seat,4) or host.engine.decision_seat() == -1, "wire decision seat is relative to receiver")

func _test_bots_and_reconnect() -> void:
	var host = make_session()
	var client = make_session()
	var port = new_port()
	check(host.host_room({"ai":"classic"}, "热点房主", port) == OK, "second room binds independent port")
	check(client.join_room("127.0.0.1", "安卓席", port) == OK, "second room joins")
	if not await wait_for(func(): return client.connected and client.local_seat == 1, "second human joins two-player room"): return
	client.set_ready(true)
	if not await wait_for(func(): return host.room.can_start, "one ready guest enables start with two empty seats"): return
	check(host.start_room(), "two-player room starts with bots")
	check(host.room.seats.filter(func(s): return s.bot).size() == 2, "exactly two empty seats become robots")
	var late = make_session()
	var late_errors: Array = []
	late.notice.connect(func(message): late_errors.append(message))
	late.connection_closed.connect(func(message): late_errors.append(message))
	late.join_room("127.0.0.1", "迟到牌友", port)
	await wait_for(func(): return not late_errors.is_empty(), "started room reports late join rejection")
	check(late.local_seat < 0, "new guest cannot replace bot after start")
	late.leave_room()
	# Begin a fresh real engine opening whose dealer is an empty robot seat.
	host.engine.start(host.room.settings, 91314, 3)
	host._publish()
	host.delay = 0.01
	host.speed = 20.0
	await wait_for(func(): return host.engine.state.revision > 0, "empty robot seat makes an actual engine move", 10000)
	host._join_worker()
	# Reset to a complete legal opening whose dealer is the human guest.
	host.engine.start(host.room.settings, 71513, 6)
	host.delay = 0.01
	host._publish()
	if not await wait_for(func(): return client.current_view.round == 6 and client.current_view.decision_seat == 0, "guest sees own turn before disconnection"): return
	check(not host.room.disconnect_autoplay, "disconnected-human autoplay is off by default")
	client._peer.close()
	if not await wait_for(func(): return not host.room.seats[1].connected, "socket loss marks reserved human seat offline", 15000): return
	var waiting_revision: int = host.engine.state.revision
	await tick(0.4)
	check(host.engine.state.revision == waiting_revision and host.worker == null, "offline human remains reserved and is not auto-played by default")
	host.set_disconnect_autoplay(true)
	await wait_for(func(): return host.engine.state.revision > waiting_revision, "host can enable robot control for offline human", 10000)
	host.set_disconnect_autoplay(false)
	host._join_worker()
	host.hold_presentation(10.0)
	check(client.reconnect_room() == OK, "same client starts credentialed reconnect")
	if not await wait_for(func(): return client.connected and client.local_seat == 1 and host.room.seats[1].connected, "reconnect restores original reserved seat", 10000): return
	check(not host.room.seats[1].autopilot and not client.autopilot, "returning human recovers manual control")
	check(client.current_view.players[0].hand == host.engine.state.players[1].hand, "reconnected human receives fresh own hand")
	check(host.room.seats.filter(func(s): return s.occupied).size() == 2, "reconnect does not allocate a duplicate human seat")
	client.leave_room()
	client.queue_free()
	await wait_for(func(): return host.room.seats[1].bot, "explicit departure releases played seat to bot")

func _test_single_host() -> void:
	var host = make_session()
	check(host.host_room({"jiang":"258", "chi":true, "ai":"classic"}, "单人建房", new_port()) == OK, "single host can create room")
	check(host.room.can_start and host.start_room(), "single host can start without waiting for absent players")
	check(host.room.seats.filter(func(s): return s.bot).size() == 3, "single host receives exactly three robot opponents")
	check(host.engine.state.players.size() == 4, "bot fill always produces four playing seats")

func _test_cancel_handshake() -> void:
	var host = make_session()
	var client = make_session()
	host.set_process(false)
	client.set_process(false)
	var port = new_port()
	check(host.host_room({}, "取消加入房间", port) == OK, "handshake cancellation fixture creates room")
	check(client.join_room("127.0.0.1", "正在连接", port) == OK, "handshake cancellation opens real client")
	var deadline = Time.get_ticks_msec()+5000
	while not client._hello_sent and Time.get_ticks_msec() < deadline:
		host._process(1.0/60.0)
		client._process(1.0/60.0)
		if client._hello_sent: break
		await process_frame
	check(client._hello_sent and not client.connected, "client sends admission request before receiving welcome")
	if not client._hello_sent: return
	client._peer.host.flush()
	deadline = Time.get_ticks_msec()+5000
	while not host.room.seats[1].occupied and Time.get_ticks_msec() < deadline:
		host._process(1.0/60.0)
		await process_frame
	check(host.room.seats[1].occupied and not client.connected, "host reserves seat while client still waits for welcome")
	client.leave_room()
	client.queue_free()
	host.set_process(true)
	await wait_for(func(): return not host.room.seats[1].occupied, "cancelling half-completed admission releases reserved seat immediately")
	check(host.room.can_start and host._peer_seats.is_empty(), "cancelled handshake leaves no ghost member or connection binding")
