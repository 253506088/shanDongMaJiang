extends "res://tests/ui_smoke.gd"
## Scene/control checks only. Requires headless; never changes desktop state.
var checks = 0
var save_directory = ""

func expect(ok: bool, message: String) -> void:
	checks += 1; check(ok,message)

func labels(node: Node) -> Array:
	var result: Array=[]
	if node is Label:result.append(node.text)
	for child in node.get_children():result.append_array(labels(child))
	return result

func tagged(node: Node, key: String, value: Variant) -> Node:
	if node.is_queued_for_deletion():return null
	if node.has_meta(key) and node.get_meta(key)==value:return node
	for child in node.get_children():
		var result=tagged(child,key,value)
		if result!=null:return result
	return null

func choose_hand(index: int) -> void:
	var card=tagged(app.modal.get_node("CompleteHand"),"field_hand_index",index)
	expect(card is Button,"every physical hand copy has a separate selectable control")
	if card is Button:card.pressed.emit();await pause_frames(2)

func fixture(id: String) -> GameEngine:
	app._close_modal()
	var engine=GameEngine.new()
	engine.start({"field_rules":not id.is_empty(),"jiang":"luan"},481,1,[],[],id)
	app.session.engine=engine;app.session.paused=false;app.last_revision=-1
	app._changed(engine.view(0))
	return engine

func finish(code: int) -> void:
	if is_instance_valid(app):app.queue_free();app=null
	await pause_frames(2)
	if not save_directory.is_empty():
		for name in ["current_match.json","current_match.json.bak","current_match.json.tmp"]:
			var path=ProjectSettings.globalize_path(save_directory+name)
			if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_directory))
	quit(code)

func _verify_field_badge_clearance() -> void:
	var engine=fixture("wildcard")
	for seat in range(1,4):
		var player=engine.state.players[seat]
		player.hand=[0,1,2,3,4,5,9,10,11,18,19,20,22,22]
		player.melds=[];player.ming=true;player.bao=true;player.drawn=13
	app._changed(engine.view(0));await pause_frames(2)
	var old_badge=Rect2(595,69,410,39)
	var reproduces_report=false
	for key in app.table.pieces:
		if not key.begins_with("h2-"):continue
		if old_badge.intersects(_project_tile(key)):reproduces_report=true
	expect(reproduces_report,"fixture reproduces the reported banner over the opposite open hand")
	for id in FieldRules.IDS:
		for status in ["", " · 可用", " · 已用"]:
			app.field_button.text="场地 · "+str(FieldRules.info(id).name)+status
			await pause_frames(1)
			var rect=app.field_button.get_global_rect()
			expect(rect.end.y<=70 and rect.end.x<app.round_text.get_parent().get_global_rect().position.x,"every field name and status stays inside its toolbar space")
	var viewport=app.scene_surface.scene_viewport
	var original_size=viewport.size
	app.field_button.text="场地 · 天使的施舍 · 已用"
	for pixels in [Vector2i(960,540),Vector2i(1600,900),Vector2i(1920,1080)]:
		viewport.size=pixels;await pause_frames(2)
		# Include the soft shadow as well as the button's hit area.
		var rect=app.field_button.get_global_rect().grow(11)
		var clear=true
		for key in app.table.pieces:
			if rect.intersects(_project_tile(key)):clear=false;break
		expect(clear,"field entry and shadow clear all projected hands, melds and wall at %s"%pixels)
		for control in app.hud.get_children():
			if not control is Control or control==app.field_button or not control.visible:continue
			expect(not rect.intersects(control.get_global_rect()),"field entry clears the round label and side information at %s"%pixels)
	viewport.size=original_size
	app.field_button.pressed.emit();await pause_frames(2)
	expect(is_instance_valid(app.modal) and labels(app.modal).has("癞子"),"relocated field entry still opens the current rule")
	app._close_modal()

func _project_tile(key: String) -> Rect2:
	var bounds=app.table.tile_bounds(key)
	var rect=Rect2(app.table.camera.unproject_position(bounds.get_endpoint(0)),Vector2.ZERO)
	for corner in range(1,8):rect=rect.expand(app.table.camera.unproject_position(bounds.get_endpoint(corner)))
	return rect

