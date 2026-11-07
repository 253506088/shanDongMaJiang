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

func clip(key: String, speaker_profile: String = "") -> AudioStream:
	if speaker_profile.is_empty(): speaker_profile = profile
	var cache_key = speaker_profile + "/" + key
	if not clips.has(cache_key):
		var path = "res://assets/bluff/audio/%s/%s.wav" % [speaker_profile, key]
		if not ResourceLoader.exists(path): return null
		clips[cache_key] = load(path)
	return clips[cache_key]

func keys(view: Dictionary) -> Array:
	return calls(view).map(func(call):return call.key)

func calls(view: Dictionary) -> Array:
	var event: Dictionary = view.get("event", {})
	var result: Array = []
	var seat = int(event.get("seat", 0))
	match event.get("type", ""):
		"play": result = [{"key":"count_%d" % event.count,"seat":seat},{"key":"rank_%d" % event.rank,"seat":seat}]
		"pass": result = [{"key":"pass","seat":seat}]
		"challenge":
			# The opener speaks both the call and the revealed verdict.
			var caller = int(event.get("caller", 0))
			result = [{"key":"challenge","seat":caller},{"key":"truth" if event.truthful else "lie","seat":caller}]
		"dead": result = [{"key":"dead","seat":seat}]
	if event.get("report_seat", -1) >= 0 and view.get("phase", "") != "finished": result.append({"key":"report_three","seat":event.report_seat})
	if view.get("phase", "") == "finished":
		# Accepting a final declaration may retain its preceding play event.
		if view.get("finish_reason", "") == "accepted": result = []
		result.append({"key":"win","seat":int(view.get("winner",seat))})
	return result

func announce(view: Dictionary, silent: bool) -> float:
	var key = "%d/%d" % [view.get("round_id", 0), view.get("revision", -1)]
	if silent:
		last_key = key; stop_all(); return 0
	if key == last_key: return 0
	last_key = key
	for call in calls(view):
		var stream = clip(call.key, Characters.voice_for(view, call.seat, profile))
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
