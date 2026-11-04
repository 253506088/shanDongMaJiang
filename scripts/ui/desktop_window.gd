class_name DesktopWindow
extends Node
## Own desktop display state separately from gameplay and saved match data.
signal fullscreen_changed(enabled: bool)

var supported = false
var preferred_fps = 60
var windowed_rect = Rect2i()
var return_mode = Window.MODE_WINDOWED
var _window: Window
var _normal_low_processor = false

func _ready() -> void:
	_window = get_window()
	supported = OS.get_name() in ["Windows", "macOS", "Linux"] and DisplayServer.get_name() != "headless"
	if not supported:
		set_process(false)
		set_process_input(false)
		return
	_window.min_size = Vector2i(960, 540)
	_normal_low_processor = OS.low_processor_usage_mode
	# Static UI/table frames need no GPU submission. Tweens and input still mark
	# the renderer dirty, so animations and interaction continue normally.
	OS.low_processor_usage_mode = true
	windowed_rect = Rect2i(_window.position, _window.size)
	return_mode = _window.mode if _window.mode == Window.MODE_MAXIMIZED else Window.MODE_WINDOWED

func is_fullscreen() -> bool:
	return supported and _window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]

func set_fullscreen(enabled: bool) -> void:
	if not supported or enabled == is_fullscreen(): return
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
	fullscreen_changed.emit(enabled)

func set_frame_limit(fps: int) -> void:
	preferred_fps = fps
	Engine.max_fps = fps

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_F11 or (event.keycode == KEY_ENTER and event.alt_pressed):
		set_fullscreen(not is_fullscreen())
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	# The native Windows bridge keeps Main::iteration out of modal movement.
	# Do not react after release by raising FPS or switching VSync again.
	if _window.mode == Window.MODE_WINDOWED:
		windowed_rect = Rect2i(_window.position, _window.size)

func _exit_tree() -> void:
	if supported: OS.low_processor_usage_mode = _normal_low_processor
