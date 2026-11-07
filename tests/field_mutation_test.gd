extends SceneTree
var checks = 0
var failures: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("MUTATION FAIL: ", message)

func assignment(owner: int, id: String) -> Array:
	var result = ["", "", "", ""]; result[owner] = id
	var neutral = ["astrology_wall", "angels_gift", "diamond_finger", "reclaim", "chosen_head"]
	neutral.erase(id)
	for seat in range(4):
		if seat != owner: result[seat] = neutral.pop_front()
	return result

func game(ids: Array = [], seed_value: int = 71703) -> GameEngine:
	var engine = GameEngine.new()
	engine.start({"field_rules": true, "field_selection": "mutation", "jiang": "luan", "chi": true}, seed_value, 1, [], [], "", 0, ids)
	return engine

func move(engine: GameEngine, kind: String, extra: Dictionary = {}) -> bool:
	for option in engine.state.pending:
		if option.kind != kind: continue
		if not extra.keys().all(func(key): return option.get(key) == extra[key]): continue
		return engine.submit(engine.decision_seat(), engine.state.revision, str(option.id))
	return false

func replay(engine: GameEngine, label: String) -> void:
	var restored = GameEngine.new()
	var data = JSON.parse_string(JSON.stringify(engine.snapshot()))
	check(restored.restore(data), label + " restores")
	if not restored.state.is_empty():
		check(JSON.parse_string(JSON.stringify(restored.state)) == data.state, label + " reproduces exact state, assignments and moves")

func test_distribution() -> void:
	check(FieldRules.MUTATION_POOL.size() == 13, "exactly thirteen personal rules")
	for excluded in ["mutation", "no_honors", "transparent", "exchange"]:
		check(excluded not in FieldRules.MUTATION_POOL, "excluded from personal pool: " + excluded)
	var seen = {}
	for seed_value in range(1, 65):
		var engine = game([], seed_value)
		check(engine.state.version == 4 and engine.state.field.id == "mutation", "mutation has a distinct save version")
		check(FieldRules.valid_assignment(engine.state.field.seat_rules), "four different eligible rules")
		for id in engine.state.field.seat_rules: seen[id] = true
		check(engine.opening.seat_rules == engine.state.field.seat_rules, "actual assignments recorded at opening")
		check(Tiles.counts(engine.opening.wall) == Tiles.counts(Tiles.wall()), "mutation keeps the normal physical deck")
		check(not engine.state.has("wall_hidden") and engine.state.phase != "exchange", "no global transparency or exchange phase")
		if seed_value <= 4:
			check(game([], seed_value).state == engine.state, "seed reproduces initial assignments")
			replay(engine, "mutation opening")
	check(seen.size() == 13, "seed sample reaches every eligible rule")
	var engine = game()
	var saved = engine.snapshot()
	for invalid in [[], null, ["chosen"], ["chosen", "chosen", "rebirth", "reclaim"], ["no_honors", "chosen", "rebirth", "reclaim"], [1, 2, 3, 4], ["transparent", "chosen", "rebirth", "reclaim"], ["exchange", "chosen", "rebirth", "reclaim"]]:
		var data = saved.duplicate(true); data.opening.seat_rules = invalid
		check(not GameEngine.new().restore(data), "malformed/global/duplicate assignment rejected")
	var data = saved.duplicate(true); data.opening.erase("seat_rules")
	check(not GameEngine.new().restore(data), "v4 requires recorded assignments")
	data = saved.duplicate(true); data.version = 3
	check(not GameEngine.new().restore(data), "mutation cannot be smuggled into v3")
	data = saved.duplicate(true); data.state.field.seat_rules.reverse()
	var restored = GameEngine.new()
	check(restored.restore(data) and restored.state.field.seat_rules == saved.opening.seat_rules, "untrusted serialized state cannot reassign powers")
	var next = GameEngine.new()
	next.start(engine.state.settings, 71704, 2, engine.state.players.map(func(p): return p.score))
	check(next.state.field.id == "mutation" and FieldRules.valid_assignment(next.state.field.seat_rules), "next round retains mode and makes a new valid assignment")
	check(next.state.field.seat_rules != engine.state.field.seat_rules, "independent sample round redistributes rules")