func _verify_exchange_context() -> void:
	var engine=fixture("exchange")
	engine.state.players[0].hand=[0,0,0,0,1,2,3,4,5,6,7,8,9,27]
	engine.state.players[0].melds=[];engine._exchange_options()
	app.last_revision=-1;app._changed(engine.view(0));await pause_frames(2)
	app._show_current_field()
	find_button(app.modal,"选择要传给下家的三张牌").pressed.emit();await pause_frames(2)
	expect(engine.state.revision==0 and app.modal.has_node("CompleteHand"),"every exchange entry opens selection instead of sending the first legal packet")
	var row=app.modal.get_node("CompleteHand")
	expect(row.get_child_count()==14 and row.get_meta("tile_count")==14,"all fourteen physical tiles are visible together")
	expect(row.get_children().filter(func(card):return card.get_meta("tile")==0).size()==4,"four identical faces remain four separate controls")
	var honor=tagged(row,"field_hand_index",13)
	expect(honor.disabled and not honor.tooltip_text.is_empty(),"honor remains visible but explains why it cannot be exchanged when enough suited tiles exist")
	honor.pressed.emit();await pause_frames(2)
	expect(app.field_exchange_selection.is_empty(),"disabled honor cannot enter the exchange selection even through a duplicate activation")
	for index in [0,1,2]:await choose_hand(index)
	expect(app.modal.get_node("SelectedExchange").get_child_count()==3,"three identical selected copies remain three visible tiles")
	expect(app.modal.get_node("KeptExchange").get_meta("tile_count")==11,"selection shows all eleven retained tiles")
	await choose_hand(1);await choose_hand(3)
	expect(app.field_exchange_selection==[0,2,3],"same-face physical copies can be independently replaced in the selection")
	expect(not find_button(app.modal,"确认传给 "+app.view.players[1].name).disabled,"equivalent duplicate indices match an authoritative packet by multiset")
	app._close_modal();app._show_exchange_picker();await pause_frames(2)
	expect(app.field_exchange_selection==[0,2,3] and engine.state.revision==0,"closing and reopening preserves the exchange draft without consuming the action")
	find_button(app.modal,"确认传给 "+app.view.players[1].name).pressed.emit();await pause_frames(2)
	expect(engine.state.revision==1,"confirmed duplicate packet submits exactly once")
	engine=fixture("exchange")
	engine.state.players[0].hand=[0,1,27,27,27,27,28,28,28,28,29,29,29,29]
	engine.state.players[0].melds=[];engine._exchange_options()
	app.last_revision=-1;app._changed(engine.view(0));app._show_exchange_picker();await pause_frames(2)
	expect(not tagged(app.modal.get_node("CompleteHand"),"field_hand_index",2).disabled,"honors remain selectable when fewer than three suited tiles exist")
	for index in [0,1,2]:await choose_hand(index)
	expect(not find_button(app.modal,"确认传给 "+app.view.players[1].name).disabled,"two suited tiles plus an honor produce a confirmable legal packet")
	app._close_modal()

