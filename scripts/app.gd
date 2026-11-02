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
var auto_button: Button
var hint_button: Button
var detail_label: Label
var sfx: AudioStreamPlayer
var last_revision = -1
var action_cue: Control
var current_screen = "lobby"
var sounds: Dictionary = {}
var tile_textures: Array = []

func _ready() -> void:
	Engine.max_fps=60
	for t in range(43): tile_textures.append(load("res://assets/tiles/%02d.png" % t))
	for name in ["click", "tile", "deal", "notify", "win"]: sounds[name] = load("res://assets/audio/" + name + ".wav")
	sfx = AudioStreamPlayer.new(); add_child(sfx)
	session = LocalSession.new(); add_child(session)
	session.changed.connect(_changed); session.hint_ready.connect(_hint); session.notice.connect(_toast)
	table = Table3D.new(); add_child(table)
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
	table.visible=false;Engine.max_fps=30
	_clear(root); modal = null; hud = null; toast_label = null
	lobby = _layer()
	var bg = UI.texture(lobby,Rect2(0,0,1600,900),load("res://assets/textures/lobby.png"))
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	UI.texture(lobby,Rect2(70,43,49,49),load("res://assets/icon.svg"))
	UI.label(lobby,Rect2(133,40,280,32),"山东麻将",27,UI.TEXT,true)
	UI.label(lobby,Rect2(135,78,300,22),"青 玉 台  /  Q I N G Y U",12,UI.MUTED)
	UI.button(lobby,Rect2(1340,48,94,46),"玩法",_show_rules)
	UI.button(lobby,Rect2(1446,48,94,46),"设置",_show_settings)
	UI.label(lobby,Rect2(103,184,650,34),"一 方 青 玉  ·  四 席 好 友",19,UI.GOLD,true)
	UI.label(lobby,Rect2(98,238,740,114),"好牌，慢慢来。",72,UI.TEXT,true)
	UI.label(lobby,Rect2(105,375,660,64),"熟悉的山东玩法，安静的一桌麻将。\n与三位电脑牌友落座，随时开始，随时续玩。",22,UI.MUTED)
	# Original tile artwork, arranged as a compact still life.
	for item in [[1,990,285,-0.18],[13,1163,238,0.06],[31,1322,319,0.21]]:
		var shadow = UI.panel(lobby,Rect2(item[1]+10,item[2]+22,164,235),Color("06191699"),Color.TRANSPARENT,22)
		shadow.rotation = item[3]
		var tile = UI.texture(lobby,Rect2(item[1],item[2],164,235),tile_textures[item[0]])
		tile.pivot_offset = Vector2(82,118); tile.rotation = item[3]
	UI.label(lobby,Rect2(1092,623,380,32),"一万一筒，一局一会",23,UI.GOLD,true)
	UI.label(lobby,Rect2(1110,668,380,28),"原生 3D  ·  离线单机  ·  自动存档",15,UI.MUTED)
	var options = UI.panel(lobby,Rect2(104,491,720,229),Color("183b3499"),Color("75846955"),18)
	UI.label(options,Rect2(25,17,240,32),"本桌约定",22,UI.TEXT,true)
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
	UI.label(lobby,Rect2(105,853,1000,24),"青玉台  0.1  /  山东麻将单机版",14,UI.MUTED)
	UI.button(lobby,Rect2(1410,833,120,42),"关于",_about)

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
	table.visible=true;Engine.max_fps=30 if low_quality else 60
	hud = _layer(); selected = -1; declare_mode = ""; last_revision = -1
	UI.texture(hud,Rect2(29,21,42,42),load("res://assets/icon.svg"))
	UI.label(hud,Rect2(83,17,230,40),"山东麻将",25,UI.TEXT,true)
	UI.label(hud,Rect2(86,55,180,22),"青 玉 台",13,UI.GOLD)
	var badge = UI.panel(hud,Rect2(581,17,438,52),Color("102f2ce8"),Color("82956b66"),26)
	round_text = UI.label(badge,Rect2(0,0,438,52),"",21,UI.TEXT,true); round_text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	UI.button(hud,Rect2(1238,24,91,46),"玩法",_show_rules)
	UI.button(hud,Rect2(1340,24,91,46),"设置",_show_settings)
	UI.button(hud,Rect2(1442,24,125,46),"暂停  II",_pause)
	var gang = UI.panel(hud,Rect2(31,103,158,89))
	head_tile = UI.texture(gang,Rect2(12,8,47,69),tile_textures[42])
	UI.label(gang,Rect2(70,11,80,30),"杠头",19,UI.GOLD)
	UI.label(gang,Rect2(70,43,85,24),"开杠即摸",13,UI.MUTED)
	players_ui = []
	for seat in range(4):
		var pos = [Vector2(34,592),Vector2(1421,335),Vector2(709,87),Vector2(34,335)][seat]
		var panel = UI.panel(hud,Rect2(pos,Vector2(146,137)),Color("102c28eb"),Color("73836577"),14)
		var seal = UI.panel(panel,Rect2(13,13,43,43),[Color("5a775f"),Color("5d777a"),Color("6e7462"),Color("96785f")][seat],UI.GOLD,22)
		var ch = UI.label(seal,Rect2(0,0,43,43),["我","松","澜","秋"][seat],22,UI.TEXT,true); ch.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var name_label = UI.label(panel,Rect2(65,11,80,27),["我","听松","观澜","知秋"][seat],19)
		var state_label = UI.label(panel,Rect2(65,38,80,23),"",12,UI.MUTED)
		var score = UI.label(panel,Rect2(16,65,118,36),"2000",28,UI.GOLD)
		var info = UI.label(panel,Rect2(16,106,120,25),"",13,UI.MUTED)
		players_ui.append({"panel":panel,"state":state_label,"score":score,"info":info,"name":name_label})
		if seat==2:
			panel.size=Vector2(190,76);panel.position=Vector2(705,87)
			name_label.position=Vector2(65,7)
			state_label.position=Vector2(65,37)
			score.position=Vector2(119,29);score.add_theme_font_size_override("font_size",21)
			info.visible=false
	var tray = UI.panel(hud,Rect2(228,729,1144,143),Color("0c2623ee"),Color("73836588"),18)
	tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label = UI.label(hud,Rect2(338,683,930,32),"",20,UI.TEXT); status_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	detail_label = UI.label(hud,Rect2(312,858,978,25),"",14,UI.MUTED); detail_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	UI.button(hud,Rect2(31,789,159,55),"暂停 / 续玩",_pause)
	hint_button=UI.button(hud,Rect2(1410,728,157,53),"牌效提示",func(): session.request_hint(); _toast("正在分析当前手牌…"))
	auto_button=UI.button(hud,Rect2(1410,791,157,53),"交给 AI",func(): session.autopilot=not session.autopilot; auto_button.text="收回操作" if session.autopilot else "交给 AI")
	UI.label(hud,Rect2(31,867,300,23),"离线对局 · 每步自动保存",13,UI.MUTED)
	UI.label(hud,Rect2(1360,869,210,23),"Esc 暂停  /  H 提示",12,UI.MUTED)
	hand_layer = _layer(); action_layer = _layer()