func test_active_ownership() -> void:
	var abilities = {"diamond_finger": "field_transform", "rebirth": "field_rebirth", "reclaim": "field_reclaim", "astrology_wall": "field_peek_wall", "astrology_waits": "field_peek_waits", "angels_gift": "field_gift"}
	for id in abilities:
		for owner in range(4):
			for actor in range(4):
				var engine = game(assignment(owner, id))
				for p in engine.state.players:
					p.hand = [0,1,2,3,4,5,9,10,11,18,19,20,22,27]; p.melds = []; p.drawn = 13
					p.bao = id in ["rebirth", "astrology_waits"] and (id == "rebirth" or p.seat != actor)
				var p = engine.state.players[actor]
				engine.state.current = actor; engine.state.first_discard = false
				if id == "reclaim":
					p.hand = [0,1,2,9,10,11,18,19,20,22,27]; p.drawn = 10
					p.melds = [{"type":"peng","tile":24,"tiles":[24,24,24]}]
				if id == "angels_gift":
					p.hand.pop_back(); p.drawn = -1
					engine.state.wall = [8,12,13,14,15]; engine.state.wall_slots = range(5); engine.state.gang_head = 15
					engine._draw(actor)
				else: engine._turn_options()
				var offered = engine.state.pending.filter(func(option): return option.kind == abilities[id])
				check(not offered.is_empty() if actor == owner else offered.is_empty(), "only assigned owner receives " + id)
				if actor != owner: continue
				var revision = engine.state.revision
				check(not engine.submit((owner + 1) % 4, revision, offered[0].id), "another seat cannot submit owner's ability ID")
				check(engine.submit(owner, revision, offered[0].id), "owner can use " + id)
				check(p.field_used and engine.state.players.all(func(other): return other.seat == owner or not other.field_used), "only owner's use consumed")
				check(not engine.submit(owner, revision, offered[0].id), "duplicate action rejected")
				for viewer in range(4):
					var view = engine.view(viewer)
					check(not view.has("wall") and view.event.tile == -1, "public ability event hides private tiles")
					if viewer != owner: check(not view.players[owner].has("field_private") and view.pending.is_empty() if engine.decision_seat() == owner else not view.players[owner].has("field_private"), "private choices stay with owner")
				if id == "angels_gift":
					check(engine.state.phase == "gift_choice" and p.field_private.gift_tiles == [8,12,13], "only owner sees original draw plus two candidates")
					check(move(engine,"field_gift_pick",{"index":1}) and p.hand.back() == 12, "owner completes three-way choice")
					check(engine.state.wall == [8,13,14,15] and not engine.state.pending.any(func(option): return option.kind == "field_gift"), "unchosen physical tiles return, use is not restored")

func test_personal_shapes() -> void:
	var shapes = {
		"ouroboros": [7,8,0,1,2,3,9,10,11,18,19,20,22,22],
		"honor_sequences": [27,28,31,0,1,2,9,10,11,18,19,20,22,22],
		"wildcard": [0,1,31,9,10,11,18,19,20,24,24,24,13,13]}
	for id in shapes:
		for owner in range(4):
			var engine = game(assignment(owner,id))
			var hand: Array = shapes[id]
			check(not Rules.winning(hand,[],true), "shape needs its assigned special rule: " + id)
			for actor in range(4):
				check(engine._winning(hand,[],actor) == (actor == owner), "winning shape only changes for assigned player")
				check(engine._waits(hand.slice(0,13),[],actor).has(hand[13]) == (actor == owner), "waits only change for assigned player")
				var p = engine.state.players[actor]
				p.hand=hand.duplicate();p.melds=[];p.bao=true;p.drawn=13;engine.state.current=actor
				engine._turn_options()
				check(engine.state.pending.any(func(option):return option.kind=="win") == (actor==owner), "self-draw action uses actor's own rule")
			if id in ["ouroboros", "honor_sequences"]:
				var tiles = [7,8] if id == "ouroboros" else [27,31]
				var discarded = 0 if id == "ouroboros" else 28
				for actor in range(4):
					var p=engine.state.players[actor];p.hand=tiles.duplicate();p.melds=[];p.bao=false;p.ming=false
					engine.state.claim_stage="chi";engine.state.claim_tile=discarded;engine.state.claim_from=(actor+3)%4;engine.state.claim_queue=[actor];engine.state.phase="claim"
					engine._offer_next_claim()
					check(engine.state.pending.any(func(option):return option.kind=="chi") == (actor==owner), "special chi only offered to owner")
	var engine = game(assignment(1,"single_wait"))
	var broad=[0,1,2,9,10,11,18,19,20,24,24,3,4]
	check(engine._waits(broad,[],0).size()>1 and engine._waits(broad,[],1).is_empty(), "single-wait restriction does not leak to others")
	for owner in range(4):
		engine=game(assignment(owner,"tolerance"))
		for actor in range(4):
			var p=engine.state.players[actor];p.hand=[0,1,2,9,10,11,18,19,20,13];p.melds=[{"type":"peng","tile":24,"tiles":[24,24,24]}];p.bao=true;p.ming=false;p.drawn=-1
			engine.state.phase="claim";engine.state.claim_stage="meld";engine.state.claim_tile=24;engine.state.claim_from=(actor+1)%4;engine.state.claim_queue=[actor]
			engine._offer_next_claim()
			check(engine.state.pending.any(func(option):return option.kind=="tolerance_gang") == (actor==owner), "only tolerance owner extends pung from another player's discard")
		engine=game(assignment(owner,"diamond_finger"))
		for actor in range(4):
			check(engine._can_extend({"type":"gang","tile":33,"tiles":[33,33,33,33]},actor) == (actor==owner), "extra white kong restricted to diamond owner")

