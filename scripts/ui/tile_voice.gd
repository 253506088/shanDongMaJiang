class_name TileVoice
extends AudioStreamPlayer
## Separate speech channel: click/notification effects never cut off a tile name.
var queue: Array = []
var clips: Dictionary = {}
var last_key = ""

func _ready() -> void:
	volume_db = -3
	# Mahjong uses the predecessor's unchanged recordings for every character.
	for tile in range(34): clips[str(tile)] = load("res://assets/audio/voice/%02d.mp3" % tile)
	for action in ["chi","peng","gang","hu","zimo"]: clips[action] = load("res://assets/audio/voice/%s.mp3" % action)
	finished.connect(_next)

func clip_for(id: String) -> AudioStream:
	return clips.get(id)

func calls(view: Dictionary) -> Array:
	var event: Dictionary = view.get("event", {})
	var result: Array = []
	var seat = int(event.get("seat", 0))
	if event.get("kind", "") in ["discard","bao","ming"] and event.get("tile", -1) >= 0 and event.tile < 34:
		result.append({"key": str(event.tile), "seat": seat})
	elif event.get("kind", "") in ["chi","peng","gang","angang","bugang","tolerance_gang"]:
		result.append({"key": "gang" if event.kind in ["gang","angang","bugang","tolerance_gang"] else event.kind, "seat": seat})
	elif event.get("kind", "") == "win":
		if view.get("last_discard", {}).get("revision", -1) == view.revision:
			result.append({"key": str(view.last_discard.tile), "seat": int(view.last_discard.seat)})
		result.append({"key": "zimo" if view.result.get("win_type", "") == "self-draw" else "hu", "seat": seat})
	return result

func announce(view: Dictionary, silent: bool) -> float:
	var key = "%s/%s" % [view.round,view.revision]
	if key == last_key: return 0
	last_key = key
	if silent: stop_all(); return 0
	var speech = calls(view)
	for call in speech:
		queue.append(clip_for(call.key))
	var duration = maxf(0,stream.get_length()-get_playback_position()) if playing else 0.0
	for clip in queue: duration += clip.get_length()
	if not playing: _next()
	return duration + 0.25 if not speech.is_empty() else 0.0

func _next() -> void:
	if queue.is_empty(): return
	stream = queue.pop_front(); play()

func stop_all() -> void:
	stop(); queue.clear(); stream = null