func _changed(new_view: Dictionary) -> void:
	view = new_view
	if current_screen != "table": return
	if last_revision != view.revision:
		selected = -1; declare_mode = ""
		if last_revision >= 0:
			_sound("win" if view.phase=="settled" and not view.result.draw else ("notify" if view.event.kind in ["bao","ming","gang","angang","bugang","peng","chi"] else "tile"))
			_show_cue(view.event)
	last_revision = view.revision
	table.update_view(view)
	var field = ["东","南","西","北"][((int(view.round)-1)/4)%4]
	round_text.text = "%s风场 · 第 %d 局   /   %s" % [field,view.round,"二五八将" if view.settings.jiang=="258" else "乱将"]
	head_tile.texture = tile_textures[view.gang_head] if view.gang_head>=0 else tile_textures[42]
	for seat in range(4):
		var p = view.players[seat]; var info = players_ui[seat]
		info.score.text = str(p.score)
		info.state.text = "庄家" if seat==view.dealer else ("本家" if seat==0 else "电脑牌友")
		info.info.text = "明搂 · 亮手" if p.ming else ("已报听 · 锁手" if p.bao else "花牌 %d 张" % Rules.flower_count(p.melds))
		info.panel.add_theme_stylebox_override("panel",UI.style(Color("183f34f5") if seat==view.decision_seat else Color("102c28eb"),UI.GOLD if seat==view.decision_seat else Color("73836566"),14,2 if seat==view.decision_seat else 1))
	hint_button.disabled = view.decision_seat != 0 or view.phase=="settled"
	auto_button.disabled = view.phase=="settled"
	if view.phase=="settled": status_label.text="本局结束 · 牌已亮开"
	elif view.decision_seat==0: status_label.text="轮到你了 · 点选一张牌，再点一次打出" if view.phase=="turn" else "有牌可应 · 请选择操作"
	else: status_label.text="%s正在%s…" % [view.players[view.decision_seat].name,"思考" if view.phase=="turn" else "应牌"]
	_draw_hand(); _draw_actions()
	if view.phase=="settled": _celebrate()

