class_name LanLobby
extends Control
## Room presentation only. The app owns discovery and the authoritative session.
signal back_requested
signal host_requested(settings: Dictionary, player_name: String)
signal join_requested(address: String, player_name: String, port: int)
signal ready_requested(ready: bool)
signal start_requested
signal settings_requested(settings: Dictionary)
signal disconnect_autoplay_requested(enabled: bool)
signal leave_requested

var configuration: Dictionary = {}
var nickname = "牌友"
var address = ""
var name_input: LineEdit
var address_input: LineEdit
var room_list: VBoxContainer
var list_scroll: ScrollContainer
var status_label: Label
var join_button: Button
var create_button: Button
var _rooms: Array = []
var _room: Dictionary = {}
var _host = false
var _seat = -1
var _browser = true
var _busy = false
var _rule_buttons: Array[Button] = []

func _base(title: String, subtitle: String) -> void:
	_rule_buttons.clear()
	for child in get_children():
		remove_child(child); child.queue_free()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var courtyard = UI.texture(self, Rect2(0,0,1600,900), load("res://assets/backgrounds/courtyard_day.jpg"))
	courtyard.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	UI.panel(self, Rect2(0,0,1600,900), Color("081f1be9"), Color.TRANSPARENT, 0)
	UI.label(self, Rect2(104,55,1180,70), title, 44, UI.TEXT, true)
	UI.label(self, Rect2(106,140,1330,35), subtitle, 20, UI.MUTED)
	UI.button(self, Rect2(1348,68,148,52), "返回大厅" if _browser else "离开房间", func():
		if _browser: back_requested.emit()
		else: leave_requested.emit())

func show_browser(settings: Dictionary, player_name: String = "牌友", host_address: String = "") -> void:
	configuration = settings.duplicate(true)
	configuration.rounds = 0
	nickname = player_name; address = host_address
	_browser = true; _busy = false
	_base("附近同桌", "连接同一 Wi-Fi 或房主的手机热点，安卓与 Windows 可以一起落座。")
	var create_panel = UI.table_panel(self, Rect2(104,215,438,562))
	UI.label(create_panel, Rect2(27,19,378,38), "我的座位", 26, UI.GOLD, true)
	UI.label(create_panel, Rect2(27,76,378,28), "昵称", 18, UI.MUTED)
	name_input = _line_edit(create_panel, Rect2(27,114,384,54), "给牌友看的名字", nickname, 12)
	name_input.text_changed.connect(func(value): nickname = value)
	UI.label(create_panel, Rect2(27,204,378,35), "本桌约定", 25, UI.TEXT, true)
	_draw_settings(create_panel, Vector2(27,256), true)
	create_button = UI.button(create_panel, Rect2(27,455,384,61), "创建房间", func():
		host_requested.emit(configuration.duplicate(true), _player_name()), true)
	UI.label(self, Rect2(586,205,670,42), "发现的房间", 27, UI.TEXT, true)
	UI.label(self, Rect2(1280,214,200,30), "自动刷新", 17, UI.MUTED)
	list_scroll = ScrollContainer.new(); list_scroll.position = Vector2(586,269); list_scroll.size = Vector2(910,314)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(list_scroll)
	room_list = VBoxContainer.new(); room_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room_list.add_theme_constant_override("separation",12); list_scroll.add_child(room_list)
	_update_room_list()
	UI.label(self, Rect2(586,613,865,30), "也可以输入房主的局域网地址", 21, UI.TEXT)
	address_input = _line_edit(self, Rect2(586,659,630,57), "例如 192.168.1.8", address, 64)
	address_input.text_changed.connect(func(value): address = value)
	address_input.text_submitted.connect(func(_value): _join_address())
	join_button = UI.button(self, Rect2(1232,659,264,57), "加入房间", _join_address, true)
	status_label = UI.label(self, Rect2(586,737,910,42), "搜索中的房间会显示在这里。", 18, UI.MUTED)
	UI.label(self, Rect2(105,818,1388,50), "无需互联网。若列表为空，可输入房主地址；设备隔离或防火墙阻断时，请检查网络或改用热点。", 18, UI.MUTED)

