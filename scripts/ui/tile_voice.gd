class_name TileVoice
extends AudioStreamPlayer
## Separate speech channel: click/notification effects never cut off a tile name.
var queue: Array = []
var clips: Dictionary = {}
var last_key = ""

func _ready() -> void:
	volume_db = -3
	for tile in range(34): clips[str(tile)] = load("res://assets/audio/voice/%02d.mp3" % tile)
	for action in ["chi","peng","gang","hu","zimo"]: clips[action] = load("res://assets/audio/voice/%s.mp3" % action)
	finished.connect(_next)

func announce(view: Dictionary, silent: bool) -> float:
	var key = "%s/%s" % [view.round,view.revision]
	if key == last_key: return 0
	last_key = key
	if silent: stop_all(); return 0
	var event = view.event
	var ids: Array = []
	if event.kind in ["discard","bao","ming"] and event.tile >= 0 and event.tile < 34:
		ids.append(str(event.tile))
	elif event.kind in ["chi","peng","gang","angang","bugang"]:
		ids.append("gang" if event.kind in ["gang","angang","bugang"] else event.kind)
	elif event.kind == "win":
		if view.last_discard.get("revision",-1) == view.revision: ids.append(str(view.last_discard.tile))
		ids.append("zimo" if view.result.get("win_type","") == "self-draw" else "hu")
	for id in ids:
		queue.append(clips[id])
	var duration = maxf(0,stream.get_length()-get_playback_position()) if playing else 0.0
	for clip in queue: duration += clip.get_length()
	if not playing: _next()
	return duration + 0.25 if not ids.is_empty() else 0.0

func _next() -> void:
	if queue.is_empty(): return
	stream = queue.pop_front(); play()

func stop_all() -> void:
	stop(); queue.clear()
