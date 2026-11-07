extends Node
## One human, 2..5 bots. Reveal time belongs to the session, not a UI prompt.
const Rules = preload("res://scripts/bluff/core/engine.gd")
const AI = preload("res://scripts/bluff/core/ai.gd")
const REVEAL_SECONDS = 4.0
const RPS_RESULT_SECONDS = 1.8
signal changed(view: Dictionary)
var engine = Rules.new()
var rng = RandomNumberGenerator.new()
var active = false
var paused = false
var delay = 0.0
var round_id = 0
var pace = 2.8
var calls_checked_revision = -1
var calls_checked_seats: Array = []

func _ready() -> void:
	rng.randomize()

func start(config: Dictionary = {}, seed_value: int = -1) -> void:
	round_id += 1
	engine.start(rng.randi() if seed_value < 0 else seed_value, config)
	active = true; paused = false; delay = pace
	calls_checked_revision = -1
	calls_checked_seats.clear()
	_publish()

func current_view() -> Dictionary:
	var view = engine.view(0)
	view["round_id"] = round_id
	view["review_remaining"] = delay if engine.state.phase == "review" else 0.0
	return view

func _publish() -> void:
	if engine.state.phase == "review":
		delay = REVEAL_SECONDS if engine.state.event.get("type", "") == "challenge" else RPS_RESULT_SECONDS
	changed.emit(current_view())

func submit(action: Dictionary) -> bool:
	if not active or paused or action.get("round_id", -1) != round_id: return false
	if engine.state.phase == "review": return false
	if not engine.act(0, action): return false
	delay = pace
	_publish()
	return true

func _process(delta: float) -> void:
	if not active or paused: return
	delay = maxf(0, delay - delta)
	if delay > 0: return
	if engine.state.phase == "review":
		if engine.act(0, {"type": "continue", "revision": engine.state.revision}):
			delay = pace
			_publish()
		return
	if engine.state.phase == "permission":
		var approver = engine.state.permission.approver
		if approver == 0: return # Human consent has no timeout or default answer.
		if engine.act(approver, AI.permission_response(engine.view(approver))):
			delay = pace; _publish()
		return
	if engine.state.phase != "playing": return
	var seat = engine.state.turn
	# In free-call rooms any bot can call before the next declaration.
	var claim_revision = engine.state.last.get("revision", engine.state.revision)
	if engine.state.config.challenge == "any":
		if calls_checked_revision != claim_revision:
			calls_checked_revision = claim_revision; calls_checked_seats.clear()
		for candidate in range(1, engine.state.config.players):
			if candidate in calls_checked_seats: continue
			calls_checked_seats.append(candidate)
			if not (engine.can_challenge(candidate) or engine.can_request_challenge(candidate)): continue
			var candidate_view = engine.view(candidate)
			if AI.wants_challenge(candidate_view, rng):
				var call = AI.challenge_action(candidate_view)
				if engine.act(candidate, call):
					delay = pace; _publish()
				return
	if seat == 0: return
	# Free-call candidates were already evaluated once for this declaration.
	var action = AI.choose(engine.view(seat), rng, engine.state.config.challenge != "any")
	if engine.act(seat, action):
		delay = pace + rng.randf_range(0, 0.8)
		_publish()
	else:
		# Fail closed; never spin on an invalid bot action.
		paused = true
		push_error("Bluff bot action rejected: " + str(action))

func shutdown() -> void:
	active = false; paused = true
