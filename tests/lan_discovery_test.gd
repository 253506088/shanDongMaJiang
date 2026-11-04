extends SceneTree
var failures = 0
var checks = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ", message)

func run() -> void:
	create_timer(18).timeout.connect(func(): printerr("Discovery test timed out"); quit(1))
	var host = LanDiscovery.new()
	var browser = LanDiscovery.new()
	host.discovery_port = 33242; browser.discovery_port = 33242
	browser.query_addresses = ["127.0.0.1"]
	root.add_child(host); root.add_child(browser)
	var room = {"id": "discovery-test", "name": "热点牌友", "port": 33241, "started": false,
		"seats": [{"occupied": true}, {"occupied": true}, {"occupied": false}, {"occupied": false}],
		"settings": {"jiang": "luan", "chi": false, "ai": "classic", "rounds": 0}}
	check(host.start_host(room) == OK, "host binds discovery socket")
	check(browser.start_browser() == OK, "browser binds ephemeral reply socket")
	await create_timer(0.5).timeout
	var found = browser.get_rooms()
	check(found.size() == 1, "real UDP query finds one room")
	if not found.is_empty():
		check(found[0].address == "127.0.0.1" and found[0].port == 33241, "join endpoint comes from socket source")
		check(found[0].players == 2 and found[0].settings.chi == false and found[0].name == "热点牌友", "Unicode name, occupancy and rules survive UDP JSON")
		check(not found[0].has("seats") and not found[0].has("host_addresses"), "discovery exposes only room summary")
		var malformed = found[0].duplicate(true)
		malformed.port = 123.5
		check(LanDiscovery._validate_room(malformed, "127.0.0.1").is_empty(), "reject fractional port")
		malformed.port = 33241; malformed.players = 5
		check(LanDiscovery._validate_room(malformed, "127.0.0.1").is_empty(), "reject impossible capacity")
	room.started = true; host.update_room(room)
	browser.countdown = 0.0
	await create_timer(0.3).timeout
	found = browser.get_rooms()
	check(found.size() == 1 and found[0].started, "start state refreshes without duplicate rooms")
	# A packet without the browser's nonce cannot overwrite the room list.
	var stranger = PacketPeerUDP.new()
	stranger.set_dest_address("127.0.0.1", browser.socket.get_local_port())
	stranger.put_packet(JSON.stringify({"magic": LanDiscovery.MAGIC, "version": 1, "type": "room", "nonce": "wrong", "room": room}).to_utf8_buffer())
	await create_timer(0.1).timeout
	check(browser.get_rooms().size() == 1, "ignore unmatched discovery replies")
	stranger.close(); host.stop()
	# Advance the timestamp instead of delaying this unit test by the whole TTL.
	for key in browser.found: browser.found[key].seen = Time.get_ticks_msec() - LanDiscovery.ROOM_TTL_MS - 1
	await create_timer(0.05).timeout
	check(browser.get_rooms().is_empty(), "stale rooms disappear")
	check(LanDiscovery.is_lan_ipv4("192.168.43.1") and LanDiscovery.is_lan_ipv4("172.20.10.1"), "Android and iPhone hotspot ranges supported")
	check(not LanDiscovery.is_lan_ipv4("127.0.0.1") and not LanDiscovery.is_lan_ipv4("8.8.8.8"), "display only local interface addresses")
	browser.stop(); host.queue_free(); browser.queue_free()
	await process_frame
	print("LAN_DISCOVERY_RESULT: ", failures, " failures, ", checks, " checks")
	quit(0 if failures == 0 else 1)