func _line_edit(parent: Node, rect: Rect2, placeholder: String, value: String, limit: int) -> LineEdit:
	var input = LineEdit.new(); input.position = rect.position; input.size = rect.size
	input.placeholder_text = placeholder; input.text = value; input.max_length = limit
	input.add_theme_font_override("font", UI.font()); input.add_theme_font_size_override("font_size",22)
	input.add_theme_color_override("font_color", UI.TEXT)
	input.add_theme_color_override("font_placeholder_color", UI.MUTED)
	input.add_theme_stylebox_override("normal", UI.style(Color("0c2724"),UI.LINE,10))
	input.add_theme_stylebox_override("focus", UI.style(Color("0c2724"),UI.GOLD,10,2))
	parent.add_child(input); return input

func _player_name() -> String:
	return nickname.strip_edges() if not nickname.strip_edges().is_empty() else "牌友"

func _join_address() -> void:
	if _busy: return
	var target = address.strip_edges()
	var port = 32141
	if target.count(":") == 1:
		var split = target.split(":")
		if not split[1].is_valid_int(): set_status("端口应为 1024–65535 的数字。"); return
		port = int(split[1]); target = split[0]
	if port < 1024 or port > 65535:
		set_status("端口应为 1024–65535 的数字。"); return
	if not target.is_valid_ip_address() or ":" in target:
		set_status("请输入房主界面显示的 IPv4 地址，例如 192.168.1.8。"); return
	join_requested.emit(target,_player_name(),port)

func update_rooms(rooms: Array) -> void:
	_rooms = rooms.duplicate(true)
	if _browser and is_instance_valid(room_list): _update_room_list()

func _update_room_list() -> void:
	var old_scroll = list_scroll.scroll_vertical
	for child in room_list.get_children():
		room_list.remove_child(child); child.queue_free()
	if _rooms.is_empty():
		var empty = Control.new(); empty.custom_minimum_size = Vector2(880,145); room_list.add_child(empty)
		UI.label(empty, Rect2(20,15,840,52), "正在寻找附近牌友…", 27, UI.TEXT)
		UI.label(empty, Rect2(20,77,840,52), "请让一位牌友先创建房间，并保持游戏在前台。", 20, UI.MUTED)
	for found in _rooms:
		var row = UI.table_panel(room_list,Rect2(0,0,880,110)); row.custom_minimum_size = Vector2(880,110)
		var caption = UI.label(row,Rect2(22,12,607,36),str(found.get("name","牌友的房间")),24,UI.TEXT,true)
		caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var settings = found.get("settings",{})
		var summary = "%d / 4 真人 · %s · %s" % [int(found.get("players",1)),"二五八将" if settings.get("jiang","258")=="258" else "乱将","允许吃" if settings.get("chi",true) else "不允许吃"]
		UI.label(row,Rect2(22,59,637,29),summary,18,UI.MUTED)
		var started = found.get("started",false)
		var full = int(found.get("players",0)) >= 4
		var enter = UI.button(row,Rect2(691,29,164,53),"正在对局" if started else ("房间已满" if full else "加入"),func():
			join_requested.emit(str(found.address),_player_name(),int(found.get("port",32141))),not started and not full)
		enter.disabled = _busy or started or full
		enter.tooltip_text = str(found.get("address",""))
	list_scroll.set_deferred("scroll_vertical",old_scroll)

func set_busy(busy: bool, message: String = "") -> void:
	_busy = busy
	if is_instance_valid(create_button): create_button.disabled = busy
	if is_instance_valid(join_button): join_button.disabled = busy
	for button in _rule_buttons:
		if is_instance_valid(button): button.disabled = busy
	if is_instance_valid(name_input): name_input.editable = not busy
	if is_instance_valid(address_input): address_input.editable = not busy
	if _browser and is_instance_valid(room_list): _update_room_list()
	if not message.is_empty(): set_status(message)

func set_status(message: String) -> void:
	if is_instance_valid(status_label): status_label.text = message

func _draw_settings(parent: Node, offset: Vector2, editable: bool) -> void:
	for row in range(3):
		var key = ["jiang","chi","ai"][row]
		var labels = [["二五八将","乱将"],["允许吃牌","不允许吃"],["牌效 AI","经典 AI"]][row]
		var values = [["258","luan"],[true,false],["efficiency","classic"]][row]
		if not editable:
			var selected = 0 if configuration.get(key)==values[0] else 1
			UI.label(parent,Rect2(offset+Vector2(0,row*56),Vector2(384,44)),labels[selected],23,UI.GOLD)
			continue
		for option in range(2):
			var value = values[option]
			var button = UI.button(parent,Rect2(offset+Vector2(option*199,row*56),Vector2(185,44)),labels[option],func():
				if _busy: return
				configuration[key] = value
				if _browser: show_browser(configuration,nickname,address)
				else: settings_requested.emit(configuration.duplicate(true)),configuration.get(key)==value)
			button.disabled = not editable
			_rule_buttons.append(button)

