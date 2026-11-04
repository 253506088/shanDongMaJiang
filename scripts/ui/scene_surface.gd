class_name SceneSurface
extends SubViewportContainer
## Keep the expensive scene target independent of native WM_WINDOWPOSCHANGED.
## The outer Window draws just this texture while the user resizes it.
const DESIGN_SIZE = Vector2i(1600, 900)
const RESIZE_SETTLE_MSEC = 400
var scene_viewport: SubViewport
var resize_pending = false
var target_changes = 0
var _last_resize_msec = 0
var _window: Window

func _ready() -> void:
	_window = get_window()
	name = "SceneSurface"
	stretch = false
	mouse_filter = Control.MOUSE_FILTER_PASS
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	scene_viewport = SubViewport.new()
	scene_viewport.name = "SceneViewport"
	# BG_CANVAS on the table must never turn the outer window into a 3D target.
	scene_viewport.own_world_3d = true
	scene_viewport.size_2d_override = DESIGN_SIZE
	scene_viewport.size_2d_override_stretch = true
	scene_viewport.oversampling_override = 2.0
	scene_viewport.msaa_3d = _window.msaa_3d
	scene_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	scene_viewport.handle_input_locally = false
	_window.disable_3d = true
	_window.msaa_3d = Viewport.MSAA_DISABLED
	_window.msaa_2d = Viewport.MSAA_DISABLED
	# Stable glyph/DPI caches even when the final scene target changes once.
	_window.oversampling_override = 2.0
	add_child(scene_viewport)
	_apply_resolution()
	_window.size_changed.connect(_queue_resolution)

static func fit_resolution(window_size: Vector2i) -> Vector2i:
	var ratio = minf(float(window_size.x) / DESIGN_SIZE.x, float(window_size.y) / DESIGN_SIZE.y)
	return Vector2i(Vector2(DESIGN_SIZE) * maxf(ratio, 0.1))

func _queue_resolution() -> void:
	# This signal is synchronous with the native size callback. Do not allocate
	# scene buffers or rasterize text here, even during a burst of Windows events.
	_last_resize_msec = Time.get_ticks_msec()
	resize_pending = true

func _process(_delta: float) -> void:
	if resize_pending and Time.get_ticks_msec() - _last_resize_msec >= RESIZE_SETTLE_MSEC:
		_apply_resolution()

func _apply_resolution() -> void:
	var pixels = fit_resolution(_window.size)
	if scene_viewport.size != pixels:
		scene_viewport.size = pixels
		target_changes += 1
	# The container displays physical render pixels in the original 1600x900
	# input domain. Its built-in forwarding handles the viewport's 2D override.
	size = pixels
	scale = Vector2(DESIGN_SIZE) / Vector2(pixels)
	resize_pending = false
