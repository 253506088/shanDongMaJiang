extends SceneTree
var failures: Array = []
var checks = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("UX FAIL: ",message)

func _initialize() -> void:
	call_deferred("run")

static func screenshot_engine() -> GameEngine:
	var e=GameEngine.new();e.start({},731)
	var p=e.state.players[0]
	p.hand=[14,14,14,16,22,23,24,3];p.drawn=7;p.bao=true;p.ming=false
	p.melds=[{"type":"angang","tile":7,"tiles":[7,7,7,7]}, {"type":"peng","tile":3,"tiles":[3,3,3],"from":3}]
	e.state.current=0;e.state.wall=[0,1,2,4,5,6,9,10];e.state.gang_head=10
	e.state.wall_slots=[136,137,138,139,140,141,143,142]
	for i in range(1,4): e.state.players[i].bao=false;e.state.players[i].ming=false
	e._turn_options()
	return e

func run() -> void:
	var e=screenshot_engine()
	var p=e.state.players[0]
	# Screenshot #2: exposed 8m kong, 4m pung, newly drawn 4m.
	var moves=e.state.pending.filter(func(a):return a.kind=="bugang" and a.tile==3)
	check(moves.size()==1,"screenshot Four Characters added kong is offered after bao")
	check(e.state.pending.filter(func(a):return a.kind=="discard").size()==1,"bao still locks every pre-existing hand tile")
	if not moves.is_empty():
		check(e.submit(0,e.state.revision,moves[0].id),"Four Characters kong can be submitted")
		check(p.melds[1].tiles==[3,3,3,3] and p.melds[1].get("added",false),"pung becomes exactly four physical tiles")
		check(p.hand.back()==10 and p.drawn==p.hand.size()-1,"kong draws the public head and updates drawn index")
		check(p.bao,"kong keeps declaration")
	e=screenshot_engine();p=e.state.players[0];p.ming=true;e._turn_options()
	check(e.state.pending.any(func(a):return a.kind=="bugang"),"ming has same unchanged-wait added-kong permission")
	p.hand=[0,1,2,3,4,5,6,7,8,9,9,9,13,9];p.drawn=13;p.melds=[];p.ming=false;e._turn_options()
	check(e.state.pending.any(func(a):return a.kind=="angang" and a.tile==9),"unchanged-wait concealed kong offered")
	# Seven-pairs interpretation must not be destroyed by a concealed kong.
	p.hand=[0,0,0,1,1,2,2,3,3,4,4,5,5,0];p.drawn=13;e._turn_options()
	check(not e.state.pending.any(func(a):return a.kind=="angang"),"locked concealed kong that changes waits rejected")
	e=screenshot_engine();p=e.state.players[0];p.drawn=0;e._turn_options()
	check(not e.state.pending.any(func(a):return a.kind=="bugang"),"old hand tile cannot be used to bypass locked discard")
	# Robbing a legal added kong must still go through the normal claims pipeline.
	e=screenshot_engine();var other=e.state.players[1]
	other.hand=[0,1,2,9,10,11,18,19,20,13,13,3,3];other.melds=[];other.bao=true
	var kong=e.state.pending.filter(func(a):return a.kind=="bugang")[0]
	e.submit(0,e.state.revision,kong.id)
	check(e.state.phase=="claim" and e.state.claim_stage=="rob" and e.decision_seat()==1,"added kong allows legal robbed-kong claim")
	check(e.state.players[0].melds[1].tiles.size()==3,"fourth tile is not committed before rob resolves")
	_test_layout()
	var session=LocalSession.new()
	check(session.action_delay("discard")>=1.8,"default visible discard beat allows human reaction")
	session.free()
	print("UX_RESULT: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_layout() -> void:
	# Packed 38-discard rivers exercise the long-game widened rows on every seat.
	var rivers: Array=[]
	for seat in range(4):
		for i in range(38):
			var size=TableLayout.TILE*TableLayout.RIVER_SCALE
			if seat%2: size=Vector3(size.z,size.y,size.x)
			rivers.append(AABB(TableLayout.river(seat,i)-size/2,size))
	for i in range(rivers.size()):
		for j in range(i+1,rivers.size()): check(not rivers[i].intersects(rivers[j]),"discard rivers do not intersect %d/%d"%[i,j])
		for index in range(144):
			var size=TableLayout.TILE
			if (index/36)%2: size=Vector3(size.z,size.y,size.x)
			check(not rivers[i].intersects(AABB(TableLayout.wall(index)-size/2,size)),"river clears wall %d/%d"%[i,index])
