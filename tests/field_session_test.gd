extends SceneTree

var checks = 0
var failures: Array = []

class MemorySession extends LocalSession:
	func _save() -> void:
		pass

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("FIELD_SESSION_FAIL: ", message)

func fixture(field_id: String = "") -> Dictionary:
	var players: Array = []
	for seat in range(4):
		players.append({"seat": seat, "hand": [], "melds": [], "discards": [], "bao": false, "ming": false, "drawn": -1})
	players[0].hand = [0,1,2,3,4,5,9,10,11,18,19,20,22]
	return {"field": {"id": field_id}, "phase": "turn", "players": players, "pending": [],
		"gang_head": -1, "wall_count": 40, "settings": {"ai": "classic", "jiang": "258", "chi": true},
		"dealer": 0, "current": 0, "decision_seat": 0, "claim_from": -1, "claim_seat": -1,
		"last_normal": -1, "event": {}, "last_discard": {}, "result": {}, "revision": 1, "round": 1}

func run() -> void:
	Engine.max_fps = 60
	_test_wire_contract()
	_test_local_selection()
	_test_seat_rotation()
	_test_abilities_stay_manual()
	_test_ai_choices()
	_test_ai_field_shapes()
	await _test_field_discovery()
	await _test_field_network()
	print("FIELD_SESSION_RESULT: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_wire_contract() -> void:
	var session = LanSession.new()
	check(LanSession.PROTOCOL == 3 and LanDiscovery.PROTOCOL == 3, "discovery and ENet reject clients using the previous gift flow")
	check(not session._settings({}).field_rules, "nearby room defaults to ordinary play")
	check(session._settings({}).field_selection == "random", "missing selection keeps compatible random default")
	check(session._settings({"field_rules": true}).field_rules, "host field toggle survives sanitization")
	check(not session._settings({"field_rules": "true"}).field_rules, "string is not a field toggle")
	for selection in ["random", "angels_gift", "chosen"]:
		var normalized = session._settings(LanSession._integers(JSON.parse_string(JSON.stringify({"field_rules":true, "field_selection":selection}))))
		check(normalized.field_rules and normalized.field_selection==selection, "JSON settings preserve selection " + selection)
	check(session._settings({"field_rules":false, "field_selection":"chosen"}).field_selection=="chosen", "switching fields off does not forget chosen field")
	for invalid in ["unknown_field", 5, null, []]:
		check(session._settings({"field_rules":true, "field_selection":invalid}).field_selection=="random", "invalid local selection normalizes safely")
	for phase in ["draw_choice", "gift_choice", "exchange"]:
		var view = fixture("angels_gift"); view.phase = phase
		check(session._valid_view(view), phase + " accepted by new wire protocol")
		view.wall = [1,2,3]
		check(not session._valid_view(view), phase + " cannot carry an authority wall")
	var private_view = fixture("angels_gift"); private_view.gift_slots = [1,2,3]
	check(not session._valid_view(private_view), "wire validator rejects authority-only gift slot pool")
	var advertised = {"id":"field-test", "name":"场地牌桌", "port":32141, "players":2, "started":false,
		"settings":{"jiang":"258", "chi":false, "ai":"classic", "field_rules":true, "field_selection":"chosen"}}
	var parsed = LanDiscovery._validate_room(advertised, "127.0.0.1")
	check(not parsed.is_empty() and parsed.settings.field_rules and not parsed.settings.chi, "discovery carries independent enhancement and eating switches")
	check(parsed.settings.field_selection=="chosen", "discovery keeps the selected field for room labels")
	advertised.settings.field_rules = "yes"
	check(LanDiscovery._validate_room(advertised, "127.0.0.1").is_empty(), "discovery rejects malformed enhancement flag")
	advertised.settings.field_rules = true
	for invalid in ["unknown_field", 5, null, []]:
		advertised.settings.field_selection = invalid
		check(LanDiscovery._validate_room(advertised, "127.0.0.1").is_empty(), "discovery rejects malformed advertised selection")
		var view = fixture(); view.settings.field_selection = invalid
		check(not session._valid_view(view), "wire view rejects malformed selected-field metadata")
	session.free()

func _test_local_selection() -> void:
	var session = MemorySession.new()
	session.engine.start({"field_rules":true, "field_selection":"chosen"}, 8117)
	check(session.engine.state.field.id=="chosen", "local engine opens the specifically selected field")
	var scores = session.engine.state.players.map(func(player):return player.score)
	session.engine._draw_result(); session.next_round()
	check(session.engine.state.round==2 and session.engine.state.field.id=="chosen" and session.engine.state.settings.field_selection=="chosen", "local next round preserves a fixed field selection")
	check(session.engine.state.players.map(func(player):return player.score)==scores, "fixed-field next round preserves cumulative scores")
	session.engine.start({"field_rules":true, "field_selection":"random"}, 8117)
	session.engine._draw_result(); session.next_round()
	check(session.engine.state.settings.field_selection=="random", "random field selection remains random for next round")
	session.engine.start({"field_rules":false, "field_selection":"chosen"}, 8117)
	session.engine._draw_result(); session.next_round()
	check(not session.engine.state.has("field") and session.engine.state.settings.field_selection=="chosen", "disabled field stays normal while remembering selected choice")
	session.free()

func _test_seat_rotation() -> void:
	var original = fixture("astrology_waits")
	original.current = 2; original.decision_seat = 2
	original.players[2].field_private = {"peek_target": 1, "peek_waits": [4,13]}
	original.pending = [{"kind":"field_peek_waits", "target":3, "id":"0"}]
	original.event = {"kind":"field_peek_waits", "seat":2, "target":1}
	var rotated = SeatView.for_seat(original, 2)
	check(rotated.players[0].field_private.peek_target == 3, "private astrology target rotates with local seat")
	check(rotated.pending[0].target == 1 and rotated.pending[0].id == "0", "target labels rotate without changing legal ID")
	check(rotated.event.seat == 0 and rotated.event.target == 3, "ability event owner and target rotate together")
	check(original.players[2].field_private.peek_target == 1 and original.pending[0].target == 3, "rotation leaves authoritative view unchanged")

func _test_abilities_stay_manual() -> void:
	for kind in ["field_rebirth", "field_transform", "field_reclaim", "field_peek_wall", "field_peek_waits", "field_gift"]:
		var local = LocalSession.new()
		var state = fixture(); state.players[0].hand.append(27)
		state.players[0].drawn = 13; state.players[0].bao = true
		state.pending = [{"kind":"discard", "index":13, "tile":27, "id":"0"}, {"kind":kind, "id":"1"}]
		local.engine.state = state
		check(local.locked_discard_action().is_empty(), "local auto-discard preserves " + kind)
		var lan = LanSession.new(); lan.engine.state = state.duplicate(true)
		check(lan._locked_discard(0).is_empty(), "LAN auto-discard preserves " + kind)
		state.pending.pop_back()
		check(local.locked_discard_action().get("id") == "0", "local automation resumes after ability use")
		lan.engine.state.pending.pop_back()
		check(lan._locked_discard(0).get("id") == "0", "LAN automation resumes after ability use")
		local.free(); lan.free()

func _test_ai_choices() -> void:
	var ai = MahjongAI.new()
	var view = fixture("angels_gift")
	view.phase = "draw_choice"
	view.pending = [{"kind":"draw_normal", "id":"0"}, {"kind":"field_gift", "id":"1"}]
	check(ai.choose(view, 0).kind == "field_gift", "robot still handles the version-two pre-draw gift phase")
	view.phase = "gift_choice"
	view.pending = [{"kind":"field_gift_pick", "tile":27, "index":0, "id":"0"},
		{"kind":"field_gift_pick", "tile":22, "index":1, "id":"1"}, {"kind":"field_gift_pick", "tile":30, "index":2, "id":"2"}]
	check(ai.choose(view, 0).tile == 22, "robot selects useful tile from private three-tile offer")
	view = fixture("angels_gift")
	view.players[0].hand.append(27); view.players[0].drawn = 13
	view.pending = [{"kind":"field_gift", "id":"0"}, {"kind":"discard", "index":13, "tile":27, "id":"1"}]
	check(ai.choose(view, 0).kind=="field_gift", "robot uses after-draw gift when the current draw is isolated")
	view.players[0].hand[-1] = 22
	view.pending = [{"kind":"field_gift", "id":"0"}, {"kind":"discard", "index":13, "tile":22, "id":"1"}]
	check(ai.choose(view, 0).kind=="discard", "robot keeps a useful complete draw instead of always spending gift")
	view.pending.append({"kind":"win", "id":"2"})
	check(ai.choose(view, 0).kind=="win", "immediate legal win has priority over gift")
	view = fixture("exchange"); view.phase = "exchange"
	view.pending = [{"kind":"field_exchange", "indices":[0,1,2], "tiles":[0,1,2], "id":"0"},
		{"kind":"field_exchange", "indices":[3,4,5], "tiles":[3,4,5], "id":"1"}]
	check(ai.choose(view, 0) in view.pending, "robot chooses a legal opening exchange without waiting for discards")
	view = fixture("astrology_wall"); view.players[0].hand.append(27)
	view.pending = [{"kind":"discard", "index":13, "tile":27, "id":"0"}, {"kind":"field_peek_wall", "id":"1"}]
	check(ai.choose(view, 0).kind == "field_peek_wall", "robot uses wall knowledge without reading authority wall")
	view = fixture("astrology_waits"); view.players[0].hand.append(27)
	view.players[2].bao = true
	view.pending = [{"kind":"field_peek_waits", "target":1, "id":"0"}, {"kind":"field_peek_waits", "target":2, "id":"1"}]
	check(ai.choose(view, 0).target == 2, "robot inspects opponent who has privately declared")
	view = fixture("rebirth"); view.players[0].hand.append(27)
	view.players[0].bao = true; view.players[0].drawn = 13
	view.players[1].melds = [{"type":"peng", "tile":22, "tiles":[22,22,22]}]
	view.pending = [{"kind":"discard", "index":13, "tile":27, "id":"0"}, {"kind":"field_rebirth", "id":"1"}]
	check(ai.choose(view, 0).kind == "field_rebirth", "robot can revoke a dead wait using public tile evidence")
	view = fixture("transparent"); view.players[0].hand.append(27)
	view.players[1].hand = [22,-1,3,-1]
	check(ai._visible_tiles(view, 0).count(22) == 2 and -1 not in ai._visible_tiles(view, 0), "robot counts transparent faces but never unknown placeholders")
	view = fixture("no_honors")
	view.field.tile_totals = []; view.field.tile_totals.resize(42); view.field.tile_totals.fill(4)
	view.field.tile_totals[22] = 7
	view.players[0].hand.append(27)
	var normal = ai.rank(view.players[0].hand, [], false, view.players[0].hand, true)
	var enlarged = ai.rank(view.players[0].hand, [], false, view.players[0].hand, true, "no_honors", view.field.tile_totals)
	check(enlarged[0].remaining == normal[0].remaining + 3, "robot uses published greater-than-four tile supply")

func _test_ai_field_shapes() -> void:
	var ai = MahjongAI.new()
	var circular = [0,7,8,9,10,11,18,19,20,24,25,26,4]
	check(ai.rank(circular + [27], [], false, circular + [27], true, "ouroboros")[0].waits.has(4), "robot recognizes a circular sequence wait")
	var honors = [27,29,31,9,10,11,18,19,20,24,25,26,4]
	check(ai.rank(honors + [32], [], false, honors + [32], true, "honor_sequences")[0].waits.has(4), "robot recognizes the honor sequence field")
	check(ai.shanten(circular, [], false, "ouroboros") <= ai.shanten(circular, [], false), "field shanten uses the additional circular group")
	check(ai.utility(31, [31,1,2], false, "wildcard") > ai.utility(31, [31,1,2], false), "wildcard heuristic protects red dragon")

func _wait_for(predicate: Callable, message: String) -> bool:
	var deadline = Time.get_ticks_msec() + 5000
	while not predicate.call() and Time.get_ticks_msec() < deadline: await process_frame
	var success: bool = predicate.call()
	check(success, message)
	return success

func _test_field_discovery() -> void:
	var host = LanDiscovery.new(); var browser = LanDiscovery.new()
	host.discovery_port = 61000 + OS.get_process_id() % 2000
	browser.discovery_port = host.discovery_port; browser.query_addresses = ["127.0.0.1"]
	root.add_child(host); root.add_child(browser)
	var room = {"id":"selected-field-discovery", "name":"自选场地牌桌", "port":32141, "started":false,
		"seats":[{"occupied":true}], "settings":{"jiang":"258", "chi":true, "ai":"classic", "field_rules":true, "field_selection":"angels_gift"}}
	check(host.start_host(room)==OK and browser.start_browser()==OK, "selected-field discovery opens real loopback sockets")
	if await _wait_for(func():return browser.get_rooms().size()==1, "selected-field room arrives over UDP discovery"):
		check(browser.get_rooms()[0].settings.field_selection=="angels_gift", "UDP summary preserves a specifically selected field")
		room.settings.field_selection = "random"; host.update_room(room); browser.countdown = 0.0
		await _wait_for(func():return not browser.get_rooms().is_empty() and browser.get_rooms()[0].settings.field_selection=="random", "UDP summary refreshes when host changes selection to random")
	host.stop(); browser.stop(); host.queue_free(); browser.queue_free()
	await process_frame

func _test_field_network() -> void:
	var host = LanSession.new(); var guest = LanSession.new()
	root.add_child(host); root.add_child(guest)
	var port = 54000 + OS.get_process_id() % 5000
	check(host.host_room({"field_rules": true, "field_selection":"chosen", "ai": "classic"}, "场地主机", port) == OK, "field host binds real loopback listener")
	check(guest.join_room("127.0.0.1", "场地客人", port) == OK, "field guest opens real ENet client")
	if not await _wait_for(func(): return guest.connected, "new protocol completes real field-room handshake"):
		await _close_network(host, guest); return
	check(guest.room.settings.field_rules, "guest receives host's field enhancement setting")
	check(guest.room.settings.field_selection=="chosen", "guest receives specifically selected field")
	guest.set_ready(true)
	if not await _wait_for(func(): return host.room.can_start, "field guest readiness reaches host"):
		await _close_network(host, guest); return
	check(host.start_room(), "field host starts a real room")
	check(host.engine.state.field.id=="chosen", "LAN starts with the host-selected field")
	host.hold_presentation(60.0)
	host.engine.start(host.room.settings, 9021, 2, [], [], "exchange")
	host._publish()
	if not await _wait_for(func(): return guest.current_view.get("phase") == "exchange", "opening exchange phase passes wire validation"):
		await _close_network(host, guest); return
	check(guest.current_view.players[0].hand == host.engine.state.players[1].hand, "exchange view keeps receiver's own concealed hand")
	check(not guest.current_view.has("exchange_picks"), "unrevealed exchange selections never enter guest view")
	var wire = {"kind":"view", "view":host._seat_view(host.engine.decision_seat()), "protocol":LanSession.PROTOCOL, "app":LanSession.APP_ID}
	check(JSON.stringify(wire).to_utf8_buffer().size() < LanSession.MAX_PACKET, "all opening three-tile choices fit the bounded packet")
	var actor = host.engine.decision_seat()
	check(actor == 1, "exchange opening starts with current dealer")
	if actor == 1:
		var before: int = host.engine.state.revision
		check(guest.play(str(guest.current_view.pending[0].id)), "guest sends a legal three-tile selection")
		await _wait_for(func(): return host.engine.state.revision == before + 1, "guest exchange action reaches authority exactly once")
	# Use later round IDs so client stale-view rejection remains active while
	# controlled engine starts isolate each field from a full game simulation.
	host.engine.start(host.room.settings, 9021, 5, [], [], "astrology_wall")
	host._publish()
	var inspect = host.engine.state.pending.filter(func(move): return move.kind == "field_peek_wall")
	check(not inspect.is_empty(), "host receives astrology as a legal field action")
	if not inspect.is_empty():
		check(host.play(str(inspect[0].id)), "host uses private astrology through session action path")
	if await _wait_for(func(): return guest.current_view.get("round") == 5 and guest.current_view.get("revision") == 1, "private astrology update reaches guest"):
		check(host.current_view.players[0].field_private.peek_wall.size() == 4, "ability owner receives exactly four preview tiles")
		check(not guest.current_view.players[3].has("field_private"), "remote opponent receives no astrology results")
	host.engine.start(host.room.settings, 9021, 6, [], [], "transparent"); host._publish()
	if await _wait_for(func(): return guest.current_view.get("round") == 6, "transparent field survives ENet delivery"):
		for relative in range(1,4):
			var player: Dictionary = guest.current_view.players[relative]
			check(player.hand.size() == player.hand_count, "transparent remote hand preserves physical slots")
		check(not guest.current_view.has("wall_hidden") and not guest.current_view.has("wall"), "transparent field never sends wall identities or hidden mask")
	host.engine.start(host.room.settings, 9021, 7, [], [], "angels_gift")
	host.engine._draw(1); host._publish()
	if await _wait_for(func(): return guest.current_view.get("round") == 7 and guest.current_view.get("phase") == "turn", "gift field draws normally before human guest chooses ability"):
		var original_draw: int = host.engine.state.players[1].hand[host.engine.state.players[1].drawn]
		var original_wall: Array = host.engine.state.wall.duplicate()
		check(guest.current_view.players[0].hand.back()==original_draw and not guest.current_view.pending.any(func(move):return move.kind=="draw_normal"), "guest already sees original draw and is not stopped at a draw gate")
		var gifts = guest.current_view.pending.filter(func(move): return move.kind == "field_gift")
		check(not gifts.is_empty() and guest.play(str(gifts[0].id)), "guest activates gift from an ordinary drawn turn")
		if await _wait_for(func(): return guest.current_view.get("phase") == "gift_choice", "gift selection phase reaches human guest"):
			check(guest.current_view.pending.size() == 3 and guest.current_view.players[0].field_private.gift_tiles.size() == 3, "only drawing guest receives three candidates")
			check(guest.current_view.players[0].field_private.gift_tiles==[original_draw, original_wall[0], original_wall[1]], "gift candidates include original drawn tile plus next two")
			check(not host.current_view.players[1].has("field_private") and host.current_view.pending.is_empty(), "host's own playing view does not reveal guest candidates")
			check(not guest.current_view.has("gift_slots") and guest.current_view.players.all(func(player):return not player.has("gift_draw_slot")), "gift candidate and draw slot bookkeeping stays off the wire")
			var before: int = host.engine.state.revision
			check(guest.play(str(guest.current_view.pending[0].id)), "guest may keep the original drawn tile")
			await _wait_for(func(): return host.engine.state.revision == before + 1 and host.engine.state.phase == "turn", "private gift pick returns to ordinary play")
			check(host.engine.state.players[1].hand.back()==original_draw and host.engine.state.wall==original_wall, "keeping original tile restores the extra candidates in original wall order")
			check(not host.engine.state.pending.any(func(move):return move.kind=="field_gift"), "used gift cannot be offered twice")
	host.engine._draw_result(); host.next_round(); host.hold_presentation(60.0)
	if await _wait_for(func():return guest.current_view.get("round")==8, "fixed-field next round reaches guest"):
		check(host.engine.state.field.id=="chosen" and guest.current_view.field.id=="chosen", "LAN next round returns to room's fixed field selection")
		check(guest.current_view.settings.field_selection=="chosen" and guest.room.settings.field_selection=="chosen", "wire game and room retain matching field selection")
	await _close_network(host, guest)

func _close_network(host: LanSession, guest: LanSession) -> void:
	var port = host._port
	guest.leave_room(); host.leave_room()
	var drains = root.get_children().filter(func(node): return node is LanSession.PeerDrain).size()
	guest.queue_free(); host.queue_free()
	# leave_room() deliberately transfers ENet ownership to PeerDrain for up
	# to one second. Finish that handshake while the scene tree is still alive
	# instead of letting native peers survive into engine shutdown.
	var started = Time.get_ticks_msec()
	while root.get_child_count() > 0 and Time.get_ticks_msec()-started < 2500:
		await process_frame
	check(root.get_child_count()==0, "network peers and teardown nodes finish before engine shutdown")
	# This headless fixture owns every child in its root. On a failed cleanup,
	# still release them normally so the assertion is reported without peers
	# being left to the engine's final destructor order.
	for child in root.get_children(): child.queue_free()
	LanSession._host_drains.erase(port)
	await process_frame
	await process_frame
	print("FIELD_SESSION_TEARDOWN: %d drain(s), %d root nodes remain, %d ms" % [drains, root.get_child_count(), Time.get_ticks_msec()-started])
