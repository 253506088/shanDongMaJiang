class_name DdzSession
extends Node
## An in-memory single-player session. Never touches Mahjong saves or LAN.
const EngineScript = preload("res://scripts/doudizhu/core/engine.gd")
const AI = preload("res://scripts/doudizhu/core/ai.gd")
signal changed(view: Dictionary)
signal hint_ready(cards: Array)
signal notice(message: String)

var engine = EngineScript.new()
var paused = true
var active = false
var delay = 0.0
var round_id = 0
var rng = RandomNumberGenerator.new()
var worker: Thread
var worker_revision = -1
var worker_round = -1
var worker_seat = -1
var worker_hint = false

func _ready() -> void:
	rng.randomize()

func start(seed_value: int = -1, first_bidder: int = -1) -> void:
	_join_worker()
	round_id += 1
	engine.start(rng.randi() if seed_value < 0 else seed_value, rng.randi_range(0, 2) if first_bidder < 0 else first_bidder)
	active = true
	paused = false
	delay = 1.6
	_publish()

func current_view() -> Dictionary:
	if not active: return {}
	var result: Dictionary = engine.view(0)
	result["round_id"] = round_id
	return result

func _publish() -> void:
	changed.emit(current_view())

func submit(action: Dictionary) -> bool:
	if not active or paused or not action.has("revision"): return false
	if not engine.act(0, action): return false
	delay = 1.6
	_publish()
	return true

func next_round() -> bool:
	if not active or engine.state.get("phase", "") != "finished": return false
	var first = (int(engine.state.get("bid_starter", 0)) + 1) % 3
	start(-1, first)
	return true

func hold_presentation(seconds: float) -> void:
	delay = maxf(delay, seconds)

func request_hint() -> void:
	if not active or paused or worker != null: return
	if engine.state.get("phase", "") != "playing" or engine.state.get("turn", -1) != 0: return
	_start_worker(true)

func _start_worker(as_hint: bool) -> void:
	worker_revision = engine.state.revision
	worker_round = round_id
	worker_seat = int(engine.state.turn)
	worker_hint = as_hint
	var private_view: Dictionary = engine.view(worker_seat)
	worker = Thread.new()
	var error = worker.start(func(): return AI.choose(private_view))
	if error != OK:
		worker = null
		paused = true
		notice.emit("机器人暂时无法开始思考，请返回大厅重开。")

func _process(delta: float) -> void:
	if not active: return
	if not paused: delay = maxf(0.0, delay - delta)
	if worker != null and not worker.is_alive():
		var move = worker.wait_to_finish()
		worker = null
		if worker_round != round_id or worker_revision != engine.state.get("revision", -1): return
		if paused: return
		if worker_hint:
			hint_ready.emit(move.get("cards", []))
		elif worker_seat != 0 and not move.is_empty():
			move["revision"] = worker_revision
			if engine.act(worker_seat, move):
				delay = 1.6
				_publish()
			else:
				paused = true
				notice.emit("机器人动作未通过规则校验，请返回大厅重开。")
	if paused or worker != null or delay > 0.0: return
	if engine.state.get("phase", "") == "finished": return
	if engine.state.get("turn", 0) != 0: _start_worker(false)

func shutdown() -> void:
	paused = true
	active = false
	_join_worker()

func _join_worker() -> void:
	if worker != null:
		worker.wait_to_finish()
		worker = null

func _exit_tree() -> void:
	shutdown()
