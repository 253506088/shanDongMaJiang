extends Control
## The app knows only this boundary; the game owns its session and UI.
const Session = preload("res://scripts/bluff/session.gd")
const Table = preload("res://scripts/bluff/ui/table.gd")
const Voice = preload("res://scripts/bluff/voice.gd")
signal character_requested
signal exit_requested
signal settings_changed(settings: Dictionary)
var session
var table
var voice
var settings: Dictionary = {}
var qa_mode = false
var character_id = Characters.DEFAULT

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	session = Session.new(); session.character_id = character_id; add_child(session)
	voice = Voice.new(); add_child(voice)
	settings.erase("voice")
	table = Table.new(); table.character_id = character_id; table.settings.merge(settings, true); add_child(table)
	table.character_requested.connect(func():character_requested.emit())
	table.start_requested.connect(func(config):
		voice.stop_all(); voice.stream_paused = false
		session.pace = float(table.settings.pace)
		session.start(config, 61106 if qa_mode else -1))
	table.action_requested.connect(func(action):
		if not session.submit(action): table.action_rejected())
	table.pause_changed.connect(func(value): session.paused = value; voice.stream_paused = value)
	table.settings_changed.connect(func(value):
		value.erase("voice"); settings = value
		if value.muted: voice.stop_all()
		settings_changed.emit(value))
	table.exit_requested.connect(func(): session.shutdown(); voice.stop_all(); exit_requested.emit())
	session.changed.connect(func(view):
		table.set_view(view)
		session.delay = maxf(session.delay, voice.announce(view, qa_mode or table.settings.muted)))

func set_character(id: String) -> void:
	character_id = Characters.normalize(id)
	table.character_id = character_id
	session.set_character(character_id)
	if not session.active: table.render()

func pause_menu() -> void:
	table.pause_menu()

func _process(_delta: float) -> void:
	if is_instance_valid(table) and is_instance_valid(session):
		table.set_review_remaining(session.delay)

func pause_on_background() -> void:
	if not table.paused: table.pause_menu()

func _exit_tree() -> void:
	if is_instance_valid(session): session.shutdown()
	if is_instance_valid(voice): voice.stop_all()
