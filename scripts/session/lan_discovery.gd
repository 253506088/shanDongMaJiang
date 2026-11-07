class_name LanDiscovery
extends Node
## Nearby room discovery uses UDP queries and unicast replies. No player
## credentials or game state are advertised. Joining always uses ENet.
signal rooms_changed(rooms: Array)

const DISCOVERY_PORT = 32142
const PROTOCOL = 5
const MAGIC = "qingyu-lan"
const MAX_PACKET = 2048
const ROOM_TTL_MS = 6500
var discovery_port = DISCOVERY_PORT
# Tests can use loopback without broadcasting onto the user's network.
var query_addresses: Array = []
var socket: PacketPeerUDP
var hosting = false
var metadata: Dictionary = {}
var found: Dictionary = {}
var nonce = ""
var countdown = 0.0
var replies: Dictionary = {}

static func local_addresses() -> Array:
	var addresses: Array = []
	if not BuildFeatures.lan_enabled(): return addresses
	for address in IP.get_local_addresses():
		if is_lan_ipv4(address) and not addresses.has(address): addresses.append(address)
	return addresses

static func is_lan_ipv4(address: String) -> bool:
	if not address.is_valid_ip_address() or address.contains(":"): return false
	var octets = address.split(".")
	if octets.size() != 4: return false
	return int(octets[0]) == 10 or (int(octets[0]) == 172 and int(octets[1]) >= 16 and int(octets[1]) <= 31) or (int(octets[0]) == 192 and int(octets[1]) == 168) or (int(octets[0]) == 169 and int(octets[1]) == 254)

func start_browser() -> Error:
	if not BuildFeatures.lan_enabled(): return ERR_UNAVAILABLE
	stop()
	socket = PacketPeerUDP.new()
	var error = socket.bind(0, "0.0.0.0")
	if error != OK: socket = null; return error
	socket.set_broadcast_enabled(true)
	nonce = Crypto.new().generate_random_bytes(16).hex_encode()
	countdown = 0.0
	return OK

func start_host(room: Dictionary) -> Error:
	if not BuildFeatures.lan_enabled(): return ERR_UNAVAILABLE
	stop()
	socket = PacketPeerUDP.new()
	var error = socket.bind(discovery_port, "0.0.0.0")
	if error != OK: socket = null; return error
	hosting = true
	update_room(room)
	return OK

func update_room(room: Dictionary) -> void:
	var count = 0
	for seat in room.get("seats", []):
		if seat.get("occupied", false): count += 1
	metadata = {"id": str(room.get("id", "")).left(64), "name": str(room.get("name", "牌友的房间")).left(24),
		"port": int(room.get("port", 32141)), "players": count, "started": bool(room.get("started", false)),
		"settings": room.get("settings", {}).duplicate(true)}

func stop() -> void:
	if socket != null: socket.close(); socket = null
	hosting = false
	metadata.clear(); found.clear(); replies.clear()
	nonce = ""
	rooms_changed.emit([])

func get_rooms() -> Array:
	var rooms: Array = []
	for entry in found.values(): rooms.append(entry.room.duplicate(true))
	rooms.sort_custom(func(a, b): return str(a.name) + str(a.id) < str(b.name) + str(b.id))
	return rooms

func _query() -> void:
	var targets = query_addresses.duplicate()
	if targets.is_empty():
		targets.append("255.255.255.255")
		# Some hotspot drivers ignore the limited broadcast. These additional
		# /24 broadcast hints cover common home/hotspot layouts, not arbitrary
		# netmasks; direct address entry remains available in the room browser.
		for address in local_addresses():
			var parts = str(address).split(".")
			var candidate = "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
			if not targets.has(candidate): targets.append(candidate)
	for address in targets:
		_send(str(address), discovery_port, {"magic": MAGIC, "version": PROTOCOL, "type": "query", "nonce": nonce})

func _send(address: String, port: int, data: Dictionary) -> void:
	if socket == null: return
	if socket.set_dest_address(address, port) == OK: socket.put_packet(JSON.stringify(data).to_utf8_buffer())

func _process(delta: float) -> void:
	if socket == null: return
	var now = Time.get_ticks_msec()
	if not hosting:
		countdown -= delta
		if countdown <= 0: countdown = 1.5; _query()
	var changed = false
	# Bound work per frame, including when malformed LAN datagrams arrive.
	for _i in range(mini(socket.get_available_packet_count(), 32)):
		var packet = socket.get_packet()
		var address = socket.get_packet_ip()
		var port = socket.get_packet_port()
		if packet.size() > MAX_PACKET: continue
		var parser = JSON.new()
		if parser.parse(packet.get_string_from_utf8()) != OK: continue
		var data = parser.data
		if not data is Dictionary or data.get("magic") != MAGIC or data.get("version") != PROTOCOL: continue
		if hosting:
			if data.get("type") != "query" or not data.get("nonce") is String: continue
			if data.nonce.length() != 32 or metadata.is_empty(): continue
			if now - int(replies.get(address, -1000)) < 200: continue
			if replies.size() >= 128: replies.clear()
			replies[address] = now
			_send(address, port, {"magic": MAGIC, "version": PROTOCOL, "type": "room", "nonce": data.nonce, "room": metadata})
		elif data.get("type") == "room" and data.get("nonce") == nonce:
			var advertised = _validate_room(data.get("room"), address)
			if advertised.is_empty(): continue
			var key = str(advertised.id)
			if not found.has(key) and found.size() >= 64: continue
			if not found.has(key) or found[key].room != advertised: changed = true
			found[key] = {"room": advertised, "seen": now}
	if not hosting:
		for key in found.keys():
			if now - int(found[key].seen) > ROOM_TTL_MS:
				found.erase(key); changed = true
		if changed: rooms_changed.emit(get_rooms())

static func _validate_room(data: Variant, address: String) -> Dictionary:
	if not data is Dictionary: return {}
	if not data.get("id") is String or data.id.is_empty() or data.id.length() > 64: return {}
	if not data.get("name") is String or data.name.length() > 24: return {}
	for key in ["port", "players"]:
		if not (data.get(key) is int or data.get(key) is float): return {}
		if data[key] != int(data[key]): return {}
	if int(data.port) < 1 or int(data.port) > 65535 or int(data.players) < 1 or int(data.players) > 4: return {}
	if not data.get("started") is bool or not data.get("settings") is Dictionary: return {}
	var settings = data.settings
	if settings.get("jiang") not in ["258", "luan"] or not settings.get("chi") is bool or settings.get("ai") not in ["classic", "efficiency"]: return {}
	if not settings.get("field_rules", false) is bool: return {}
	var selection = settings.get("field_selection", "random")
	if not selection is String or (selection != "random" and selection not in FieldRules.IDS): return {}
	return {"id": data.id, "name": data.name.strip_edges(), "address": address, "port": int(data.port),
		"players": int(data.players), "started": data.started, "version": PROTOCOL,
		"settings": {"jiang": settings.jiang, "chi": settings.chi, "ai": settings.ai, "rounds": 0,
			"field_rules": settings.get("field_rules", false), "field_selection": selection}}

func _exit_tree() -> void:
	if socket != null: socket.close()
