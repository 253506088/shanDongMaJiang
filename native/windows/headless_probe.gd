extends SceneTree
## Minimal extension-load probe: no scene, renderer frame or player storage.
func _initialize() -> void:
	print("NATIVE_HEADLESS_PROBE: initialized")
	quit()
