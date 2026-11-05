extends SceneTree

var checks = 0
var failures: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FIELD ENGINE FAIL: ", message)

func game(id: String, game_seed: int = 5713) -> GameEngine:
	var engine = GameEngine.new()
	engine.start({"field_rules": true, "jiang": "luan", "chi": true}, game_seed, 1, [], [], id)
	return engine

func move(engine: GameEngine, kind: String, extra: Dictionary = {}) -> bool:
	for option in engine.state.pending:
		if option.kind != kind: continue
		var matches = true
		for key in extra:
			if option.get(key) != extra[key]: matches = false
		if matches: return engine.submit(engine.decision_seat(), engine.state.revision, str(option.id))
	return false

func replay(engine: GameEngine, label: String) -> void:
	var restored = GameEngine.new()
	var data = JSON.parse_string(JSON.stringify(engine.snapshot()))
	var ok = restored.restore(data)
	check(ok, label + " restores")
	if ok: check(JSON.parse_string(JSON.stringify(engine.state)) == JSON.parse_string(JSON.stringify(restored.state)), label + " exact replay state")

func run() -> void:
	var started = Time.get_ticks_msec()
	_test_opening()
	_test_actions()
	_test_privacy()
	_test_exchange()
	_test_simulations()
	print("FIELD_ENGINE_RESULT: %d checks, %d failures, %.2fs" % [checks, failures.size(), (Time.get_ticks_msec()-started)/1000.0])
	quit(0 if failures.is_empty() else 1)

func _test_opening() -> void:
	var engine = GameEngine.new(); engine.start({}, 5713)
	check(not engine.state.has("field") and engine.snapshot().version == 1, "normal games retain version 1 and no field")
	engine.start({"field_rules": false}, 5713)
	check(not engine.state.has("field"), "explicitly disabled field remains normal")
	var seen = {}
	for seed_value in range(1, 257):
		engine.start({"field_rules": true}, seed_value)
		seen[engine.state.field.id] = true
	check(seen.size() == 16, "random draw can select all 16 fields")
	for id in FieldRules.IDS:
		engine = game(id)
		check(engine.state.field.id == id and engine.snapshot().version == 2, "field opening " + id)
		replay(engine, "opening " + id)
		if id == "no_honors":
			var counts = Tiles.counts(engine.opening.wall)
			check(engine.opening.wall.size() == 144 and counts.slice(27, 34).all(func(n): return n == 0), "no honors replaces 28 and keeps flowers")
			check(counts.slice(0, 27).reduce(func(a,b):return a+b,0) == 136, "136 suited tiles in no honors")
		if id == "chosen":
			var targets = engine.state.field.chosen_tiles
			check(targets.size() == 3 and targets[0] != targets[1] and targets[0] != targets[2] and targets[1] != targets[2] and targets.all(func(t):return t<27), "chosen targets distinct suited faces")
		if id == "transparent":
			var hidden = []
			for i in range(engine.state.wall.size()):
				if engine.state.wall_hidden[i]: hidden.append(engine.state.wall[i])
			for p in engine.state.players:
				for i in range(p.hand.size()):
					if p.hidden[i]: hidden.append(p.hand[i])
			check(hidden.size() == 34 and Tiles.counts(hidden).slice(0,34).all(func(n):return n==1), "one opaque physical copy per face")

