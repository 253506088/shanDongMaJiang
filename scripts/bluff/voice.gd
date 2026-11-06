extends AudioStreamPlayer
## Local generated speech; public declarations only, no private card narration.
var queue: Array = []
var last_key = ""
var profile = "male"
var clips: Dictionary = {}

func _ready() -> void:
	volume_db = -3
	finished.connect(_next)

func set_profile(value: String) -> void:
	value = "female" if value == "female" else "male"
	if value == profile: return
	profile = value; stop_all(); clips.clear()

func clip(key: String) -> AudioStream:
	if not clips.has(key):
		var path = "res://assets/bluff/audio/%s/%s.wav" % [profile, key]
		if not ResourceLoader.exists(path): return null
		clips[key] = load(path)
	return clips[key]

func keys(view: Dictionary) -> Array:
	var event: Dictionary = view.get("event", {})
	var result: Array = []
	match event.get("type", ""):
		"play": result = ["count_%d" % event.count, "rank_%d" % event.rank]
		"pass": result = ["pass"]
		"challenge": result = ["challenge", "truth" if event.truthful else "lie"]
		"dead": result = ["dead"]
	if view.get("phase", "") == "finished":
		# Accepting a final declaration may retain its preceding play event.
		if view.get("finish_reason", "") == "accepted": result = []
		result.append("win")
	return result

func announce(view: Dictionary, silent: bool) -> float:
	var key = "%d/%d" % [view.get("round_id", 0), view.get("revision", -1)]
	if silent:
		last_key = key; stop_all(); return 0
	if key == last_key: return 0
	last_key = key
	for name in keys(view):
		var stream = clip(name)
		if stream: queue.append(stream)
	var length = maxf(0, stream.get_length() - get_playback_position()) if playing and stream else 0.0
	for item in queue: length += item.get_length()
	if not playing: _next()
	return length + 0.45

func _next() -> void:
	if queue.is_empty(): return
	stream = queue.pop_front(); play()

func stop_all() -> void:
	stop(); queue.clear(); stream = null

func _exit_tree() -> void:
	stop_all()