func test_scoring_and_peeks() -> void:
	for id in ["chosen", "chosen_head", "single_wait"]:
		var engine=game(assignment(2,id))
		var tile=engine.state.field.chosen_tiles[0] if id=="chosen" else engine.state.gang_head
		for actor in range(4):
			var bonus=engine._field_bonuses(actor,[tile],{"self_draw":true,"tile":tile})
			check(not bonus.is_empty() if actor==2 else bonus.is_empty(), "bonus only belongs to " + id + " owner")
	var engine=game(["astrology_waits","ouroboros","chosen","chosen_head"])
	var target=engine.state.players[1]
	target.hand=[7,8,0,1,2,3,9,10,11,18,19,20,22];target.melds=[];target.bao=true;target.drawn=-1
	engine.state.current=0;engine._turn_options()
	check(move(engine,"field_peek_waits",{"target":1}), "astrologer can inspect another owner's waits")
	check(engine.state.players[0].field_private.peek_waits.has(22) and not Rules.waits(target.hand,[],true).has(22), "peek uses target's ouroboros rather than astrologer's ordinary rules")
	engine._settle(1,{"source":0,"tile":22,"self_draw":false})
	check(engine.state.result.patterns.any(func(pattern):return pattern.name=="占星·点炮"), "astrology user's dealing-in penalty applies across personal rules")
	engine=game(["astrology_waits","chosen","reclaim","chosen_head"])
	engine.state.players[0].field_private.peek_target=1
	var tile=engine.state.field.chosen_tiles[0]
	check(engine._field_bonuses(1,[tile],{"source":0,"tile":tile})==["天选","占星·点炮"], "winner's own bonus and source's astrology penalty both apply")
	engine.state.players[2].field_private.peek_target=1
	check(engine._field_bonuses(1,[tile],{"source":2,"tile":tile})==["天选"], "non-owner cannot impersonate astrology through private metadata")

func test_replays_and_simulations() -> void:
	var legacy=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/replay-field-v3.json"))
	for id in legacy:
		var restored=GameEngine.new()
		check(restored.restore(legacy[id]), "pre-change v3 fixture restores: " + id)
		check(JSON.parse_string(JSON.stringify(restored.state))==legacy[id].state, "pre-change v3 state and private randomness unchanged: " + id)
	var sets=[
		["angels_gift","ouroboros","honor_sequences","wildcard"],
		["rebirth","diamond_finger","reclaim","tolerance"],
		["astrology_wall","astrology_waits","single_wait","chosen"],
		["chosen_head","angels_gift","astrology_wall","ouroboros"]]
	var ai=MahjongAI.new()
	for index in range(sets.size()):
		var engine=game(sets[index],72110+index)
		var steps=0
		while engine.state.phase!="settled" and steps<800:
			var seat=engine.decision_seat();var view=engine.view(seat)
			var expected=view.duplicate(true);expected.field.id=FieldRules.for_seat(view.field,seat)
			var selected=ai.choose(view,seat,0.25)
			if steps<3: check(selected==ai.choose(expected,seat,0.25), "AI applies its assigned field to card analysis")
			check(engine.submit(seat,engine.state.revision,str(selected.id)), "mixed-rule AI submits legal action")
			var total=engine.state.wall.size()
			for p in engine.state.players:
				total+=p.hand.size()+p.discards.size()+p.field_private.get("gift_tiles",[]).size()
				for meld in p.melds:total+=meld.tiles.size()
			check(total==144 and engine.state.wall.size()==engine.state.wall_slots.size(), "mixed abilities preserve every physical tile and slot")
			if steps in [2,15]:replay(engine,"mixed rules during play")
			steps+=1
		check(engine.state.phase=="settled", "mixed-rule simulation finishes")
		check(engine.state.players.reduce(func(sum,p):return sum+p.score,0)==8000, "mixed-rule scores remain zero sum")
		replay(engine,"mixed rules final")
		print("Mutation simulation %d: %d actions" % [index+1,steps])

func run() -> void:
	test_distribution()
	test_active_ownership()
	test_personal_shapes()
	test_scoring_and_peeks()
	test_replays_and_simulations()
	print("FIELD_MUTATION_RESULT: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
