extends Node
## One human, 2..5 bots. Review screens wait for the human indefinitely.
const Rules = preload("res://scripts/bluff/core/engine.gd")
const AI = preload("res://scripts/bluff/core/ai.gd")
signal changed(view: Dictionary)
var engine = Rules.new()
var rng = RandomNumberGenerator.new()
var active = false
var paused = false
var delay = 0.0
var round_id = 0
var pace = 2.8
var calls_checked_revision = -1

func _ready() -> void:
	rng.randomize()

func start(config: Dictionary = {}, seed_value: int = -1) -> void:
	round_id += 1
	engine.start(rng.randi() if seed_value < 0 else seed_value, config)
	active = true; paused = false; delay = pace
	calls_checked_revision = -1
	_publish()

func current_view() -> Dictionary:
	var view = engine.view(0)
	view["round_id"] = round_id
	return view

func _publish() -> void:
	changed.emit(current_view())

func submit(action: Dictionary) -> bool:
	if not active or paused or action.get("round_id", -1) != round_id: return false
	if not engine.act(0, action): return false
	delay = pace
	_publish()
	return true

func _process(delta: float) -> void:
	if not active or paused: return
	delay = maxf(0, delay - delta)
	if delay > 0 or engine.state.phase != "playing": return
	var seat = engine.state.turn
	# In free-call rooms any bot can call before the next declaration.
	if engine.state.config.challenge == "any" and calls_checked_revision != engine.state.revision:
		calls_checked_revision = engine.state.revision
		for candidate in range(1, engine.state.config.players):
			if not engine.can_challenge(candidate): continue
			var call = AI.choose(engine.view(candidate), rng)
			if call.type == "challenge":
				if engine.act(candidate, call):
					delay = pace; _publish()
				return
	if seat == 0: return
	var action = AI.choose(engine.view(seat), rng)
	if engine.act(seat, action):
		delay = pace + rng.randf_range(0, 0.8)
		_publish()
	else:
		# Fail closed; never spin on an invalid bot action.
		paused = true
		push_error("Bluff bot action rejected: " + str(action))

func shutdown() -> void:
	active = false; paused = true
