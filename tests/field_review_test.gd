extends SceneTree

var checks = 0
var failures: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("FIELD_REVIEW_FAIL: ", message)

func game(field_id: String) -> GameEngine:
	var engine = GameEngine.new()
	engine.start({"field_rules":true, "jiang":"258"}, 45127, 1, [], [], field_id)
	return engine

func run() -> void:
	_test_opaque_order()
	_test_public_status()
	_test_locked_tolerance()
	_test_repeated_kong()
	_test_restore_validation()
	_test_chosen_payment()
	print("FIELD_REVIEW_RESULT: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_opaque_order() -> void:
	var engine = game("transparent")
	# Swapping two concealed identities preserves every public fact. The
	# observer must not learn their rank through private sorting positions.
	var first = engine.state.players[1]
	var second = engine.state.players[2]
	first.hand = [0,2,3,4,5,6,7,8,9,10,11,12,13]
	second.hand = [1,14,15,16,17,18,19,20,21,22,23,24,25]
	first.hidden = [true,false,false,false,false,false,false,false,false,false,false,false,false]
	second.hidden = [false,false,false,false,false,false,false,false,false,false,false,false,true]
	first.drawn = -1; second.drawn = -1
	var before = engine.view(0)
	first.hand[0] = 25; second.hand[12] = 0
	engine._sort_hand(first); engine._sort_hand(second)
	var after = engine.view(0)
	check(before.players[1].hand == after.players[1].hand and before.players[2].hand == after.players[2].hand, "opaque identities cannot leak through sorted hand position")
	check(after.players[1].hand.filter(func(tile):return tile>=0) == [2,3,4,5,6,7,8,9,10,11,12,13], "visible faces remain complete when dark slots are grouped")
	# A newly drawn transparent tile stays recognisable as the new tile; a
	# newly drawn opaque tile retains only its slot, not its rank.
	first.hand.append(30); first.hidden.append(true); first.drawn = first.hand.size()-1
	var drawn = engine.view(0).players[1]
	check(drawn.drawn == drawn.hand.size()-1 and drawn.hand.back() == -1 and not drawn.hand_public.back(), "opaque newly drawn tile remains private in its drawn slot")
	first.hidden[-1] = false
	drawn = engine.view(0).players[1]
	check(drawn.hand.back() == 30 and drawn.hand_public.back(), "transparent newly drawn tile is actually visible")

func _test_public_status() -> void:
	var engine = game("transparent")
	var owner = engine.state.players[0]
	var own_view = engine.view(0).players[0]
	check(engine.view(0).gang_head == -1 and engine.view(1).gang_head == -1, "transparent field also conceals the wall's kong head")
	owner.last_draw_head = 13
	check(engine.view(1).players[0].last_draw_head == -1, "past concealed kong-head identity is not a side channel")
	check(own_view.hand == owner.hand, "owner always knows the faces of opaque tiles")
	check(own_view.hand_public == owner.hidden.map(func(hidden):return not hidden), "owner knows exactly which tiles opponents can see")
	owner.ming = true
	check(engine.view(0).players[0].hand_public.all(func(value):return value), "open declaration updates owner's visibility badges")
	check(engine.view(1).players[0].hand == owner.hand, "open declaration reveals all opaque tiles to other seats")
	owner.ming = false; engine._draw_result()
	check(engine.view(0).players[0].hand_public.all(func(value):return value), "settlement marks every revealed tile as public")

func _test_locked_tolerance() -> void:
	var engine = game("tolerance")
	var player = engine.state.players[1]
	player.hand = [27,27,27,28,28,28,29,29,29,31]
	player.melds = [{"type":"peng", "tile":30, "tiles":[30,30,30]}]
	player.bao = true; player.drawn = -1
	var before = engine._waits(player.hand, player.melds)
	var changed = player.melds.duplicate(true); changed[0].type = "gang"; changed[0].tiles.append(30)
	check(before == [31] and engine._waits(player.hand, changed).is_empty(), "tolerance fixture detects base-rule special-color wait change")
	engine.state.players[0].discards = [30]
	engine.state.claim_from = 0; engine.state.claim_tile = 30
	engine.state.claim_stage = "meld"; engine.state.claim_queue = [1]; engine.state.phase = "claim"
	engine._offer_next_claim()
	check(not engine.state.pending.any(func(move):return move.kind=="tolerance_gang"), "locked tolerance cannot destroy the declared wait")

func _test_repeated_kong() -> void:
	var engine = game("no_honors")
	var player = engine.state.players[0]
	player.hand = [0,1,2,9,10,11,18,19,20,4,24]
	player.melds = [{"type":"angang", "tile":24, "tiles":[24,24,24,24]}]
	player.bao = true; player.drawn = 10
	engine.state.wall = [1,2,3,24,24]; engine.state.wall_slots = [0,1,2,3,4]; engine.state.gang_head = 24
	engine._turn_options()
	for expected_size in [5,6]:
		var moves = engine.state.pending.filter(func(move):return move.kind=="bugang" and move.tile==24)
		check(not moves.is_empty(), "each excess tile can extend the same declared concealed kong")
		if moves.is_empty(): break
		var previous_wall_size = engine.state.wall.size()
		check(engine.submit(0, engine.state.revision, moves[0].id), "excess kong submits through normal action authority")
		check(player.melds[0].tiles.size()==expected_size and engine.state.wall.size()==previous_wall_size-1, "one excess tile earns exactly one head draw")
		var remote = engine.view(1)
		check(remote.players[0].melds[0].tiles.all(func(tile):return tile==-1) and remote.event.tile==-1, "excess concealed kong keeps all faces private")
	var winning_hand = [0,1,2,9,10,11,18,19,20,4,4]
	var first_kong = [{"type":"angang", "tile":24, "tiles":[24,24,24,24]}]
	var extended = [{"type":"angang", "tile":24, "tiles":[24,24,24,24,24,24]}]
	var flags = {"field_id":"no_honors", "bao":true, "self_draw":true}
	var first_score = Rules.evaluate(winning_hand, first_kong, flags)
	var extended_score = Rules.evaluate(winning_hand, extended, flags)
	check(extended_score.hua == first_score.hua+4, "two additional concealed kongs each add their normal flower points")

func _test_restore_validation() -> void:
	var source = game("astrology_wall")
	var action = source.state.pending.filter(func(move):return move.kind=="field_peek_wall")[0]
	source.submit(0, source.state.revision, action.id)
	var baseline = JSON.parse_string(JSON.stringify(source.snapshot()))
	var receiver = GameEngine.new(); receiver.start({}, 7654)
	var untouched = receiver.state.duplicate(true)
	var cases: Array = []
	var data = baseline.duplicate(true); data.version = 2.25; cases.append(["fractional version", data])
	data = baseline.duplicate(true); data.opening.settings = []; cases.append(["non-dictionary settings", data])
	data = baseline.duplicate(true); data.opening.settings.field_rules = "true"; cases.append(["non-boolean field toggle", data])
	data = baseline.duplicate(true); data.state.players = null; cases.append(["non-array player list", data])
	data = baseline.duplicate(true); data.opening.scores = [1,2]; cases.append(["wrong score count", data])
	data = baseline.duplicate(true); data.opening.erase("scores"); cases.append(["missing scores", data])
	data = baseline.duplicate(true); data.opening.scores = [1,2,3,4.5]; cases.append(["fractional scores", data])
	data = baseline.duplicate(true); data.opening.dice = "11"; cases.append(["non-array dice", data])
	data = baseline.duplicate(true); data.opening.dice = [0,7]; cases.append(["out-of-range dice", data])
	data = baseline.duplicate(true); data.opening.round = -1; cases.append(["negative round", data])
	data = baseline.duplicate(true); data.opening.erase("seed"); cases.append(["missing seed", data])
	data = baseline.duplicate(true); data.journal[0].seat = 0.5; cases.append(["fractional seat", data])
	data = baseline.duplicate(true); data.journal[0].revision = 0.25; cases.append(["fractional revision", data])
	data = baseline.duplicate(true); data.journal[0].erase("action"); cases.append(["missing journal action", data])
	data = baseline.duplicate(true); data.rng_state = {}; cases.append(["non-string random state", data])
	for item in cases:
		check(not receiver.restore(item[1]), "restore rejects " + item[0])
		check(receiver.state == untouched, "rejected " + item[0] + " leaves running game intact")
	check(receiver.restore(baseline), "validated field snapshot still restores after malformed attempts")

func _test_chosen_payment() -> void:
	var engine = game("chosen")
	engine.state.field.chosen_tiles = [4,13,22]
	var player = engine.state.players[0]
	player.hand = [0,1,2,3,4,5,9,10,11,18,19,20,22,22]
	player.melds = []; player.bao = true; player.drawn = 13
	var regular = Rules.evaluate(player.hand, [], {"luan":false, "bao":true, "self_draw":true})
	engine._settle(0, {"self_draw":true, "tile":22})
	check(engine.state.result.points == regular.points*2, "chosen adds exactly one fan despite multiple selected faces in hand")
	check(engine.state.result.deltas.reduce(func(total,value):return total+value,0)==0, "chosen extra fan preserves zero-sum settlement")
	engine = game("chosen_head"); player = engine.state.players[0]
	player.hand = [0,1,2,3,4,5,9,10,11,18,19,20,22,22]
	player.melds = []; player.bao = true; player.drawn = 13; player.last_draw_head = -1
	engine.state.gang_head = 22
	engine._settle(0, {"self_draw":true, "tile":22})
	check(engine.state.result.points==regular.points*2, "ordinary draw matching current head also earns chosen-head fan")
