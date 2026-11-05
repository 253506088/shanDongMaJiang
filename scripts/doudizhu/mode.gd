extends Control
## The only bridge from the Mahjong app to this independent game mode.
const SessionScript = preload("res://scripts/doudizhu/session.gd")
const TableScript = preload("res://scripts/doudizhu/ui/table.gd")
const VoiceScript = preload("res://scripts/doudizhu/audio/voice.gd")
signal exit_requested
signal mute_changed(enabled: bool)
var session: DdzSession
var table: Control
var voice: AudioStreamPlayer
var muted = false
var qa_mode = false
var notice_label: Label
var notice_time = 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	session = SessionScript.new()
	add_child(session)
	voice = VoiceScript.new()
	add_child(voice)
	table = TableScript.new()
	add_child(table)
	table.set_muted(muted)
	table.action_requested.connect(func(action):
		if not session.submit(action): table.action_rejected("这次操作已失效，请按当前牌面重新选择。"))
	table.hint_requested.connect(session.request_hint)
	table.next_requested.connect(_next_round)
	table.exit_requested.connect(_leave)
	table.pause_changed.connect(func(value):
		session.paused = value
		# The result panel must not interrupt the final card or spring call.
		voice.stream_paused = value and session.engine.state.get("phase", "") != "finished")
	table.mute_requested.connect(func():
		muted = not muted
		voice.stop_all()
		table.set_muted(muted)
		mute_changed.emit(muted))
	session.changed.connect(_changed)
	session.hint_ready.connect(table.set_hint)
	session.notice.connect(_notice)
	session.start(5105 if qa_mode else -1, 0 if qa_mode else -1)

func _changed(view: Dictionary) -> void:
	table.set_view(view)
	session.hold_presentation(voice.announce(view, muted))

func _next_round() -> void:
	voice.stop_all()
	voice.stream_paused = false
	session.next_round()

func pause_menu() -> void:
	if is_instance_valid(table): table.pause_menu()

func pause_on_background() -> void:
	# Background notifications must never toggle an already open menu closed.
	if is_instance_valid(session) and not session.paused: pause_menu()
	if is_instance_valid(voice): voice.stream_paused = true

func _notice(message: String) -> void:
	if not is_instance_valid(notice_label):
		notice_label = UI.label(self, Rect2(270, 102, 1060, 50), "", 20)
		notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		notice_label.add_theme_stylebox_override("normal", UI.style(UI.PAPER, UI.LINE))
	notice_label.text = message
	notice_label.visible = true
	notice_time = 4.0
	move_child(notice_label, -1)

func _process(delta: float) -> void:
	if notice_time > 0.0:
		notice_time -= delta
		if notice_time <= 0.0 and is_instance_valid(notice_label): notice_label.hide()

func _leave() -> void:
	session.shutdown()
	voice.stop_all()
	exit_requested.emit()

func _exit_tree() -> void:
	if is_instance_valid(session): session.shutdown()
	if is_instance_valid(voice): voice.stop_all()
