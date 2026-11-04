class_name DesktopWindow
extends Node
## Own desktop display state separately from gameplay and saved match data.
signal fullscreen_changed(enabled: bool)

const SETTLE_MSEC = 180
const ADJUSTMENT_FPS = 120
var supported = false
var preferred_fps = 60
var adjusting = false
var resizing = false
var adjustment_count = 0
var windowed_rect = Rect2i()
var return_mode = Window.MODE_WINDOWED
var _window: Window
var _last_position = Vector2i.ZERO
var _last_size = Vector2i.ZERO
var _last_change = 0
var _normal_scale_mode: Window.ContentScaleMode
var _normal_vsync: DisplayServer.VSyncMode

func _ready() -> void:
	_window = get_window()
	supported = OS.get_name() in ["Windows", "macOS", "Linux"] and DisplayServer.get_name() != "headless"
	if not supported:
		set_process(false)
		set_process_input(false)
		return
	_window.min_size = Vector2i(960, 540)
	_normal_scale_mode = _window.content_scale_mode
	_normal_vsync = DisplayServer.window_get_vsync_mode()
	_last_position = _window.position
	_last_size = _window.size
	windowed_rect = Rect2i(_last_position, _last_size)
	return_mode = _window.mode if _window.mode == Window.MODE_MAXIMIZED else Window.MODE_WINDOWED

func is_fullscreen() -> bool:
	return supported and _window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]

func set_fullscreen(enabled: bool) -> void:
	if not supported or enabled == is_fullscreen(): return
	_finish_adjustment()
	if enabled:
		return_mode = _window.mode if _window.mode == Window.MODE_MAXIMIZED else Window.MODE_WINDOWED
		if _window.mode == Window.MODE_WINDOWED:
			windowed_rect = Rect2i(_window.position, _window.size)
		# MODE_FULLSCREEN is the composited, borderless mode. Exclusive mode
		# would blank the display during task switching on some drivers.
		_window.mode = Window.MODE_FULLSCREEN
	else:
		_window.mode = Window.MODE_WINDOWED
		var area = DisplayServer.screen_get_usable_rect(_window.current_screen)
		# Godot's position/size describe the client area. Include the title bar
		# and borders when fitting a window after changing monitors.
		var inset = _window.position - _window.get_position_with_decorations()
		var decoration = _window.get_size_with_decorations() - _window.size
		var size = windowed_rect.size.min(area.size - decoration).max(_window.min_size)
		var outer_size = size + decoration
		var outer_position = windowed_rect.position - inset
		_window.size = size
		_window.position = Vector2i(
			clampi(outer_position.x, area.position.x, maxi(area.position.x, area.end.x - outer_size.x)),
			clampi(outer_position.y, area.position.y, maxi(area.position.y, area.end.y - outer_size.y))) + inset
		if return_mode == Window.MODE_MAXIMIZED: _window.mode = Window.MODE_MAXIMIZED
	_last_position = _window.position
	_last_size = _window.size
	fullscreen_changed.emit(enabled)

func set_frame_limit(fps: int) -> void:
	preferred_fps = fps
	if not adjusting: Engine.max_fps = fps

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_F11 or (event.keycode == KEY_ENTER and event.alt_pressed):
		set_fullscreen(not is_fullscreen())
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	# Windows runs Main::iteration inside its native move/size modal loop.
	# A frame-cap sleep or blocking swap there also stalls the window itself.
	# Detect BOTH position and size, and shorten those waits only during the
	# gesture. Keep a hard cap even then so other desktop apps retain resources.
	var position = _window.position
	var size = _window.size
	var size_changed = size != _last_size
	if position != _last_position or size_changed:
		_last_position = position
		_last_size = size
		if OS.get_name() == "Windows" and _window.mode == Window.MODE_WINDOWED:
			_last_change = Time.get_ticks_msec()
			if not adjusting:
				adjusting = true
				adjustment_count += 1
				_normal_vsync = DisplayServer.window_get_vsync_mode()
				Engine.max_fps = ADJUSTMENT_FPS
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			if size_changed and not resizing:
				resizing = true
				# Keep the 1600x900 canvas stable during live resize: avoids an
				# MSAA framebuffer allocation and font rerasterization per pixel.
				# Restore native-resolution canvas_items when the gesture settles.
				_window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	if adjusting and (Time.get_ticks_msec() - _last_change >= SETTLE_MSEC or _window.mode != Window.MODE_WINDOWED):
		_finish_adjustment()
	if not adjusting and _window.mode == Window.MODE_WINDOWED:
		windowed_rect = Rect2i(position, size)

func _finish_adjustment() -> void:
	if not adjusting: return
	if resizing: _window.content_scale_mode = _normal_scale_mode
	DisplayServer.window_set_vsync_mode(_normal_vsync)
	Engine.max_fps = preferred_fps
	adjusting = false
	resizing = false

func _exit_tree() -> void:
	_finish_adjustment()
