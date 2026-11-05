extends Node
const DoudizhuMode = preload("res://scripts/doudizhu/mode.gd")
var doudizhu: Control
var doudizhu_voice = "male"
var session: LocalSession
var table: Table3D
var canvas: CanvasLayer
var root: Control
var lobby: Control
var hud: Control
var hand_layer: Control
var action_layer: Control
var modal: Control
var toast_label: Label
var toast_time = 0.0
var view: Dictionary = {}
var selected = -1
var declare_mode = ""
var config = {"jiang": "258", "chi": true, "ai": "efficiency", "rounds": 4, "field_rules": false, "field_selection": "random"}
var muted = false
var low_quality = false
var desktop_window: DesktopWindow
var scene_surface: SceneSurface
var display_button: Button
# Render/input checks must neither read nor overwrite a player's preferences.
var qa_mode = "--qa" in OS.get_cmdline_user_args()
var preferences_path = "user://preferences.json"
var players_ui: Array = []
var round_text: Label
var head_tile: TextureRect
var head_name: Label
var recent_panel: Panel
var auto_button: Button
var hint_button: Button
var detail_label: Label
var sfx: AudioStreamPlayer
var last_revision = -1
var action_cue: Control
var current_screen = "lobby"
var sounds: Dictionary = {}
var tile_textures: Array = []
var voice: TileVoice
var last_tile: TextureRect
var last_tile_label: Label
var last_actor_label: Label
var waits_button: Button
var waits_panel: Panel
var waits_expanded = true
var opponent_waits_panels: Dictionary = {}
var opponent_waits_cache: Dictionary = {}
var opponent_waits_round = -1
var public_tiles_button: Button
var inspect_layer: Control
var last_touch_ms = -1000
var touch_started = Vector2.ZERO
var touch_started_ms = 0
var touch_index = -1
var suppress_click_until = -1
var lan_lobby: LanLobby
var discovery: LanDiscovery
var lan_player_name = "牌友"
var lan_address = ""
var lan_room_menu = false
var field_button: Button
var field_exchange_selection: Array = []
var field_picker_selection = -1

func _ready() -> void:
	Engine.max_fps=60
	desktop_window = DesktopWindow.new(); add_child(desktop_window)
	desktop_window.fullscreen_changed.connect(_display_changed)
	scene_surface = SceneSurface.new(); add_child(scene_surface)
	for t in range(43): tile_textures.append(load(Tiles.texture_path(t)))
	for name in ["click", "tile", "deal", "notify", "win"]: sounds[name] = load("res://assets/audio/" + name + ".wav")
	sfx = AudioStreamPlayer.new(); add_child(sfx)
	voice = TileVoice.new(); add_child(voice)
	session = LocalSession.new(); add_child(session)
	session.changed.connect(_changed); session.hint_ready.connect(_hint); session.notice.connect(_toast)
	discovery = LanDiscovery.new(); add_child(discovery)
	discovery.rooms_changed.connect(_lan_rooms_changed)
	table = Table3D.new(); scene_surface.scene_viewport.add_child(table)
	table.tile_inspected.connect(func(tile,position):
		if current_screen=="table" and not is_instance_valid(modal): _inspect_tile(tile,position.x,position.y))
	canvas = CanvasLayer.new(); scene_surface.scene_viewport.add_child(canvas)
	root = Control.new(); root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_IGNORE; canvas.add_child(root)
	root.theme=Theme.new();root.theme.default_font=UI.font();root.theme.default_font_size=18
	_load_preferences()
	if qa_mode:session.storage_root="user://qa/";muted=true
	_show_lobby()
	get_tree().auto_accept_quit = false
	var args = OS.get_cmdline_user_args()
	if "--doudizhu" in args:
		_open_doudizhu()
	elif "--demo" in args:
		_start_game(false)
	if "--autoplay" in args: session.autopilot = true; session.speed = 8
	if "--capture" in args:
		var idx = args.find("--capture")
		if idx + 1 < args.size(): _capture(args[idx + 1])

func _capture(path: String) -> void:
	await get_tree().create_timer(3).timeout
	RenderingServer.force_draw(false)
	get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE_SAVED ",path)
	if "--capture-exit" in OS.get_cmdline_user_args(): get_tree().quit()

func _sound(name: String) -> void:
	if muted: return
	sfx.stream = sounds[name]; sfx.volume_db = -9; sfx.play()

func _clear(node: Node) -> void:
	if is_instance_valid(node):
		for child in node.get_children(): child.queue_free()

func _layer() -> Control:
	var node = Control.new(); node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE; root.add_child(node); return node

func _show_lobby() -> void:
	if _is_lan(): _confirm_leave_lan(); return
	if is_instance_valid(doudizhu):
		doudizhu.session.shutdown()
		doudizhu.voice.stop_all()
		doudizhu = null
	discovery.stop()
	current_screen = "lobby"; session.paused = true
	if is_instance_valid(voice): voice.stop_all()
	table.visible=false;desktop_window.set_frame_limit(60)
	_clear(root); modal = null; hud = null; toast_label = null
	opponent_waits_panels.clear();opponent_waits_cache.clear();opponent_waits_round=-1
	lobby = _layer()
	var courtyard=UI.texture(lobby,Rect2(0,0,1600,900),load("res://assets/backgrounds/courtyard_day.jpg"))
	courtyard.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var gradient=Gradient.new();gradient.set_color(0,Color("071d1af5"));gradient.set_color(1,Color("0b211b32"))
	gradient.add_point(0.52,Color("102b23c8"))
	var backdrop=GradientTexture2D.new();backdrop.gradient=gradient;backdrop.width=1600;backdrop.height=900
	backdrop.fill_from=Vector2.ZERO;backdrop.fill_to=Vector2(1,0.35)
	var bg = UI.texture(lobby,Rect2(0,0,1600,900),backdrop);bg.stretch_mode = TextureRect.STRETCH_SCALE
	UI.table_button(lobby,Rect2(1314,40,110,46),"玩法",_show_rules,false,"help")
	UI.table_button(lobby,Rect2(1436,40,110,46),"设置",_show_settings,false,"settings")
	UI.button(lobby,Rect2(105,90,180,46),"山东麻将",func(): pass,true)
	UI.button(lobby,Rect2(297,90,180,46),"斗地主",_open_doudizhu)
	UI.label(lobby,Rect2(104,157,650,30),"山 东 麻 将  ·  青 玉 台",20,UI.ACCENT,true)
	UI.label(lobby,Rect2(98,215,740,106),"好牌，慢慢来。",70,UI.TEXT,true)
	UI.label(lobby,Rect2(105,344,660,65),"一方庭院，四席牌友。\n熟悉的山东玩法，随时落座，随时续玩。",22,UI.MUTED)
	# Original tile artwork, arranged as a compact still life.
	for item in [[1,990,285,-0.18],[13,1163,238,0.06],[31,1322,319,0.21]]:
		var shadow = UI.panel(lobby,Rect2(item[1]+4,item[2]+12,164,235),Color("07151088"),Color.TRANSPARENT,15)
		shadow.pivot_offset=Vector2(82,118);shadow.rotation = item[3]
		var tile = UI.texture(lobby,Rect2(item[1],item[2],164,235),tile_textures[item[0]])
		tile.pivot_offset = Vector2(82,118); tile.rotation = item[3]
	var companions=UI.table_panel(lobby,Rect2(1060,626,404,118),false,18)
	for seat in range(1,4):
		var x=32+(seat-1)*128
		UI.portrait(companions,Vector2(x,14),56,seat)
		var caption=UI.label(companions,Rect2(x-12,77,80,26),["","听松","观澜","知秋"][seat],16,UI.TABLE_TEXT)
		caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var options = UI.table_panel(lobby,Rect2(104,465,720,249),false,18)
	UI.label(options,Rect2(25,17,240,32),"本桌约定",22,UI.TEXT)
	UI.label(options,Rect2(25,67,65,42),"将牌",17,UI.MUTED)
	_toggle(options,Rect2(89,68,124,42),"二五八将",config.jiang=="258",func(): config.jiang="258"; _save_preferences(); _show_lobby())
	_toggle(options,Rect2(219,68,100,42),"乱将",config.jiang=="luan",func(): config.jiang="luan"; _save_preferences(); _show_lobby())
	UI.label(options,Rect2(357,67,60,42),"吃牌",17,UI.MUTED)
	_toggle(options,Rect2(420,68,123,42),"允许吃",config.chi,func(): config.chi=true; _save_preferences(); _show_lobby())
	_toggle(options,Rect2(549,68,142,42),"不允许吃",not config.chi,func(): config.chi=false; _save_preferences(); _show_lobby())
	UI.label(options,Rect2(25,119,65,42),"牌友",17,UI.MUTED)
	_toggle(options,Rect2(89,120,124,42),"牌效 AI",config.ai=="efficiency",func(): config.ai="efficiency"; _save_preferences(); _show_lobby())
	_toggle(options,Rect2(219,120,100,42),"经典 AI",config.ai=="classic",func(): config.ai="classic"; _save_preferences(); _show_lobby())
	UI.label(options,Rect2(357,119,60,42),"场次",17,UI.MUTED)
	for i in range(3):
		var rounds = [4,8,0][i]
		_toggle(options,Rect2(420+i*92,120,86,42),["东风","半庄","自由"][i],config.rounds==rounds,func(): config.rounds=rounds; _save_preferences(); _show_lobby())
	UI.label(options,Rect2(25,180,65,42),"场地",17,UI.MUTED)
	_toggle(options,Rect2(89,180,102,42),"不开启",not config.get("field_rules",false),func(): config.field_rules=false; _save_preferences(); _show_lobby())
	_toggle(options,Rect2(199,180,124,42),"每局随机",config.get("field_rules",false) and FieldRules.selection(config)=="random",func(): config.field_rules=true; config.field_selection="random"; _save_preferences(); _show_lobby())
	var selection=FieldRules.selection(config)
	var specified=config.get("field_rules",false) and selection!="random"
	UI.button(options,Rect2(331,180,250,42),"指定 · "+str(FieldRules.info(selection).name) if specified else "指定规则…",func():
		_show_field_selector(config,func(settings):config=settings;_save_preferences();_show_lobby()),specified).add_theme_font_size_override("font_size",16)
	UI.button(options,Rect2(589,180,102,42),"说明",_show_field_catalog)
	UI.button(lobby,Rect2(105,726,279,66),"入 座 开 局   →",func(): _start_game(true),true)
	if session.has_save(): UI.button(lobby,Rect2(402,726,221,66),"继续上次牌局",_resume)
	UI.button(lobby,Rect2(641,726,183,66),"附近同桌",_show_lan_browser)
	UI.label(lobby,Rect2(105,839,1000,24),"麻将单机 / 附近同桌   ·   斗地主单机",14,UI.MUTED)
	UI.button(lobby,Rect2(1426,829,120,42),"关于",_about)

func _open_doudizhu() -> void:
	if _is_lan(): return
	session.paused = true
	discovery.stop()
	voice.stop_all()
	current_screen = "doudizhu"
	table.visible = false
	desktop_window.set_frame_limit(60)
	_clear(root)
	modal = null; lobby = null; hud = null; toast_label = null
	doudizhu = DoudizhuMode.new()
	doudizhu.muted = muted
	doudizhu.voice_profile = doudizhu_voice
	doudizhu.qa_mode = qa_mode
	doudizhu.exit_requested.connect(_show_lobby)
	doudizhu.mute_changed.connect(func(value): muted = value; _save_preferences())
	doudizhu.voice_profile_changed.connect(func(value): doudizhu_voice = value; _save_preferences())
	root.add_child(doudizhu)

func _toggle(parent: Node, rect: Rect2, text: String, on: bool, callback: Callable) -> void:
	var b = UI.button(parent,rect,text,callback,on)
	b.add_theme_font_size_override("font_size",16)

func _is_lan() -> bool:
	return session is LanSession

func _replace_session(next: LocalSession) -> void:
	var previous = session
	var previous_speed = previous.speed
	previous.changed.disconnect(_changed); previous.hint_ready.disconnect(_hint); previous.notice.disconnect(_toast)
	if previous is LanSession:
		previous.room_changed.disconnect(_lan_room_changed)
		previous.connection_closed.disconnect(_lan_closed)
		previous.leave_room()
	previous.set_process(false); previous.queue_free()
	session = next; session.speed = previous_speed
	if qa_mode: session.storage_root = "user://qa/"
	add_child(session)
	session.changed.connect(_changed); session.hint_ready.connect(_hint); session.notice.connect(_toast)
	if session is LanSession:
		session.room_changed.connect(_lan_room_changed)
		session.connection_closed.connect(_lan_closed)
	view = {}; last_revision = -1