func _verify_gift_context() -> void:
	var engine=fixture("angels_gift")
	var player: Dictionary=engine.state.players[0]
	player.hand=[0,1,2,3,4,5,9,10,11,18,19,20,22];player.melds=[];player.drawn=-1
	engine.state.wall=[8,8,8,9,10,11,12,13];engine.state.wall_slots=range(8);engine.state.gang_head=13
	engine.state.first_discard=false;engine._draw(0)
	app.last_revision=-1;app._changed(engine.view(0));await pause_frames(2)
	expect(engine.state.phase=="turn" and player.hand.size()==14 and player.hand[player.drawn]==8,"first gift tile is already normally drawn and visible in the hand")
	var skill=find_button(app.root,"天使的施舍 · 三选一")
	expect(skill!=null,"after normal draw the ability has a direct named action")
	if skill:skill.pressed.emit();await pause_frames(2)
	expect(engine.state.phase=="gift_choice" and player.hand.size()==13,"using gift opens its three choices with the base hand retained")
	expect(app.modal.has_node("CompleteHand") and app.modal.get_node("CompleteHand").get_meta("tile_count")==13,"gift choice shows all thirteen base hand tiles")
	expect(labels(app.modal).has("本次摸牌"),"the originally drawn physical tile is identified")
	for index in range(3):
		expect(tagged(app.modal,"field_choice_index",index)!=null,"identical gift candidate %d stays separately selectable"%index)
	expect(find_button(app.modal,"确认加入手牌").disabled,"gift does not preselect or silently accept any candidate")
	var revision=int(engine.state.revision)
	tagged(app.modal,"field_choice_index",2).pressed.emit();await pause_frames(2)
	expect(engine.state.revision==revision and app.modal.get_node("ResultHand").get_meta("tile_count")==14,"choosing a candidate previews the whole hand without submitting yet")
	app._close_modal();app._changed(engine.view(0));await pause_frames(2)
	expect(not is_instance_valid(app.modal),"a repeated gift snapshot respects a deliberately closed picker")
	find_button(app.root,"天使的施舍 · 继续选牌").pressed.emit();await pause_frames(2)
	expect(app.field_picker_selection==2 and engine.state.revision==revision,"gift selection can be reopened without spending another use")
	find_button(app.modal,"确认加入手牌").pressed.emit();await pause_frames(2)
	expect(engine.state.phase=="turn" and player.hand.size()==14 and player.field_used,"only confirmation places the selected candidate into the hand")
	expect(not app.view.pending.any(func(action):return action.kind=="field_gift"),"used gift cannot be offered a second time")
	# A legacy v2 choice did not begin from a normal draw; never mislabel it.
	var legacy=app.view.duplicate(true);legacy.version=2;legacy.phase="gift_choice";legacy.decision_seat=0
	legacy.pending=[{"kind":"field_gift_pick","id":"0","index":0,"tile":1},{"kind":"field_gift_pick","id":"1","index":1,"tile":2},{"kind":"field_gift_pick","id":"2","index":2,"tile":3}]
	legacy.players[0].field_private={"gift_tiles":[1,2,3]};app.view=legacy
	app._show_field_picker("field_gift_pick",true);await pause_frames(2)
	expect(not labels(app.modal).has("本次摸牌"),"legacy candidates are displayed without a fabricated original draw")
	app._close_modal();app._show_current_field();await pause_frames(2)
	expect(labels(app.modal).any(func(value):return str(value).contains("本局为旧版存档") and str(value).contains("下一局")),"legacy gift explanation matches its preserved flow and says when the new flow starts")
	app._close_modal()

func _verify_reclaim_context() -> void:
	var engine=fixture("reclaim")
	var player: Dictionary=engine.state.players[0]
	player.hand=[0,1,2,3,4,5,9,10,11,22,22]
	player.melds=[{"type":"peng","tile":18,"tiles":[18,18,18],"from":1}]
	player.drawn=10;engine._turn_options()
	app.last_revision=-1;app._changed(engine.view(0));await pause_frames(2)
	find_button(app.root,"上架 · 撤回副露").pressed.emit();await pause_frames(2)
	expect(app.modal.get_node("CompleteHand").get_meta("tile_count")==11,"reclaim keeps the full eleven-tile hand visible beside the exposed group")
	expect(find_button(app.modal,"确认撤回").disabled and engine.state.revision==0,"opening reclaim spends nothing and requires a selection")
	tagged(app.modal,"field_choice_index",0).pressed.emit();await pause_frames(2)
	expect(app.modal.get_node("ResultHand").get_meta("tile_count")==14,"reclaim previews all fourteen tiles before changing melds")
	app._close_modal();app._show_field_picker("field_reclaim");await pause_frames(2)
	expect(app.field_picker_selection==0 and not player.field_used,"reclaim draft remains available after closing without using the ability")
	find_button(app.modal,"确认撤回").pressed.emit();await pause_frames(2)
	expect(player.hand.size()==14 and player.melds.is_empty() and player.field_used,"confirmed reclaim moves the complete exposed group exactly once")

