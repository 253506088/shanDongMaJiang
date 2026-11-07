extends SceneTree
## Run against the exported EXE with --main-pack and --path build/windows.
var checks=0
var failures: Array=[]
var app
var save_directory=""

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message);printerr("MUTATION PACKAGE FAIL: ",message)

func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless":return
	var args=OS.get_cmdline_user_args();var index=args.find("--capture-dir")
	if index<0:return
	for frame in range(4):await process_frame
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(args[index+1].path_join(name+".png"))==OK,"capture packaged mutation table")

func find_button(node: Node, text: String) -> Button:
	if node is Button and node.text==text:return node
	for child in node.get_children():
		var found=find_button(child,text)
		if found:return found
	return null

func run() -> void:
	Engine.max_fps=60
	# Load the real entry scene before directly probing its core resources,
	# matching startup order and avoiding a second global-class load cycle.
	app=load("res://scenes/main.tscn").instantiate();app.qa_mode=true;root.add_child(app)
	app.muted=true;app.session.set_process(false)
	save_directory="user://qa-mutation-package-%d-%d/"%[OS.get_process_id(),Time.get_ticks_msec()]
	app.session.storage_root=save_directory
	check(ProjectSettings.get_setting("application/config/version")=="0.10.3","exported version is current")
	check(not FileAccess.file_exists("res://tests/field_mutation_test.gd") and not FileAccess.file_exists("res://tests/fixtures/replay-field-v3.json"),"tests and reference saves stay outside package")
	check(FieldRules.IDS.size()==17 and FieldRules.MUTATION_POOL.size()==13,"package has expanded catalog and limited personal pool")
	var script=load("res://scripts/core/game_engine.gd")
	for seed_value in range(1,17):
		var engine=script.new();engine.start({"field_rules":true,"field_selection":"mutation"},seed_value)
		check(engine.state.version==4 and FieldRules.valid_assignment(engine.state.field.seat_rules),"packaged assignment is four distinct eligible rules")
		var restored=script.new();var data=JSON.parse_string(JSON.stringify(engine.snapshot()))
		check(restored.restore(data) and JSON.parse_string(JSON.stringify(restored.state))==data.state,"packaged v4 opening replays exactly")
	var ids=["angels_gift","ouroboros","honor_sequences","chosen"]
	var engine=script.new();engine.start({"field_rules":true,"field_selection":"mutation","jiang":"luan"},84103,1,[],[],"",0,ids)
	var steps=0
	while not (engine.decision_seat()==0 and engine.state.pending.any(func(move):return move.kind=="field_gift")) and engine.state.phase!="settled" and steps<80:
		var moves=engine.state.pending.filter(func(move):return move.kind in ["discard","pass"])
		if moves.is_empty():break
		check(engine.submit(engine.decision_seat(),engine.state.revision,str(moves[0].id)),"packaged journal reaches gift owner's normal draw")
		steps+=1
	check(engine.state.pending.any(func(move):return move.kind=="field_gift"),"recipient has gift after actual normal draw")
	app._build_hud();app.session.engine=engine;app.session.paused=false;app.last_revision=-1;app._changed(engine.view(0))
	check(app.field_button.text.begins_with("突变 · 天使的施舍"),"packaged toolbar shows recipient's actual rule")
	for seat in range(4):check(app.players_ui[seat].field.text==FieldRules.info(ids[seat]).name,"packaged player badges show four assignments")
	await capture("package-mutation-table")
	app._show_current_field()
	check(app.modal.find_child("MutationAssignments",true,false)!=null,"package exposes four-seat assignment overview")
	await capture("package-mutation-overview")
	app._close_modal()
	var gift=find_button(app.root,"天使的施舍 · 三选一")
	check(gift!=null,"recipient's named action ships")
	if gift:
		gift.pressed.emit()
		check(engine.state.phase=="gift_choice" and app.modal.has_node("CompleteHand"),"package opens full-hand picker after legal activation")
		for seat in range(1,4):
			var public=engine.view(seat)
			check(public.pending.is_empty() and not public.players[0].has("field_private"),"package conceals candidates from other three players")
		var data=JSON.parse_string(JSON.stringify(engine.snapshot()));var restored=script.new()
		check(restored.restore(data) and JSON.parse_string(JSON.stringify(restored.state))==data.state,"packaged in-progress gift and assignment survive save/replay")
		await capture("package-mutation-gift")
		app.field_picker_selection=1;app._show_field_picker("field_gift_pick")
		find_button(app.modal,"确认加入手牌").pressed.emit()
		check(engine.state.phase=="turn" and engine.state.players[0].field_used,"package UI commits one selected tile and consumes owner's use")
		check(engine.state.players.slice(1).all(func(p):return not p.field_used),"other three players' opportunities unchanged")
	var ai=load("res://scripts/core/mahjong_ai.gd").new()
	steps=0
	while engine.state.phase!="settled" and steps<800:
		var seat=engine.decision_seat();var move=ai.choose(engine.view(seat),seat,0.25)
		check(engine.submit(seat,engine.state.revision,str(move.id)),"packaged mixed-rule AI action accepted")
		steps+=1
	check(engine.state.phase=="settled","packaged mixed-rule match completes")
	check(engine.state.players.reduce(func(sum,p):return sum+p.score,0)==8000,"packaged mixed-rule scores remain zero sum")
	var rotated=SeatView.for_seat(engine.view(1),1)
	check(FieldRules.for_seat(rotated.field,0)=="ouroboros","packaged guest rotation keeps its own field")
	print("MUTATION_PACKAGE_RESULT: %d failures; %d checks"%[failures.size(),checks])
	call_deferred("finish",0 if failures.is_empty() else 1)

func finish(code: int) -> void:
	app.queue_free();app=null
	for frame in range(4):await process_frame
	for name in ["current_match.json","current_match.json.bak","current_match.json.tmp"]:
		var path=ProjectSettings.globalize_path(save_directory+name)
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_directory))
	quit(code)
