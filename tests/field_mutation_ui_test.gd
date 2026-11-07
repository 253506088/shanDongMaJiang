extends "res://tests/ui_smoke.gd"
## Uses application viewport input and explicit rendering; no desktop controls.
var checks=0
var save_directory=""

func expect(ok: bool, message: String) -> void:
	checks+=1;check(ok,message)

func labels(node: Node) -> Array:
	var result: Array=[]
	if node is Label:result.append(node.text)
	for child in node.get_children():result.append_array(labels(child))
	return result

func tagged(node: Node, key: String, value: Variant) -> Node:
	if node.is_queued_for_deletion():return null
	if node.has_meta(key) and node.get_meta(key)==value:return node
	for child in node.get_children():
		var found=tagged(child,key,value)
		if found:return found
	return null

func finish(code: int) -> void:
	app.queue_free();app=null
	await pause_frames(4)
	for name in ["current_match.json","current_match.json.bak","current_match.json.tmp"]:
		var path=ProjectSettings.globalize_path(save_directory+name)
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_directory))
	quit(code)

func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await super.capture(name)

func mutation_fixture(ids: Array):
	app._close_modal()
	var engine=load("res://scripts/core/game_engine.gd").new()
	engine.start({"field_rules":true,"field_selection":"mutation","jiang":"luan","chi":true},84103,1,[],[],"",0,ids)
	app.session.engine=engine;app.session.paused=false;app.last_revision=-1
	app._changed(engine.view(0))
	return engine