func _show_cue(event: Dictionary) -> void:
	var names={"bao":"报 听","ming":"明 搂","upgrade_ming":"明 搂","chi":"吃","peng":"碰","gang":"杠","angang":"暗 杠","bugang":"补 杠"}
	if not names.has(event.kind):return
	if is_instance_valid(action_cue):action_cue.queue_free()
	action_cue=Control.new();hud.add_child(action_cue);action_cue.mouse_filter=Control.MOUSE_FILTER_IGNORE
	action_cue.position=[Vector2(690,517),Vector2(1110,385),Vector2(690,220),Vector2(270,385)][int(event.seat)]
	var word=UI.label(action_cue,Rect2(0,0,220,88),names[event.kind],54,UI.GOLD,true);word.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	word.add_theme_color_override("font_shadow_color",Color("09241d"));word.add_theme_constant_override("shadow_offset_y",4)
	action_cue.modulate.a=0
	var tween=action_cue.create_tween();tween.tween_property(action_cue,"modulate:a",1.0,0.12);tween.tween_interval(0.8);tween.tween_property(action_cue,"modulate:a",0.0,0.25)
	tween.tween_callback(action_cue.queue_free)

func _celebrate() -> void:
	var round_number=view.round
	if not view.result.draw:
		var effect=_layer()
		var veil=ColorRect.new();veil.size=Vector2(1600,900);veil.color=Color(0.015,0.06,0.045,0.38);veil.mouse_filter=Control.MOUSE_FILTER_IGNORE;effect.add_child(veil)
		var box=Control.new();box.position=Vector2(450,268);box.size=Vector2(700,310);box.pivot_offset=Vector2(350,155);effect.add_child(box)
		var line=ColorRect.new();line.position=Vector2(103,29);line.size=Vector2(494,2);line.color=UI.GOLD;box.add_child(line)
		var title={"self-draw":"自  摸","discard":"胡","robbed-kong":"抢 杠 胡","tianhu":"天  胡","dihu":"地  胡"}.get(view.result.win_type,"胡")
		var label=UI.label(box,Rect2(0,33,700,189),title,119,UI.GOLD,true);label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_shadow_color",Color("071f1b"));label.add_theme_constant_override("shadow_offset_y",8)
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
		var top = 741-(14 if selected==i else 0)
		var button = TextureButton.new(); button.position=Vector2(left,top); button.size=Vector2(70,108)
		button.texture_normal=tile_textures[p.hand[i]]; button.ignore_texture_size=true; button.stretch_mode=TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND if legal else Control.CURSOR_ARROW
		button.modulate=Color.WHITE if legal or view.decision_seat!=0 else Color("a0aaa1")
		button.pressed.connect(func(): _select(i))
		button.mouse_entered.connect(func():
			if selected!=i and legal: button.position.y=top-5)
		button.mouse_exited.connect(func(): button.position.y=top)
		hand_layer.add_child(button)
		if selected==i:
			var line = ColorRect.new(); line.position=Vector2(left+8,top+108); line.size=Vector2(54,3); line.color=UI.GOLD; line.mouse_filter=Control.MOUSE_FILTER_IGNORE; hand_layer.add_child(line)
		if view.pending.any(func(a): return a.kind=="bao" and a.index==i):
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