func _make_lan_screen() -> void:
	current_screen = "lan"; table.visible = false; desktop_window.set_frame_limit(60)
	voice.stop_all(); _clear(root); modal = null; hud = null; lobby = null; toast_label = null
	opponent_waits_panels.clear(); opponent_waits_cache.clear(); opponent_waits_round = -1
	lan_lobby = LanLobby.new(); root.add_child(lan_lobby)
	lan_lobby.back_requested.connect(func():
		lan_player_name = lan_lobby.nickname; lan_address = lan_lobby.address
		if _is_lan(): _leave_lan()
		else: _show_lobby())
	lan_lobby.host_requested.connect(_host_lan)
	lan_lobby.join_requested.connect(_join_lan)
	lan_lobby.ready_requested.connect(func(ready):
		if _is_lan(): (session as LanSession).set_ready(ready))
	lan_lobby.start_requested.connect(func():
		if _is_lan() and not (session as LanSession).start_room(): _toast("请等待在座牌友全部准备。"))
	lan_lobby.settings_requested.connect(func(settings):
		if _is_lan(): (session as LanSession).set_room_settings(settings))
	lan_lobby.field_catalog_requested.connect(_show_field_catalog)
	lan_lobby.field_selection_requested.connect(func(settings):
		_show_field_selector(settings,func(next_settings):
			if _is_lan(): (session as LanSession).set_room_settings(next_settings)
			elif is_instance_valid(lan_lobby):lan_lobby.show_browser(next_settings,lan_lobby.nickname,lan_lobby.address)))
	lan_lobby.disconnect_autoplay_requested.connect(func(enabled):
		if _is_lan(): (session as LanSession).set_disconnect_autoplay(enabled))
	lan_lobby.leave_requested.connect(_confirm_leave_lan)

func _show_lan_browser() -> void:
	if _is_lan(): _leave_lan(false)
	session.paused = true
	_make_lan_screen()
	lan_lobby.show_browser(config,lan_player_name,lan_address)
	if discovery.start_browser() != OK:
		lan_lobby.set_status("附近房间搜索暂不可用，仍可输入房主地址加入。")

func _host_lan(settings: Dictionary, player_name: String) -> void:
	lan_player_name = player_name
	discovery.stop(); _replace_session(LanSession.new())
	var error = (session as LanSession).host_room(settings,player_name)
	if error != OK:
		_replace_session(LocalSession.new()); _show_lan_browser()
		lan_lobby.set_status("创建房间失败，请检查网络或是否已经开着另一间房。")
		return
	if discovery.start_host((session as LanSession).room) != OK:
		_toast("房间已创建，附近搜索暂不可用；牌友仍可输入房主地址加入。")

func _join_lan(address: String, player_name: String, port: int = 32141) -> void:
	lan_player_name = player_name; lan_address = address+(":%d"%port if port != 32141 else "")
	discovery.stop(); _replace_session(LanSession.new())
	lan_lobby.set_busy(true,"正在连接房主…")
	var error = (session as LanSession).join_room(address,player_name,port)
	if error != OK: _lan_closed("连接失败，请检查房主地址和网络。")

func _lan_rooms_changed(rooms: Array) -> void:
	if current_screen == "lan" and is_instance_valid(lan_lobby): lan_lobby.update_rooms(rooms)

func _lan_room_changed(room: Dictionary) -> void:
	if not _is_lan(): return
	var lan = session as LanSession
	if lan.is_host: discovery.update_room(room)
	if current_screen == "table" and is_instance_valid(auto_button):
		auto_button.text = "收回操作" if session.autopilot else "交给 AI"
	if current_screen == "lan" and not room.get("started",false):
		lan_lobby.show_room(room,lan.is_host,lan.local_seat)
	elif current_screen == "table" and lan_room_menu:
		_show_lan_room_menu()

func _lan_closed(reason: String) -> void:
	if not _is_lan(): return
	if is_instance_valid(lan_lobby): lan_lobby.set_busy(false,reason)
	_popup("连接已中断",Vector2(760,380))
	var detail = UI.label(modal,Rect2(43,101,672,94),reason+"\n请确认所有设备仍连接同一 Wi-Fi / 热点，且房主在游戏前台。",21,UI.MUTED)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI.button(modal,Rect2(43,264,279,59),"返回附近房间",_show_lan_browser)
	UI.button(modal,Rect2(340,264,374,59),"重新连接",_reconnect_lan,true)

func _reconnect_lan() -> void:
	if not _is_lan(): return
	_close_modal()
	if (session as LanSession).room.is_empty():
		var parts = lan_address.split(":")
		_join_lan(parts[0],lan_player_name,int(parts[1]) if parts.size()==2 else 32141)
	elif (session as LanSession).reconnect_room() != OK: _lan_closed("暂时无法重新连接。")
	else: _toast("正在重新连接原房间…")

func _confirm_leave_lan() -> void:
	if not _is_lan(): _show_lobby(); return
	if (session as LanSession).room.is_empty(): _leave_lan(); return
	var host = (session as LanSession).is_host
	_popup("解散房间" if host else "离开房间",Vector2(680,354))
	UI.label(modal,Rect2(43,100,594,98),"解散后，所有牌友都会离开本桌。\n当前局域网牌局不会保存为单机存档。" if host else "离开后，这个座位将交给电脑。\n本桌开局后不能作为新玩家再次加入。",21,UI.MUTED)
	UI.button(modal,Rect2(43,251,274,56),"继续留在房间",_close_modal)
	UI.button(modal,Rect2(335,251,301,56),"解散并返回大厅" if host else "离开并返回大厅",_leave_lan,true)

func _leave_lan(show_lobby: bool = true) -> void:
	discovery.stop(); _close_modal()
	if _is_lan(): _replace_session(LocalSession.new())
	lan_room_menu = false
	if show_lobby: _show_lobby()

func _show_lan_room_menu() -> void:
	if not _is_lan(): return
	var lan = session as LanSession
	_popup("本桌房间",Vector2(820,626)); lan_room_menu = true
	var names: Array = []
	for member in lan.room.get("seats",[]):
		var suffix = "电脑" if member.get("bot",false) else ("在线" if member.get("connected",true) else "离线，保留座位")
		names.append(str(member.get("name","电脑"))+" · "+suffix)
	UI.label(modal,Rect2(43,101,729,154),"\n".join(names),22,UI.TEXT)
	var addresses: Array = lan.room.get("host_addresses",[])
	var addresses_label = UI.label(modal,Rect2(43,275,729,59),"房主地址："+"、".join(addresses.map(func(item):return str(item))),18,UI.MUTED)
	addresses_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if lan.is_host:
		UI.button(modal,Rect2(43,355,729,51),"掉线托管：开启" if lan.room.get("disconnect_autoplay",false) else "掉线托管：关闭",func():
			lan.set_disconnect_autoplay(not bool(lan.room.get("disconnect_autoplay",false))))
	else:
		UI.label(modal,Rect2(43,355,729,51),"掉线托管当前"+("开启" if lan.room.get("disconnect_autoplay",false) else "关闭")+"，由房主控制。",20,UI.MUTED)
	UI.label(modal,Rect2(43,427,729,52),"查看房间时对局继续。房主请保持游戏在前台。" if lan.connected else "连接已中断。检查网络后可重新连接原座位。",20,UI.MUTED)
	var settled = view.get("phase","") == "settled"
	if not lan.connected:
		UI.button(modal,Rect2(43,520,352,57),"重新连接",_reconnect_lan,true)
	else:
		UI.button(modal,Rect2(43,520,352,57),"查看本局结算" if settled else "回到牌桌",_show_result if settled else _close_modal,true)
	UI.button(modal,Rect2(412,520,360,57),"解散房间" if lan.is_host else "离开房间",_confirm_leave_lan)

func _start_game(confirm_replace: bool) -> void:
	if confirm_replace and session.has_save():
		_popup("开始新牌局",Vector2(640,325))
		UI.label(modal,Rect2(44,94,550,66),"开始新牌局会替换当前续玩存档。\n已有存档会保留一份本地备份。",21,UI.MUTED)
		UI.button(modal,Rect2(43,235,252,54),"取消",_close_modal)
		UI.button(modal,Rect2(313,235,282,54),"开始新牌局",func(): _start_game(false),true)
		return
	_close_modal(); _build_hud(); session.start_match(config); _sound("deal")

func _resume() -> void:
	_build_hud()
	if not session.resume_match(): _show_lobby(); _toast("存档校验失败，请开始新对局。")

func _build_hud() -> void:
	current_screen = "table"; _clear(root); modal = null; lobby = null; toast_label = null
	voice.stop_all();voice.last_key="";table.last_round=-1;table.last_revision=-1
	table.visible=true;desktop_window.set_frame_limit(30 if low_quality else 60)
	hud = _layer(); selected = -1; declare_mode = ""; last_revision = -1
	waits_panel=null;waits_expanded=true
	opponent_waits_panels.clear();opponent_waits_cache.clear();opponent_waits_round=-1
	var badge = UI.table_panel(hud,Rect2(625,24,350,36),false,18)
	round_text = UI.label(badge,Rect2(0,0,350,36),"",18,UI.TABLE_TEXT); round_text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	# The second row belongs to the opposite player's exposed hand. Keep the
	# field entry in the top toolbar band, beside the centred round information.
	field_button = UI.table_button(hud,Rect2(28,23,300,42),"",_show_current_field)
	field_button.visible = false
	UI.table_button(hud,Rect2(1245,23,96,42),"玩法",_show_rules,false,"help")
	UI.table_button(hud,Rect2(1351,23,96,42),"设置",_show_settings,false,"settings")
	UI.table_button(hud,Rect2(1457,23,115,42),"房间" if _is_lan() else "暂停  II",_pause).tooltip_text="查看房间（Esc）" if _is_lan() else "暂停对局（Esc）"
	var gang = UI.table_panel(hud,Rect2(28,108,152,78))
	gang.tooltip_text="当前公开的杠头牌；开杠后从牌墙末端补入。"
	head_tile = UI.texture(gang,Rect2(12,8,44,61),tile_textures[42])
	head_name=UI.label(gang,Rect2(70,24,75,30),"",20,UI.TABLE_TEXT)
	players_ui = []
	for seat in range(4):
		var pos = [Vector2(28,778),Vector2(1396,386),Vector2(1242,108),Vector2(28,386)][seat]
		var panel = UI.table_panel(hud,Rect2(pos,Vector2(176,92)))
		UI.portrait(panel,Vector2(12,12),54,(seat+(session as LanSession).local_seat)%4 if _is_lan() else seat)
		var name_label = UI.label(panel,Rect2(78,6,58,28),["我","听松","观澜","知秋"][seat],20,UI.TABLE_TEXT)
		name_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		var state_label = UI.label(panel,Rect2(135,12,24,22),"",15,UI.TABLE_GOLD)
		state_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var score = UI.label(panel,Rect2(78,33,92,31),"2000",24,UI.TABLE_TEXT)
		var info = UI.label(panel,Rect2(14,68,150,22),"",15,UI.TABLE_MUTED)
		var turn_dot=UI.panel(panel,Rect2(160,10,5,5),UI.TABLE_GOLD,Color.TRANSPARENT,3)
		turn_dot.mouse_filter=Control.MOUSE_FILTER_IGNORE
		players_ui.append({"panel":panel,"state":state_label,"score":score,"info":info,"name":name_label,"turn":turn_dot})
	var recent = UI.table_panel(hud,Rect2(28,224,152,126))
	recent_panel=recent
	last_actor_label = UI.label(recent,Rect2(6,7,140,23),"等待出牌",15,UI.TABLE_MUTED); last_actor_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	last_tile = UI.texture(recent,Rect2(52,32,48,66),tile_textures[42])
	last_tile_label = UI.label(recent,Rect2(6,98,140,24),"",15,UI.TABLE_GOLD); last_tile_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	detail_label = UI.label(hud,Rect2(312,872,978,24),"",12,UI.TABLE_TEXT); detail_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	hint_button=UI.table_button(hud,Rect2(1406,770,166,44),"牌效提示",func(): session.request_hint(); _toast("正在分析当前手牌…"),false,"hint")
	hint_button.tooltip_text="查看当前手牌的出牌建议（H）"
	auto_button=UI.table_button(hud,Rect2(1406,824,166,44),"交给 AI",func():
		session.autopilot=not session.autopilot
		auto_button.text="收回操作" if session.autopilot else "交给 AI",false,"bot")
	hand_layer = _layer(); action_layer = _layer(); inspect_layer = _layer()
	waits_button = UI.table_button(hud,Rect2(1406,716,166,44),"听牌一览",_show_waits,false,"tiles")
	public_tiles_button=UI.table_button(hud,Rect2(28,500,176,42),"查看桌面牌",_show_public_tiles,false,"eye")