func run() -> void:
	create_timer(100).timeout.connect(func():printerr("MUTATION UI watchdog");call_deferred("finish",1))
	app=load("res://scenes/main.tscn").instantiate();app.qa_mode=true;root.add_child(app)
	app.session.set_process(false);app.muted=true
	save_directory="user://qa-mutation-ui-%d-%d/"%[OS.get_process_id(),Time.get_ticks_msec()]
	app.session.storage_root=save_directory
	await pause_frames(4)
	app._show_field_selector(app.config,func(settings):app.config=settings;app._show_lobby())
	await pause_frames(3)
	var scroll=app.modal.get_node("FieldChoices") as ScrollContainer
	scroll.scroll_vertical=100000;await pause_frames(3)
	var selected_rule=tagged(app.modal,"field_selection","mutation")
	expect(selected_rule!=null and scroll.get_global_rect().encloses(selected_rule.get_global_rect()),"seventeenth field is fully accessible by scrolling")
	await capture("01-mutation-selector")
	await click_control(selected_rule)
	expect(app.config.field_rules and app.config.field_selection=="mutation","selecting mutation updates the existing field setting")
	app._build_hud()
	var engine=mutation_fixture(["angels_gift","ouroboros","honor_sequences","chosen"])
	engine.state.players[0].hand=[0,1,2,3,4,5,9,10,11,18,19,20,22];engine.state.players[0].melds=[];engine.state.players[0].drawn=-1
	engine.state.wall=[8,8,12,13,14,15];engine.state.wall_slots=range(6);engine.state.gang_head=15
	engine.state.first_discard=false;engine._draw(0)
	for seat in [1,2]:
		var p=engine.state.players[seat]
		p.hand=([7,8,0] if seat==1 else [27,28,31])+[1,2,3,9,10,11,18,19,20,22]
		p.melds=[];p.ming=true;p.bao=true;p.drawn=-1
	app.last_revision=-1;app._changed(engine.view(0));await pause_frames(4)
	expect(app.field_button.text.begins_with("突变 · 天使的施舍"),"toolbar shows mutation and own rule")
	for seat in range(4):
		var badge=app.players_ui[seat].field
		expect(badge.visible and badge.text==FieldRules.info(engine.state.field.seat_rules[seat]).name,"each player has the correct permanent rule label")
		expect(app.players_ui[seat].panel.get_global_rect().encloses(badge.get_global_rect()),"personal rule label fits its player panel")
	for seat in [1,2]:
		expect(app._opponent_waits(seat).any(func(entry):return entry.tile==22),"public waits use each opponent's own special shape")
		var panel=app.opponent_waits_panels.get(seat)
		expect(panel!=null and not panel.get_global_rect().intersects(app.players_ui[seat].panel.get_global_rect()),"wait panels clear the extended player rule labels")
	expect(app.public_tiles_button.get_global_rect().position.y>=app.players_ui[3].panel.get_global_rect().end.y+8,"public tile button clears the left player's personal rule panel")
	await capture("02-four-personal-rules")
	await click_control(app.field_button);await pause_frames(3)
	var assignments=app.modal.find_child("MutationAssignments",true,false)
	expect(assignments!=null and assignments.get_child_count()==4,"current mutation detail displays all four assignments")
	expect(labels(app.modal).any(func(text):return text.contains("效果仅归获得者")),"detail explicitly explains personal ownership")
	await capture("03-mutation-assignments")
	await click_control(tagged(assignments,"field_seat",1));await pause_frames(3)
	expect(labels(app.modal).has("衔尾蛇") and find_button(app.modal,"使用天使的施舍")==null,"browsing someone else's rule never offers own or borrowed ability")
	app._close_modal();app._show_current_field();await pause_frames(2)
	var detail_scroll=app.modal.find_children("*","ScrollContainer",true,false)[0] as ScrollContainer
	detail_scroll.scroll_vertical=100000;await pause_frames(3)
	expect(find_button(app.modal,"使用天使的施舍")!=null,"own legal ability is reachable in mutation detail")
	await capture("04-own-rule-detail")
	app._close_modal()
	await click_control(find_button(app.root,"天使的施舍 · 三选一"));await pause_frames(3)
	expect(engine.state.phase=="gift_choice" and app.modal.has_node("CompleteHand"),"gift recipient opens existing full-hand candidate picker")
	await capture("05-owner-gift-choices")
	await click_control(tagged(app.modal,"field_choice_index",2));await pause_frames(2)
	await click_control(find_button(app.modal,"确认加入手牌"));await pause_frames(3)
	expect(engine.state.players[0].field_used and engine.state.phase=="turn","owner confirms gift exactly once")
	expect(app.field_button.text.ends_with("已用"),"toolbar reflects own spent power")
	await capture("06-owner-gift-used")
	engine=mutation_fixture(["ouroboros","angels_gift","chosen","single_wait"])
	var p=engine.state.players[0];p.hand=[0,1,2,3,4,5,9,10,11,18,19,20,22];p.melds=[];p.drawn=-1
	engine.state.wall=[8,8,12,13,14,15];engine.state.wall_slots=range(6);engine.state.gang_head=15
	engine._draw(0);app.last_revision=-1;app._changed(engine.view(0));await pause_frames(3)
	expect(find_button(app.root,"天使的施舍 · 三选一")==null and not app.view.pending.any(func(action):return action.kind=="field_gift"),"other player's gift does not give human a button or action")
	await capture("07-non-owner-turn")
	app._show_current_field();await pause_frames(2)
	expect(find_button(app.modal,"使用天使的施舍")==null,"current mutation detail cannot borrow another player's power")
	expect(labels(app.modal).any(func(text):return text.contains("仅该玩家胡牌加番")),"public chosen tiles name their sole bonus recipient")
	app._close_modal()
	var view=SeatView.for_seat(engine.view(1),1)
	app.last_revision=-1;app._changed(view);await pause_frames(3)
	expect(app._field_id()=="angels_gift" and app.players_ui[0].field.text=="天使的施舍","rotated guest UI identifies its own assigned rule")
	await capture("08-rotated-guest")
	var ordinary=load("res://scripts/core/game_engine.gd").new();ordinary.start({},8401)
	app.session.engine=ordinary;app.last_revision=-1;app._changed(ordinary.view(0));await pause_frames(2)
	expect(not app.field_button.visible and app.players_ui.all(func(info):return not info.field.visible and info.panel.size.y==92),"ordinary game restores the original player panels")
	print("MUTATION_UI_RESULT: %d failures; %d checks"%[failures.size(),checks])
	call_deferred("finish",0 if failures.is_empty() else 1)
