extends Node
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
var config = {"jiang": "258", "chi": true, "ai": "efficiency", "rounds": 4}
var muted = false
var low_quality = false
var players_ui: Array = []
var status_label: Label
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
var inspect_layer: Control
var last_touch_ms = -1000
var touch_started = Vector2.ZERO
var touch_started_ms = 0
var touch_index = -1
var last_tap_index = -1
var last_tap_ms = -1000
var suppress_click_until = -1

func _ready() -> void:
	Engine.max_fps=60
	for t in range(43): tile_textures.append(load(Tiles.texture_path(t)))
	for name in ["click", "tile", "deal", "notify", "win"]: sounds[name] = load("res://assets/audio/" + name + ".wav")
	sfx = AudioStreamPlayer.new(); add_child(sfx)
	voice = TileVoice.new(); add_child(voice)
	session = LocalSession.new(); add_child(session)
	session.changed.connect(_changed); session.hint_ready.connect(_hint); session.notice.connect(_toast)
	table = Table3D.new(); add_child(table)
	table.tile_inspected.connect(func(tile,position):
		if current_screen=="table" and not is_instance_valid(modal): _inspect_tile(tile,position.x,position.y))
	canvas = CanvasLayer.new(); add_child(canvas)
	root = Control.new(); root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_IGNORE; canvas.add_child(root)
	_load_preferences()
	if "--qa" in OS.get_cmdline_user_args():session.storage_root="user://qa/";muted=true
	_show_lobby()
	get_tree().auto_accept_quit = false
	var args = OS.get_cmdline_user_args()
	if "--demo" in args:
		_start_game(false)
	if "--autoplay" in args: session.autopilot = true; session.speed = 8
	if "--capture" in args:
		var idx = args.find("--capture")
		if idx + 1 < args.size(): _capture(args[idx + 1])

func _capture(path: String) -> void:
	await get_tree().create_timer(3).timeout
	await RenderingServer.frame_post_draw
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
	current_screen = "lobby"; session.paused = true
	if is_instance_valid(voice): voice.stop_all()
	table.visible=false;Engine.max_fps=30
	_clear(root); modal = null; hud = null; toast_label = null
	lobby = _layer()
	var gradient=Gradient.new();gradient.set_color(0,Color("f3f6f2"));gradient.set_color(1,Color("cde5e1"))
	var backdrop=GradientTexture2D.new();backdrop.gradient=gradient;backdrop.width=1600;backdrop.height=900
	backdrop.fill_from=Vector2.ZERO;backdrop.fill_to=Vector2(1,0.7)
	var bg = UI.texture(lobby,Rect2(0,0,1600,900),backdrop);bg.stretch_mode = TextureRect.STRETCH_SCALE
	# Quiet, oversized arcs frame the tile still life without competing with it.
	for ring in range(3):
		var extent=640+ring*100
		var orbit=UI.panel(lobby,Rect2(1200-extent/2,428-extent/2,extent,extent),Color.TRANSPARENT,Color("ffffff45"),extent/2)
		orbit.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_brand(lobby,Vector2(70,43),true)
	UI.button(lobby,Rect2(1340,48,94,46),"玩法",_show_rules)
	UI.button(lobby,Rect2(1446,48,94,46),"设置",_show_settings)
	UI.label(lobby,Rect2(104,185,650,30),"青玉台  /  四席之间，自在相见",17,UI.ACCENT)
	UI.label(lobby,Rect2(98,244,740,106),"好牌，慢慢来。",70,UI.TEXT)
	UI.label(lobby,Rect2(105,370,660,65),"熟悉的山东玩法，清爽的一桌麻将。\n与三位电脑牌友落座，随时开始，随时续玩。",21,UI.MUTED)
	# Original tile artwork, arranged as a compact still life.
	for item in [[1,990,285,-0.18],[13,1163,238,0.06],[31,1322,319,0.21]]:
		var shadow = UI.panel(lobby,Rect2(item[1]+4,item[2]+12,164,235),Color("658f8633"),Color.TRANSPARENT,15)
		shadow.pivot_offset=Vector2(82,118);shadow.rotation = item[3]
		var tile = UI.texture(lobby,Rect2(item[1],item[2],164,235),tile_textures[item[0]])
		tile.pivot_offset = Vector2(82,118); tile.rotation = item[3]
	UI.label(lobby,Rect2(1084,609,400,32),"一万一筒，一局一会",22,UI.ACCENT)
	UI.label(lobby,Rect2(1065,654,450,28),"离线畅玩    ·    每一步，自动保存",15,UI.MUTED)
	var options = UI.panel(lobby,Rect2(104,491,720,229),Color("ffffffad"),Color("ffffffc0"),20)
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
	UI.label(options,Rect2(25,180,665,28),"底分 10  ·  起始 2000 分  ·  144 张含花牌  ·  每局轮庄",16,UI.MUTED)
	UI.button(lobby,Rect2(105,754,279,66),"入 座 开 局   →",func(): _start_game(true),true)
	if session.has_save(): UI.button(lobby,Rect2(402,754,221,66),"继续上次牌局",_resume)
	UI.label(lobby,Rect2(105,853,1000,24),"山东麻将 · 青玉台",13,UI.MUTED)
	UI.button(lobby,Rect2(1410,833,120,42),"关于",_about)

