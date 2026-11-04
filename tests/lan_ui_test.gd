extends "res://tests/ui_smoke.gd"
## Headless control/state checks. This never injects OS input or opens a window.
var checks = 0

func expect(ok: bool, message: String) -> void:
	checks += 1; check(ok,message)

func labels(node: Node) -> Array:
	var result: Array = []
	if node is Label: result.append(node.text)
	for child in node.get_children(): result.append_array(labels(child))
	return result

func run() -> void:
	if DisplayServer.get_name() != "headless":
		printerr("LAN UI checks require --headless"); quit(1); return
	create_timer(45).timeout.connect(func(): printerr("LAN UI watchdog"); quit(1))
	app = load("res://scenes/main.tscn").instantiate(); app.qa_mode = true; root.add_child(app)
	app.session.set_process(false); app.session.speed = 0.75
	expect(find_button(app.root,"附近同桌") != null,"lobby provides a nearby-room entry")
	app._show_lan_browser(); await pause_frames(2)
	expect(app.current_screen=="lan" and app.lan_lobby != null,"nearby entry opens browser")
	var name_input: LineEdit = app.lan_lobby.name_input
	var address_input: LineEdit = app.lan_lobby.address_input
	name_input.text = "一位测试牌友"; name_input.text_changed.emit(name_input.text)
	address_input.text = "192.168.1.10"; address_input.text_changed.emit(address_input.text)
	address_input.grab_focus()
	app._lan_rooms_changed([{"id":"test-room","name":"另一位牌友的房间","address":"192.168.1.11","port":32141,"players":2,"started":false,"settings":{"jiang":"luan","chi":false}}])
	await pause_frames(2)
	expect(app.lan_lobby.name_input==name_input and app.lan_lobby.address_input==address_input,"automatic discovery preserves input nodes")
	expect(address_input.has_focus() and address_input.text=="192.168.1.10","automatic discovery preserves typed address and focus")
	expect(find_button(app.lan_lobby,"加入") != null,"a discovered room has join action")
	var original_jiang = app.lan_lobby.configuration.jiang
	app.lan_lobby.set_busy(true,"正在连接房主…")
	var rule_button = find_button(app.lan_lobby,"乱将")
	expect(rule_button.disabled,"rule changes are disabled while a join is pending")
	rule_button.pressed.emit()
	expect(app.lan_lobby.configuration.jiang==original_jiang and app.lan_lobby.name_input==name_input and app.lan_lobby.create_button.disabled,"a pending join cannot rebuild the browser or enable a second room operation")
	app.lan_lobby.set_busy(false)
	app.lan_lobby.address = "not-an-ip"; app.lan_lobby._join_address()
	expect(app.lan_lobby.status_label.text.contains("IPv4"),"invalid manual addresses get actionable feedback")
	app.lan_lobby.address = "192.168.1.10:80"; app.lan_lobby._join_address()
	expect(app.lan_lobby.status_label.text.contains("1024"),"manual join enforces the transport's allowed port range")
	app.discovery.stop()
	app._replace_session(LanSession.new())
	var host: LanSession = app.session
	host.set_process(false)
	expect(host.host_room({"jiang":"luan","chi":false,"ai":"classic"},"房主测试",32171)==OK,"host session creates on a test port")
	await pause_frames(2)
	expect(labels(app.lan_lobby).has("电脑补位"),"waiting room identifies empty seats as computer fill")
	expect(not find_button(app.lan_lobby,"开始对局 →").disabled,"one host can start with three computers")
	expect(find_button(app.lan_lobby,"掉线托管：关闭") != null,"disconnected-player takeover starts off")
	var fake_room = host.room.duplicate(true)
	fake_room.seats[1].merge({"occupied":true,"name":"客人","connected":true,"ready":false,"bot":false},true)
	fake_room.can_start = false
	app.lan_lobby.show_room(fake_room,false,1)
	expect(find_button(app.lan_lobby,"我准备好了") != null,"guest has an explicit ready action")
	expect(find_button(app.lan_lobby,"开始对局 →")==null,"guest cannot start the room")
	expect(find_button(app.lan_lobby,"二五八将")==null and labels(app.lan_lobby).has("乱将"),"guest sees the selected rule without editable rule buttons")
	app.lan_lobby.show_room(host.room,true,0)
	expect(host.start_room(),"host starts a LAN table")
	await pause_frames(3)
	expect(app.current_screen=="table" and app.view.players[0].name=="房主测试","start switches to table with network player names")
	app._show_settings()
	expect(not host.paused,"LAN settings never pause the shared game")
	app._close_modal(); app._show_lan_room_menu()
	expect(not host.paused and find_button(app.modal,"解散房间")!=null,"room menu keeps the game running and offers dissolve")
	app._confirm_leave_lan()
	expect(app.session==host and host.connected,"dissolve is reviewable before leaving")
	app._close_modal()
	host.engine._draw_result(); host.engine.state.revision += 1; host._publish()
	await pause_frames(3)
	expect(find_button(app.modal,"继续下一局 →") != null,"host settlement can continue")
	var result_modal = app.modal
	host._publish(); await pause_frames(2)
	expect(app.modal==result_modal,"a repeated settled snapshot does not reopen celebration")
	app._close_modal(); app._pause()
	expect(find_button(app.modal,"查看本局结算")!=null,"room menu offers settlement after it was dismissed")
	find_button(app.modal,"查看本局结算").pressed.emit()
	expect(find_button(app.modal,"继续下一局 →")!=null,"host can recover the next-round action from the room menu")
	host.next_round(); await pause_frames(2)
	expect(app.view.round==2 and not is_instance_valid(app.modal),"new round closes prior settlement")
	app.auto_button.text = "收回操作"; host.autopilot = false
	app._lan_room_changed(host.room)
	expect(app.auto_button.text=="交给 AI","a room refresh clears stale takeover text without a new game revision")
	app._show_settings()
	host.is_host = false
	app._show_settings()
	expect(find_button(app.modal,"由房主控制").disabled,"guest cannot change shared AI pace")
	app._close_modal()
	var result_view = app.view.duplicate(true)
	result_view.phase = "settled"; result_view.pending = []
	result_view.result = {"draw":true,"deltas":[0,0,0,0],"winner":-1,"round":2}
	app.view = result_view; app._show_result()
	expect(find_button(app.modal,"等待房主开始下一局").disabled,"guest settlement waits for host")
	expect(find_button(app.modal,"导出本局牌谱").disabled,"guest cannot export an authoritative replay")
	host.is_host = true
	app._lan_closed("测试连接中断")
	expect(find_button(app.modal,"重新连接")!=null and find_button(app.modal,"返回附近房间")!=null,"connection loss offers retry and browser return")
	host.connected = false
	var disconnected_modal = app.modal
	app._celebrate()
	expect(app.modal==disconnected_modal,"settlement presentation cannot replace a disconnected prompt")
	app._close_modal(); app._pause()
	expect(find_button(app.modal,"重新连接")!=null,"room menu preserves retry after the disconnected prompt is dismissed")
	app._leave_lan(); await pause_frames(2)
	expect(app.current_screen=="lobby" and not app._is_lan(),"leaving restores the single-player lobby")
	expect(app.session.storage_root=="user://qa/" and app.session.speed==0.75,"session replacement preserves test isolation and pace")
	app._start_game(false); app.session.set_process(false)
	expect(app.current_screen=="table" and not app.view.is_empty(),"single-player starts after leaving LAN")
	app._pause(); expect(app.session.paused,"single-player modal pause still works")
	app._close_modal(); expect(not app.session.paused,"single-player modal close still resumes")
	app.queue_free(); await pause_frames(2)
	print("LAN UI checks: %d; failures: %d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
