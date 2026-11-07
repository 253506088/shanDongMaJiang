extends SceneTree
## Optional reproducible cross-play evaluation, not a strength assertion.
## --baseline-script <absolute old ai.gd> --output <absolute report.json>
const Game = preload("res://scripts/bluff/core/engine.gd")
const Cards = preload("res://scripts/bluff/core/cards.gd")
const AI = preload("res://scripts/bluff/core/ai.gd")
var failures: Array = []

func _initialize() -> void:
	run()

func argument(key: String) -> String:
	var args = OS.get_cmdline_user_args(); var index = args.find(key)
	return args[index + 1] if index >= 0 and index + 1 < args.size() else ""

func run() -> void:
	var baseline_path = argument("--baseline-script")
	if baseline_path.is_empty():
		printerr("Provide --baseline-script with an archived AI source for cross-play."); quit(1); return
	var baseline = load(baseline_path)
	# Reproduce the complaint with complete, conserved physical hands. The
	# bot receives no knowledge of the three K in its next opponent's hand.
	var example = Game.new(); example.start(71107)
	var own = [0, 1, 4, 8, 12, 16, 20, 24, 28, 32, 36, 44, 48, 49, 5, 9, 13, 17]
	var rest = range(54).filter(func(id): return id not in own and id not in [40, 41, 42])
	example.state.hands = [own, [40, 41, 42] + rest.slice(0, 15), rest.slice(15)]
	example.state.phase = "playing"; example.state.turn = 2
	example.act(2, {"revision": 0, "type": "play", "cards": [example.state.hands[2][0]], "rank": 13})
	var example_rates = {"seeds": 1000, "old_five_k": 0, "new_five_k": 0}
	for seed_value in range(1000):
		for policy in ["old", "new"]:
			var rng = RandomNumberGenerator.new(); rng.seed = 77100 + seed_value
			var view = example.view(0)
			var action = baseline.choose(view, rng, false) if policy == "old" else AI.choose(view, rng, false)
			if action.type == "play" and action.cards.size() >= 5: example_rates[policy + "_five_k"] += 1
	if example_rates.new_five_k != 0: failures.append("five-K regression")
	var report = {"games": 0, "finished": 0, "new_wins": 0, "equal_seat_expectation": 0.0, "by_players": {},
		"new": {"plays": 0, "lies": 0, "next_seat_can_disprove": 0, "cards_played": 0},
		"old": {"plays": 0, "lies": 0, "next_seat_can_disprove": 0, "cards_played": 0}}
	report["five_k_case"] = example_rates
	var timings: Array = []; var move_counts: Array = []
	for players in range(3, 7):
		var summary = {"games": 0, "wins": 0, "unfinished": 0}
		for seed_index in range(int(24 / players)):
			for candidate_seat in range(players):
				var game = Game.new(); game.start(71000 + seed_index, {"players": players})
				var randoms: Array = []
				for seat in range(players):
					var rng = RandomNumberGenerator.new(); rng.seed = 93000 + seed_index * 37 + seat
					randoms.append(rng)
				var steps = 0
				while game.state.phase != "finished" and steps < 2500:
					var seat = 0; var action = {"revision": game.state.revision}
					if game.state.phase == "rps": action.merge({"type": "rps", "gesture": randoms[0].randi_range(0, 2)})
					elif game.state.phase == "review": action["type"] = "continue"
					else:
						seat = game.state.permission.approver if game.state.phase == "permission" else game.state.turn
						var view = game.view(seat)
						var start = Time.get_ticks_usec()
						action = AI.choose(view, randoms[seat]) if seat == candidate_seat else baseline.choose(view, randoms[seat])
						if seat == candidate_seat: timings.append(Time.get_ticks_usec() - start)
					if not game.act(seat, action):
						failures.append("illegal action " + str(action)); break
					if action.type == "play" and game.state.phase == "playing":
						var stats: Dictionary = report["new" if seat == candidate_seat else "old"]
						stats.plays += 1; stats.cards_played += action.cards.size()
						if not action.cards.all(func(id): return Cards.matches(id, action.rank)):
							stats.lies += 1
							# Evaluation may inspect the next seat's own view after the
							# action; that information was never supplied to the actor.
							var evidence = AI.assessment(game.view(game.state.turn))
							if evidence.certain and evidence.false_chance > 0.5: stats.next_seat_can_disprove += 1
					steps += 1
				move_counts.append(steps)
				report.games += 1; summary.games += 1
				report.equal_seat_expectation += 1.0 / players
				if game.state.phase == "finished":
					report.finished += 1
					if game.state.winner == candidate_seat: report.new_wins += 1; summary.wins += 1
				else: summary.unfinished += 1; failures.append("game did not finish")
		report.by_players[players] = summary
		print("BLUFF_EVAL_PROGRESS: ", players, " players ", summary)
	timings.sort(); move_counts.sort()
	report["decision_ms"] = {"median": timings[timings.size() / 2] / 1000.0, "p95": timings[int(timings.size() * 0.95)] / 1000.0, "max": timings.back() / 1000.0}
	report["moves"] = {"median": move_counts[move_counts.size() / 2], "max": move_counts.back()}
	report["failures"] = failures
	if not argument("--output").is_empty():
		var file = FileAccess.open(argument("--output"), FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t")); file.close()
	print("BLUFF_STRATEGY_EVAL: ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
