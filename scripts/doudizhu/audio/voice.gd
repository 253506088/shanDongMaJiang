class_name DdzVoice
extends AudioStreamPlayer
## Offline speech owns its channel; another effect cannot cut off a card name.
const AUDIO_ROOT = "res://assets/doudizhu/audio/"
const COMBOS = ["triple_single", "triple_pair", "straight", "pair_chain", "airplane", "airplane_single", "airplane_pair", "four_two_single", "four_two_pair", "bomb", "rocket"]
var clips: Dictionary = {}
var queue: Array[AudioStream] = []
var last_key = ""
var profile: String = "male"
var _loaded_profile: String = ""
var gender_clips: Dictionary = {}

func _ready() -> void:
	volume_db = -3.0
	profile = "female" if profile == "female" else "male"
	_load_profile()
	finished.connect(_next)

func set_profile(value: String) -> void:
	var next = "female" if value == "female" else "male"
	if profile == next and (_loaded_profile == next or not is_node_ready()): return
	profile = next
	stop_all()
	# Retain last_key so a setting change cannot replay the previous action.
	if is_node_ready(): _load_profile()

func _load_profile() -> void:
	clips.clear()
	_loaded_profile = profile
	for rank_value in range(3, 18): _load_clip("single_%d" % rank_value)
	for rank_value in range(3, 16):
		_load_clip("pair_%d" % rank_value)
		_load_clip("triple_%d" % rank_value)
	for kind in COMBOS: _load_clip(kind)
	for value in range(4): _load_clip("bid_%d" % value)
	for key in ["pass", "redeal", "spring", "counter_spring"]: _load_clip(key)
	for count in range(1, 4): _load_clip("remaining_%d" % count)

func _load_clip(key: String) -> void:
	var path = AUDIO_ROOT + ("female/" if profile == "female" else "") + key + ".wav"
	if ResourceLoader.exists(path): clips[key] = load(path)

func clip_for(speaker_profile: String, key: String) -> AudioStream:
	if speaker_profile == profile: return clips.get(key)
	var cache_key = speaker_profile + "/" + key
	if not gender_clips.has(cache_key):
		var path = AUDIO_ROOT + ("female/" if speaker_profile == "female" else "") + key + ".wav"
		if not ResourceLoader.exists(path): return null
		gender_clips[cache_key] = load(path)
	return gender_clips[cache_key]

func clip_keys(view: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	var event: Dictionary = view.get("event", {})
	var type = str(event.get("type", ""))
	if type == "bid": keys.append("bid_%d" % int(event.get("value", 0)))
	elif type in ["pass", "redeal"]: keys.append(type)
	elif type == "play":
		var combo: Dictionary = event.get("combo", {})
		var kind = str(combo.get("kind", ""))
		if kind in ["single", "pair", "triple"]:
			keys.append("%s_%d" % [kind, int(combo.get("main", 3))])
		elif kind in COMBOS: keys.append(kind)
		var remaining = int(event.get("remaining", 0))
		if view.get("phase", "") == "playing" and remaining >= 1 and remaining <= 3:
			keys.append("remaining_%d" % remaining)
		if view.get("phase", "") == "finished":
			var spring = str(view.get("result", {}).get("spring", ""))
			if spring in ["spring", "counter_spring"]: keys.append(spring)
	return keys

func announce(view: Dictionary, silent: bool) -> float:
	var key = "%s/%s/%s" % [view.get("round_id", 0), view.get("deal", 0), view.get("revision", -1)]
	if silent:
		stop_all()
		last_key = key
		return 0.0
	if key == last_key: return 0.0
	last_key = key
	var added = false
	var speaker_profile = Characters.voice_for(view, int(view.get("event", {}).get("seat", 0)), profile)
	for clip_key in clip_keys(view):
		var spoken = clip_for(speaker_profile, clip_key)
		if spoken:
			queue.append(spoken)
			added = true
	var duration = maxf(0.0, stream.get_length() - get_playback_position()) if playing and stream else 0.0
	for clip in queue: duration += clip.get_length()
	if not playing: _next()
	return duration + 0.3 if added else 0.0

func _next() -> void:
	if queue.is_empty(): return
	stream = queue.pop_front()
	play()

func stop_all() -> void:
	stop()
	queue.clear()
	stream = null