func _test_actions() -> void:
	var engine = game("diamond_finger"); var p = engine.state.players[0]
	p.hand = [0,1,2,3,4,5,6,7,8,9,10]; p.melds = [{"type":"gang","tile":33,"tiles":[33,33,33,33]}]; p.drawn = 10
	engine._turn_options()
	check(move(engine,"field_transform",{"index":0}), "transform is legal")
	check(p.hand[0] == 33 and p.field_used, "transform replaces exactly one tile")
	check(not engine.state.pending.any(func(a):return a.kind=="field_transform"), "transform cannot repeat")
	check(engine.view(1).field.tile_totals[0] == 4 and engine.view(1).field.tile_totals[33] == 5, "missing face remains private")
	var old_head = engine.state.gang_head
	check(move(engine,"bugang"), "fifth white extends kong")
	check(p.melds[0].tiles.size() == 5 and p.hand.back() == old_head, "fifth tile earns a replacement draw")

	engine = game("rebirth"); p = engine.state.players[0]
	p.hand = [0,1,2,3,4,5,9,10,11,18,19,20,22,27]; p.melds = []; p.bao = true; p.drawn = 13
	engine._turn_options(); check(move(engine,"field_rebirth"), "rebirth offered after declaration")
	check(p.revealed_hand and not p.bao and not p.ming and p.field_used, "rebirth reveals but unlocks")
	check(engine.view(1).players[0].hand == p.hand, "reborn hand is public")
	check(not engine.state.pending.any(func(a):return a.kind=="bao") and engine.state.pending.any(func(a):return a.kind=="ming"), "reborn player can only redeclare open")
	check(engine._scores_as_ming(p), "reborn player retains open-hand scoring")

	engine = game("reclaim"); p = engine.state.players[0]
	p.hand = [0,1,2,3,4,5,6,7,8,9,9]; p.melds = [{"type":"peng","tile":13,"tiles":[13,13,13],"from":1}]; p.drawn = 10
	engine._turn_options(); check(move(engine,"field_reclaim"), "reclaim a meld")
	check(p.hand.size()==14 and p.melds.is_empty() and p.hand.count(13)==3 and p.field_used, "reclaim conserves effective hand size")

	engine = game("tolerance"); p = engine.state.players[1]
	p.hand = [0,1,2,9,10,11,18,19,20,13]; p.melds = [{"type":"peng","tile":24,"tiles":[24,24,24]}]; p.bao = true; p.drawn = -1
	engine.state.players[0].discards = [24]; engine.state.claim_from = 0; engine.state.claim_tile = 24; engine.state.claim_stage = "meld"; engine.state.claim_queue = [1]; engine.state.phase = "claim"
	engine._offer_next_claim(); old_head = engine.state.gang_head
	check(move(engine,"tolerance_gang"), "declared player may extend pung with discard")
	check(p.melds[0].tiles.size()==4 and p.hand.back()==old_head, "tolerance draws kong head and keeps hand")

	engine = game("angels_gift"); p = engine.state.players[1]
	engine.state.wall = [1,2,3,8]; engine.state.wall_slots = [0,1,2,3]; engine.state.gang_head = 8
	var size_before = p.hand.size()
	engine._draw(1); check(engine.state.phase=="draw_choice", "gift is offered before normal draw")
	check(move(engine,"field_gift"), "gift use")
	check(engine.state.phase=="gift_choice" and p.field_private.gift_tiles==[1,2,3], "gift shows top three")
	check(move(engine,"field_gift_pick",{"index":1}), "pick middle of three")
	check(p.hand.size()==size_before+1 and p.hand.back()==2 and engine.state.wall==[1,3,8], "unchosen gift tiles preserve original wall order")
	p.bao=true; p.field_used=false; engine.state.wall=[0,1,2,3,8]; engine.state.wall_slots=[0,1,2,3,4]
	engine._draw(1); check(engine.state.phase!="draw_choice", "gift unavailable while declared")

	engine=game("astrology_waits"); p=engine.state.players[0]
	var target=engine.state.players[1]
	target.hand=[0,1,2,9,10,11,18,19,20,24,24,24,13]; target.melds=[];target.bao=true;target.drawn=-1
	engine._turn_options(); check(move(engine,"field_peek_waits",{"target":1}), "peek declared opponent")
	check(p.field_private.peek_target==1 and 13 in p.field_private.peek_waits, "peek returns true waits to owner")
	engine._settle(1,{"self_draw":false,"source":0,"tile":13})
	check(engine.state.result.patterns.any(func(pattern):return pattern.name=="占星·点炮"), "dealing into peeked target adds a fan")

	engine=game("chosen_head");p=engine.state.players[0]
	p.last_draw_head=13;engine.state.gang_head=2
	check(engine._field_bonuses(0,[13],{"self_draw":true,"tile":13})==["天选·杠头"], "kong win compares the consumed head")
	check(engine._field_bonuses(0,[2],{"tianhu":true,"tile":3})==["天选·杠头"], "heavenly win checks presence of current head")

