extends SceneTree
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var app=load("res://scenes/main.tscn").instantiate();app.qa_mode=true;root.add_child(app)
	for frame in range(6):await process_frame
	if app.character_id!=Characters.DEFAULT or app.current_screen!="lobby":
		printerr("CHARACTER launch mismatch");quit(1);return
	app._show_character_picker()
	for frame in range(3):await process_frame
	if not is_instance_valid(app.character_picker):printerr("CHARACTER picker missing");quit(1);return
	app._close_character_picker()
	print("CHARACTERS_LAUNCH_RESULT: 0 failures; default role, picker and window-close path")
	create_timer(5).timeout.connect(func():printerr("Character close watchdog");quit(1))
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
