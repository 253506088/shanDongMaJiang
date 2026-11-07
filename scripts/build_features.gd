class_name BuildFeatures
extends RefCounted
## Source/editor runs keep LAN available for development. Exports opt in.

static func lan_enabled() -> bool:
	if OS.has_feature("offline"): return false
	return OS.has_feature("editor") or OS.has_feature("lan")
