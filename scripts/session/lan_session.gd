class_name LanSession
extends LocalSession
## The host owns the rules. Guests send only a round, revision and legal ID.
## Raw ENet peers keep this transport independent of scene paths and RPC nodes.

signal room_changed(room: Dictionary)
signal connection_closed(reason: String)

const GAME_PORT = 32141
const PROTOCOL = 1
const APP_ID = "qingyu-shandong-lan"
const MAX_PACKET = 65536
const HEARTBEAT_SECONDS = 2.0
const TIMEOUT_SECONDS = 12.0
static var _host_drains: Dictionary = {}

var is_host = false
var local_seat = -1
var room: Dictionary = {}
var connected = false
var current_view: Dictionary = {}
var _peer: ENetMultiplayerPeer
var _members: Array = []
var _peer_seats: Dictionary = {}
var _last_seen: Dictionary = {}
var _rejected: Dictionary = {}
var _rates: Dictionary = {}
var _token = ""
var _address = ""
var _port = GAME_PORT
var _player_name = "牌友"
var _remembered_room = ""
var _hello_sent = false
var _elapsed = 0.0
var _heartbeat = 0.0
var _server_seen = 0.0
var _control_epoch = 0
var _worker_epoch = -1
var _worker_round = -1
var _last_autopilot = false

# ENet close() resets the transport immediately; a flushed reliable packet
# still needs acknowledgements/retransmissions. This short-lived node survives
# a screen/session replacement long enough to deliver leave/room-closed.
class PeerDrain extends Node:
	var peer: ENetMultiplayerPeer
	var remaining = 1.0
	func _process(delta: float) -> void:
		remaining -= delta
		if peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
			peer.poll()
			while peer.get_available_packet_count() > 0: peer.get_packet()
		if remaining <= 0 or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			peer.close(); queue_free()
	func _exit_tree() -> void:
		if peer != null: peer.close()

func _safe_name(value: String, fallback: String) -> String:
	var clean = value.strip_edges().replace("\n", " ").replace("\r", " ").replace("\t", " ").left(12)
	return clean if not clean.is_empty() else fallback

func _new_token() -> String:
	return Crypto.new().generate_random_bytes(24).hex_encode()

func _settings(value: Dictionary) -> Dictionary:
	return {"jiang": "luan" if value.get("jiang") == "luan" else "258", "chi": value.get("chi", true) == true,
		"ai": "classic" if value.get("ai") == "classic" else "efficiency", "rounds": 0, "takeover": false}

func host_room(settings: Dictionary, player_name: String = "房主", port: int = GAME_PORT) -> Error:
	leave_room()
	if port < 1024 or port > 65535: return ERR_INVALID_PARAMETER
	# An explicit replacement room takes precedence over the old listener's
	# short goodbye grace period. Never make rapid re-creation fail on its port.
	if _host_drains.has(port):
		var old_drain = _host_drains[port].get_ref()
		if is_instance_valid(old_drain): old_drain.peer.close(); old_drain.queue_free()
		_host_drains.erase(port)
	_peer = ENetMultiplayerPeer.new()
	var error = _peer.create_server(port, 8, 1)
	if error != OK:
		_peer = null
		notice.emit("房间创建失败，请检查端口是否已被占用。")
		return error
	_peer.peer_connected.connect(_peer_connected)
	_peer.peer_disconnected.connect(_peer_disconnected)
	is_host = true; connected = true; local_seat = 0; _port = port
	_player_name = _safe_name(player_name, "房主")
	_token = _new_token()
	_members = []
	for seat in range(4):
		_members.append({"seat": seat, "name": ["房主", "听松", "观澜", "知秋"][seat], "occupied": false,
			"connected": false, "ready": false, "autopilot": false, "token": "", "peer": 0})
	_members[0].merge({"name": _player_name, "occupied": true, "connected": true, "ready": true, "token": _token, "peer": 1}, true)
	var addresses = LanDiscovery.local_addresses()
	room = {"id": _new_token().left(12), "name": _player_name + "的房间", "port": port, "host_addresses": addresses,
		"settings": _settings(settings), "started": false, "disconnect_autoplay": false, "seats": [], "can_start": true}
	_remembered_room = room.id
	_publish_room()
	return OK