func _brand(parent: Node,position: Vector2,large: bool=false) -> void:
	var mark=UI.panel(parent,Rect2(position,Vector2(40,48)),Color("fcfdf9"),Color("bcd8d2"),9)
	var edge=UI.panel(mark,Rect2(1,39,38,8),UI.ACCENT,Color.TRANSPARENT,5);edge.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var symbol=UI.label(mark,Rect2(0,0,40,39),"中",26,UI.CORAL);symbol.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	UI.label(parent,Rect2(position+Vector2(54,-1),Vector2(225,30)),"山东麻将",24 if large else 21,UI.TEXT)
	UI.label(parent,Rect2(position+Vector2(56,31),Vector2(235,19)),"青玉台  /  QINGYU",11,UI.MUTED)

func _toggle(parent: Node, rect: Rect2, text: String, on: bool, callback: Callable) -> void:
	var b = UI.button(parent,rect,text,callback,on)
	b.add_theme_font_size_override("font_size",16)

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
	table.visible=true;Engine.max_fps=30 if low_quality else 60
	hud = _layer(); selected = -1; declare_mode = ""; last_revision = -1
	_brand(hud,Vector2(27,21))
	var badge = UI.panel(hud,Rect2(625,18,350,40),UI.SURFACE,Color("ffffff99"),20)
	round_text = UI.label(badge,Rect2(0,0,350,40),"",16,UI.TEXT); round_text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	UI.button(hud,Rect2(1258,23,82,42),"玩法",_show_rules)
	UI.button(hud,Rect2(1350,23,82,42),"设置",_show_settings)
	UI.button(hud,Rect2(1442,23,125,42),"暂停  II",_pause)
	var gang = UI.panel(hud,Rect2(25,104,170,98),UI.SURFACE,UI.LINE,16)
	head_tile = UI.texture(gang,Rect2(10,12,51,73),tile_textures[42])
	UI.label(gang,Rect2(73,8,90,21),"杠头",12,UI.ACCENT)
	head_name=UI.label(gang,Rect2(73,30,93,31),"",21,UI.TEXT)
	UI.label(gang,Rect2(73,65,90,22),"开杠即摸",12,UI.MUTED)
	players_ui = []
	for seat in range(4):
		var pos = [Vector2(28,739),Vector2(1406,378),Vector2(1210,103),Vector2(28,378)][seat]
		var panel = UI.panel(hud,Rect2(pos,Vector2(166,117)),UI.SURFACE,UI.LINE,16)
		var seal = UI.panel(panel,Rect2(13,13,42,42),[Color("d4eae2"),Color("d5e9ee"),Color("e5e4f0"),Color("f1dfd1")][seat],Color("ffffff80"),21)
		var ch = UI.label(seal,Rect2(0,0,42,42),["我","松","澜","秋"][seat],21,UI.TEXT); ch.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var name_label = UI.label(panel,Rect2(66,10,80,27),["我","听松","观澜","知秋"][seat],18)
		var state_label = UI.label(panel,Rect2(66,37,88,21),"",11,UI.MUTED)
		var score = UI.label(panel,Rect2(16,64,133,32),"2000",25,UI.TEXT)
		var info = UI.label(panel,Rect2(16,94,143,19),"",11,UI.MUTED)
		var turn_dot=UI.panel(panel,Rect2(145,15,7,7),UI.ACCENT,Color.TRANSPARENT,4)
		turn_dot.mouse_filter=Control.MOUSE_FILTER_IGNORE
		players_ui.append({"panel":panel,"state":state_label,"score":score,"info":info,"name":name_label,"turn":turn_dot})
		if seat==2:
			panel.size=Vector2(183,77)
			name_label.position=Vector2(66,7)
			state_label.position=Vector2(66,34)
			score.position=Vector2(112,42);score.size=Vector2(64,25);score.add_theme_font_size_override("font_size",18)
			turn_dot.position=Vector2(163,16)
			info.visible=false
	var recent = UI.panel(hud,Rect2(25,221,170,140),UI.SURFACE,UI.LINE,16)
	recent_panel=recent
	last_actor_label = UI.label(recent,Rect2(8,7,154,23),"等待出牌",13,UI.MUTED); last_actor_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	last_tile = UI.texture(recent,Rect2(59,33,52,72),tile_textures[42])
	last_tile_label = UI.label(recent,Rect2(8,109,154,24),"",16,UI.ACCENT); last_tile_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var tray = UI.panel(hud,Rect2(220,784,1160,106),Color("f5faf6b8"),Color("ffffff8c"),22)
	tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label = UI.label(hud,Rect2(32,563,158,103),"",15,UI.MUTED)
	status_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	detail_label = UI.label(hud,Rect2(312,868,978,22),"",12,UI.MUTED); detail_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	hint_button=UI.button(hud,Rect2(1406,739,166,50),"牌效提示",func(): session.request_hint(); _toast("正在分析当前手牌…"))
	auto_button=UI.button(hud,Rect2(1406,801,166,50),"交给 AI",func(): session.autopilot=not session.autopilot; auto_button.text="收回操作" if session.autopilot else "交给 AI")
	UI.label(hud,Rect2(29,871,188,19),"离线对局 · 已自动保存",11,UI.MUTED)
	UI.label(hud,Rect2(1406,871,180,19),"Esc 暂停  /  H 提示",10,UI.MUTED)
	hand_layer = _layer(); action_layer = _layer(); inspect_layer = _layer()
	waits_button = UI.button(hud,Rect2(1406,677,166,50),"听牌一览",_show_waits)
	UI.button(hud,Rect2(28,514,166,43),"查看桌面牌",_show_public_tiles).add_theme_font_size_override("font_size",16)

