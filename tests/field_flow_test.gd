extends SceneTree

var checks=0
var failures: Array=[]

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures.append(message);printerr("FIELD FLOW FAIL: ",message)

func normalized(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))

func replay(engine: GameEngine, label: String) -> void:
	var saved=normalized(engine.snapshot())
	var restored=GameEngine.new()
	var ok=restored.restore(saved)
	check(ok,label+" restores")
	if ok:check(normalized(restored.state)==normalized(engine.state),label+" reconstructs every field exactly")

func has_action(engine: GameEngine, kind: String) -> bool:
	return engine.state.pending.any(func(action):return action.kind==kind)

func play(engine: GameEngine, kind: String, index: int=-1) -> bool:
	for action in engine.state.pending:
		if action.kind==kind and (index<0 or action.get("index",-1)==index):
			return engine.submit(engine.decision_seat(),engine.state.revision,action.id)
	return false

func fixture(wall: Array=[1,2,3,4,8]) -> GameEngine:
	var engine=GameEngine.new()
	engine.start({"field_rules":true,"field_selection":"angels_gift","jiang":"luan"},63117)
	var p=engine.state.players[1]
	p.hand=[0,1,2,9,10,11,18,19,20,24,24,24,13]
	p.melds=[];p.drawn=-1;p.bao=false;p.ming=false
	engine.state.wall=wall.duplicate()
	engine.state.wall_slots=range(wall.size())
	engine.state.gang_head=wall.back()
	return engine

func physical_tiles(engine: GameEngine) -> Array:
	var all=engine.state.wall.duplicate()
	for p in engine.state.players:
		all.append_array(p.hand);all.append_array(p.discards)
		for meld in p.melds:all.append_array(meld.tiles)
		if engine.state.version>=3 and engine.state.phase=="gift_choice":all.append_array(p.field_private.get("gift_tiles",[]))
	all.sort();return all

