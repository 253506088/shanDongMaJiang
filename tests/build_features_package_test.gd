extends SceneTree
## Run with the actual exported EXE and an absolute --script path.
var failures: Array = []
var checks = 0
var app

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("BUILD FEATURES FAIL: ", message)

func find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text: return node
	for child in node.get_children():
		var found = find_button(child, text)
		if found: return found
	return null

func capture(name: String) -> void:
	var args = OS.get_cmdline_user_args()
	var index = args.find("--capture-dir")
	if DisplayServer.get_name() == "headless" or index < 0: return
	for frame in range(4): await process_frame
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(args[index + 1].path_join(name + ".png")) == OK, "save package screenshot")

func run() -> void:
	Engine.max_fps = 60
	create_timer(45).timeout.connect(func(): printerr("Package features watchdog"); quit(1))
	var expected = "--expect-lan" in OS.get_cmdline_user_args()
	app = load("res://scenes/main.tscn").instantiate(); app.qa_mode = true; root.add_child(app)
	app.session.set_process(false); app.muted = true
	check(ProjectSettings.get_setting("application/config/version") == "0.10.3", "current package version")
	check(BuildFeatures.lan_enabled() == expected, "package capability matches build choice")
	check(OS.has_feature("lan") == expected and OS.has_feature("offline") != expected, "explicit export feature tags")
	check((find_button(app.root, "附近同桌") != null) == expected, "nearby entry follows build choice")
	check(app._games_description().contains("附近同桌") == expected, "lobby and about describe available games")
	check(app.discovery.socket == null, "launch does not open discovery sockets")
	await capture("lobby-lan" if expected else "lobby-offline")
	app._about(); await capture("about-lan" if expected else "about-offline"); app._close_modal()
	if not expected:
		var original_session = app.session
		app._show_lan_browser(); app._host_lan({}, "test"); app._join_lan("127.0.0.1", "test")
		check(app.current_screen == "lobby" and app.session == original_session, "direct UI entry cannot enable LAN")
		check(app.discovery.start_browser() == ERR_UNAVAILABLE, "discovery browser disabled")
		check(app.discovery.start_host({}) == ERR_UNAVAILABLE, "discovery host disabled")
		check(app.discovery.socket == null and LanDiscovery.local_addresses().is_empty(), "offline discovery leaves no socket or addresses")
		var lan = LanSession.new()
		check(lan.host_room({}) == ERR_UNAVAILABLE, "ENet server disabled")
		check(lan.join_room("127.0.0.1") == ERR_UNAVAILABLE, "ENet client disabled")
		check(lan._connect_client() == ERR_UNAVAILABLE and lan._peer == null, "reconnect transport cannot bypass build setting")
		lan.free()
	# All three local games remain reachable without writing a real save.
	app._open_doudizhu(); app.doudizhu.session.set_process(false)
	check(app.current_screen == "doudizhu", "local Dou Dizhu available")
	app._show_lobby(); await process_frame
	app._open_bluff(); app.bluff.session.set_process(false)
	check(app.current_screen == "bluff", "local bluff available")
	app._show_lobby(); await process_frame
	app.session.engine.start({}, 8912)
	app._build_hud(); app._changed(app.session.presentation_view())
	check(app.view.players.size() == 4, "local Mahjong available")
	check(app.table.seat_labels.map(func(label): return label.text) == ["东", "南", "西", "北"], "seat winds follow existing turn order")
	var south = app.table.camera.unproject_position(app.table.seat_labels[1].global_position)
	var north = app.table.camera.unproject_position(app.table.seat_labels[3].global_position)
	check(south.x > north.x, "with east below, south is right and north is left")
	await capture("mahjong-winds")
	print("BUILD_FEATURES_PACKAGE_RESULT: %d failures; %d checks" % [failures.size(), checks])
	var code = 0 if failures.is_empty() else 1
	app.queue_free(); app = null
	for frame in range(4): await process_frame
	RenderingServer.force_draw(false)
	await create_timer(.2).timeout
	quit(code)