func join_room(address: String, player_name: String = "牌友", port: int = GAME_PORT) -> Error:
	leave_room()
	_address = address.strip_edges(); _port = port; _player_name = _safe_name(player_name, "牌友")
	_token = ""; _remembered_room = ""
	return _connect_client()

func reconnect_room() -> Error:
	if is_host or _address.is_empty() or _token.is_empty(): return ERR_UNCONFIGURED
	_close_peer()
	return _connect_client()

func _connect_client() -> Error:
	if not _address.is_valid_ip_address() or ":" in _address or _port < 1024 or _port > 65535:
		notice.emit("请输入房主的局域网 IPv4 地址，例如 192.168.1.10。")
		return ERR_INVALID_PARAMETER
	_peer = ENetMultiplayerPeer.new()
	var error = _peer.create_client(_address, _port, 1)
	if error != OK:
		_peer = null; notice.emit("连接失败，请检查 Wi-Fi 和房主地址。")
		return error
	is_host = false; connected = false; paused = true; autopilot = false; _last_autopilot = false
	_hello_sent = false; _elapsed = 0.0; _heartbeat = 0.0; _server_seen = 0.0
	return OK

func _close_peer() -> void:
	if _peer != null:
		_peer.close(); _peer = null
	_peer_seats.clear(); _last_seen.clear(); _rejected.clear(); _rates.clear()
	connected = false

func leave_room() -> void:
	_join_worker()
	# A hello may already have reserved a seat even before welcome reaches us.
	# Cancel that handshake in the same reliable stream so it cannot leave a
	# ghost reservation when the player backs out during connection.
	if _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and (connected or _hello_sent):
		if is_host:
			for id in _peer_seats: _send(id, {"kind": "closed", "reason": "房主已解散房间。"})
		else: _send(1, {"kind": "leave"})
		_peer.host.flush()
		if is_inside_tree() and (not is_host or not _peer_seats.is_empty()):
			if _peer.peer_connected.is_connected(_peer_connected): _peer.peer_connected.disconnect(_peer_connected)
			if _peer.peer_disconnected.is_connected(_peer_disconnected): _peer.peer_disconnected.disconnect(_peer_disconnected)
			var drain = PeerDrain.new(); drain.peer = _peer
			if is_host: _host_drains[_port] = weakref(drain)
			get_tree().root.add_child(drain); _peer = null
	_close_peer()
	is_host = false; local_seat = -1; paused = true; autopilot = false; _last_autopilot = false
	room = {}; current_view = {}; _members = []; engine = GameEngine.new()
	_token = ""; _address = ""; _remembered_room = ""; _control_epoch += 1
	_elapsed = 0; _heartbeat = 0; _hello_sent = false

func set_ready(value: bool) -> void:
	if not connected or room.get("started", false): return
	if is_host:
		_members[0].ready = value; _publish_room()
	else: _send(1, {"kind": "ready", "value": value})

func set_room_settings(settings: Dictionary) -> bool:
	if not is_host or not connected or room.started: return false
	room.settings = _settings(settings)
	for seat in range(1, 4): _members[seat].ready = false
	_publish_room()
	return true

func set_disconnect_autoplay(value: bool) -> void:
	if not is_host or not connected: return
	room.disconnect_autoplay = value; _control_epoch += 1; _publish_room()

func start_room() -> bool:
	if not is_host or not connected or room.started or not _can_start(): return false
	_join_worker()
	engine.start(room.settings, ai_rng.randi())
	room.started = true; paused = false; delay = 2.0; presentation_delay = 0
	_publish_room(); _publish()
	return true

func start_match(_settings_value: Dictionary) -> void:
	start_room()