func _discard_selected() -> void:
	var kind="discard" if declare_mode.is_empty() else declare_mode
	for move in view.pending:
		if move.kind==kind and move.get("index",-1)==selected:
			session.play(move.id,view.revision); return
	_toast("这张牌不能用于报听，请选择标有「听」的牌。")

func _draw_actions() -> void:
	_clear(action_layer)
	if not view.is_empty() and view.phase=="settled":
		UI.button(action_layer,Rect2(652,621,296,52),"查看本局结算",_show_result,true)
		return
	if view.is_empty() or view.decision_seat!=0: return
	var actions=[]
	if view.phase=="claim":
		for move in view.pending:
			var label={"win":"胡", "peng":"碰", "gang":"杠", "pass":"过", "chi":"吃"}.get(move.kind,move.kind)
			if move.kind=="chi": label="吃 "+"·".join(move.tiles.map(func(t):return Tiles.title(t)))
			actions.append({"text":label,"move":move,"primary":move.kind=="win"})
	elif view.phase=="turn":
		for move in view.pending:
			if move.kind in ["win","angang","bugang","upgrade_ming"]:
				actions.append({"text":{"win":"自摸胡","angang":"暗杠","bugang":"补杠","upgrade_ming":"升级明搂"}[move.kind]+(" "+Tiles.title(move.tile) if move.has("tile") else ""),"move":move,"primary":move.kind=="win"})
		for kind in ["bao","ming"]:
			if view.pending.any(func(a):return a.kind==kind): actions.append({"text":("取消" if declare_mode==kind else "")+("报听" if kind=="bao" else "明搂"),"declare":kind,"primary":declare_mode==kind})
		if selected>=0: actions.append({"text":"打出 "+Tiles.title(view.players[0].hand[selected]),"discard":true,"primary":true})
	var widths=[]; var total=0
	for a in actions:
		var width=clampi(a.text.length()*21+34,91,320); widths.append(width); total+=width+10
	var x=800-total/2.0
	for i in range(actions.size()):
		var a=actions[i]
		UI.button(action_layer,Rect2(x,621,widths[i],52),a.text,func():
			_sound("click")
			if a.has("declare"):
				declare_mode="" if declare_mode==a.declare else a.declare
				if selected>=0 and not declare_mode.is_empty(): _discard_selected()
				else: _draw_actions(); _toast("选择一张标有「听」的牌打出，即可"+("报听" if a.declare=="bao" else "明搂"))
			elif a.has("discard"): _discard_selected()
			else: session.play(a.move.id,view.revision),a.primary)
		x+=widths[i]+10

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
	var shade=ColorRect.new(); shade.color=Color(0.01,0.035,0.03,0.77); shade.size=Vector2(1600,900); root.add_child(shade)
	shade.name="ModalShade"
	modal=UI.panel(shade,Rect2((Vector2(1600,900)-dimensions)/2,dimensions),Color("12382ffb"),Color("bda56b"),20)
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
	text.text="[color=#d8bb7b]开局与行牌[/color]\n144 张牌，含春夏秋冬、梅兰竹菊八花。庄家 14 张，闲家 13 张；起手补花。每局轮庄，初始 2000 分，底分 10。\n\n[color=#d8bb7b]报听、明搂[/color]\n普通胡牌必须先报听或明搂。选择能听牌的弃牌，同时完成声明。报听后锁手，只能打出新摸到的牌，不能吃碰杠。明搂亮开手牌，只能自摸，赢输均按规则翻倍；报听后可在自己回合升级明搂。\n\n[color=#d8bb7b]胡牌与响应[/color]\n二五八将：普通牌型须以数牌 2、5、8 作将；乱将允许任意将。十三幺、十三不靠、风一色、将一色及八花有原规则豁免。优先胡，再碰杠，最后下家吃。单响截胡，前家放弃后下一位仍可胡。过胡、过碰限制持续到本人再次摸到普通牌。\n\n[color=#d8bb7b]补花与杠头[/color]\n杠头公开。正常摸牌从牌头拿，补花取杠头前一张；开杠才摸走杠头，再翻下一张。只剩杠头时不能普通摸牌。八花齐集立即花胡。\n\n[color=#d8bb7b]计分[/color]\n基本单位＝花分 × 番型倍数 × 10。基础 1 花；每张花牌 1 花；字刻 1 花；数牌明杠 1、暗杠 2 花；字牌明杠 2、暗杠 3 花。杠分并入胡牌结算，不即时收取。\n自摸由其余三家各付一份；普通点炮由出牌者付一份；抢杠胡由被抢者付三份。明搂的输家付款另翻倍。\n\n[color=#d8bb7b]番型[/color]\n平胡 1；七对／碰碰胡 2；豪华七对 4；风一色／将一色 6；双豪华七对 8；十三不靠 12；十三幺／超豪华七对 16。附加：清一色 4／混一色 2、一条龙 4、大吊车 2、门清 2（指定特殊牌型除外）、持花 2、海底 2、明搂 2。天胡固定 30、地胡固定 25，不加花分。\n\n以上按原项目山东玩法迁移；完整细节以随项目保存的规则基线与牌例测试为准。"
	modal.add_child(text)