func show_room(room: Dictionary, host: bool, local_seat: int) -> void:
	_browser = false; _busy = false; _room = room.duplicate(true); _host = host; _seat = local_seat
	configuration = room.get("settings",{}).duplicate(true)
	_base(str(room.get("name","附近同桌")),"真人入座准备后，由房主开始；不足四位的空位由电脑补齐。")
	var addresses: Array = room.get("host_addresses",[])
	var address_text = "、".join(addresses.map(func(item): return str(item)))
	if address_text.is_empty(): address_text = "请查看房主设备的 Wi-Fi / 热点地址"
	var port = int(room.get("port",32141))
	if port != 32141: address_text += "  端口 %d" % port
	UI.label(self, Rect2(106,196,1388,33),"房主地址："+address_text,19,UI.GOLD)
	var seats: Array = room.get("seats",[])
	for index in range(4):
		var seat: Dictionary = seats[index] if index < seats.size() else {}
		var x = 104+index*354
		var panel = UI.table_panel(self,Rect2(x,256,330,175),index==local_seat)
		UI.portrait(panel,Vector2(21,27),72,index)
		var occupied = seat.get("occupied",false)
		var name_text = str(seat.get("name","牌友")) if occupied else "电脑补位"
		var name_label = UI.label(panel,Rect2(113,26,198,37),name_text,25,UI.TEXT,true)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.tooltip_text = name_text
		UI.label(panel,Rect2(113,68,192,29),["东","南","西","北"][index]+"位"+(" · 房主" if index==0 else "")+(" · 我" if index==local_seat else ""),18,UI.MUTED)
		var state_text = "空位将自动加入电脑"
		if occupied:
			state_text = "已准备" if seat.get("ready",false) else "等待准备"
			if not seat.get("connected",true): state_text = "已离线 · 座位保留"
			elif index==0: state_text = "等待牌友落座" if not room.get("can_start",false) else "可以开始了"
		UI.label(panel,Rect2(21,124,285,30),state_text,19,UI.GOLD if occupied else UI.MUTED)
	UI.label(self,Rect2(106,469,390,42),"本桌规则"+(" · 房主可调整" if host else " · 由房主设置"),26,UI.TEXT,true)
	_draw_settings(self,Vector2(106,537),host and not room.get("started",false))
	UI.label(self,Rect2(586,478,872,39),"每局轮庄 · 积分累计 · 自由续局",25,UI.TEXT,true)
	UI.label(self,Rect2(586,537,872,64),"真人没有出牌倒计时。\n房主修改规则后，牌友需要重新准备。",21,UI.MUTED)
	if host:
		UI.button(self,Rect2(586,635,412,53),"掉线托管：开启" if room.get("disconnect_autoplay",false) else "掉线托管：关闭",func():
			disconnect_autoplay_requested.emit(not bool(_room.get("disconnect_autoplay",false))))
	else:
		UI.label(self,Rect2(586,635,866,53),"掉线托管由房主控制，当前"+("开启" if room.get("disconnect_autoplay",false) else "关闭"),21,UI.MUTED)
	if host:
		var start = UI.button(self,Rect2(1084,747,412,64),"开始对局 →",func(): start_requested.emit(),true)
		start.disabled = not room.get("can_start",false)
		UI.label(self,Rect2(586,756,477,46),"未坐满也可以开始，空位由电脑补齐。",19,UI.MUTED)
	else:
		var ready = local_seat>=0 and local_seat<seats.size() and bool(seats[local_seat].get("ready",false))
		UI.button(self,Rect2(1084,747,412,64),"取消准备" if ready else "我准备好了",func(): ready_requested.emit(not ready),not ready)
		UI.label(self,Rect2(586,756,477,46),"已准备，等待房主开始。" if ready else "核对规则后，点击准备。",21,UI.MUTED)
	UI.label(self,Rect2(106,837,1388,28),"房主请保持游戏在前台，避免手机后台休眠中断连接。",17,UI.MUTED)