func run() -> void:
	_test_selection()
	_test_gift_choices()
	_test_gift_boundaries()
	_test_old_gift_replays()
	_test_new_gift_replays()
	print("FIELD_FLOW_RESULT: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_selection() -> void:
	for id in FieldRules.IDS:
		for round_number in [1,2,5]:
			var engine=GameEngine.new()
			engine.start({"field_rules":true,"field_selection":id},439+round_number,round_number)
			check(engine.state.field.id==id and engine.opening.field_id==id,"fixed field remains fixed across seeds and rounds: "+id)
			replay(engine,"fixed "+id+" round "+str(round_number))
	var engine=GameEngine.new()
	engine.start({"field_rules":false,"field_selection":"angels_gift"},331)
	check(not engine.state.has("field") and engine.state.settings.field_selection=="angels_gift","disabled modifier remembers selection without activating it")
	replay(engine,"disabled fixed preference")
	var results={}
	for seed_value in range(1,97):
		engine.start({"field_rules":true,"field_selection":"random"},seed_value)
		results[engine.state.field.id]=true
	check(results.size()>8,"explicit random selection still varies")
	engine.start({"field_rules":true,"field_selection":{}},1)
	check(engine.state.settings.field_selection=="random","invalid local selection safely falls back to random")
	var bad=engine.snapshot();bad.opening.settings.field_selection="unknown"
	check(not GameEngine.new().restore(bad),"unknown saved field selection is rejected")
	bad=engine.snapshot();bad.opening.settings.field_selection="chosen" if engine.state.field.id!="chosen" else "exchange"
	check(not GameEngine.new().restore(bad),"saved fixed selection must agree with the actual opening field")

func _test_gift_choices() -> void:
	for picked in range(3):
		var engine=fixture();var p=engine.state.players[1]
		var original=physical_tiles(engine)
		var original_hand=p.hand.duplicate()
		engine._draw(1)
		check(engine.state.phase=="turn" and p.hand==original_hand+[1],"draw goes straight into ordinary play")
		check(has_action(engine,"field_gift") and not has_action(engine,"draw_normal"),"gift is optional after seeing first tile")
		var revision=engine.state.revision
		var action=engine.state.pending.filter(func(move):return move.kind=="field_gift")[0]
		check(not engine.submit(0,revision,action.id),"another seat cannot spend this player's gift")
		check(play(engine,"field_gift"),"activate optional gift")
		check(not engine.submit(1,revision,action.id),"duplicate gift activation is rejected")
		check(p.hand==original_hand and p.field_private.gift_tiles==[1,2,3],"choice shows original draw plus exactly two added physical tiles")
		check(p.field_private.gift_after_draw and p.field_used and not p.gift_ready,"activation spends the single use")
		check(engine.state.wall==[4,8] and physical_tiles(engine)==original,"candidate pool conserves every physical tile")
		for seat in [0,2,3]:
			var public=engine.view(seat)
			check(not public.has("gift_slots") and not public.players[1].has("field_private") and public.event.tile==-1,"added faces and original draw stay private")
		check(play(engine,"field_gift_pick",picked),"confirm one of three")
		var expected=[1,2,3];var selected=expected.pop_at(picked)
		check(p.hand==original_hand+[selected],"only selected tile enters the final hand")
		check(engine.state.wall==expected+[4,8],"unchosen copies return in original candidate order")
		var slot_order=[0,1,2];slot_order.remove_at(picked)
		check(engine.state.wall_slots==slot_order+[3,4],"wall positions follow returned physical copies")
		check(physical_tiles(engine)==original and not engine.state.has("gift_slots"),"confirmation leaves no lost or duplicated candidate")
		check(not has_action(engine,"field_gift") and not p.field_private.has("gift_tiles"),"gift cannot be reused after confirmation")

func _test_gift_boundaries() -> void:
	var engine=fixture([1,2,3,4,5,6,7,8]);var p=engine.state.players[1]
	for _turn in range(2):
		engine._draw(1)
		check(has_action(engine,"field_gift"),"unused ability remains available on a later normal draw")
		var index=p.drawn
		check(play(engine,"discard",index),"ordinary discard needs no ability decision")
		check(not p.field_used and not p.gift_ready,"declining this draw neither spends nor carries its draw window")
	engine=fixture();p=engine.state.players[1]
	engine.state.current=1;engine._turn_options()
	check(not has_action(engine,"field_gift"),"initial deal or claim without a normal draw cannot activate gift")
	engine._draw(1,"kong")
	check(not has_action(engine,"field_gift"),"kong replacement cannot activate gift")
	for locked in ["bao","ming"]:
		engine=fixture();p=engine.state.players[1];p[locked]=true
		engine._draw(1)
		check(not has_action(engine,"field_gift") and engine.state.phase=="turn","declared hand draws without gift interruption")
	engine=fixture([1,2,8]);engine._draw(1)
	check(not has_action(engine,"field_gift"),"reserved head is never taken as the second added candidate")
	engine=fixture([34,1,2,3,4,8]);p=engine.state.players[1]
	var before=physical_tiles(engine)
	engine._draw(1)
	check(p.hand.back()==4 and has_action(engine,"field_gift"),"normal-draw flower replacement becomes the visible first candidate")
	play(engine,"field_gift")
	check(p.field_private.gift_tiles==[4,1,2],"flower replacement uses its actual physical first tile")
	play(engine,"field_gift_pick",1)
	check(engine.state.wall==[4,2,3,8] and physical_tiles(engine)==before,"flower replacement return restores physical accounting")
	engine=fixture([1,34,3,4,8]);p=engine.state.players[1]
	before=physical_tiles(engine);engine._draw(1);play(engine,"field_gift");play(engine,"field_gift_pick",1)
	check(p.melds.size()==1 and p.melds[0].tile==34 and p.hand.back()==4,"selecting added flower applies ordinary flower replacement")
	check(engine.state.wall==[1,3,8] and physical_tiles(engine)==before,"flower candidate neither loses original draw nor duplicates replacements")

func _test_old_gift_replays() -> void:
	# Produced by the released v2 engine before this flow change, not by the
	# implementation under test. Exact snapshots protect historical action IDs.
	var data=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/replay-field-v2-gift.json"))
	for key in ["before_use","choosing","after_use"]:
		var engine=GameEngine.new()
		var ok=engine.restore(data[key])
		check(ok,"released v2 gift "+key+" loads")
		if not ok:continue
		check(normalized(engine.state)==data[key].state,"released v2 gift "+key+" stays byte-meaning identical")
		replay(engine,"resaved v2 "+key)
		if key=="before_use":check(engine.state.phase=="draw_choice" and play(engine,"field_gift"),"legacy pending prompt still accepts its old choice")
		if key=="choosing":
			check(play(engine,"field_gift_pick",1),"legacy pending candidates still resolve")
			check(normalized(engine.state)==data.after_use.state,"legacy confirmation preserves old result")

func _test_new_gift_replays() -> void:
	var engine=GameEngine.new()
	engine.start({"field_rules":true,"field_selection":"angels_gift","jiang":"luan"},63117)
	check(not has_action(engine,"field_gift"),"dealer opening is not a normal draw")
	for _step in range(40):
		if has_action(engine,"field_gift"):break
		check(engine.state.phase!="draw_choice","new games never stop before a normal draw")
		var actions=engine.state.pending.filter(func(action):return action.kind in ["discard","pass"])
		check(not actions.is_empty(),"new fixture progresses to first ordinary draw")
		if actions.is_empty():return
		engine.submit(engine.decision_seat(),engine.state.revision,actions[0].id)
	check(has_action(engine,"field_gift"),"real game offers gift after an actual draw")
	replay(engine,"new drawn first tile")
	play(engine,"field_gift");replay(engine,"new private candidate pool")
	var original=engine.snapshot()
	for index in range(3):
		var copy=GameEngine.new();check(copy.restore(original),"candidate state restores for every choice")
		play(copy,"field_gift_pick",index)
		replay(copy,"new choice "+str(index))
		check(physical_tiles(copy).size()==144,"real new gift keeps 144 tiles")