func _changed(new_view: Dictionary) -> void:
	var new_result = new_view.phase == "settled" and (view.is_empty() or view.phase != "settled" or view.round != new_view.round)
	if _is_lan() and current_screen == "lan": _build_hud()
	if _is_lan() and not view.is_empty() and view.round != new_view.round:
		_close_modal(); last_revision = -1
	view = new_view
	if current_screen != "table": return
	var revision_changed=last_revision!=view.revision
	if revision_changed:
		selected = -1; declare_mode = ""
		field_exchange_selection.clear()
		field_picker_selection=-1
		if is_instance_valid(modal) and modal.get_meta("field_action",false): _close_modal()
		_clear(inspect_layer)
		if last_revision >= 0:
			_sound("win" if view.phase=="settled" and not view.result.draw else ("notify" if view.event.kind in ["bao","ming","gang","angang","bugang","peng","chi"] else "tile"))
			_show_cue(view.event)
			session.hold_presentation(voice.announce(view,muted))
	last_revision = view.revision
	var target = {"tile":view.claim_tile,"seat":view.claim_from} if view.phase == "claim" else view.last_discard
	recent_panel.visible=not target.is_empty() and target.tile>=0
	recent_panel.add_theme_stylebox_override("panel",UI.table_style(view.phase=="claim" and view.decision_seat==0))
	if not target.is_empty() and target.tile >= 0:
		last_tile.texture = tile_textures[target.tile]
		last_actor_label.text = view.players[target.seat].name + (" · 待应牌" if view.phase == "claim" else " · 刚打出")
		last_tile_label.text = Tiles.spoken_title(target.tile)
	else:
		last_actor_label.text = "等待出牌"; last_tile_label.text = ""; last_tile.texture = tile_textures[42]
	table.update_view(view)
	var field = ["东","南","西","北"][((int(view.round)-1)/4)%4]
	round_text.text = "%s风 · 第 %d 局  /  %s" % [field,view.round,"二五八将" if view.settings.jiang=="258" else "乱将"]
	field_button.visible = not _field_id().is_empty()
	if field_button.visible:
		var rule = FieldRules.info(_field_id())
		var ability = " · 已用" if view.players[0].get("field_used",false) else (" · 可用" if _field_moves().size()>0 else "")
		field_button.text = "场地 · "+str(rule.name)+ability
		field_button.tooltip_text = str(rule.summary)+"\n点击查看规则、能力与本局信息。"
		if _field_id()=="no_honors":
			var additions=_no_honors_additions()
			var extra=additions.reduce(func(total,entry):return total+entry.added,0)
			field_button.text="无字天书 · 新增%d张"%extra if not additions.is_empty() else "无字天书 · 新增牌清单"
			field_button.tooltip_text="点击查看本局增加了哪些牌、每种增加多少张，以及本局各牌总数。"
	head_tile.texture = tile_textures[view.gang_head] if view.gang_head>=0 else tile_textures[42]
	head_name.text=Tiles.spoken_title(view.gang_head) if view.gang_head>=0 else ("盖牌" if _field_id()=="transparent" else "—")
	for seat in range(4):
		var p = view.players[seat]; var info = players_ui[seat]
		info.name.text = str(p.name); info.panel.tooltip_text = str(p.name)
		info.score.text = str(p.score)
		info.state.text = "庄" if seat==view.dealer else ""
		var flowers=Rules.flower_count(p.melds)
		var state_text="明搂" if p.ming else ("已听" if p.bao else ("亮手 · 未听" if p.get("revealed_hand",false) else ""))
		info.info.text = state_text + ("  ·  " if not state_text.is_empty() and flowers>0 else "") + ("花 %d"%flowers if flowers>0 else "")
		var active=seat==view.decision_seat and view.phase!="settled"
		info.turn.visible=active
		info.panel.add_theme_stylebox_override("panel",UI.table_style(active))
	hint_button.disabled = view.decision_seat != 0 or view.phase=="settled"
	auto_button.disabled = view.phase=="settled"
	auto_button.text = "收回操作" if session.autopilot else "交给 AI"
	waits_button.disabled = view.phase == "settled"
	_draw_hand(); _draw_actions(); _draw_waits_panel(); _draw_opponent_waits()
	if view.decision_seat == 0 and view.pending.any(func(a):return a.kind in ["win","gang","peng","chi","angang","bugang"]): _sound("notify")
	if view.phase == "settled" and (not _is_lan() or new_result): _celebrate()
	elif revision_changed and view.decision_seat==0 and view.phase=="gift_choice" and not is_instance_valid(modal): _show_field_picker("field_gift_pick")
	elif revision_changed and view.event.get("seat",-1)==0 and view.event.kind in ["field_peek_wall","field_peek_waits"]: _show_current_field()

func _show_cue(event: Dictionary) -> void:
	var names={"bao":"报 听","ming":"明 搂","upgrade_ming":"明 搂","chi":"吃","peng":"碰","gang":"杠","angang":"暗 杠","bugang":"补 杠","field_transform":"变 白","field_rebirth":"新 生","field_reclaim":"撤 回","field_gift":"施 舍","field_exchange":"换 牌"}
	if not names.has(event.kind):return
	if is_instance_valid(action_cue):action_cue.queue_free()
	action_cue=Control.new();hud.add_child(action_cue);action_cue.mouse_filter=Control.MOUSE_FILTER_IGNORE
	action_cue.position=[Vector2(690,570),Vector2(1160,390),Vector2(690,195),Vector2(225,390)][int(event.seat)]
	var word=UI.label(action_cue,Rect2(0,0,220,88),names[event.kind],54,UI.TABLE_GOLD,true);word.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	word.add_theme_color_override("font_shadow_color",Color("13251eda"));word.add_theme_constant_override("shadow_offset_y",3)
	action_cue.modulate.a=0
	var tween=action_cue.create_tween();tween.tween_property(action_cue,"modulate:a",1.0,0.12);tween.tween_interval(0.8);tween.tween_property(action_cue,"modulate:a",0.0,0.25)
	tween.tween_callback(action_cue.queue_free)