func _can_start() -> bool:
	if room.get("started", false): return false
	for member in _members:
		if member.occupied and (not member.connected or not member.ready): return false
	return not _members.is_empty()

func _public_room() -> Dictionary:
	var result = room.duplicate(true)
	result.can_start = _can_start()
	result.seats = []
	for member in _members:
		result.seats.append({"seat": member.seat, "name": member.name, "occupied": member.occupied,
			"connected": member.connected, "ready": member.ready, "bot": not member.occupied, "autopilot": member.autopilot})
	return result

func _publish_room() -> void:
	if not is_host: return
	room = _public_room()
	for id in _peer_seats: _send(id, {"kind": "room", "room": room})
	room_changed.emit(room.duplicate(true))

func _seat_view(seat: int) -> Dictionary:
	var result = engine.view(seat)
	if result.is_empty(): return {}
	# The core event is authoritative and may contain a concealed-kong tile;
	# a remote observer receives the action cue without the concealed face.
	if result.phase != "settled" and result.event.kind == "angang" and int(result.event.seat) != seat:
		result.event.tile = -1
	for index in range(4):
		result.players[index].name = _members[index].name
		result.players[index].bot = not _members[index].occupied
		result.players[index].connected = _members[index].connected
	return result

func _publish() -> void:
	if not is_host or engine.state.is_empty(): return
	for id in _peer_seats:
		_send(id, {"kind": "view", "view": _seat_view(int(_peer_seats[id]))})
	current_view = SeatView.for_seat(_seat_view(0), 0)
	changed.emit(current_view.duplicate(true))

func play(action_id: String, revision: int = -1) -> bool:
	if not connected or current_view.is_empty(): return false
	var expected = int(current_view.revision) if revision < 0 else revision
	if is_host: return _submit(0, expected, int(current_view.round), action_id)
	if int(current_view.decision_seat) != 0 or expected != int(current_view.revision): return false
	if not current_view.pending.any(func(move): return str(move.id) == action_id): return false
	_send(1, {"kind": "action", "revision": expected, "round": int(current_view.round), "id": action_id})
	return true

func _submit(seat: int, revision: int, round_number: int, action_id: String) -> bool:
	if engine.state.is_empty() or round_number != int(engine.state.round): return false
	if not engine.submit(seat, revision, action_id): return false
	delay = action_delay(engine.state.event.kind)
	_publish()
	return true

func next_round() -> void:
	if not is_host:
		notice.emit("请等待房主开始下一局。")
		return
	if not connected or engine.state.is_empty() or engine.state.phase != "settled": return
	_join_worker()
	var state = engine.state
	engine.start(room.settings, ai_rng.randi(), int(state.round) + 1, state.players.map(func(player): return player.score))
	delay = 2.0; presentation_delay = 0; _control_epoch += 1
	_publish()

func _peer_connected(id: int) -> void:
	_last_seen[id] = _elapsed
	_rates[id] = {"since": _elapsed, "count": 0}

func _peer_disconnected(id: int) -> void:
	_last_seen.erase(id); _rates.erase(id); _rejected.erase(id)
	if not _peer_seats.has(id): return
	var seat = int(_peer_seats[id]); _peer_seats.erase(id)
	_members[seat].connected = false; _members[seat].peer = 0; _members[seat].autopilot = false
	_members[seat].ready = false; _control_epoch += 1
	_publish_room()
	notice.emit(_members[seat].name + "已掉线，保留原座位。")

func _send(id: int, message: Dictionary) -> void:
	if _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED: return
	var packet = message.duplicate()
	packet.protocol = PROTOCOL; packet.app = APP_ID
	_peer.set_target_peer(id); _peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE; _peer.transfer_channel = 0
	_peer.put_packet(JSON.stringify(packet).to_utf8_buffer())

func _reject(id: int, reason: String) -> void:
	_send(id, {"kind": "rejected", "reason": reason})
	_rejected[id] = _elapsed + 0.4