func _verify_gift_flower_preview() -> void:
	var engine=fixture("angels_gift")
	var player: Dictionary=engine.state.players[0]
	player.hand=[0,1,2,3,4,5,9,10,11,18,19,20,22];player.melds=[];player.drawn=-1
	engine.state.wall=[8,34,2,9,10,11,12,13];engine.state.wall_slots=range(8);engine.state.gang_head=13
	engine.state.first_discard=false;engine._draw(0)
	app.last_revision=-1;app._changed(engine.view(0));await pause_frames(2)
	find_button(app.root,"天使的施舍 · 三选一").pressed.emit();await pause_frames(2)
	tagged(app.modal,"field_choice_index",1).pressed.emit();await pause_frames(2)
	var result=app.modal.get_node("ResultHand")
	expect(result.get_child(result.get_child_count()-1).get_meta("tile")==-1,"flower choice previews an unknown replacement card back instead of a flower in the hand")
	expect(result.get_children().all(func(card):return card.get_meta("tile")<34),"flower candidate is never presented as a retained hand tile")
	expect(labels(app.modal).any(func(value):return str(value).contains("所选花牌将亮出") and str(value).contains("补牌尚未知")),"flower preview explains public flower placement and the unknown replacement draw")
	var confirm=find_button(app.modal,"确认补花并补牌")
	expect(confirm!=null and not confirm.disabled,"flower confirmation names the actual replacement operation")
	if confirm:confirm.pressed.emit();await pause_frames(2)
	expect(player.melds.any(func(meld):return meld.type=="flower" and meld.tile==34) and player.hand.size()==14 and player.hand.all(func(tile):return tile<34),"confirmed flower is exposed and an ordinary replacement restores the hand")