func _changed(new_view: Dictionary) -> void:
	view = new_view
	if current_screen != "table": return
	if last_revision != view.revision:
		selected = -1; declare_mode = ""
		last_tap_index=-1; _clear(inspect_layer)
		if last_revision >= 0:
			_sound("win" if view.phase=="settled" and not view.result.draw else ("notify" if view.event.kind in ["bao","ming","gang","angang","bugang","peng","chi"] else "tile"))
			_show_cue(view.event)
			session.hold_presentation(voice.announce(view,muted))
	last_revision = view.revision
	var target = {"tile":view.claim_tile,"seat":view.claim_from} if view.phase == "claim" else view.last_discard
	recent_panel.visible=not target.is_empty() and target.tile>=0
	if not target.is_empty() and target.tile >= 0:
		last_tile.texture = tile_textures[target.tile]
		last_actor_label.text = view.players[target.seat].name + (" · 待应牌" if view.phase == "claim" else " · 刚打出")
		last_tile_label.text = Tiles.spoken_title(target.tile)
	else:
		last_actor_label.text = "等待出牌"; last_tile_label.text = ""; last_tile.texture = tile_textures[42]
	table.update_view(view)
	var field = ["东","南","西","北"][((int(view.round)-1)/4)%4]
	round_text.text = "%s风 · 第 %d 局  /  %s" % [field,view.round,"二五八将" if view.settings.jiang=="258" else "乱将"]
	head_tile.texture = tile_textures[view.gang_head] if view.gang_head>=0 else tile_textures[42]
	head_name.text=Tiles.spoken_title(view.gang_head) if view.gang_head>=0 else "—"
	for seat in range(4):
		var p = view.players[seat]; var info = players_ui[seat]
		info.score.text = str(p.score)
		info.state.text = "庄家" if seat==view.dealer else ("本家" if seat==0 else "电脑牌友")
		info.info.text = "明搂 · 亮手" if p.ming else ("已报听 · 锁手" if p.bao else "花牌 %d 张" % Rules.flower_count(p.melds))
		var active=seat==view.decision_seat and view.phase!="settled"
		info.turn.visible=active
		info.panel.add_theme_stylebox_override("panel",UI.style(Color("eefaf6f7") if active else UI.SURFACE,Color("69aca5") if active else UI.LINE,16,2 if active else 1))
	hint_button.disabled = view.decision_seat != 0 or view.phase=="settled"
	auto_button.disabled = view.phase=="settled"
	waits_button.disabled = view.phase == "settled"
	if view.phase=="settled": status_label.text="本局结束 · 牌已亮开"
	elif view.decision_seat==0: status_label.text="轮到你了 · 悬停看牌，点击打出" if view.phase=="turn" else "%s打出【%s】 · 请选择操作" % [view.players[view.claim_from].name,Tiles.spoken_title(view.claim_tile)]
	else: status_label.text="%s正在%s…" % [view.players[view.decision_seat].name,"思考" if view.phase=="turn" else "应牌"]
	_draw_hand(); _draw_actions()
	if view.decision_seat == 0 and view.phase == "turn" and (view.players[0].bao or view.players[0].ming):
		status_label.text = "已报听 · 可胡、可杠时请先选择；否则打出新摸牌"
	if view.decision_seat == 0 and view.pending.any(func(a):return a.kind in ["win","gang","peng","chi","angang","bugang"]): _sound("notify")
	if view.phase=="settled": _celebrate()