func _receive_host(id: int, message: Dictionary) -> void:
	if _rejected.has(id): return
	if message.get("kind") == "hello":
		_admit(id, message); return
	if not _peer_seats.has(id):
		_reject(id, "请先加入房间。"); return
	var seat = int(_peer_seats[id])
	match message.get("kind"):
		"ping": _send(id, {"kind": "pong"})
		"ready":
			if not room.started and message.get("value") is bool:
				_members[seat].ready = message.value; _publish_room()
		"autopilot":
			if message.get("value") is bool:
				_members[seat].autopilot = message.value; _control_epoch += 1; _publish_room()
		"action":
			if not message.get("id") is String or not message.get("revision") is int or not message.get("round") is int: return
			if not _submit(seat, message.revision, message.round, message.id):
				_send(id, {"kind": "notice", "message": "这次操作已过期，请按当前牌面操作。"})
				if not engine.state.is_empty(): _send(id, {"kind": "view", "view": _seat_view(seat)})
		"leave":
			_peer_seats.erase(id); _last_seen.erase(id); _rates.erase(id)
			_members[seat].merge({"occupied": false, "connected": false, "ready": false, "autopilot": false,
				"name": ["房主", "听松", "观澜", "知秋"][seat], "token": "", "peer": 0}, true)
			_control_epoch += 1; _publish_room()
			_peer.disconnect_peer(id)

func _admit(id: int, message: Dictionary) -> void:
	if _peer_seats.has(id): return
	if not message.get("name") is String or not message.get("token", "") is String: return
	var token: String = message.get("token", "")
	var seat = -1
	if not token.is_empty():
		if message.get("room_id", "") != room.id:
			_reject(id, "原房间已结束，请重新加入新房间。"); return
		for index in range(1, 4):
			if _members[index].occupied and _members[index].token == token: seat = index; break
		if seat < 0:
			_reject(id, "原座位已释放，请重新加入房间。"); return
		var previous_peer = int(_members[seat].peer)
		if previous_peer != 0 and previous_peer != id:
			_peer_seats.erase(previous_peer); _last_seen.erase(previous_peer); _rates.erase(previous_peer)
			_peer.disconnect_peer(previous_peer)
	else:
		if room.started:
			_reject(id, "这桌已开局，请等房主重新建房。"); return
		for index in range(1, 4):
			if not _members[index].occupied: seat = index; break
		if seat < 0:
			_reject(id, "房间已满，最多四位真人。"); return
		token = _new_token()
		_members[seat].name = _safe_name(message.name, "牌友%d" % seat)
	_members[seat].merge({"occupied": true, "connected": true, "ready": false, "autopilot": false, "token": token, "peer": id}, true)
	_peer_seats[id] = seat; _control_epoch += 1
	room = _public_room()
	_send(id, {"kind": "welcome", "seat": seat, "token": token, "room": room})
	_publish_room()
	if room.started: _send(id, {"kind": "view", "view": _seat_view(seat)})

func _receive_client(message: Dictionary) -> void:
	match message.get("kind"):
		"welcome":
			if not message.get("seat") is int or message.seat < 1 or message.seat > 3 or not message.get("token") is String or not _valid_room(message.get("room")): return
			local_seat = message.seat; _token = message.token; room = message.room
			_remembered_room = str(room.id); connected = true; paused = not room.started; autopilot = false; _last_autopilot = false
			room_changed.emit(room.duplicate(true))
		"room":
			if not connected or not _valid_room(message.get("room")): return
			room = message.room; room_changed.emit(room.duplicate(true))
		"view":
			if not connected or not message.get("view") is Dictionary: return
			var state: Dictionary = message.view
			if not _valid_view(state): return
			if not current_view.is_empty() and (int(state.round) < int(current_view.round) or (int(state.round) == int(current_view.round) and int(state.revision) <= int(current_view.revision))): return
			current_view = SeatView.for_seat(state, local_seat); paused = false
			changed.emit(current_view.duplicate(true))
		"notice": notice.emit(str(message.get("message", "操作未完成。")).left(120))
		"rejected", "closed": _connection_lost(str(message.get("reason", "房间连接已关闭。")).left(120))

