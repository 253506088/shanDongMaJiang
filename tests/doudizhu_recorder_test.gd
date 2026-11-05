extends SceneTree
const EngineScript = preload("res://scripts/doudizhu/core/engine.gd")
const Cards = preload("res://scripts/doudizhu/core/cards.gd")
const Recorder = preload("res://scripts/doudizhu/core/recorder.gd")
const AI = preload("res://scripts/doudizhu/core/ai.gd")
var checks = 0
var failures: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("DDZ RECORDER FAIL: ", message)

func tally(cards: Array) -> Array:
	var counts: Array = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	for card in cards: counts[Cards.rank(card) - 3] += 1
	return counts

func run() -> void:
	var engine = EngineScript.new()
	engine.start(6150, 0)
	var original = engine.view(0)
	check(Recorder.remaining(original).reduce(func(sum, value): return sum + value, 0) == 37, "bidding outside count includes unrevealed bottom")
	check(original.played_cards.is_empty(), "new deal has no public plays")
	for seat in range(3):
		check(engine.act(seat, {"type":"bid", "value":0}), "all-pass bid accepted")
	check(engine.state.deal == 2 and engine.view(0).played_cards.is_empty(), "redeal resets history")
	check(Recorder.remaining(engine.view(0)).reduce(func(sum, value): return sum + value, 0) == 37, "redeal starts from the new physical hand")
	check(Recorder.remaining({"hand":[0]}).is_empty(), "missing public history is unavailable")
	check(Recorder.remaining({"hand":[0], "played_cards":[0]}).is_empty(), "duplicate accounted card is rejected")
	for seed_value in range(8):
		engine.start(6151 + seed_value, seed_value % 3)
		var actions = 0
		var passed_tricks = 0
		while engine.state.phase != "finished" and actions < 500:
			for viewer in range(3):
				var view = engine.view(viewer)
				var external: Array = []
				for other in range(3):
					if other != viewer: external.append_array(engine.state.hands[other])
				if engine.state.phase == "bidding": external.append_array(engine.state.bottom)
				check(Recorder.remaining(view) == tally(external), "counter equals actual external cards without exposing their owners")
				var repeated = Recorder.remaining(view)
				check(Recorder.remaining(view) == repeated, "refresh does not subtract played cards twice")
				view.played_cards.clear()
				check(view.played_cards.is_empty() and engine.view(viewer).played_cards == engine.state.played_cards, "public history is copied out")
			var seat = engine.state.turn
			var action = AI.choose(engine.view(seat))
			var before = Recorder.remaining(engine.view(seat))
			var previous_history = engine.state.played_cards.duplicate()
			check(engine.act(seat, action), "legal play advances")
			if action.type == "play":
				check(Recorder.remaining(engine.view(seat)) == before, "own play moves hand to history without changing outside counts")
			elif action.type == "pass":
				check(engine.state.played_cards == previous_history, "pass and trick reset keep public history")
				if engine.state.target.is_empty(): passed_tricks += 1
			actions += 1
		check(engine.state.phase == "finished", "simulation finishes")
		for viewer in range(3):
			var external: Array = []
			for other in range(3):
				if other != viewer: external.append_array(engine.state.hands[other])
			check(Recorder.remaining(engine.view(viewer)) == tally(external), "winning final card is recorded once")
		var private_view = engine.view(0)
		private_view["reveal_hands"] = [[53], [52], []]
		private_view["bottom"] = [0, 1, 2]
		check(Recorder.remaining(private_view) == Recorder.remaining(engine.view(0)), "counter ignores revealed hands and bottom, avoiding double subtraction")
	print("DDZ_RECORDER_RESULT: %d failures; %d checks" % [failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