func _show_cue(event: Dictionary) -> void:
	var names={"bao":"报 听","ming":"明 搂","upgrade_ming":"明 搂","chi":"吃","peng":"碰","gang":"杠","angang":"暗 杠","bugang":"补 杠"}
	if not names.has(event.kind):return
	if is_instance_valid(action_cue):action_cue.queue_free()
	action_cue=Control.new();hud.add_child(action_cue);action_cue.mouse_filter=Control.MOUSE_FILTER_IGNORE
	action_cue.position=[Vector2(690,570),Vector2(1160,390),Vector2(690,195),Vector2(225,390)][int(event.seat)]
	var word=UI.label(action_cue,Rect2(0,0,220,88),names[event.kind],54,UI.GOLD,true);word.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	word.add_theme_color_override("font_shadow_color",Color("ffffffa0"));word.add_theme_constant_override("shadow_offset_y",2)
	action_cue.modulate.a=0
	var tween=action_cue.create_tween();tween.tween_property(action_cue,"modulate:a",1.0,0.12);tween.tween_interval(0.8);tween.tween_property(action_cue,"modulate:a",0.0,0.25)
	tween.tween_callback(action_cue.queue_free)

func _celebrate() -> void:
	var round_number=view.round
	if not view.result.draw:
		var effect=_layer()
		var veil=ColorRect.new();veil.size=Vector2(1600,900);veil.color=Color("eef7f0c9");veil.mouse_filter=Control.MOUSE_FILTER_IGNORE;effect.add_child(veil)
		var box=Control.new();box.position=Vector2(450,268);box.size=Vector2(700,310);box.pivot_offset=Vector2(350,155);effect.add_child(box)
		var line=ColorRect.new();line.position=Vector2(103,29);line.size=Vector2(494,2);line.color=UI.GOLD;box.add_child(line)
		var title={"self-draw":"自  摸","discard":"胡","robbed-kong":"抢 杠 胡","tianhu":"天  胡","dihu":"地  胡"}.get(view.result.win_type,"胡")
		var label=UI.label(box,Rect2(0,33,700,189),title,119,UI.GOLD,true);label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_shadow_color",Color("ffffffad"));label.add_theme_constant_override("shadow_offset_y",3)
		var caption=UI.label(box,Rect2(0,235,700,53),view.players[view.result.winner].name+"  ·  "+view.result.pattern,26,UI.TEXT,true);caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		box.scale=Vector2(0.86,0.86);effect.modulate.a=0
		var tween=create_tween().set_parallel()
		tween.tween_property(effect,"modulate:a",1.0,0.2)
		tween.tween_property(box,"scale",Vector2.ONE,0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		await get_tree().create_timer(1.3).timeout
		if is_instance_valid(effect):effect.queue_free()
	if current_screen=="table" and view.round==round_number and view.phase=="settled":_show_result()

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
		var shell=UI.panel(hand_layer,Rect2(left+(70-face_size.x)/2+1,shell_y,face_size.x-2,face_size.y),Color("197d83"),Color("429b9e"),5)
		shell.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var shell_ref=weakref(shell)
		var button = TextureButton.new(); button.position=Vector2(left,top); button.size=Vector2(70,108)
		button.texture_normal=tile_textures[p.hand[i]]; button.ignore_texture_size=true; button.stretch_mode=TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND if legal else Control.CURSOR_ARROW
		button.modulate=Color.WHITE
		button.tooltip_text=Tiles.spoken_title(p.hand[i])
		var ready_discard=view.pending.any(func(a): return a.kind=="bao" and a.index==i)
		if p.drawn==i:
			UI.label(hand_layer,Rect2(left,top-23,70,21),"新摸 · 听" if ready_discard else "新摸",12,UI.GOLD).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		button.pressed.connect(func(): _activate_tile(i))
		button.set_meta("hand_index",i)
		button.mouse_entered.connect(func():
			if selected!=i and legal:
				button.position.y=top-5
				var plate=shell_ref.get_ref()
				if plate:plate.position.y=shell_y-5
			_inspect_tile(p.hand[i],left,top))
		button.mouse_exited.connect(func():
			button.position.y=top
			var plate=shell_ref.get_ref()
			if plate:plate.position.y=shell_y
			_clear(inspect_layer))
		hand_layer.add_child(button)
		if selected==i:
			var line = ColorRect.new(); line.position=Vector2(left+8,top+108); line.size=Vector2(54,3); line.color=UI.GOLD; line.mouse_filter=Control.MOUSE_FILTER_IGNORE; hand_layer.add_child(line)
		if ready_discard and p.drawn!=i:
			var marker=UI.label(hand_layer,Rect2(left+43,top-16,23,24),"听",13,UI.GOLD); marker.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	if selected>=0 and selected<p.hand.size():
		var waiting=[]
		for a in view.pending:
			if a.kind=="bao" and a.index==selected: waiting=a.waits
		detail_label.text = "打出 " + Tiles.title(p.hand[selected]) + (" · 听 " + "、".join(waiting.map(func(t): return Tiles.title(t))) if not waiting.is_empty() else " · 再点一次打出")
	elif p.bao or p.ming:
		var base=p.hand.duplicate()
		if p.drawn>=0 and base.size()%3==2: base.remove_at(p.drawn)
		var waiting=Rules.waits(base,p.melds,view.settings.jiang=="luan")
		detail_label.text=("明搂：只可自摸" if p.ming else "已报听：锁定手牌")+" · 听 "+"、".join(waiting.map(func(t):return Tiles.title(t)))
	else: detail_label.text="报听后才可胡牌 · 明搂赢输翻倍，仅可自摸"

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
	if last_tap_index==index and now-last_tap_ms<=360:
		last_tap_index=-1; selected=index; _discard_selected(); return
	last_tap_index=index;last_tap_ms=now;selected=index;_draw_hand();_draw_actions()

func _input(event: InputEvent) -> void:
	if current_screen != "table" or is_instance_valid(modal): return
	if event is InputEventScreenTouch:
		last_touch_ms=Time.get_ticks_msec()
		if event.pressed:
			touch_started=event.position;touch_started_ms=Time.get_ticks_msec();touch_index=-1
			for button in hand_layer.get_children():
				if button is TextureButton and button.get_global_rect().has_point(event.position): touch_index=button.get_meta("hand_index")
			if touch_index<0: selected=-1;declare_mode="";_draw_hand();_draw_actions();_clear(inspect_layer)
		elif touch_index>=0:
			var travel=event.position-touch_started
			if -travel.y>=28 and -travel.y>absf(travel.x)*1.15 and Time.get_ticks_msec()-touch_started_ms<700:
				suppress_click_until=Time.get_ticks_msec()+500
				if not session.paused and view.decision_seat==0 and view.pending.any(func(a):return a.kind=="discard" and a.index==touch_index):
					selected=touch_index;_discard_selected()
			touch_index=-1

func _discard_selected() -> void:
	var kind="discard" if declare_mode.is_empty() else declare_mode
	for move in view.pending:
		if move.kind==kind and move.get("index",-1)==selected:
			session.play(move.id,view.revision); return
	_toast("这张牌不能用于报听，请选择标有「听」的牌。")

func _draw_actions() -> void:
	_clear(action_layer)
	if not view.is_empty() and view.phase=="settled":
		UI.button(action_layer,Rect2(652,650,296,52),"查看本局结算",_show_result,true)
		return
	if view.is_empty() or view.decision_seat!=0: return
	var actions=[]
	if view.phase=="claim":
		for move in view.pending:
			if move.kind == "chi": continue
			var label={"win":"胡", "peng":"碰", "gang":"杠", "pass":"过", "chi":"吃"}.get(move.kind,move.kind)
			if move.kind != "pass": label += " " + Tiles.title(move.tile)
			if move.kind=="chi": label="吃 "+"·".join(move.tiles.map(func(t):return Tiles.title(t)))
			actions.append({"text":label,"move":move,"primary":move.kind=="win"})
		var chi_options = view.pending.filter(func(a): return a.kind == "chi")
		if not chi_options.is_empty(): actions.append({"text":"吃牌组合" if chi_options.size()>1 else "吃 "+Tiles.title(view.claim_tile),"picker":chi_options,"primary":false})
	elif view.phase=="turn":
		var kongs = view.pending.filter(func(a): return a.kind in ["angang","bugang"])
		for move in view.pending:
			if move.kind in ["angang","bugang"] and kongs.size() > 1: continue
			if move.kind in ["win","angang","bugang","upgrade_ming"]:
				actions.append({"text":{"win":"自摸胡","angang":"暗杠","bugang":"补杠","upgrade_ming":"升级明搂"}[move.kind]+(" "+Tiles.title(move.tile) if move.has("tile") else ""),"move":move,"primary":move.kind=="win"})
		if kongs.size() > 1: actions.append({"text":"杠 · 选择牌","picker":kongs,"primary":false})
		for kind in ["bao","ming"]:
			if view.pending.any(func(a):return a.kind==kind): actions.append({"text":("取消" if declare_mode==kind else "")+("报听" if kind=="bao" else "明搂"),"declare":kind,"primary":declare_mode==kind})
		if selected>=0: actions.append({"text":"打出 "+Tiles.title(view.players[0].hand[selected]),"discard":true,"primary":true})
	var widths=[]; var total=0
	for a in actions:
		var width=clampi(a.text.length()*21+34,91,320); widths.append(width); total+=width+10
	var x=800-total/2.0
	for i in range(actions.size()):
		var a=actions[i]
		UI.button(action_layer,Rect2(x,650,widths[i],52),a.text,func():
			_sound("click")
			if a.has("declare"):
				declare_mode="" if declare_mode==a.declare else a.declare
				if selected>=0 and not declare_mode.is_empty(): _discard_selected()
				else: _draw_actions(); _toast("选择一张标有「听」的牌打出，即可"+("报听" if a.declare=="bao" else "明搂"))
			elif a.has("picker"): _show_move_picker(a.picker)
			elif a.has("discard"): _discard_selected()
			else: session.play(a.move.id,view.revision),a.primary)
		x+=widths[i]+10

func _show_move_picker(moves: Array) -> void:
	if moves.size() == 1:
		session.play(moves[0].id,view.revision); return
	var revision = view.revision
	_popup("请选择吃牌组合" if moves[0].kind == "chi" else "请选择要杠的牌", Vector2(850,380))
	for i in range(moves.size()):
		var move = moves[i]
		var x = 45 + i * 185
		var tiles = move.get("tiles",[move.tile])
		for j in range(tiles.size()): UI.texture(modal,Rect2(x+j*44,113,42,58),tile_textures[tiles[j]])
		var caption = "吃这组" if move.kind == "chi" else ("暗杠 " if move.kind == "angang" else "补杠 ") + Tiles.title(move.tile)
		UI.button(modal,Rect2(x,195,165,53),caption,func(): _close_modal(); session.play(move.id,revision),true)
	UI.label(modal,Rect2(45,293,760,32),"牌局已暂停，选定后继续。关闭窗口可取消选择。",18,UI.MUTED)

func _visible_remaining(tile: int) -> int:
	var visible = view.players[0].hand.count(tile)
	for p in view.players:
		visible += p.discards.count(tile)
		for meld in p.melds: visible += meld.tiles.count(tile)
		if p.seat != 0 and not p.hand.is_empty(): visible += p.hand.count(tile)
	if view.gang_head == tile: visible += 1
	return maxi(0,4-visible)

func _inspect_tile(tile: int, left: float, top: float) -> void:
	_clear(inspect_layer)
	var neighbors = [tile]
	if tile < 27:
		if tile%9 > 0: neighbors.push_front(tile-1)
		if tile%9 < 8: neighbors.append(tile+1)
	var waits: Array = []
	for move in view.pending:
		if move.kind=="bao" and move.tile==tile: waits=move.waits; break
	var height = 235 if not waits.is_empty() else 143
	var panel = UI.panel(inspect_layer,Rect2(clampf(left-105,235,1060),maxf(180,top-height-18),300,height),UI.PAPER,Color("80b4ac"),16)
	panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	for i in range(neighbors.size()):
		var item = neighbors[i]
		UI.texture(panel,Rect2(16+i*94,12,45,62),tile_textures[item])
		UI.label(panel,Rect2(12+i*94,76,92,26),Tiles.spoken_title(item),16,UI.GOLD if item==tile else UI.TEXT)
		UI.label(panel,Rect2(12+i*94,106,92,24),"未见 %d 张" % _visible_remaining(item),13,UI.MUTED)
	if not waits.is_empty():
		UI.label(panel,Rect2(12,139,276,25),"打出后可报听 · 听口",15,UI.GOLD)
		for i in range(mini(7,waits.size())): UI.texture(panel,Rect2(12+i*39,173,35,47),tile_textures[waits[i]])

func _scroll_body() -> Control:
	var scroll = ScrollContainer.new(); scroll.position=Vector2(40,100); scroll.size=Vector2(1000,570)
	modal.add_child(scroll)
	var body = Control.new(); body.custom_minimum_size=Vector2(970,570); scroll.add_child(body)
	return body

func _show_waits() -> void:
	if view.is_empty(): return
	_popup("听牌一览",Vector2(1080,720))
	var body = _scroll_body()
	var p = view.players[0]
	var rows: Array = []
	var seen: Array = []
	for move in view.pending:
		if move.kind != "bao" or move.tile in seen: continue
		seen.append(move.tile); rows.append({"discard":move.tile,"waits":move.waits})
	if rows.is_empty():
		var base = p.hand.duplicate()
		if base.size()%3 == 2 and p.drawn >= 0: base.remove_at(p.drawn)
		var waits = Rules.waits(base,p.melds,view.settings.jiang=="luan")
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
			var score=Rules.evaluate(base+[tile],p.melds,{"self_draw":true,"bao":true,"ming":p.ming,"luan":view.settings.jiang=="luan"})
			UI.label(body,Rect2(x-3,ty+59,62,22),"%d 倍" % score.get("multiplier",1),13,UI.GOLD)
			UI.label(body,Rect2(x-3,ty+81,62,22),"%d 张" % _visible_remaining(tile),13,UI.MUTED)
		y += maxf(112,ceil(row.waits.size()/12.0)*103+15)
	if rows.is_empty():
		UI.label(body,Rect2(0,25,950,90),"当前没有听口。选择「牌效提示」可查看出牌建议。",23,UI.MUTED)
		y=130
	UI.label(body,Rect2(0,y+12,950,55),"倍数按当前手牌自摸估算。余张按自己的手牌、公开牌和杠头计算。\n未见的牌也可能在其他玩家手中。",16,UI.MUTED)
	body.custom_minimum_size.y = y + 95

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
	body.custom_minimum_size.y = y

func _hint(move: Dictionary) -> void:
	if current_screen!="table" or not is_instance_valid(hand_layer):return
	if move.is_empty(): return
	if move.has("index"):
		selected=move.index; _draw_hand(); _draw_actions()
		var a=move.get("analysis",{})
		_toast("建议打出 "+Tiles.title(move.tile)+(" · 可报听" if move.kind in ["bao","ming"] else " · 兼顾向听与有效进张")+(" · 有效进张 %d"%a.ukeire if a.has("ukeire") else ""))
	else: _toast("建议操作："+{"win":"胡牌","peng":"碰牌","gang":"杠牌","chi":"吃牌","angang":"暗杠","bugang":"补杠","pass":"过"}.get(move.kind,move.kind))

func _popup(title: String, dimensions: Vector2) -> void:
	_close_modal(); session.paused=true
	var shade=ColorRect.new(); shade.color=Color("183b435c"); shade.size=Vector2(1600,900); root.add_child(shade)
	shade.name="ModalShade"
	modal=UI.panel(shade,Rect2((Vector2(1600,900)-dimensions)/2,dimensions),UI.PAPER,Color("ffffff"),22)
	UI.label(modal,Rect2(42,25,dimensions.x-110,53),title,32,UI.TEXT,true)
	UI.button(modal,Rect2(dimensions.x-78,29,42,42),"×",_close_modal)

func _close_modal() -> void:
	var shade=root.get_node_or_null("ModalShade") if is_instance_valid(root) else null
	if shade: shade.name="ClosingModal";shade.queue_free()
	modal=null
	if current_screen=="table": session.paused=false

func _pause() -> void:
	if is_instance_valid(modal): _close_modal(); return
	_popup("暂歇一会",Vector2(640,374))
	UI.label(modal,Rect2(43,106,556,66),"当前牌局已自动保存。\n关闭游戏后，也可以从大厅继续。",22,UI.MUTED)
	UI.button(modal,Rect2(44,212,552,57),"继续对局",_close_modal,true)
	UI.button(modal,Rect2(44,286,552,51),"保存并返回大厅",_show_lobby)

func _show_rules() -> void:
	_popup("本桌玩法",Vector2(934,756))
	var text=RichTextLabel.new(); text.position=Vector2(42,100); text.size=Vector2(850,602)
	text.add_theme_font_override("normal_font",UI.font()); text.add_theme_font_size_override("normal_font_size",21)
	text.add_theme_color_override("default_color",UI.TEXT); text.bbcode_enabled=true
	text.text="[color=#187f80]开局与行牌[/color]\n144 张牌，含春夏秋冬、梅兰竹菊八花。庄家 14 张，闲家 13 张；起手补花。每局轮庄，初始 2000 分，底分 10。\n\n[color=#187f80]报听、明搂[/color]\n普通胡牌必须先报听或明搂。选择能听牌的弃牌，同时完成声明。报听后锁手，只能打出新摸到的牌，不能吃碰。摸到第四张且杠前后听口不变时，可暗杠或补杠。明搂亮开手牌，只能自摸，赢输均按规则翻倍；报听后可在自己回合升级明搂。\n\n[color=#187f80]胡牌与响应[/color]\n二五八将：普通牌型须以数牌 2、5、8 作将；乱将允许任意将。十三幺、十三不靠、风一色、将一色及八花有原规则豁免。优先胡，再碰杠，最后下家吃。单响截胡，前家放弃后下一位仍可胡。过胡、过碰限制持续到本人再次摸到普通牌。\n\n[color=#187f80]补花与杠头[/color]\n杠头公开。正常摸牌从牌头拿，补花取杠头前一张；开杠才摸走杠头，再翻下一张。只剩杠头时不能普通摸牌。八花齐集立即花胡。\n\n[color=#187f80]计分[/color]\n基本单位＝花分 × 番型倍数 × 10。基础 1 花；每张花牌 1 花；字刻 1 花；数牌明杠 1、暗杠 2 花；字牌明杠 2、暗杠 3 花。杠分并入胡牌结算，不即时收取。\n自摸由其余三家各付一份；普通点炮由出牌者付一份；抢杠胡由被抢者付三份。明搂的输家付款另翻倍。\n\n[color=#187f80]番型[/color]\n平胡 1；七对／碰碰胡 2；豪华七对 4；风一色／将一色 6；双豪华七对 8；十三不靠 12；十三幺／超豪华七对 16。附加：清一色 4／混一色 2、一条龙 4、大吊车 2、门清 2（指定特殊牌型除外）、持花 2、海底 2、明搂 2。天胡固定 30、地胡固定 25，不加花分。\n\n以上按原项目山东玩法迁移；完整细节以随项目保存的规则基线与牌例测试为准。"
	modal.add_child(text)

func _show_settings() -> void:
	_popup("桌边设置",Vector2(680,454))
	UI.label(modal,Rect2(44,108,230,40),"声音",22)
	UI.button(modal,Rect2(307,106,325,49),"已静音" if muted else "已开启",func(): muted=not muted; voice.stop_all(); _save_preferences(); _show_settings())
	UI.label(modal,Rect2(44,183,230,40),"画质",22)
	UI.button(modal,Rect2(307,181,325,49),"省电 · 关闭阴影" if low_quality else "精致 · 柔和阴影",func(): low_quality=not low_quality; table.quality(low_quality); _save_preferences(); _show_settings())
	UI.label(modal,Rect2(44,258,230,40),"电脑行牌速度",22)
	UI.button(modal,Rect2(307,256,325,49),("舒缓 · 约 2.4 秒" if session.speed < 1 else ("标准 · 约 1.8 秒" if session.speed == 1 else "利落 · 约 1.2 秒")),func(): session.speed=1.0 if session.speed<1 else (1.5 if session.speed==1 else 0.75); _save_preferences(); _show_settings())
	UI.label(modal,Rect2(44,340,585,69),"对局规则在开局时固定。\n新一局的将牌、吃牌与 AI 设置请返回大厅选择。",18,UI.MUTED)

func _about() -> void:
	_popup("关于青玉台",Vector2(760,453))
	UI.label(modal,Rect2(43,108,671,210),"山东麻将 · 青玉台  0.1.0\nGodot 4.5 · 原生 GDScript · 离线运行\n\n规则迁移自莲花广麻项目的山东麻将（MIT）。\n牌面图片与逐牌语音沿用莲花麻将；花牌 CC BY-SA 4.0。\n字体：Noto Sans SC / Noto Serif SC（SIL OFL 1.1）。",20,UI.MUTED)
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
		UI.panel(modal,Rect2(43,y,900,51),Color("dcefe7") if i==r.winner else Color("edf2f0"),Color.TRANSPARENT,10)
		UI.label(modal,Rect2(65,y+8,280,36),view.players[i].name+("  ·  本家" if i==0 else ""),21)
		UI.label(modal,Rect2(519,y+8,180,36),str(view.players[i].score)+" 分",21,UI.MUTED)
		UI.label(modal,Rect2(778,y+6,148,39),("+" if r.deltas[i]>0 else "")+str(r.deltas[i]),25,UI.GOLD if r.deltas[i]>0 else UI.TEXT)
	var ended=view.settings.rounds>0 and view.round>=view.settings.rounds
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
		toast_label=UI.label(root,Rect2(270,100,1060,44),"",19,UI.TEXT)
		toast_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		toast_label.add_theme_stylebox_override("normal",UI.style(UI.PAPER,Color("80b4ac"),12))
	toast_label.text=message; toast_label.visible=true; toast_time=4.2
	root.move_child(toast_label,-1)

func _process(delta: float) -> void:
	if toast_time>0:
		toast_time-=delta
		if toast_time<=0 and is_instance_valid(toast_label):toast_label.visible=false

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:return
	if event.keycode==KEY_ESCAPE:
		if is_instance_valid(modal):_close_modal()
		elif is_instance_valid(inspect_layer) and inspect_layer.get_child_count()>0: _clear(inspect_layer)
		elif current_screen=="table":_pause()
	elif current_screen=="table" and not is_instance_valid(modal):
		if event.keycode==KEY_H:session.request_hint()
		if event.keycode in [KEY_SPACE,KEY_ENTER] and selected>=0:_discard_selected()

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:get_tree().quit()
	if what==NOTIFICATION_APPLICATION_PAUSED or what==NOTIFICATION_WM_GO_BACK_REQUEST:
		if current_screen=="table" and not is_instance_valid(modal):_pause()

func _save_preferences() -> void:
	var file=FileAccess.open("user://preferences.json",FileAccess.WRITE)
	if file:file.store_string(JSON.stringify({"config":config,"muted":muted,"low_quality":low_quality,"speed":session.speed,"pace_version":2}))

func _load_preferences() -> void:
	if not FileAccess.file_exists("user://preferences.json"):return
	var prefs=JSON.parse_string(FileAccess.get_file_as_string("user://preferences.json"))
	if not prefs is Dictionary:return
	config.merge(prefs.get("config",{}),true); muted=prefs.get("muted",false);low_quality=prefs.get("low_quality",false)
	session.speed=clampf(prefs.get("speed",1.0),0.75,1.5) if prefs.get("pace_version",0)==2 else 1.0;table.quality(low_quality)