func _valid_room(value: Variant) -> bool:
	if not value is Dictionary: return false
	if not value.get("id") is String or not value.get("settings") is Dictionary or not value.get("seats") is Array: return false
	if value.seats.size() != 4 or not value.get("started") is bool: return false
	for seat in value.seats:
		if not seat is Dictionary or not seat.get("name") is String: return false
	return true

func _valid_view(value: Dictionary) -> bool:
	if value.has("wall") or value.has("journal") or value.has("claim_queue"): return false
	if value.get("phase") not in ["turn", "claim", "settled"] or not value.get("revision") is int or not value.get("round") is int: return false
	if not value.get("players") is Array or value.players.size() != 4 or not value.get("pending") is Array: return false
	for player in value.players:
		if not player is Dictionary or not player.get("hand") is Array or not player.get("melds") is Array or not player.get("discards") is Array: return false
	return true

static func _integers(value: Variant) -> Variant:
	# JSON numbers are doubles. Game/view consumers use integer array indexes.
	if value is float: return int(value) if is_finite(value) and value == floor(value) else value
	if value is Array:
		for index in range(value.size()): value[index] = _integers(value[index])
	elif value is Dictionary:
		for key in value: value[key] = _integers(value[key])
	return value

func _poll_network(delta: float) -> void:
	if _peer == null: return
	_elapsed += delta; _heartbeat += delta
	if _peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		_connection_lost("连接已断开，请确认仍在同一 Wi-Fi 或热点下，再点重新连接。"); return
	_peer.poll()
	if _peer == null: return
	if not is_host:
		if _peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			_connection_lost("连接已断开，请确认仍在同一 Wi-Fi 或热点下，再点重新连接。"); return
		if _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and not _hello_sent:
			_hello_sent = true
			_send(1, {"kind": "hello", "name": _player_name, "token": _token, "room_id": _remembered_room})
	var remaining = 64
	while _peer != null and _peer.get_available_packet_count() > 0 and remaining > 0:
		remaining -= 1
		var id = _peer.get_packet_peer()
		var data = _peer.get_packet()
		if data.size() > MAX_PACKET: continue
		var parser = JSON.new()
		if parser.parse(data.get_string_from_utf8()) != OK or not parser.data is Dictionary: continue
		var message: Dictionary = _integers(parser.data)
		if message.get("app") != APP_ID or message.get("protocol") != PROTOCOL:
			if is_host: _reject(id, "游戏版本不一致，请所有人安装同一版本。")
			else: _connection_lost("游戏版本不一致，请所有人安装同一版本。")
			continue
		if is_host:
			if not _rates.has(id): _rates[id] = {"since": _elapsed, "count": 0}
			var rate: Dictionary = _rates[id]
			if _elapsed - rate.since >= 1.0: rate.since = _elapsed; rate.count = 0
			rate.count += 1
			if rate.count > 60: continue
			_last_seen[id] = _elapsed
			_receive_host(id, message)
		elif id == 1:
			_server_seen = _elapsed; _receive_client(message)
	if _peer == null: return
	if is_host:
		for id in _last_seen.keys():
			if _elapsed - float(_last_seen[id]) > TIMEOUT_SECONDS:
				_peer.disconnect_peer(id); _peer_disconnected(id)
		for id in _rejected.keys():
			if _elapsed >= float(_rejected[id]):
				_peer.disconnect_peer(id); _peer_disconnected(id)
	elif _elapsed - _server_seen > TIMEOUT_SECONDS:
		_connection_lost("连接房主超时，请检查 Wi-Fi、热点和防火墙，然后重新连接。"); return
	if _heartbeat >= HEARTBEAT_SECONDS:
		_heartbeat = 0
		if is_host:
			for id in _peer_seats: _send(id, {"kind": "ping"})
		elif _hello_sent: _send(1, {"kind": "ping"})