func _test_privacy() -> void:
	var engine=game("astrology_wall")
	check(move(engine,"field_peek_wall"),"wall astrology use")
	check(engine.view(0).players[0].field_private.peek_wall==engine.state.wall.slice(0,4),"wall astrology exact snapshot")
	for seat in range(1,4):
		var public=engine.view(seat)
		check(not public.has("wall") and not public.players[0].has("field_private"),"astrology private for seat %d"%seat)
		check(public.event.tile==-1 and not public.event.has("target"),"ability event reveals no private result")
	replay(engine,"used astrology")
	engine=game("transparent")
	for seat in range(4):
		var public=engine.view(seat)
		check(not public.has("wall_hidden"),"opaque wall identity redacted")
		for other in range(4):
			var owner=engine.state.players[other];var shown=public.players[other]
			check(shown.hand.size()==owner.hand.size(),"transparent mixed hand retains count")
			var expected=[]
			for i in range(owner.hand.size()):
				expected.append(-1 if owner.hidden[i] and other!=seat else owner.hand[i])
			expected.sort()
			var faces=shown.hand.duplicate();faces.sort()
			check(faces==expected,"physical visibility survives sorting and flower replacement")
	engine=game("diamond_finger")
	move(engine,"field_transform")
	check(engine.view(1).event.tile==-1,"transformation event hides lost tile")
	replay(engine,"used transformation")

func _test_exchange() -> void:
	var engine=game("exchange")
	var originals=engine.state.players.map(func(p):return p.hand.duplicate())
	var packets=[]
	for seat in range(4):
		var selected=engine.state.pending[0].duplicate(true)
		packets.append(selected.tiles)
		check(selected.tiles.all(func(tile):return tile<27),"exchange prioritizes suited tiles")
		check(move(engine,"field_exchange",{"indices":selected.indices}),"submit exchange packet")
		if seat<3:
			check(engine.state.players.map(func(p):return p.hand)==originals,"no packet moves before all choose")
			replay(engine,"exchange choice %d"%seat)
			check(not engine.view((seat+1)%4).has("exchange_picks"),"exchange indices private")
	for seat in range(4):
		var expected=originals[seat].duplicate()
		for tile in packets[seat]:expected.erase(tile)
		expected.append_array(packets[(seat+3)%4]);expected.sort()
		check(engine.state.players[seat].hand==expected,"exchange passes to next seat")
	replay(engine,"complete exchange")

func _test_simulations() -> void:
	var ai=MahjongAI.new()
	for id in FieldRules.IDS:
		var engine=game(id,63117)
		var steps=0
		while engine.state.phase!="settled" and steps<800:
			var seat=engine.decision_seat();var public=engine.view(seat)
			check(public.pending.size()>0,"live decision has actions "+id)
			if public.pending.is_empty():break
			check(JSON.stringify(public).to_utf8_buffer().size()<65536,"seat view fits LAN packet "+id)
			var choice=ai.choose(public,seat,0.1)
			check(not choice.is_empty(),"AI handles field phase "+id)
			if choice.is_empty():break
			check(engine.submit(seat,engine.state.revision,str(choice.id)),"field action accepted "+id)
			check(engine.state.wall.size()==engine.state.wall_slots.size(),"wall physical slots remain aligned "+id)
			var total=engine.state.wall.size()
			for player in engine.state.players:
				total+=player.hand.size()+player.discards.size()
				for meld in player.melds:total+=meld.tiles.size()
			check(total==144,"field actions conserve tile count "+id)
			if steps in [3,25]:replay(engine,id+" step "+str(steps))
			steps+=1
		check(engine.state.phase=="settled","field game terminates "+id)
		check(engine.state.players.reduce(func(sum,p):return sum+p.score,0)==8000,"field settlement zero sum "+id)
		replay(engine,id+" final")
		print("Field simulation: ",id," / ",steps," actions")