func _celebrate() -> void:
	var round_number=view.round
	if not view.result.draw:
		var effect=_layer()
		var veil=ColorRect.new();veil.size=Vector2(1600,900);veil.color=Color("071d19d9");veil.mouse_filter=Control.MOUSE_FILTER_IGNORE;effect.add_child(veil)
		var box=Control.new();box.position=Vector2(450,268);box.size=Vector2(700,310);box.pivot_offset=Vector2(350,155);effect.add_child(box)
		var line=ColorRect.new();line.position=Vector2(103,29);line.size=Vector2(494,2);line.color=UI.GOLD;box.add_child(line)
		var title={"self-draw":"自  摸","discard":"胡","robbed-kong":"抢 杠 胡","tianhu":"天  胡","dihu":"地  胡"}.get(view.result.win_type,"胡")
		var label=UI.label(box,Rect2(0,33,700,189),title,119,UI.GOLD,true);label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_shadow_color",Color("000c0a99"));label.add_theme_constant_override("shadow_offset_y",3)
		var caption=UI.label(box,Rect2(0,235,700,53),view.players[view.result.winner].name+"  ·  "+view.result.pattern,26,UI.TEXT,true);caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		box.scale=Vector2(0.86,0.86);effect.modulate.a=0
		var tween=create_tween().set_parallel()
		tween.tween_property(effect,"modulate:a",1.0,0.2)
		tween.tween_property(box,"scale",Vector2.ONE,0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		await get_tree().create_timer(1.3).timeout
		if is_instance_valid(effect):effect.queue_free()
	if current_screen=="table" and view.round==round_number and view.phase=="settled":
		if _is_lan() and not (session as LanSession).connected: return
		_show_result()

func _draw_hand() -> void:
	_clear(hand_layer)
	if view.is_empty(): return
	var p = view.players[0]
	var gap = 72.0
	var width = p.hand.size()*gap + (17 if p.drawn>=0 else 0)
	var start = 800-width/2
	for i in range(p.hand.size()):
		var legal = view.pending.any(func(a): return a.get("index",-1)==i and a.kind in ["discard","bao","ming"])
		var left = start+i*gap+(17 if p.drawn==i else 0)
		var top = 763-(14 if selected==i else 0)
		var texture_size=tile_textures[p.hand[i]].get_size()
		var face_size=texture_size*minf(70.0/texture_size.x,108.0/texture_size.y)
		var shell_y=top+(108-face_size.y)/2+4
		var shell=UI.panel(hand_layer,Rect2(left+(70-face_size.x)/2+1,shell_y,face_size.x-2,face_size.y),Color("17605c"),Color("619589"),5)
		var shell_style=shell.get_theme_stylebox("panel").duplicate()
		shell_style.shadow_color=Color("041b1970");shell_style.shadow_size=8;shell_style.shadow_offset=Vector2(1,5)
		shell.add_theme_stylebox_override("panel",shell_style)
		shell.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var shell_ref=weakref(shell)
		# Keep the hit region fixed while the face rises. Moving the button itself
		# makes a pointer at its lower edge repeatedly enter and exit the tile.
		var button = TextureButton.new(); button.position=Vector2(left,top); button.size=Vector2(70,108)
		button.ignore_texture_size=true
		var face=UI.texture(button,Rect2(0,0,70,108),tile_textures[p.hand[i]])
		button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND if legal else Control.CURSOR_ARROW
		button.modulate=Color.WHITE
		var ready_discard=view.pending.any(func(a): return a.kind in ["bao","ming"] and a.index==i)
		if _field_id()=="transparent" and i<p.get("hand_public",[]).size():
			var visibility="明" if p.hand_public[i] else "暗"
			_hand_tag(Rect2(left,top-23,70,21),("新摸 · " if p.drawn==i else "")+visibility+(" · 听" if ready_discard and p.drawn!=i else ""))
		elif p.drawn==i:
			_hand_tag(Rect2(left,top-23,70,21),"新摸 · 听" if ready_discard else "新摸")
		button.pressed.connect(func(): _activate_tile(i))
		button.set_meta("hand_index",i)
		button.mouse_entered.connect(func():
			if selected!=i and legal:
				face.position.y=-12
				var plate=shell_ref.get_ref()
				if plate:plate.position.y=shell_y-12
			_inspect_tile(p.hand[i],left,top))
		button.mouse_exited.connect(func():
			face.position.y=0
			var plate=shell_ref.get_ref()
			if plate:plate.position.y=shell_y
			_clear(inspect_layer))
		hand_layer.add_child(button)
		if selected==i:
			var line = ColorRect.new(); line.position=Vector2(left+8,top+108); line.size=Vector2(54,3); line.color=UI.TABLE_GOLD; line.mouse_filter=Control.MOUSE_FILTER_IGNORE; hand_layer.add_child(line)
		if ready_discard and p.drawn!=i and _field_id()!="transparent":
			_hand_tag(Rect2(left+43,top-16,23,24),"听")
	if selected>=0 and selected<p.hand.size():
		var waiting=[]
		for a in view.pending:
			if a.kind in ["bao","ming"] and a.index==selected: waiting=a.waits
		detail_label.text = "打出 " + Tiles.title(p.hand[selected]) + (" · 听 " + "、".join(waiting.map(func(t): return Tiles.title(t))) if not waiting.is_empty() else " · 再点一次打出")
	else: detail_label.text=""

func _hand_tag(rect: Rect2, text: String) -> void:
	var tag=UI.label(hand_layer,rect,text,12,UI.TABLE_GOLD)
	tag.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_color_override("font_shadow_color",Color("10251ee6"))
	tag.add_theme_constant_override("shadow_offset_y",1)
	tag.add_theme_constant_override("shadow_offset_x",1)

func _select(index: int) -> void:
	if session.paused or view.decision_seat!=0 or view.phase!="turn": return
	if not view.pending.any(func(a): return a.kind=="discard" and a.index==index): return
	_sound("click")
	if selected==index: _discard_selected()
	else: selected=index; _draw_hand(); _draw_actions()

func _activate_tile(index: int) -> void:
	var now = Time.get_ticks_msec()
	if now < suppress_click_until or session.paused or view.decision_seat != 0 or view.phase != "turn": return
	if not view.pending.any(func(a):return a.kind=="discard" and a.index==index): return
	if now-last_touch_ms > 500:
		selected=index; _discard_selected(); return
	# Touch confirms the visibly selected tile, regardless of time between taps.
	# Activation stays on button release to avoid handling its paired mouse twice.
	_select(index)

func _input(event: InputEvent) -> void:
	if current_screen != "table" or is_instance_valid(modal): return
	if event is InputEventScreenTouch:
		last_touch_ms=Time.get_ticks_msec()
		if event.pressed:
			touch_started=event.position;touch_started_ms=Time.get_ticks_msec();touch_index=-1
			for button in hand_layer.get_children():
				if button is TextureButton and button.get_global_rect().has_point(event.position): touch_index=button.get_meta("hand_index")
			if touch_index<0 and not _touch_over_button(event.position):
				selected=-1;declare_mode=""
				_draw_hand();_draw_actions();_clear(inspect_layer)
		elif touch_index>=0:
			var travel=event.position-touch_started
			if -travel.y>=28 and -travel.y>absf(travel.x)*1.15 and Time.get_ticks_msec()-touch_started_ms<700:
				suppress_click_until=Time.get_ticks_msec()+500
				if not session.paused and view.decision_seat==0 and view.pending.any(func(a):return a.kind=="discard" and a.index==touch_index):
					selected=touch_index;_discard_selected()
			touch_index=-1

func _touch_over_button(point: Vector2) -> bool:
	# Like Lotus's action-row exclusion: touching a control must not remove or
	# replace it before the emulated mouse release activates that same control.
	for layer in [hud,action_layer]:
		for child in layer.get_children():
			if child is BaseButton and child.is_visible_in_tree() and child.get_global_rect().has_point(point): return true
	return false

func _discard_selected() -> void:
	var kind="discard" if declare_mode.is_empty() else declare_mode
	for move in view.pending:
		if move.kind==kind and move.get("index",-1)==selected:
			session.play(move.id,view.revision); return
	_toast("这张牌不能用于报听，请选择标有「听」的牌。")

func _draw_actions() -> void:
	_clear(action_layer)
	if not view.is_empty() and view.phase=="settled":
		UI.table_button(action_layer,Rect2(652,650,296,52),"查看本局结算",_show_result,true)
		return
	if view.is_empty() or view.decision_seat!=0: return
	var actions=[]
	if view.phase=="exchange":
		actions.append({"text":"选择传给下家的 3 张牌","exchange":true,"primary":true})
	elif view.phase in ["draw_choice","gift_choice"]:
		for move in view.pending:
			if move.kind=="field_gift_pick": continue
			actions.append({"text":"天使的施舍 · 三选一" if move.kind=="field_gift" else "正常摸牌","move":move,"primary":move.kind=="field_gift"})
		if view.phase=="gift_choice": actions.append({"text":"天使的施舍 · 继续选牌","field_picker":"field_gift_pick","primary":true})
	elif view.phase=="claim":
		for move in view.pending:
			if move.kind == "chi": continue
			var label={"win":"胡", "peng":"碰", "gang":"杠", "pass":"过", "chi":"吃", "tolerance_gang":"借牌补杠"}.get(move.kind,move.kind)
			if move.kind != "pass": label += " " + Tiles.title(move.tile)
			if move.kind=="chi": label="吃 "+"·".join(move.tiles.map(func(t):return Tiles.title(t)))
			actions.append({"text":label,"move":move,"primary":move.kind!="pass"})
		var chi_options = view.pending.filter(func(a): return a.kind == "chi")
		if not chi_options.is_empty(): actions.append({"text":"吃牌组合" if chi_options.size()>1 else "吃 "+Tiles.title(view.claim_tile),"picker":chi_options,"primary":true})
	elif view.phase=="turn":
		var kongs = view.pending.filter(func(a): return a.kind in ["angang","bugang"])
		for move in view.pending:
			if move.kind in ["angang","bugang"] and kongs.size() > 1: continue
			if move.kind in ["win","angang","bugang","upgrade_ming"]:
				actions.append({"text":{"win":"自摸胡","angang":"暗杠","bugang":"补杠","upgrade_ming":"升级明搂"}[move.kind]+(" "+Tiles.title(move.tile) if move.has("tile") else ""),"move":move,"primary":true})
		if kongs.size() > 1: actions.append({"text":"杠 · 选择牌","picker":kongs,"primary":true})
		if not kongs.is_empty() and (view.players[0].bao or view.players[0].ming) and selected<0:
			for move in view.pending:
				if move.kind=="discard": actions.append({"text":"过杠 · 出牌","move":move,"primary":false})
		for kind in ["bao","ming"]:
			if view.pending.any(func(a):return a.kind==kind): actions.append({"text":("取消" if declare_mode==kind else "")+("报听" if kind=="bao" else "明搂"),"declare":kind,"primary":declare_mode!=kind})
		if selected>=0: actions.append({"text":"打出 "+Tiles.title(view.players[0].hand[selected]),"discard":true,"primary":true})
		if not _field_moves().is_empty():
			var kind=str(_field_moves()[0].kind)
			actions.append({"text":_field_action_name(kind),"field_kind":kind,"primary":true})
			if (view.players[0].bao or view.players[0].ming) and kongs.is_empty() and selected<0:
				for move in view.pending:
					if move.kind=="discard": actions.append({"text":"出牌 · 暂不使用","move":move,"primary":false})
	var widths=[]; var rows: Array=[[]];var row_widths: Array=[0]
	for a in actions:
		var width=clampi(a.text.length()*21+34,91,320)
		if row_widths[-1]>0 and row_widths[-1]+width+10>1180:rows.append([]);row_widths.append(0)
		rows[-1].append(widths.size());widths.append(width);row_widths[-1]+=width+10
	var positions: Array=[];positions.resize(actions.size())
	for row in range(rows.size()):
		var x=800-(row_widths[row]-10)/2.0
		for index in rows[row]:
			positions[index]=Vector2(x,650-(rows.size()-1-row)*62)
			x+=widths[index]+10
	for i in range(actions.size()):
		var a=actions[i]
		UI.table_button(action_layer,Rect2(positions[i],Vector2(widths[i],52)),a.text,func():
			_sound("click")
			if a.has("declare"):
				declare_mode="" if declare_mode==a.declare else a.declare
				if selected>=0 and not declare_mode.is_empty(): _discard_selected()
				else: _draw_actions(); _toast("选择一张标有「听」的牌打出，即可"+("报听" if a.declare=="bao" else "明搂"))
			elif a.has("picker"): _show_move_picker(a.picker)
			elif a.has("exchange"): _show_exchange_picker()
			elif a.has("field_picker"): _show_field_picker(a.field_picker)
			elif a.has("field_kind"): _open_field_action(a.field_kind)
			elif a.has("discard"): _discard_selected()
			else: session.play(a.move.id,view.revision),a.primary)

func _show_move_picker(moves: Array) -> void:
	if moves.size() == 1:
		session.play(moves[0].id,view.revision); return
	var revision = view.revision
	_popup("请选择吃牌组合" if moves[0].kind == "chi" else "请选择要杠的牌", Vector2(850,574 if moves.size()>4 else 380))
	for i in range(moves.size()):
		var move = moves[i]
		var x = 45 + (i%4) * 185
		var y = (i/4) * 174
		var tiles = move.get("tiles",[move.tile])
		for j in range(tiles.size()): UI.texture(modal,Rect2(x+j*44,113+y,42,58),tile_textures[tiles[j]])
		var caption = "吃这组" if move.kind == "chi" else ("暗杠 " if move.kind == "angang" else "补杠 ") + Tiles.title(move.tile)
		UI.button(modal,Rect2(x,195+y,165,53),caption,func(): _close_modal(); session.play(move.id,revision),true)
	UI.label(modal,Rect2(45,487 if moves.size()>4 else 293,760,32),"请选择本次操作。关闭窗口可取消选择。" if _is_lan() else "牌局已暂停，选定后继续。关闭窗口可取消选择。",18,UI.MUTED)

func _visible_remaining(tile: int) -> int:
	var visible = view.players[0].hand.count(tile)
	for p in view.players:
		visible += p.discards.count(tile)
		for meld in p.melds: visible += meld.tiles.count(tile)
		if p.seat != 0 and not p.hand.is_empty(): visible += p.hand.count(tile)
	if view.gang_head == tile: visible += 1
	var totals: Array = view.get("field",{}).get("tile_totals",[])
	return maxi(0,(int(totals[tile]) if tile>=0 and tile<totals.size() else 4)-visible)

func _inspect_tile(tile: int, left: float, top: float) -> void:
	_clear(inspect_layer)
	var neighbors = [tile]
	if tile < 27:
		if tile%9 > 0: neighbors.push_front(tile-1)
		if tile%9 < 8: neighbors.append(tile+1)
	var waits: Array = []
	for move in view.pending:
		if move.kind in ["bao","ming"] and move.tile==tile: waits=move.waits; break
	var height = 235 if not waits.is_empty() else 143
	var panel = UI.table_panel(inspect_layer,Rect2(clampf(left-105,235,1060),maxf(180,top-height-18),300,height),false,16)
	var inspection_style=UI.table_style(false,16);inspection_style.bg_color=Color("112f2cf5")
	panel.add_theme_stylebox_override("panel",inspection_style)
	panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	for i in range(neighbors.size()):
		var item = neighbors[i]
		UI.texture(panel,Rect2(16+i*94,12,45,62),tile_textures[item])
		UI.label(panel,Rect2(12+i*94,76,92,26),Tiles.spoken_title(item),16,UI.TABLE_GOLD if item==tile else UI.TABLE_TEXT)
		UI.label(panel,Rect2(12+i*94,106,92,24),_remaining_prefix()+" %d 张" % _visible_remaining(item),13,UI.TABLE_MUTED)
	if not waits.is_empty():
		UI.label(panel,Rect2(12,139,276,25),"打出后可明搂 · 听口" if view.players[0].get("revealed_hand",false) else "打出后可报听 · 听口",15,UI.TABLE_GOLD)
		for i in range(mini(7,waits.size())): UI.texture(panel,Rect2(12+i*39,173,35,47),tile_textures[waits[i]])

func _scroll_body() -> Control:
	var scroll = ScrollContainer.new(); scroll.position=Vector2(40,100); scroll.size=Vector2(1000,570)
	modal.add_child(scroll)
	var body = Control.new(); body.custom_minimum_size=Vector2(970,570); scroll.add_child(body)
	return body

func _show_waits() -> void:
	if view.is_empty(): return
	if view.players[0].bao or view.players[0].ming:
		waits_expanded=not waits_expanded
		_draw_waits_panel()
		return
	_popup("听牌一览",Vector2(1080,720),true)
	var body = _scroll_body()
	var p = view.players[0]
	var rows: Array = []
	var seen: Array = []
	for move in view.pending:
		if move.kind not in ["bao","ming"] or move.tile in seen: continue
		seen.append(move.tile); rows.append({"discard":move.tile,"waits":move.waits})
	if rows.is_empty():
		var base = p.hand.duplicate()
		if base.size()%3 == 2 and p.drawn >= 0 and p.drawn<base.size(): base.remove_at(p.drawn)
		var waits = Rules.waits(base,p.melds,view.settings.jiang=="luan",_field_id())
		if not waits.is_empty(): rows.append({"discard":-1,"waits":waits})
	var y = 0.0
	for row in rows:
		UI.label(body,Rect2(0,y,180,30),"当前听口" if row.discard < 0 else "打出 "+Tiles.title(row.discard),19,UI.GOLD)
		if row.discard >= 0: UI.texture(body,Rect2(5,y+36,43,58),tile_textures[row.discard])
		for i in range(row.waits.size()):
			var tile = row.waits[i]
			var x = 200 + (i%12)*61
			var ty = y + (i/12)*103
			UI.texture(body,Rect2(x,ty,43,58),tile_textures[tile])
			var base=p.hand.duplicate()
			if row.discard>=0: base.erase(row.discard)
			elif base.size()%3==2 and p.drawn>=0: base.remove_at(p.drawn)
			var score=_wait_score(base,tile)
			UI.label(body,Rect2(x-3,ty+59,62,22),"%d 番" % score.get("multiplier",1),15,UI.GOLD)
			UI.label(body,Rect2(x-3,ty+81,62,22),("≤" if _field_id()=="diamond_finger" else "")+"%d 张" % _visible_remaining(tile),15,UI.MUTED)
		y += maxf(112,ceil(row.waits.size()/12.0)*103+15)
	if rows.is_empty():
		UI.label(body,Rect2(0,25,950,90),"当前没有听口。选择「牌效提示」可查看出牌建议。",23,UI.MUTED)
		y=130
	UI.label(body,Rect2(0,y+12,950,55),"番数按当前手牌自摸预估。余张按自己的手牌、公开牌和杠头计算。\n"+_remaining_note()+" 点击窗口外可收起。",16,UI.MUTED)
	body.custom_minimum_size.y = y + 95

func _wait_score(base: Array, tile: int) -> Dictionary:
	var p=view.players[0]
	var bonus: Array = []
	if _field_id()=="single_wait": bonus.append("听单张")
	if _field_id()=="chosen" and tile in view.get("field",{}).get("chosen_tiles",[]): bonus.append("天选")
	if _field_id()=="chosen_head":
		var head = int(p.get("last_draw_head",-1))
		if head<0: head=int(view.gang_head)
		if tile==head: bonus.append("天选 2")
	return Rules.evaluate(base+[tile],p.melds,{"self_draw":true,"bao":true,"ming":p.ming or p.get("revealed_hand",false),"luan":view.settings.jiang=="luan","field_id":_field_id(),"field_bonus":bonus})

func _locked_waits() -> Array:
	var p=view.players[0]
	var base=p.hand.duplicate()
	if base.size()%3==2 and p.drawn>=0 and p.drawn<base.size():base.remove_at(p.drawn)
	var entries: Array=[]
	for tile in Rules.waits(base,p.melds,view.settings.jiang=="luan",_field_id()):
		entries.append({"tile":tile,"remaining":_visible_remaining(tile),"fan":_wait_score(base,tile).get("multiplier",1)})
	return entries

func _opponent_waits(seat: int) -> Array:
	if view.is_empty() or seat not in [1,2,3] or view.phase=="settled":return []
	var p=view.players[seat]
	# Only the public seat view is used. An unexposed hand, including a player
	# who only declared bao, never gets a wait calculation or a card.
	if not p.ming or p.hand.is_empty():return []
	var base=p.hand.duplicate()
	if base.size()%3==2 and p.drawn>=0 and p.drawn<base.size():base.remove_at(p.drawn)
	var signature=var_to_str([base,p.melds,view.settings.jiang,_field_id()])
	if not opponent_waits_cache.has(seat) or opponent_waits_cache[seat].signature!=signature:
		opponent_waits_cache[seat]={"signature":signature,"tiles":Rules.waits(base,p.melds,view.settings.jiang=="luan",_field_id())}
	var entries: Array=[]
	for tile in opponent_waits_cache[seat].tiles:
		entries.append({"tile":tile,"remaining":_visible_remaining(tile)})
	return entries

func _remove_opponent_waits(seat: int) -> void:
	if opponent_waits_panels.has(seat):
		var panel=opponent_waits_panels[seat]
		if is_instance_valid(panel):panel.hide();panel.queue_free()
		opponent_waits_panels.erase(seat)

func _draw_opponent_waits() -> void:
	if opponent_waits_round!=view.round:
		for seat in opponent_waits_panels.keys():_remove_opponent_waits(seat)
		opponent_waits_cache.clear();opponent_waits_round=view.round
	for seat in range(1,4):
		if not view.players[seat].ming or view.phase=="settled":
			_remove_opponent_waits(seat);opponent_waits_cache.erase(seat);continue
		var entries=_opponent_waits(seat)
		var scroll_position=0
		if opponent_waits_panels.has(seat):
			var previous=opponent_waits_panels[seat]
			if previous.get_meta("entries")==entries:continue
			scroll_position=previous.get_node("WaitsScroll").scroll_vertical
			_remove_opponent_waits(seat)
		var width=142 if seat==2 else 176
		var body_height=mini(108,maxi(54,entries.size()*54))
		var height=body_height+46
		# The top/right cards occupy separate columns outside the physical table.
		# Leave the lower-right lane for the local player's existing wait panel.
		var position={1:Vector2(1396,374-height),2:Vector2(1242,208),3:Vector2(28,488)}[seat]
		var panel=UI.table_panel(hud,Rect2(position,Vector2(width,height)))
		panel.name="OpponentWaits%d"%seat;panel.set_meta("entries",entries)
		opponent_waits_panels[seat]=panel
		var heading=UI.label(panel,Rect2(12,5,width-24,27),"明搂听口",18,UI.TABLE_GOLD)
		heading.mouse_filter=Control.MOUSE_FILTER_PASS
		heading.tooltip_text="%s的公开听口。未见余张按你的手牌、桌面明牌、明搂手牌和杠头计算；也可能在其他人的暗手中。"%view.players[seat].name
		var scroll=ScrollContainer.new();scroll.name="WaitsScroll"
		scroll.position=Vector2(12,36);scroll.size=Vector2(width-24,body_height)
		scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;panel.add_child(scroll)
		var body=Control.new();body.custom_minimum_size=Vector2(width-38,maxi(54,entries.size()*54));scroll.add_child(body)
		for i in range(entries.size()):
			var entry=entries[i];var y=i*54
			var face=UI.texture(body,Rect2(0,y+2,34,48),tile_textures[entry.tile])
			face.set_meta("wait_tile",entry.tile)
			UI.label(body,Rect2(42,y,width-80,26),Tiles.spoken_title(entry.tile),20,UI.TABLE_TEXT)
			UI.label(body,Rect2(42,y+27,width-80,23),_remaining_prefix()+"%d张"%entry.remaining,17,UI.TABLE_MUTED)
			if entry.remaining==0:face.modulate.a=0.45
		if entries.is_empty():UI.label(body,Rect2(0,3,width-38,48),"听口更新中",17,UI.TABLE_MUTED)
		scroll.set_deferred("scroll_vertical",scroll_position)
	public_tiles_button.position.y=opponent_waits_panels[3].get_rect().end.y+10 if opponent_waits_panels.has(3) else 500

func _draw_waits_panel() -> void:
	var scroll_position=0
	if is_instance_valid(waits_panel):
		scroll_position=waits_panel.get_node("WaitsScroll").scroll_vertical
		waits_panel.hide();waits_panel.queue_free();waits_panel=null
	var locked=not view.is_empty() and (view.players[0].bao or view.players[0].ming) and view.phase!="settled"
	if not locked:waits_expanded=true
	waits_button.text="收起听牌" if locked and waits_expanded else "听牌一览"
	if not locked or not waits_expanded:return
	var entries=_locked_waits()
	var body_height=mini(150,maxi(50,entries.size()*50))
	var panel_height=body_height+62
	waits_panel=UI.table_panel(hud,Rect2(1372,704-panel_height,200,panel_height))
	waits_panel.name="LockedWaits"
	UI.label(waits_panel,Rect2(13,5,174,28),"明搂 · 听牌" if view.players[0].ming else "已报听 · 听牌",17,UI.TABLE_GOLD)
	var scroll=ScrollContainer.new();scroll.name="WaitsScroll"
	scroll.position=Vector2(12,38);scroll.size=Vector2(176,body_height)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	waits_panel.add_child(scroll)
	var body=Control.new();body.custom_minimum_size=Vector2(158,maxi(50,entries.size()*50));scroll.add_child(body)
	for i in range(entries.size()):
		var entry=entries[i];var y=i*50
		var face=UI.texture(body,Rect2(0,y+3,31,44),tile_textures[entry.tile])
		face.set_meta("wait_tile",entry.tile)
		UI.label(body,Rect2(41,y,115,25),Tiles.spoken_title(entry.tile),18,UI.TABLE_TEXT)
		UI.label(body,Rect2(41,y+25,67,23),_remaining_prefix()+"%d张"%entry.remaining,16,UI.TABLE_MUTED)
		UI.label(body,Rect2(108,y+25,50,23),"%d番"%entry.fan,16,UI.TABLE_GOLD)
		if entry.remaining==0:face.modulate.a=0.45
	if entries.is_empty():UI.label(body,Rect2(0,0,158,48),"听口更新中",16,UI.TABLE_MUTED)
	var note=UI.label(waits_panel,Rect2(13,body_height+40,174,18),"自摸预估 · 未见余张",13,UI.TABLE_MUTED)
	note.mouse_filter=Control.MOUSE_FILTER_PASS
	note.tooltip_text="番数按当前手牌自摸预估。未见余张也可能在其他玩家的暗手中。"
	scroll.set_deferred("scroll_vertical",scroll_position)

func _show_public_tiles() -> void:
	_popup("桌面明牌",Vector2(1080,720))
	var body = _scroll_body()
	var y = 0
	for p in view.players:
		UI.label(body,Rect2(0,y,950,34),p.name+" · 弃牌",21,UI.GOLD); y += 40
		for i in range(p.discards.size()):
			var tile = p.discards[i]
			UI.texture(body,Rect2((i%18)*52,y+(i/18)*90,43,58),tile_textures[tile])
			UI.label(body,Rect2((i%18)*52,y+(i/18)*90+59,51,23),Tiles.title(tile),12,UI.MUTED)
		y += maxi(1,int(ceil(p.discards.size()/18.0)))*90
		var x = 0
		for meld in p.melds:
			var caption = {"chi":"吃","peng":"碰","gang":"杠","angang":"暗杠","flower":"花"}.get(meld.type,"副露")
			UI.label(body,Rect2(x,y,190,24),caption,14,UI.MUTED)
			for j in range(meld.tiles.size()): UI.texture(body,Rect2(x+j*32,y+28,30,41),tile_textures[42 if meld.tiles[j]<0 else meld.tiles[j]])
			x += meld.tiles.size()*32+18
			if x > 760: x=0; y+=80
		y += 92
		if p.seat!=0 and not p.hand.is_empty():
			UI.label(body,Rect2(0,y,950,30),p.name+" · 公开手牌"+("（暗牌保留牌背）" if p.hand.has(-1) else ""),20,UI.GOLD);y+=38
			y=_field_tile_row(body,p.hand,y)
	body.custom_minimum_size.y = y

func _hint(move: Dictionary) -> void:
	if current_screen!="table" or not is_instance_valid(hand_layer):return
	if move.is_empty(): return
	if move.has("index"):
		selected=move.index; _draw_hand(); _draw_actions()
		var a=move.get("analysis",{})
		_toast("建议打出 "+Tiles.title(move.tile)+(" · 可报听" if move.kind in ["bao","ming"] else " · 兼顾向听与有效进张")+(" · 有效进张 %d"%a.ukeire if a.has("ukeire") else ""))
	else: _toast("建议操作："+{"win":"胡牌","peng":"碰牌","gang":"杠牌","chi":"吃牌","angang":"暗杠","bugang":"补杠","pass":"过"}.get(move.kind,move.kind))

func _popup(title: String, dimensions: Vector2, dismiss_outside: bool = false) -> void:
	_close_modal()
	if not _is_lan(): session.paused=true
	var shade=ColorRect.new(); shade.color=Color("061512b8"); shade.size=Vector2(1600,900); root.add_child(shade)
	shade.name="ModalShade"
	shade.mouse_filter=Control.MOUSE_FILTER_STOP
	if dismiss_outside:
		shade.gui_input.connect(func(event):
			var mouse_release=event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed
			var touch_release=event is InputEventScreenTouch and not event.pressed
			if mouse_release or touch_release:
				shade.accept_event();suppress_click_until=Time.get_ticks_msec()+500
				touch_index=-1;_close_modal())
	modal=UI.panel(shade,Rect2((Vector2(1600,900)-dimensions)/2,dimensions),UI.PAPER,Color("baa57966"),20)
	var rim=modal.get_theme_stylebox("panel").duplicate()
	rim.shadow_color=Color("020c0ab0");rim.shadow_size=28;rim.shadow_offset=Vector2(0,12)
	modal.add_theme_stylebox_override("panel",rim)
	modal.mouse_filter=Control.MOUSE_FILTER_STOP
	UI.label(modal,Rect2(42,25,dimensions.x-110,53),title,32,UI.TEXT,true)
	UI.button(modal,Rect2(dimensions.x-78,29,42,42),"×",_close_modal)

func _close_modal() -> void:
	lan_room_menu = false
	var shade=root.get_node_or_null("ModalShade") if is_instance_valid(root) else null
	if shade: shade.name="ClosingModal";shade.queue_free()
	modal=null
	if current_screen=="table" and not _is_lan(): session.paused=false

func _pause() -> void:
	if is_instance_valid(modal): _close_modal(); return
	if _is_lan(): _show_lan_room_menu(); return
	_popup("暂歇一会",Vector2(640,374))
	UI.label(modal,Rect2(43,106,556,66),"当前牌局已自动保存。\n关闭游戏后，也可以从大厅继续。",22,UI.MUTED)
	UI.button(modal,Rect2(44,212,552,57),"继续对局",_close_modal,true)
	UI.button(modal,Rect2(44,286,552,51),"保存并返回大厅",_show_lobby)

func _field_id() -> String:
	return str(view.get("field",{}).get("id",""))

func _field_moves() -> Array:
	return view.get("pending",[]).filter(func(move): return str(move.kind).begins_with("field_") and move.kind not in ["field_exchange","field_gift_pick"])

func _remaining_note() -> String:
	return "未见余张为数量上限：变白前的牌种保密，未见牌也可能在别人手中。" if _field_id()=="diamond_finger" else "未见的牌也可能在其他玩家手中。"

func _remaining_prefix() -> String:
	return "至多" if _field_id()=="diamond_finger" else "未见"

func _field_action_name(kind: String) -> String:
	return {"field_transform":"大力金刚指 · 变白板","field_rebirth":"新生 · 撤听亮手","field_reclaim":"上架 · 撤回副露","field_peek_wall":"占星Ⅰ · 看四张","field_peek_waits":"占星Ⅱ · 看听口","field_gift":"天使的施舍 · 三选一"}.get(kind,"场地能力")

func _open_field_action(kind: String) -> void:
	if kind=="field_exchange":_show_exchange_picker();return
	if kind in ["field_transform","field_reclaim","field_peek_waits"]:
		_show_field_picker(kind);return
	var moves=_field_moves().filter(func(move):return move.kind==kind)
	if not moves.is_empty():_submit_field(moves[0],int(view.revision))

func _show_field_selector(settings: Dictionary, apply_selection: Callable) -> void:
	_popup("选择场地规则",Vector2(1080,786),true)
	UI.label(modal,Rect2(42,84,996,30),"场地是独立增强选项；指定后每局使用同一种，开局前可改回随机。",18,UI.MUTED)
	for i in range(2):
		var enabled=i==1
		UI.button(modal,Rect2(42+i*502,130,488,52),"每局随机" if enabled else "关闭场地 · 正常玩法",func():
			var next=settings.duplicate(true);next.field_rules=enabled
			if enabled:next.field_selection="random"
			_close_modal();apply_selection.call(FieldRules.normalize(next)),settings.get("field_rules",false)==enabled and (not enabled or FieldRules.selection(settings)=="random"))
	UI.label(modal,Rect2(42,196,996,28),"指定一种场地",20,UI.GOLD,true)
	for i in range(FieldRules.IDS.size()):
		var id=str(FieldRules.IDS[i]);var rule=FieldRules.info(id)
		var chosen=settings.get("field_rules",false) and FieldRules.selection(settings)==id
		var card=UI.button(modal,Rect2(42+(i%4)*251,236+(i/4)*128,237,116),"",func():
			var next=settings.duplicate(true);next.field_rules=true;next.field_selection=id
			_close_modal();apply_selection.call(FieldRules.normalize(next)),chosen)
		card.set_meta("field_selection",id)
		UI.label(card,Rect2(14,10,207,30),str(rule.name),21,Color("342e21") if chosen else UI.GOLD,true)
		var summary=UI.label(card,Rect2(14,47,207,57),str(rule.summary),16,Color("342e21") if chosen else UI.MUTED)
		summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART

func _field_scroll(height: float = 566) -> Control:
	var scroll = ScrollContainer.new(); scroll.position=Vector2(40,112); scroll.size=Vector2(modal.size.x-80,height)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; modal.add_child(scroll)
	var body=Control.new(); body.custom_minimum_size=Vector2(modal.size.x-106,height); scroll.add_child(body)
	return body

func _show_field_catalog() -> void:
	_popup("场地规则",Vector2(1080,784),true)
	UI.label(modal,Rect2(42,81,996,28),"独立增强选项 · 可以每局随机，也可以指定一种；关闭即按正常玩法进行。",18,UI.MUTED)
	var body=_field_scroll(623)
	for i in range(FieldRules.IDS.size()):
		var id=str(FieldRules.IDS[i]); var rule=FieldRules.info(id)
		var x=(i%2)*492; var y=(i/2)*161
		var card=UI.button(body,Rect2(x,y,470,147),"",func(): _show_field_detail(id,false))
		UI.label(card,Rect2(20,12,427,34),str(rule.name),24,UI.GOLD,true)
		var summary=UI.label(card,Rect2(20,48,427,57),str(rule.summary),18,UI.TEXT)
		summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		UI.label(card,Rect2(20,111,427,24),"每人每局一次 · 查看详情 →" if rule.get("active",false) else "整局生效 · 查看详情 →",15,UI.MUTED)
	body.custom_minimum_size.y=ceil(FieldRules.IDS.size()/2.0)*161

func _show_current_field() -> void:
	if not _field_id().is_empty(): _show_field_detail(_field_id(),true)

func _show_field_detail(id: String, current: bool) -> void:
	var rule=FieldRules.info(id)
	_popup(str(rule.name),Vector2(1040,766),true)
	# Opening composition is read-only for the whole round. Keep its list open
	# while a LAN table continues taking turns; a new round still closes it.
	modal.set_meta("field_action",current and id!="no_honors")
	var subtitle="规则说明 · 可指定，也可每局随机"
	if current:subtitle="本局场地 · 每位玩家拥有独立次数" if rule.get("active",false) else "本局场地 · 全体玩家共同遵守"
	UI.label(modal,Rect2(42,81,956,28),subtitle,18,UI.GOLD)
	var body=_field_scroll(598)
	var description_text=str(rule.description)
	if current and id=="angels_gift" and int(view.get("version",3))==2:
		description_text="本局为旧版存档，继续沿用摸牌前选择是否三选一的原流程，保留已经发生的动作。下一局将使用先正常摸一张、再主动追加两张的新流程。每人每局仍限一次；已听不能使用。"
	var description=UI.label(body,Rect2(0,0,934,148),description_text,22,UI.TEXT)
	description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var y=164.0
	if current:
		var p: Dictionary=view.players[0]
		if id=="no_honors": y=_draw_no_honors_additions(body,y)
		if rule.get("active",false):
			UI.label(body,Rect2(0,y,934,35),"你的本局次数：已使用" if p.get("field_used",false) else "你的本局次数：剩余 1 次",22,UI.GOLD,true); y+=49
		var chosen: Array=view.get("field",{}).get("chosen_tiles",[])
		if not chosen.is_empty():
			UI.label(body,Rect2(0,y,934,31),"本局天选牌",21,UI.GOLD); y+=39
			y=_field_tile_row(body,chosen,y)
		if id=="chosen_head":
			UI.label(body,Rect2(0,y,934,31),"当前公开杠头",21,UI.GOLD); y+=39
			y=_field_tile_row(body,[view.gang_head] if view.gang_head>=0 else [],y)
		var private_info: Dictionary=p.get("field_private",{})
		if private_info.has("peek_wall"):
			UI.label(body,Rect2(0,y,934,31),"你的占星记录 · 从左至右为当时的牌头顺序",21,UI.GOLD); y+=39
			y=_field_tile_row(body,private_info.peek_wall,y)
			UI.label(body,Rect2(0,y,934,31),"仅你可见。记录不会随着摸牌更新。",17,UI.MUTED); y+=43
		if private_info.has("peek_target"):
			var target=int(private_info.peek_target)
			var who=str(view.players[target].name) if target>=0 and target<4 else "目标玩家"
			UI.label(body,Rect2(0,y,934,31),"你的占星记录 · "+who+"当时的听口",21,UI.GOLD); y+=39
			if private_info.get("peek_waits",[]).is_empty():
				UI.label(body,Rect2(0,y,934,40),"当时没有听口。",21,UI.TEXT); y+=49
			else: y=_field_tile_row(body,private_info.peek_waits,y)
			UI.label(body,Rect2(0,y,934,51),"仅你可见。若你给此玩家点炮，对方本次胡牌另加一番。",17,UI.MUTED); y+=63
		var kinds: Array=[]
		for move in _field_moves():
			if move.kind not in kinds: kinds.append(move.kind)
		for kind in kinds:
			var label={"field_transform":"选择一张手牌，变为白板","field_rebirth":"撤销报听，亮手继续","field_reclaim":"选择一组副露撤回","field_peek_wall":"查看接下来的四张牌","field_peek_waits":"选择一位玩家占星","field_gift":"使用天使的施舍"}.get(kind,"使用场地能力")
			UI.button(body,Rect2(0,y,934,55),label,func():_open_field_action(kind),true)
			y+=68
		if view.phase=="exchange" and view.decision_seat==0:
			UI.button(body,Rect2(0,y,934,55),"选择要传给下家的三张牌",_show_exchange_picker,true);y+=68
		if view.phase=="gift_choice" and view.decision_seat==0:
			UI.button(body,Rect2(0,y,934,55),"继续选择本次候选牌",func():_show_field_picker("field_gift_pick"),true);y+=68
		if kinds.is_empty() and rule.get("active",false) and not p.get("field_used",false):
			UI.label(body,Rect2(0,y,934,62),"符合使用条件时，牌桌会出现本场地的具名操作按钮。\n你的次数会保留到本局结束，不使用也可以正常出牌。",19,UI.MUTED); y+=80
	else:
		UI.label(body,Rect2(0,y,934,64),"场地叠加在地方玩法上；普通吃牌仍受「允许吃牌」控制。\n所有“一局一次”均按每位玩家分别计算；加一番即本次分数翻倍。",19,UI.MUTED); y+=84
	UI.button(body,Rect2(0,y,934,51),"查看全部场地规则",_show_field_catalog);y+=69
	body.custom_minimum_size.y=maxf(598,y)

func _no_honors_additions() -> Array:
	# Counts are the public opening composition, not the remaining wall or
	# anyone's private hand. They remain stable through draws and saved games.
	if _field_id()!="no_honors":return []
	var totals: Array=view.get("field",{}).get("tile_totals",[])
	if totals.size()<27:return []
	var entries: Array=[]
	for tile in range(27):
		var total=int(totals[tile])
		if total>4:entries.append({"tile":tile,"added":total-4,"total":total})
	return entries

func _draw_no_honors_additions(parent: Node, y: float) -> float:
	var section=Control.new();section.name="NoHonorsAdditions"
	section.position=Vector2(0,y);parent.add_child(section)
	var entries=_no_honors_additions()
	if entries.is_empty():
		UI.label(section,Rect2(0,0,934,50),"本局新增牌明细暂不可用。",22,UI.MUTED)
		section.size=Vector2(934,62)
		return y+78
	var extra=entries.reduce(func(total,entry):return total+entry.added,0)
	UI.label(section,Rect2(0,0,934,37),"本局新增 %d 张 · %d 种牌"%[extra,entries.size()],26,UI.GOLD,true)
	UI.label(section,Rect2(0,44,934,32),"原本每种数牌4张，以下为额外补入的牌；不是剩余牌数。",18,UI.MUTED)
	var top=91.0
	for suit in range(3):
		var group=entries.filter(func(entry):return int(entry.tile)/9==suit)
		if group.is_empty():continue
		var amount=group.reduce(func(total,entry):return total+entry.added,0)
		UI.label(section,Rect2(0,top,934,30),["万牌","筒牌","条牌"][suit]+" · 新增 %d 张"%amount,21,UI.GOLD,true)
		top+=38
		for i in range(group.size()):
			var entry: Dictionary=group[i]
			var card=UI.table_panel(section,Rect2((i%3)*312,top+(i/3)*114,298,102))
			card.set_meta("extra_tile",entry.tile);card.set_meta("extra_count",entry.added);card.set_meta("tile_total",entry.total)
			UI.texture(card,Rect2(12,10,60,82),tile_textures[entry.tile])
			UI.label(card,Rect2(90,4,192,28),Tiles.spoken_title(entry.tile),19,UI.TEXT)
			UI.label(card,Rect2(90,34,192,34),"增加 %d 张"%entry.added,24,UI.GOLD,true)
			UI.label(card,Rect2(90,70,192,26),"本局共 %d 张"%entry.total,18,UI.MUTED)
		top+=ceil(group.size()/3.0)*114+12
	UI.label(section,Rect2(0,top,934,40),"未列出的数牌仍为4张，明细不会随摸牌或出牌减少。",18,UI.MUTED)
	section.size=Vector2(934,top+48)
	return y+section.size.y+20

func _field_tile_row(parent: Node, tiles: Array, y: float) -> float:
	for i in range(tiles.size()):
		var tile=int(tiles[i]); var x=(i%12)*77;var top=y+(i/12)*110
		UI.texture(parent,Rect2(x,top,56,77),tile_textures[tile if tile>=0 else 42])
		UI.label(parent,Rect2(x-4,top+77,76,26),Tiles.spoken_title(tile),15,UI.MUTED)
	return y+ceil(tiles.size()/12.0)*110+6

func _submit_field(move: Dictionary, revision: int) -> void:
	_close_modal()
	if not session.play(str(move.id),revision): _toast("牌局已更新，请重新选择本次操作。"); return

func _field_hand_row(parent: Node, rect: Rect2, tiles: Array, options: Dictionary = {}) -> Control:
	# Every element is a physical tile. Never collapse identical faces into one
	# button: a player's choice is an index until the final server-approved move.
	var row=Control.new();row.position=rect.position;row.size=rect.size
	row.name=str(options.get("name","HandContext"));parent.add_child(row)
	row.set_meta("tile_count",tiles.size())
	var pitch=minf(80,rect.size.x/maxi(1,tiles.size()))
	var card_width=pitch-6
	var chosen: Array=options.get("selected",[])
	var disabled: Array=options.get("disabled",[])
	var pick: Callable=options.get("on_pick",Callable())
	for i in range(tiles.size()):
		var selected_tile=i in chosen
		var card: Control
		var box=Rect2(i*pitch,0,card_width,rect.size.y)
		if pick.is_valid():
			card=UI.button(row,box,"",func():pick.call(i),selected_tile)
			card.disabled=i in disabled
			if card.disabled:card.tooltip_text=str(options.get("disabled_reason","当前不能选择这张牌。"))
		else:card=UI.table_panel(row,box,selected_tile,8)
		card.set_meta("field_hand_index",i);card.set_meta("tile",int(tiles[i]))
		var face_height=minf(98,rect.size.y-29);var face_width=face_height*0.73
		UI.texture(card,Rect2((card_width-face_width)/2,3,face_width,face_height),tile_textures[int(tiles[i]) if int(tiles[i])>=0 else 42])
		var tile_name=str(options.get("unknown_label","暗牌")) if int(tiles[i])<0 else Tiles.title(int(tiles[i]))
		var caption=("✓ " if selected_tile else "")+tile_name
		var name_label=UI.label(card,Rect2(0,rect.size.y-26,card_width,24),caption,15,Color("342e21") if selected_tile and pick.is_valid() else UI.TEXT)
		name_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	return row

func _field_meld_context(parent: Node, top: float) -> void:
	UI.label(parent,Rect2(44,top,1132,26),"当前副露与花牌",17,UI.MUTED)
	var x=44.0
	for meld in view.players[0].melds:
		var width=meld.tiles.size()*34+13
		if x+width>1176:top+=69;x=44
		for j in range(meld.tiles.size()):UI.texture(parent,Rect2(x+j*34,top+30,31,43),tile_textures[int(meld.tiles[j]) if int(meld.tiles[j])>=0 else 42])
		x+=width
	if view.players[0].melds.is_empty():UI.label(parent,Rect2(44,top+28,1132,31),"暂无副露",18,UI.MUTED)

func _show_field_picker(kind: String, reset_selection: bool = false) -> void:
	var moves: Array=view.get("pending",[]).filter(func(move):return move.kind==kind)
	if moves.is_empty(): _toast("当前没有可用的操作。"); return
	if reset_selection:field_picker_selection=-1
	var revision=int(view.revision)
	var p: Dictionary=view.players[0]
	var gift=kind=="field_gift_pick"
	var titles={"field_transform":"大力金刚指 · 选择手牌","field_reclaim":"上架 · 撤回副露","field_peek_waits":"占星Ⅱ · 选择目标","field_gift_pick":"天使的施舍 · 看牌再选"}
	_popup(titles.get(kind,"选择场地能力"),Vector2(1220,814),true)
	modal.set_meta("field_action",true)
	UI.label(modal,Rect2(44,87,1132,34),"本次已发动 · 三张必须选一张；关闭只是收起，可在牌桌继续选择。" if gift else "本局剩余 1 次 · 先选中，再确认；关闭窗口不消耗次数。",20,UI.MUTED)
	UI.label(modal,Rect2(44,130,1132,30),("基础手牌" if gift else "完整手牌")+" · %d 张，同牌逐张显示"%p.hand.size(),21,UI.GOLD,true)
	var chosen_move: Dictionary=moves[field_picker_selection] if field_picker_selection>=0 and field_picker_selection<moves.size() else {}
	var gift_flower=gift and not chosen_move.is_empty() and int(chosen_move.tile)>=34
	var row_options={"name":"CompleteHand"}
	if kind=="field_transform":
		row_options.selected=[int(chosen_move.index)] if not chosen_move.is_empty() else []
		row_options.disabled=[]
		for i in range(p.hand.size()):
			if not moves.any(func(move):return int(move.index)==i):row_options.disabled.append(i)
		row_options.on_pick=func(index):
			for i in range(moves.size()):
				if int(moves[i].index)==index:field_picker_selection=i;break
			_show_field_picker(kind,false)
	_field_hand_row(modal,Rect2(44,168,1132,128),p.hand,row_options)
	_field_meld_context(modal,307)
	if kind=="field_transform":
		UI.label(modal,Rect2(44,404,1132,32),"点击上方要改变的那张牌。白板不能再次变白。" if chosen_move.is_empty() else "将 %s 变为白板，其他手牌保持不变。"%Tiles.spoken_title(int(chosen_move.tile)),21,UI.GOLD)
		if not chosen_move.is_empty():
			UI.texture(modal,Rect2(44,446,67,92),tile_textures[int(chosen_move.tile)])
			UI.label(modal,Rect2(135,469,62,44),"→",32,UI.GOLD)
			UI.texture(modal,Rect2(221,446,67,92),tile_textures[33])
			var preview: Array=p.hand.duplicate();preview[int(chosen_move.index)]=33
			UI.label(modal,Rect2(44,549,1132,28),"变白后的手牌预览",18,UI.MUTED)
			_field_hand_row(modal,Rect2(44,584,1132,105),preview,{"name":"ResultHand","selected":[int(chosen_move.index)]})
	else:
		var label="三张候选牌 · 选择一张，随后确认加入手牌" if gift else ("选择要撤回的一组，确认前可查看收回后的手牌" if kind=="field_reclaim" else "选择已听牌的目标；向这位玩家点炮将额外加一番")
		UI.label(modal,Rect2(44,401,1132,30),label,20,UI.GOLD)
		var pitch=1132.0/maxi(3,moves.size())
		for i in range(moves.size()):
			var move: Dictionary=moves[i];var active=i==field_picker_selection
			var card=UI.button(modal,Rect2(44+i*pitch,443,pitch-14,126),"",func():field_picker_selection=i;_show_field_picker(kind,false),active)
			card.set_meta("field_choice_index",i)
			var ink=Color("342e21") if active else UI.TEXT
			if kind=="field_peek_waits":
				var target=int(move.target)
				UI.portrait(card,Vector2(18,21),67,(target+int(view.get("local_seat",0)))%4)
				UI.label(card,Rect2(102,25,pitch-132,43),str(view.players[target].name),23,ink,true)
				UI.label(card,Rect2(102,72,pitch-132,27),"已选目标" if active else "点击选择",18,ink)
			elif gift:
				UI.texture(card,Rect2(18,12,67,92),tile_textures[int(move.tile)])
				var original=p.get("field_private",{}).get("gift_after_draw",false) and int(move.index)==0
				UI.label(card,Rect2(103,13,pitch-134,32),"本次摸牌" if original else "追加候选 %d"%int(move.index) if p.get("field_private",{}).get("gift_after_draw",false) else "候选 %d"%(int(move.index)+1),19,ink)
				UI.label(card,Rect2(103,52,pitch-134,32),Tiles.spoken_title(int(move.tile)),24,ink,true)
				UI.label(card,Rect2(103,90,pitch-134,26),"已选 · 待确认" if active else "点击选择",16,ink)
			else:
				for j in range(move.tiles.size()):UI.texture(card,Rect2(16+j*52,10,48,66),tile_textures[int(move.tiles[j])])
				UI.label(card,Rect2(16,86,pitch-44,29),"已选 · 将收回这组" if active else "选择这组副露",18,ink)
		if not chosen_move.is_empty() and kind in ["field_reclaim","field_gift_pick"]:
			var preview: Array=p.hand.duplicate()
			if gift:preview.append(-1 if gift_flower else int(chosen_move.tile))
			else:preview.append_array(chosen_move.tiles);preview.sort()
			var preview_text="所选花牌将亮出，再补一张，补牌尚未知；下方牌背表示待补牌。" if gift_flower else "确认后的手牌预览 · %d 张"%preview.size()+(" · 另两张回到牌山" if gift else "")
			UI.label(modal,Rect2(44,586,1132,27),preview_text,18,UI.MUTED)
			_field_hand_row(modal,Rect2(44,620,1132,85),preview,{"name":"ResultHand","selected":[preview.size()-1] if gift else [],"unknown_label":"待补牌"})
		elif gift:UI.label(modal,Rect2(44,607,1132,61),"未选中的两张会按原顺序放回牌山。\n"+("即使选回本次摸牌，也会消耗本局这次机会。" if p.get("field_private",{}).get("gift_after_draw",false) else "本局这次机会已经使用；收起后仍可回来完成选择。"),20,UI.MUTED)
	var caption={"field_transform":"确认变白板","field_reclaim":"确认撤回","field_peek_waits":"查看其听口","field_gift_pick":"确认加入手牌"}.get(kind,"确认")
	if gift_flower:caption="确认补花并补牌"
	var confirm=UI.button(modal,Rect2(44,737,1132,53),caption,func():
		if not chosen_move.is_empty():_submit_field(chosen_move,revision),true)
	confirm.disabled=chosen_move.is_empty()

func _show_exchange_picker(reset_selection: bool = false) -> void:
	if view.get("phase","")!="exchange" or view.decision_seat!=0:return
	if reset_selection: field_exchange_selection.clear()
	var revision=int(view.revision)
	_popup("换牌 · 传给下家",Vector2(1220,790))
	modal.set_meta("field_action",true)
	var hand: Array=view.players[0].hand
	var required=mini(3,hand.filter(func(tile):return tile>=0 and tile<27).size())
	var blocked: Array=[]
	if required==3:
		for i in range(hand.size()):
			if int(hand[i])>=27:blocked.append(i)
	UI.label(modal,Rect2(44,91,1132,56),"完整展示每一张牌，同牌可分别选择。须选 %d 张万、筒或条；只有数牌不足三张时，才可用字牌补足。"%required,20,UI.MUTED).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	UI.label(modal,Rect2(44,151,1132,31),"完整手牌 · %d 张"%hand.size(),21,UI.GOLD,true)
	_field_hand_row(modal,Rect2(44,194,1132,128),hand,{"name":"CompleteHand","selected":field_exchange_selection,"disabled":blocked,"disabled_reason":"手中数牌足够三张，换牌时须选择万、筒或条；这张字牌保留在手中。","on_pick":func(index):
		if index in blocked:return
		if index in field_exchange_selection:field_exchange_selection.erase(index)
		elif field_exchange_selection.size()<3:field_exchange_selection.append(index)
		else:_toast("已经选了三张；先取消一张，再换选其他牌。")
		_show_exchange_picker(false)})
	var selected_tiles: Array=field_exchange_selection.map(func(index):return hand[index])
	UI.label(modal,Rect2(44,345,1132,31),"传给 %s · 已选 %d / 3"%[view.players[1].name,selected_tiles.size()],21,UI.GOLD,true)
	_field_hand_row(modal,Rect2(44,390,360,108),selected_tiles,{"name":"SelectedExchange"})
	if selected_tiles.is_empty():UI.label(modal,Rect2(44,401,1132,68),"点击上方三张手牌加入这里；再次点击已选牌可取消。",20,UI.MUTED)
	var kept: Array=[]
	for i in range(hand.size()):
		if i not in field_exchange_selection:kept.append(hand[i])
	UI.label(modal,Rect2(44,521,1132,30),"留在手中的牌 · %d 张"%kept.size(),20,UI.MUTED)
	_field_hand_row(modal,Rect2(44,562,1132,111),kept,{"name":"KeptExchange"})
	var chosen_tiles: Array=field_exchange_selection.map(func(index):return hand[index]);chosen_tiles.sort()
	var choices: Array=view.pending.filter(func(move):
		if move.kind!="field_exchange":return false
		var proposed: Array=move.get("tiles",[]).duplicate();proposed.sort()
		return proposed==chosen_tiles)
	var confirm=UI.button(modal,Rect2(44,711,1132,56),"确认传给 "+str(view.players[1].name),func():
		if not choices.is_empty():_submit_field(choices[0],revision),true)
	confirm.disabled=choices.is_empty()

func _show_rules() -> void:
	_popup("本桌玩法",Vector2(934,756))
	var text=RichTextLabel.new(); text.position=Vector2(42,100); text.size=Vector2(850,532)
	text.add_theme_font_override("normal_font",UI.font()); text.add_theme_font_size_override("normal_font_size",21)
	text.add_theme_color_override("default_color",UI.TEXT); text.bbcode_enabled=true
	text.text="[color=#dec18b]开局与行牌[/color]\n144 张牌，含春夏秋冬、梅兰竹菊八花。庄家 14 张，闲家 13 张；起手补花。每局轮庄，初始 2000 分，底分 10。\n\n[color=#dec18b]报听、明搂[/color]\n普通胡牌必须先报听或明搂。选择能听牌的弃牌，同时完成声明。报听后锁手，非胡的新摸牌会自动打出，不能吃碰；可胡或可合法杠牌时保留选择。摸到第四张且杠前后听口不变时，可暗杠或补杠。明搂亮开手牌，只能自摸，赢输均按规则翻倍；报听后可在自己回合升级明搂。\n\n[color=#dec18b]胡牌与响应[/color]\n二五八将：普通牌型须以数牌 2、5、8 作将；乱将允许任意将。十三幺、十三不靠、风一色、将一色及八花有原规则豁免。优先胡，再碰杠，最后下家吃。单响截胡，前家放弃后下一位仍可胡。过胡、过碰限制持续到本人再次摸到普通牌。\n\n[color=#dec18b]补花与杠头[/color]\n杠头公开。正常摸牌从牌头拿，补花取杠头前一张；开杠才摸走杠头，再翻下一张。只剩杠头时不能普通摸牌。八花齐集立即花胡。\n\n[color=#dec18b]计分[/color]\n基本单位＝花分 × 番型倍数 × 10。基础 1 花；每张花牌 1 花；字刻 1 花；数牌明杠 1、暗杠 2 花；字牌明杠 2、暗杠 3 花。杠分并入胡牌结算，不即时收取。\n自摸由其余三家各付一份；普通点炮由出牌者付一份；抢杠胡由被抢者付三份。明搂的输家付款另翻倍。\n\n[color=#dec18b]番型[/color]\n平胡 1；七对／碰碰胡 2；豪华七对 4；风一色／将一色 6；双豪华七对 8；十三不靠 12；十三幺／超豪华七对 16。附加：清一色 4／混一色 2、一条龙 4、大吊车 2、门清 2（指定特殊牌型除外）、持花 2、海底 2、明搂 2。天胡固定 30、地胡固定 25，不加花分。\n\n以上按原项目山东玩法迁移；完整细节以随项目保存的规则基线与牌例测试为准。"
	modal.add_child(text)
	UI.button(modal,Rect2(42,659,850,52),"查看本局场地 · "+str(FieldRules.info(_field_id()).name) if current_screen=="table" and not _field_id().is_empty() else "场地规则 · 可选增强玩法",_show_current_field if current_screen=="table" and not _field_id().is_empty() else _show_field_catalog)

func _show_settings() -> void:
	var desktop = desktop_window.supported
	_popup("桌边设置",Vector2(680,554 if desktop else 454))
	display_button = null
	UI.label(modal,Rect2(44,108,230,40),"声音",22)
	UI.button(modal,Rect2(307,106,325,49),"已静音" if muted else "已开启",func(): muted=not muted; voice.stop_all(); _save_preferences(); _show_settings())
	UI.label(modal,Rect2(44,183,230,40),"画质",22)
	UI.button(modal,Rect2(307,181,325,49),"省电 · 关闭阴影" if low_quality else "精致 · 柔和阴影",func(): low_quality=not low_quality; table.quality(low_quality); desktop_window.set_frame_limit(30 if low_quality and current_screen=="table" else 60); _save_preferences(); _show_settings())
	UI.label(modal,Rect2(44,258,230,40),"电脑行牌速度",22)
	var pace_button = UI.button(modal,Rect2(307,256,325,49),("舒缓 · 约 2.4 秒" if session.speed < 1 else ("标准 · 约 1.8 秒" if session.speed == 1 else "利落 · 约 1.2 秒")),func(): session.speed=1.0 if session.speed<1 else (1.5 if session.speed==1 else 0.75); _save_preferences(); _show_settings())
	if _is_lan() and not (session as LanSession).is_host:
		pace_button.text = "由房主控制"; pace_button.disabled = true
	if desktop:
		UI.label(modal,Rect2(44,333,230,40),"显示模式",22)
		display_button = UI.button(modal,Rect2(307,331,325,49),_display_text(),func(): desktop_window.set_fullscreen(not desktop_window.is_fullscreen()))
		UI.label(modal,Rect2(307,388,325,29),"F11 / Alt + Enter  切换",17,UI.MUTED)
	UI.label(modal,Rect2(44,440 if desktop else 340,585,69),"对局规则在开局时固定。\n局域网玩法由房主创建房间时设置。" if _is_lan() else "对局规则在开局时固定。\n新一局的将牌、吃牌与 AI 设置请返回大厅选择。",18,UI.MUTED)

func _display_text() -> String:
	return "无边框全屏" if desktop_window.is_fullscreen() else "窗口模式"

func _display_changed(_enabled: bool) -> void:
	if is_instance_valid(display_button): display_button.text = _display_text()
	_save_preferences()

func _about() -> void:
	_popup("关于青玉台",Vector2(760,453))
	UI.label(modal,Rect2(43,98,671,235),"山东麻将 · 青玉台  "+str(ProjectSettings.get_setting("application/config/version","0.6.0"))+"\n山东麻将单机 / 附近同桌 · 独立单机斗地主\n\n麻将规则、牌面和语音参考／沿用莲花麻将（MIT）。\n花牌 CC BY-SA 4.0；字体 Noto（SIL OFL 1.1）。\n扑克牌面 SVG-cards（LGPL-2.1），原始SVG随包。\n男女声报牌：Kokoro / sherpa-onnx（Apache-2.0）。",20,UI.MUTED)
	UI.button(modal,Rect2(43,350,324,55),"查看开源许可",_licenses)
	UI.button(modal,Rect2(381,350,333,55),"打开存档文件夹",func(): OS.shell_open(ProjectSettings.globalize_path("user://")))

func _licenses() -> void:
	_popup("开源许可",Vector2(950,756))
	var text=RichTextLabel.new();text.position=Vector2(42,100);text.size=Vector2(866,605)
	text.add_theme_font_override("normal_font",UI.font());text.add_theme_font_size_override("normal_font_size",17)
	text.add_theme_color_override("default_color",UI.TEXT)
	text.text=FileAccess.get_file_as_string("res://assets/licenses.txt");modal.add_child(text)

func _show_result() -> void:
	var r=view.result
	_popup("荒庄流局" if r.draw else view.players[r.winner].name+" · "+r.pattern,Vector2(986,733))
	UI.label(modal,Rect2(45,91,885,35),"本局无人胡牌，积分不变。" if r.draw else "%s   ·   %d 花 × %d 倍 × 10 底分"%[{"self-draw":"自摸","discard":"点炮胡","robbed-kong":"抢杠胡","tianhu":"天胡","dihu":"地胡"}.get(r.win_type,r.win_type),r.hua,r.multiplier],21,UI.GOLD)
	if not r.draw:
		var hand=r.win_hand
		var x=45
		for tile in hand:
			UI.texture(modal,Rect2(x,147,41,64),tile_textures[tile]);x+=43
		x+=17
		for meld in Rules.active(view.players[r.winner].melds):
			for tile in meld.tiles:
				UI.texture(modal,Rect2(x,155,35,54),tile_textures[tile]);x+=37
			x+=9
		var parts=[]
		for p in r.patterns: parts.append(p.name+" ×"+str(p.multiplier))
		var summary=UI.label(modal,Rect2(45,227,890,64),"  ·  ".join(parts),18,UI.MUTED); summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		var flowers=[]
		for item in r.hua_details:flowers.append(item.name+" "+str(item.points))
		UI.label(modal,Rect2(45,270,892,27),"花分："+" + ".join(flowers),15,UI.MUTED)
	else:UI.label(modal,Rect2(45,158,890,91),"牌有尽时，来日方长。",38,UI.TEXT,true)
	for i in range(4):
		var y=309+i*58
		UI.panel(modal,Rect2(43,y,900,51),Color("335047") if i==r.winner else Color("1c3933"),Color.TRANSPARENT,10)
		UI.label(modal,Rect2(65,y+8,280,36),view.players[i].name+("  ·  本家" if i==0 else ""),21)
		UI.label(modal,Rect2(519,y+8,180,36),str(view.players[i].score)+" 分",21,UI.MUTED)
		UI.label(modal,Rect2(778,y+6,148,39),("+" if r.deltas[i]>0 else "")+str(r.deltas[i]),25,UI.GOLD if r.deltas[i]>0 else UI.TEXT)
	var ended=view.settings.rounds>0 and view.round>=view.settings.rounds
	if _is_lan():
		UI.label(modal,Rect2(45,561,882,35),"每局轮庄 · 下一局由%s坐庄"%view.players[(view.dealer+1)%4].name,19,UI.MUTED)
		UI.button(modal,Rect2(44,630,239,57),"查看房间",_show_lan_room_menu)
		var host = (session as LanSession).is_host
		var replay = UI.button(modal,Rect2(301,630,269,57),"导出本局牌谱",func():
			var path = session.export_replay()
			_toast("牌谱已保存到本地 replays 文件夹" if not path.is_empty() else "导出失败"))
		replay.disabled = not host
		replay.tooltip_text = "完整牌谱由房主导出" if not host else ""
		var next = UI.button(modal,Rect2(588,630,353,57),"继续下一局 →" if host else "等待房主开始下一局",func():
			_close_modal(); session.next_round(),host)
		next.disabled = not host
		return
	UI.label(modal,Rect2(45,561,882,35),"本场结束。回大厅开启新一场。" if ended else "每局轮庄 · 下一局由%s坐庄"%view.players[(view.dealer+1)%4].name,19,UI.MUTED)
	UI.button(modal,Rect2(44,630,239,57),"返回大厅",_show_lobby)
	UI.button(modal,Rect2(301,630,269,57),"导出本局牌谱",func():
		var path=session.export_replay()
		_toast("牌谱已保存到本地 replays 文件夹" if not path.is_empty() else "导出失败"))
	UI.button(modal,Rect2(588,630,353,57),"返回大厅 · 本场结束" if ended else "继续下一局 →",func():
		if ended:_show_lobby()
		else:_close_modal(); session.next_round(),true)

func _toast(message: String) -> void:
	if not is_instance_valid(toast_label):
		toast_label=UI.label(root,Rect2(270,100,1060,44),"",19,UI.TABLE_TEXT if current_screen=="table" else UI.TEXT)
		toast_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		toast_label.add_theme_stylebox_override("normal",UI.style(Color("112f2cf5"),UI.TABLE_LINE,12) if current_screen=="table" else UI.style(UI.PAPER,Color("80b4ac"),12))
	toast_label.text=message; toast_label.visible=true; toast_time=4.2
	var width=clampf(UI.font().get_string_size(message,HORIZONTAL_ALIGNMENT_LEFT,-1,19).x+48,360,1060)
	toast_label.size.x=width;toast_label.position.x=(1600-width)/2
	root.move_child(toast_label,-1)

func _process(delta: float) -> void:
	if toast_time>0:
		toast_time-=delta
		if toast_time<=0 and is_instance_valid(toast_label):toast_label.visible=false

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:return
	if current_screen=="doudizhu":
		if event.keycode==KEY_ESCAPE and is_instance_valid(doudizhu): doudizhu.pause_menu()
		return
	if event.keycode==KEY_ESCAPE:
		if is_instance_valid(modal):_close_modal()
		elif is_instance_valid(inspect_layer) and inspect_layer.get_child_count()>0: _clear(inspect_layer)
		elif current_screen=="table":_pause()
		elif current_screen=="lan":
			if _is_lan(): _confirm_leave_lan()
			else: _show_lobby()
	elif current_screen=="table" and not is_instance_valid(modal):
		if event.keycode==KEY_H:session.request_hint()
		if event.keycode in [KEY_SPACE,KEY_ENTER] and selected>=0:_discard_selected()

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		if _is_lan(): (session as LanSession).leave_room()
		get_tree().quit()
	if what==NOTIFICATION_APPLICATION_PAUSED or what==NOTIFICATION_WM_GO_BACK_REQUEST:
		if current_screen=="doudizhu" and is_instance_valid(doudizhu):
			if what==NOTIFICATION_APPLICATION_PAUSED: doudizhu.pause_on_background()
			else: doudizhu.pause_menu()
		elif current_screen=="table" and not is_instance_valid(modal):_pause()
		elif what==NOTIFICATION_WM_GO_BACK_REQUEST and current_screen=="lan":
			if _is_lan(): _confirm_leave_lan()
			else: _show_lobby()

func _save_preferences() -> void:
	if qa_mode:return
	var file=FileAccess.open(preferences_path,FileAccess.WRITE)
	if file:file.store_string(JSON.stringify({"config":config,"muted":muted,"low_quality":low_quality,"speed":session.speed,"pace_version":2,"fullscreen":desktop_window.is_fullscreen(),"doudizhu_voice":doudizhu_voice}))

func _load_preferences() -> void:
	if qa_mode:return
	if not FileAccess.file_exists(preferences_path):return
	var prefs=JSON.parse_string(FileAccess.get_file_as_string(preferences_path))
	if not prefs is Dictionary:return
	config.merge(prefs.get("config",{}),true); muted=prefs.get("muted",false);low_quality=prefs.get("low_quality",false)
	doudizhu_voice = "female" if prefs.get("doudizhu_voice", "male") == "female" else "male"
	session.speed=clampf(prefs.get("speed",1.0),0.75,1.5) if prefs.get("pace_version",0)==2 else 1.0;table.quality(low_quality)
	desktop_window.set_fullscreen(prefs.get("fullscreen",false) == true)
