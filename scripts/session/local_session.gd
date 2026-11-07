class_name LocalSession
extends Node
signal changed(view: Dictionary)
signal hint_ready(move: Dictionary)
signal notice(message: String)

var storage_root = "user://"
var engine = GameEngine.new()
var paused = true
var autopilot = false
var speed = 1.0
var delay = 0.0
var worker: Thread
var worker_revision = -1
var worker_seat = -1
var worker_hint = false
var ai = MahjongAI.new()
var ai_rng = RandomNumberGenerator.new()
var presentation_delay = 0.0
var character_id = Characters.DEFAULT

func presentation_view() -> Dictionary:
	if engine.state.is_empty(): return {}
	var result = Characters.decorate(engine.view(0), Characters.roster(character_id, 4))
	for seat in range(1, 4): result.players[seat].name = Characters.info(result.characters[seat]).name
	return result

func set_character(id: String) -> bool:
	if not Characters.valid(id): return false
	character_id = id
	if not engine.state.is_empty(): changed.emit(presentation_view())
	return true

func action_delay(kind: String) -> float:
	# A readable beat after the visible action, independent of AI compute time.
	var seconds = 2.1 if kind in ["chi", "peng", "gang", "angang", "bugang", "bao", "ming"] or kind.begins_with("field_") else 1.8
	return seconds / maxf(speed, 0.1)

func hold_presentation(seconds: float) -> void:
	presentation_delay = maxf(presentation_delay, seconds)

func _ready() -> void:
	ai_rng.randomize()

func start_match(settings: Dictionary) -> void:
	_join_worker()
	engine.start(settings, int(Time.get_unix_time_from_system()))
	paused = false; autopilot = false; delay = 2.0; presentation_delay = 0
	_publish()

func _publish() -> void:
	_save()
	changed.emit(presentation_view())

func play(action_id: String, revision: int = -1) -> bool:
	if paused or engine.state.is_empty(): return false
	var accepted = engine.submit(0, engine.state.revision if revision < 0 else revision, action_id)
	if accepted:
		delay = action_delay(engine.state.event.kind)
		_publish()
	return accepted

func next_round() -> void:
	if engine.state.is_empty() or engine.state.phase != "settled": return
	_join_worker()
	var s = engine.state
	engine.start(s.settings, ai_rng.randi(), s.round + 1, s.players.map(func(p): return p.score))
	delay = 2.0; presentation_delay = 0; _publish()

func request_hint() -> void:
	if worker != null or engine.state.is_empty() or engine.decision_seat() != 0: return
	_start_worker(true)

func _start_worker(hint: bool = false) -> void:
	worker_revision = engine.state.revision
	worker_seat = engine.decision_seat()
	worker_hint = hint
	var private_view = engine.view(worker_seat)
	var random_value = ai_rng.randf()
	worker = Thread.new()
	var error = worker.start(func(): return ai.choose(private_view, worker_seat, random_value))
	if error != OK:
		worker = null; notice.emit("AI 线程启动失败，请暂停后重试")

static func keeps_human_choice(move: Dictionary) -> bool:
	# A once-per-round ability remains the owner's decision. Discarding the
	# drawn tile skips it for this turn; using it restores automatic play.
	return move.kind in ["win", "angang", "bugang", "field_rebirth", "field_transform", "field_reclaim", "field_peek_wall", "field_peek_waits", "field_gift"]

func locked_discard_action() -> Dictionary:
	# Lotus's local locked turns show the new tile briefly, then discard it.
	# Keep real choices (winning or a legal wait-preserving kong) with the human.
	var state = engine.state
	if state.is_empty() or state.phase != "turn" or state.current != 0: return {}
	var player = state.players[0]
	if not (player.bao or player.ming) or player.drawn < 0 or player.drawn >= player.hand.size(): return {}
	if state.pending.any(keeps_human_choice): return {}
	for move in state.pending:
		if move.kind == "discard" and move.index == player.drawn: return move
	return {}

func _process(delta: float) -> void:
	if not paused: presentation_delay = maxf(0, presentation_delay - delta)
	if worker != null and not worker.is_alive():
		var move = worker.wait_to_finish(); worker = null
		if worker_revision != engine.state.get("revision", -1): return
		if worker_hint: hint_ready.emit(move)
		elif not move.is_empty():
			# Pause preserves a pending AI result without advancing the game.
			if paused: return
			if worker_seat == 0 and not autopilot: return
			if engine.submit(worker_seat, worker_revision, str(move.id)):
				delay = action_delay(engine.state.event.kind); _publish()
	if paused or engine.state.is_empty() or worker != null: return
	delay -= delta
	if delay > 0 or presentation_delay > 0 or engine.state.phase == "settled": return
	if engine.decision_seat() == 0 and not autopilot:
		var move = locked_discard_action()
		# Submit the current legal action through the same journal/save/voice path
		# as a click. No stored timer action can outlive a pause or a new revision.
		if not move.is_empty(): play(str(move.id), engine.state.revision)
	else: _start_worker()

func has_save() -> bool:
	return FileAccess.file_exists(storage_root + "current_match.json") or FileAccess.file_exists(storage_root + "current_match.json.bak")

func resume_match() -> bool:
	_join_worker()
	for suffix in ["", ".bak"]:
		var path=storage_root + "current_match.json" + suffix
		if not FileAccess.file_exists(path):continue
		var parser=JSON.new()
		if parser.parse(FileAccess.get_file_as_string(path))!=OK:continue
		var data=parser.data
		if not data is Dictionary or not engine.restore(data):continue
		paused=false;autopilot=false;delay=1.8;presentation_delay=0;changed.emit(presentation_view())
		if suffix==".bak":notice.emit("主存档无法读取，已从上一手备份恢复。")
		return true
	notice.emit("存档无法读取。可以开始新对局，原存档备份仍会保留。")
	return false

func _save() -> void:
	if engine.state.is_empty(): return
	var save_path = storage_root + "current_match.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(storage_root))
	var temp = save_path + ".tmp"
	var file = FileAccess.open(temp, FileAccess.WRITE)
	if file == null: notice.emit("保存失败：请检查磁盘空间"); return
	file.store_string(JSON.stringify(engine.snapshot())); file.flush(); file.close()
	var absolute = ProjectSettings.globalize_path(save_path)
	if FileAccess.file_exists(save_path):
		DirAccess.copy_absolute(absolute, absolute + ".bak")
		DirAccess.remove_absolute(absolute)
	var error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), absolute)
	if error != OK: notice.emit("存档替换失败，临时文件仍已保存")

func export_replay() -> String:
	var path = "user://replays/round-%d-%d.json" % [engine.state.round, Time.get_unix_time_from_system()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://replays"))
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(engine.snapshot(), "  "))
		return ProjectSettings.globalize_path(path)
	return ""

func _join_worker() -> void:
	if worker != null:
		worker.wait_to_finish(); worker = null

func _exit_tree() -> void:
	_join_worker()
