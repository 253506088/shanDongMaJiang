extends SceneTree
var checks = 0
var failures: Array = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		if failures.size() < 25: printerr("FAIL: ",message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var start = Time.get_ticks_msec()
	var fixtures = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/upstream_rules.json"))
	for i in range(fixtures.cases.size()):
		var c = fixtures.cases[i]
		var hand = integers(c.hand)
		var melds = c.melds.duplicate(true)
		for m in melds: m.tile=int(m.tile); m.tiles=integers(m.tiles)
		check(Rules.winning(hand,melds,c.flags.luan)==c.winning,"winning oracle %d %s"%[i,c.label])
		var result = Rules.evaluate(hand,melds,c.flags)
		if c.expected==null:check(result.is_empty(),"invalid score oracle %d"%i)
		else:
			for key in c.expected:check(result.get(key)==c.expected[key],"score oracle %d %s: %s != %s"%[i,key,result.get(key),c.expected[key]])
	print("Rule oracle complete: ",checks," checks")
	var ai=MahjongAI.new()
	for i in range(fixtures.ai.size()):
		var c=fixtures.ai[i];var hand=integers(c.hand)
		var best=ai.rank(hand,[],c.luan,hand,c.classic)[0]
		check(best.index==c.index,"AI oracle %d index %s != %s"%[i,best.index,c.index])
		check((not best.waits.is_empty() and (c.classic or best.remaining>0))==c.ready,"AI ready oracle %d"%i)
	print("AI oracle complete")
	_test_edges()
	_test_engine()
	_test_storage()
	print("RESULT: %d checks, %d failures, %.2fs"%[checks,failures.size(),(Time.get_ticks_msec()-start)/1000.0])
	quit(0 if failures.is_empty() else 1)

func integers(array: Array) -> Array:
	return array.map(func(v):return int(v))

func _test_edges() -> void:
	var e=GameEngine.new();e.start({},8912)
	var p=e.state.players[0]
	e.state.current=0;p.hand=[0,1,2,9,10,11,18,19,20,24,24,24,13,13];p.melds=[];p.drawn=13;p.bao=true
	e._turn_options()
	check(e.state.pending.any(func(a):return a.kind=="win"),"declared self draw legal")
	check(not e.state.pending.any(func(a):return a.kind in ["angang","bugang","bao","ming"]),"declared hand cannot remeld or redeclare")
	check(e.state.pending.filter(func(a):return a.kind=="discard").size()==1,"locked discard only drawn tile")
	p.bao=false;e._turn_options()
	check(not e.state.pending.any(func(a):return a.kind=="win"),"undeclared normal self draw rejected")
	var decision=e.state.pending.filter(func(a):return a.kind=="bao")
	check(not decision.is_empty(),"ready discard declaration offered")
	for move in decision:
		var hand=p.hand.duplicate();hand.remove_at(move.index)
		check(not Rules.waits(hand,p.melds).is_empty(),"declaration validates actual discarded tile")
	# Flowers replace before the public head; kongs consume and replace it.
	p.hand=[];p.melds=[];e.state.wall=[34,5,1];e.state.gang_head=1;e.state.phase="turn"
	e._draw(0,"normal")
	check(p.hand==[5] and e.state.wall==[1] and e.state.gang_head==1,"flower does not consume gang head")
	check(Rules.flower_count(p.melds)==1,"flower exposed exactly once")
	e.state.wall=[4,35,1];e.state.gang_head=1;e._draw(0,"kong")
	check(p.hand.back()==1 and e.state.gang_head==4 and e.state.wall==[35,4],"kong draws public head and replaces flower tail")
	e.state.wall=[4];e._draw(0,"normal")
	check(e.state.phase=="settled" and e.state.result.draw,"reserved head cannot be normal draw")
	# Score transfer conventions, including the separate payer ming multiplier.
	for scenario in ["self","discard","rob","dihu"]:
		e=GameEngine.new();e.start({},9312);p=e.state.players[0]
		p.hand=[0,1,2,9,10,11,18,19,20,24,24,24,13];p.melds=[];p.bao=true;e.state.players[1].ming=true
		var flags={"tile":13,"source":1}
		if scenario=="self":p.hand.append(13);flags.self_draw=true
		if scenario=="rob":flags.robbed=true
		if scenario=="dihu":flags.dihu=true
		e._settle(0,flags)
		var r=e.state.result;var unit=r.points
		check(r.deltas[1]==-unit*(6 if scenario=="rob" else 2),"ming payer multiplier "+scenario)
		check(r.deltas[2]==(-unit if scenario in ["self","dihu"] else 0),"ordinary ron has one payer "+scenario)
		check(r.deltas.reduce(func(a,b):return a+b,0)==0,"settlement balanced "+scenario)
	# Corrupt saved walls never become active states.
	e=GameEngine.new();e.start({},31)
	var saved=e.snapshot();saved.opening.wall[0]=999
	check(not GameEngine.new().restore(saved),"reject malformed saved tile")

func _test_engine() -> void:
	var bot=MahjongAI.new()
	for match_index in range(12):
		var settings={"jiang":"258" if match_index%2==0 else "luan","chi":match_index%3!=0,"ai":"classic" if match_index%2==0 else "efficiency"}
		var engine=GameEngine.new();engine.start(settings,93000+match_index)
		var steps=0
		while engine.state.phase!="settled" and steps<650:
			_conservation(engine)
			var seat=engine.decision_seat();var view=engine.view(seat)
			check(not view.has("wall"),"seat view hides wall")
			for p in view.players:
				if p.seat!=seat and not p.ming:check(p.hand.is_empty(),"seat view hides opponents")
			check(not engine.submit((seat+1)%4,engine.state.revision,"0"),"reject wrong seat")
			check(not engine.submit(seat,engine.state.revision-1,"0"),"reject stale command")
			check(not engine.submit(seat,engine.state.revision,"99999"),"reject forged action")
			var move=bot.choose(view,seat,0.1 if steps%7==0 else 0.8)
			check(not move.is_empty(),"AI has a legal action")
			check(engine.submit(seat,engine.state.revision,str(move.id)),"accept valid action")
			if steps==25:
				var saved=JSON.parse_string(JSON.stringify(engine.snapshot()))
				var restored=GameEngine.new()
				check(restored.restore(saved),"restore replay")
				check(JSON.stringify(restored.state)==JSON.stringify(engine.state),"restored state exact")
			steps+=1
		check(engine.state.phase=="settled","full match terminates %d"%match_index)
		_conservation(engine)
		var sum=0
		for p in engine.state.players:sum+=p.score
		check(sum==8000,"scores conserve")
		var snapshot=engine.snapshot();var final=GameEngine.new()
		check(final.restore(snapshot),"settled replay")
		check(final.state.result.deltas==engine.state.result.deltas,"settlement not doubled")
		print("Simulation ",match_index+1," / 12: ",steps," decisions, ","draw" if engine.state.result.draw else engine.state.result.pattern)

func _conservation(engine: GameEngine) -> void:
	var all=engine.state.wall.duplicate()
	for p in engine.state.players:
		all.append_array(p.hand);all.append_array(p.discards)
		for m in p.melds:all.append_array(m.tiles)
	check(all.size()==144,"144 physical tiles")
	var counts=Tiles.counts(all)
	for t in range(42):check(counts[t]==(4 if t<34 else 1),"tile count %d"%t)

func _test_storage() -> void:
	var session=LocalSession.new();root.add_child(session)
	session.storage_root="user://qa-storage/"
	session.engine.start({},93000)
	session._save()
	check(session.has_save(),"session persists save")
	var move=session.engine.state.pending.filter(func(a):return a.kind=="discard")[0]
	session.engine.submit(0,session.engine.state.revision,move.id)
	session._save()
	session.autopilot=true
	check(session.resume_match() and session.engine.state.revision==1,"session resumes accepted action")
	check(not session.autopilot,"resume returns control to human")
	session.paused=true
	var file=FileAccess.open(session.storage_root+"current_match.json",FileAccess.WRITE)
	file.store_string("{truncated");file.close()
	check(session.resume_match() and session.engine.state.revision==0,"session recovers valid backup")
	session.paused=true
	session.queue_free()