func _connection_lost(reason: String) -> void:
	_close_peer(); paused = true; autopilot = false; _last_autopilot = false; _control_epoch += 1
	notice.emit(reason); connection_closed.emit(reason)

func _is_bot_controlled(seat: int) -> bool:
	if seat < 0 or seat >= _members.size(): return false
	var member: Dictionary = _members[seat]
	return not member.occupied or member.autopilot or (not member.connected and room.get("disconnect_autoplay", false))

func _locked_discard(seat: int) -> Dictionary:
	var state = engine.state
	if state.is_empty() or state.phase != "turn" or state.current != seat: return {}
	var player: Dictionary = state.players[seat]
	if not (player.bao or player.ming) or player.drawn < 0 or player.drawn >= player.hand.size(): return {}
	if state.pending.any(func(move): return move.kind in ["win", "angang", "bugang"]): return {}
	for move in state.pending:
		if move.kind == "discard" and move.index == player.drawn: return move
	return {}

func locked_discard_action() -> Dictionary:
	return _locked_discard(local_seat) if is_host else {}

func request_hint() -> void:
	if not connected or worker != null or current_view.is_empty() or current_view.decision_seat != 0: return
	worker_hint = true; worker_revision = current_view.revision; _worker_round = current_view.round
	_worker_epoch = _control_epoch; worker_seat = local_seat
	var private_view = current_view.duplicate(true)
	var random_value = ai_rng.randf()
	worker = Thread.new()
	if worker.start(func(): return ai.choose(private_view, 0, random_value)) != OK:
		worker = null; notice.emit("牌效分析暂时不可用。")

func _start_worker(hint: bool = false) -> void:
	if hint: request_hint(); return
	if not is_host or worker != null: return
	worker_seat = engine.decision_seat(); worker_revision = engine.state.revision
	_worker_round = engine.state.round; _worker_epoch = _control_epoch; worker_hint = false
	var private_view = engine.view(worker_seat)
	var seat = worker_seat
	var random_value = ai_rng.randf()
	worker = Thread.new()
	if worker.start(func(): return ai.choose(private_view, seat, random_value)) != OK:
		worker = null; notice.emit("机器人暂时无法行动，请稍后重试。")

func _process(delta: float) -> void:
	_poll_network(delta)
	if not connected: return
	if autopilot != _last_autopilot:
		_last_autopilot = autopilot; _control_epoch += 1
		if is_host:
			_members[0].autopilot = autopilot; _publish_room()
		else: _send(1, {"kind": "autopilot", "value": autopilot})
	presentation_delay = maxf(0, presentation_delay - delta)
	if worker != null and not worker.is_alive():
		var move = worker.wait_to_finish(); worker = null
		if worker_hint:
			if not current_view.is_empty() and worker_revision == current_view.revision and _worker_round == current_view.round: hint_ready.emit(move)
		elif is_host and _worker_epoch == _control_epoch and _is_bot_controlled(worker_seat):
			if not move.is_empty(): _submit(worker_seat, worker_revision, _worker_round, str(move.id))
	if not is_host or engine.state.is_empty() or worker != null or engine.state.phase == "settled": return
	delay -= delta
	if delay > 0 or presentation_delay > 0: return
	var seat = engine.decision_seat()
	if _is_bot_controlled(seat): _start_worker()
	elif _members[seat].connected:
		var move = _locked_discard(seat)
		if not move.is_empty(): _submit(seat, engine.state.revision, engine.state.round, str(move.id))

func has_save() -> bool:
	return false

func resume_match() -> bool:
	return false

func _save() -> void:
	# LAN must never overwrite a player's independent single-player save.
	pass

func export_replay() -> String:
	if not is_host or engine.state.is_empty():
		notice.emit("完整牌谱由房主保存。")
		return ""
	return super.export_replay()

func _exit_tree() -> void:
	_join_worker(); _close_peer()