func _show_settings() -> void:
	_popup("桌边设置",Vector2(680,454))
	UI.label(modal,Rect2(44,108,230,40),"声音",22)
	UI.button(modal,Rect2(307,106,325,49),"已静音" if muted else "已开启",func(): muted=not muted; _save_preferences(); _show_settings())
	UI.label(modal,Rect2(44,183,230,40),"画质",22)
	UI.button(modal,Rect2(307,181,325,49),"省电 · 关闭阴影" if low_quality else "精致 · 柔和阴影",func(): low_quality=not low_quality; table.quality(low_quality); _save_preferences(); _show_settings())
	UI.label(modal,Rect2(44,258,230,40),"电脑行牌速度",22)
	UI.button(modal,Rect2(307,256,325,49),"%.1f 倍"%session.speed,func(): session.speed=1.5 if session.speed==1 else (2.5 if session.speed==1.5 else 1.0); _save_preferences(); _show_settings())
	UI.label(modal,Rect2(44,340,585,69),"对局规则在开局时固定。\n新一局的将牌、吃牌与 AI 设置请返回大厅选择。",18,UI.MUTED)

func _about() -> void:
	_popup("关于青玉台",Vector2(760,453))
	UI.label(modal,Rect2(43,108,671,210),"山东麻将 · 青玉台  0.1.0\nGodot 4.5 · 原生 GDScript · 离线运行\n\n规则迁移自莲花广麻项目的山东麻将（MIT）。\n牌面、桌布、界面图形与音效为本项目原创。\n字体：Noto Sans SC / Noto Serif SC（SIL OFL 1.1）。",20,UI.MUTED)
	UI.button(modal,Rect2(43,350,324,55),"查看开源许可",_licenses)
	UI.button(modal,Rect2(381,350,333,55),"打开存档文件夹",func(): OS.shell_open(ProjectSettings.globalize_path("user://")))

func _licenses() -> void:
	_popup("开源许可",Vector2(950,756))
	var text=RichTextLabel.new();text.position=Vector2(42,100);text.size=Vector2(866,605)
	text.add_theme_font_override("normal_font",UI.font());text.add_theme_font_size_override("normal_font_size",17)
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
		UI.panel(modal,Rect2(43,y,900,51),Color("234a3d") if i==r.winner else Color("173d32"),Color.TRANSPARENT,8)
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
		toast_label.add_theme_stylebox_override("normal",UI.style(Color("102b25f5"),UI.GOLD,12))
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
	if file:file.store_string(JSON.stringify({"config":config,"muted":muted,"low_quality":low_quality,"speed":session.speed}))

func _load_preferences() -> void:
	if not FileAccess.file_exists("user://preferences.json"):return
	var prefs=JSON.parse_string(FileAccess.get_file_as_string("user://preferences.json"))
	if not prefs is Dictionary:return
	config.merge(prefs.get("config",{}),true); muted=prefs.get("muted",false);low_quality=prefs.get("low_quality",false)
	session.speed=clampf(prefs.get("speed",1.0),0.5,3.0);table.quality(low_quality)