func run() -> void:
	if DisplayServer.get_name()!="headless":printerr("Field UI checks require --headless");quit(1);return
	create_timer(100).timeout.connect(func():printerr("FIELD_UI watchdog timeout");await finish(1))
	app=load("res://scenes/main.tscn").instantiate();app.qa_mode=true;root.add_child(app)
	app.session.set_process(false)
	save_directory="user://qa-field-ui-%d-%d/"%[OS.get_process_id(),Time.get_ticks_msec()]
	app.session.storage_root=save_directory
	expect(not app.config.field_rules,"field enhancement defaults off")
	find_button(app.root,"每局随机").pressed.emit();await pause_frames(2)
	expect(app.config.field_rules and app.config.jiang=="258","field toggle preserves regional rule settings")
	app._show_field_selector(app.config,func(settings):app.config=settings;app._show_lobby())
	tagged(app.modal,"field_selection","angels_gift").pressed.emit();await pause_frames(2)
	expect(app.config.field_rules and app.config.field_selection=="angels_gift","specific field selection is saved independently of the regional rules")
	expect(find_button(app.root,"指定 · 天使的施舍")!=null,"lobby names the selected field")
	find_button(app.root,"不开启").pressed.emit();await pause_frames(2)
	expect(not app.config.field_rules and app.config.field_selection=="angels_gift","turning enhancement off preserves the remembered specific selection")
	find_button(app.root,"每局随机").pressed.emit();await pause_frames(2)
	expect(app.config.field_rules and app.config.field_selection=="random","random remains available after choosing a specific field")
	app._show_field_catalog();await pause_frames(2)
	for id in FieldRules.IDS:
		expect(labels(app.modal).has(FieldRules.info(id).name),"catalog includes "+id)
	app._show_field_detail("rebirth",false)
	expect(labels(app.modal).any(func(value):return str(value).contains("每人每局")),"catalog explains per-player per-round limit")
	app._close_modal();app._show_lan_browser();await pause_frames(2)
	expect(find_button(app.lan_lobby,"场地：每局随机")!=null,"LAN creation exposes the same independent modifier")
	app.lan_lobby.nickname="同桌测试";app.lan_lobby.address="192.168.1.7"
	find_button(app.lan_lobby,"场地：每局随机").pressed.emit();await pause_frames(2)
	tagged(app.modal,"field_selection","rebirth").pressed.emit();await pause_frames(2)
	expect(app.lan_lobby.configuration.field_selection=="rebirth" and app.lan_lobby.configuration.field_rules,"LAN creator can specify a field through the shared selector")
	expect(app.lan_lobby.nickname=="同桌测试" and app.lan_lobby.address=="192.168.1.7","field selection preserves nickname and join address")
	var room={"settings":{"jiang":"luan","chi":true,"ai":"efficiency","field_rules":true},"seats":[],"started":false}
	app.lan_lobby.show_room(room,false,1)
	expect(labels(app.lan_lobby).has("场地：每局随机") and find_button(app.lan_lobby,"场地：每局随机")==null,"guest sees field setting without host-only controls")
	room.settings.field_selection="angels_gift";app.lan_lobby.show_room(room,false,1)
	expect(labels(app.lan_lobby).has("场地：天使的施舍（指定）"),"guest sees the full specified field name")
	app.discovery.stop();app._build_hud()
	fixture("");await pause_frames(2)
	expect(not app.field_button.visible,"normal table has no field badge")
	await _verify_field_badge_clearance()
	var engine=fixture("diamond_finger");await pause_frames(2)
	expect(app.field_button.visible and app.field_button.text.contains("大力金刚指"),"table identifies active field")
	expect(find_button(app.root,"大力金刚指 · 变白板")!=null,"legal field skill has a direct named table action")
	app._show_current_field();await pause_frames(2)
	expect(find_button(app.modal,"选择一张手牌，变为白板")!=null,"skill panel explains transformation before selection")
	app._show_field_picker("field_transform");await pause_frames(2)
	var old_revision=int(engine.state.revision)
	expect(find_button(app.modal,"确认变白板").disabled,"transformation requires selecting a hand tile before confirmation")
	var transform: Dictionary=engine.state.pending.filter(func(action):return action.kind=="field_transform")[0]
	await choose_hand(int(transform.index))
	expect(app.modal.get_node("ResultHand").get_meta("tile_count")==engine.state.players[0].hand.size(),"transformation previews the complete resulting hand")
	find_button(app.modal,"确认变白板").pressed.emit();await pause_frames(2)
	expect(engine.state.revision==old_revision+1 and engine.state.players[0].field_used,"explicit tile confirmation submits transformation once")
	app._show_current_field()
	expect(labels(app.modal).has("你的本局次数：已使用"),"used skill is visible as spent")
	app._close_modal();app._inspect_tile(0,600,763)
	expect(labels(app.inspect_layer).any(func(value):return str(value).begins_with("至多")),"secret transformation counts are presented as upper bounds beside the number")
	engine=fixture("rebirth");await pause_frames(2)
	var reborn: Dictionary=engine.state.players[0]
	reborn.hand=[0,1,2,3,4,5,9,10,11,18,19,20,22,27];reborn.melds=[]
	reborn.bao=false;reborn.ming=false;reborn.revealed_hand=true;reborn.drawn=13
	engine._turn_options();app.last_revision=-1;app._changed(engine.view(0));await pause_frames(2)
	expect(not app.view.pending.any(func(action):return action.kind=="bao") and app.view.pending.any(func(action):return action.kind=="ming"),"rebirth fixture has only legal open-ready declarations")
	app._show_waits();await pause_frames(2)
	expect(labels(app.modal).has("打出 东"),"wait overview includes open-ready-only discard choices after rebirth")
	app._close_modal();app._inspect_tile(27,600,763)
	expect(labels(app.inspect_layer).has("打出后可明搂 · 听口"),"tile inspection explains the legal post-rebirth declaration")
	engine=fixture("astrology_wall");await pause_frames(2)
	var peek: Dictionary=engine.state.pending.filter(func(action):return action.kind=="field_peek_wall")[0]
	app._submit_field(peek,int(engine.state.revision));await pause_frames(2)
	expect(is_instance_valid(app.modal) and labels(app.modal).any(func(value):return str(value).contains("你的占星记录")),"an authoritative private result opens after the updated view arrives")
	app._close_modal();app._changed(engine.view(0));await pause_frames(2)
	expect(not is_instance_valid(app.modal),"repeated snapshots do not reopen dismissed private information")
	engine=fixture("exchange");await pause_frames(2)
	app._show_exchange_picker();await pause_frames(2)
	expect(find_button(app.modal,"确认传给 "+app.view.players[1].name).disabled,"exchange requires a complete legal three-tile selection")
	var move: Dictionary=engine.state.pending[0]
	app.field_exchange_selection=move.indices.duplicate()
	app._show_exchange_picker(false);await pause_frames(2)
	var exchange=find_button(app.modal,"确认传给 "+app.view.players[1].name)
	expect(not exchange.disabled,"engine-approved exchange becomes confirmable")
	exchange.pressed.emit();await pause_frames(2)
	expect(engine.state.revision==1,"exchange confirmation passes through authoritative action")
	await _verify_exchange_context()
	await _verify_gift_context()
	await _verify_reclaim_context()
	await _verify_gift_flower_preview()
	engine=fixture("transparent");await pause_frames(2)
	var mixed=engine.view(0)
	mixed.players[1].hand=[-1,0,1,2];mixed.players[1].hand_count=4;mixed.players[1].drawn=-1
	app._changed(mixed);await pause_frames(2)
	expect(app.table.pieces["h1-0"].get_meta("tile")==-1 and app.table.pieces["h1-0"].get_meta("pose")=="back","opaque tile keeps an unidentified back in a partially public hand")
	expect(app.table.pieces["h1-1"].get_meta("tile")==0 and app.table.pieces["h1-1"].get_meta("pose")=="face","public tile displays only the known identity")
	var before=app._visible_remaining(0)
	app.view.players[1].hand=[-1,-1,1,2]
	expect(app._visible_remaining(0)==before+1,"visible remaining count includes publicly visible opponent tiles")
	app.view.field={"id":"no_honors","tile_totals":Tiles.counts(Tiles.wall())}
	app.view.field.tile_totals[0]=9
	expect(app._visible_remaining(0)>4,"unusual decks use their actual public tile totals")
	app._show_public_tiles();await pause_frames(2)
	expect(labels(app.modal).any(func(value):return str(value).contains("公开手牌")),"public-tile viewer makes partial hands inspectable")
	engine=fixture("chosen");await pause_frames(2)
	app.view.field.chosen_tiles=[22,0,18]
	var base=[0,1,2,3,4,5,9,10,11,18,19,20,22]
	var normal=Rules.evaluate(base+[22],[],{"self_draw":true,"bao":true,"luan":true})
	app.view.players[0].melds=[]
	expect(app._wait_score(base,22).points==normal.points*2,"wait preview includes the current field bonus")
	var six=[]
	for group in Rules.chi([27,28,29,30],31,"honor_sequences"):
		six.append({"kind":"chi","tile":31,"tiles":group,"id":str(six.size())})
	app._show_move_picker(six);await pause_frames(2)
	expect(six.size()==6 and app.modal.size.y>380,"all six honor-sequence choices fit across two rows")
	app._close_modal()
	app.view.phase="turn";app.view.decision_seat=0;app.view.pending=[]
	for index in range(14):app.view.pending.append({"kind":"win","id":str(index)})
	app._draw_actions();await pause_frames(2)
	var rows: Array=[]
	for button in app.action_layer.get_children():
		if not button is Button or button.is_queued_for_deletion():continue
		var rect: Rect2=button.get_rect()
		expect(rect.position.x>=0 and rect.end.x<=1600,"long action set stays inside the logical screen")
		if rect.position.y not in rows:rows.append(rect.position.y)
	expect(rows.size()>1,"long action sets wrap instead of shrinking readable targets")
	print("FIELD_UI_RESULT: %d checks; %d failures"%[checks,failures.size()])
	engine=null
	call_deferred("finish",0 if failures.is_empty() else 1)
