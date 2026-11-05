extends SceneTree
## Run as an external --script with the exported EXE so res:// is the PCK.
var failures: Array = []
var checks = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("DDZ PACKAGE FAIL: ", message)

func run() -> void:
	check(str(ProjectSettings.get_setting("application/config/version")) == "0.6.0", "package version")
	check(not FileAccess.file_exists("res://tests/doudizhu_package_test.gd"), "development tests are excluded")
	check(not FileAccess.file_exists("res://tools/import_doudizhu_audio.py"), "voice generator is excluded")
	check(FileAccess.file_exists("res://assets/licenses/doudizhu-voice-manifest.json"), "voice provenance ships with package")
	check(FileAccess.file_exists("res://assets/licenses/doudizhu-Apache-2.0.txt"), "complete voice license ships with package")
	check(FileAccess.file_exists("res://assets/licenses/doudizhu-cards-source.svg.txt"), "editable licensed card source ships with package")
	check(ResourceLoader.exists("res://assets/doudizhu/cards/53.png") and ResourceLoader.exists("res://assets/doudizhu/cards/back.png"), "traditional joker and back artwork ships with package")
	var engine_script = load("res://scripts/doudizhu/core/engine.gd")
	var ai = load("res://scripts/doudizhu/core/ai.gd")
	for seed_value in range(3):
		var engine = engine_script.new()
		engine.start(50110 + seed_value, seed_value)
		var moves = 0
		while engine.state.phase != "finished" and moves < 500:
			var seat = engine.state.turn
			check(engine.act(seat, ai.choose(engine.view(seat))), "packaged core accepts legal AI move")
			moves += 1
		check(engine.state.phase == "finished", "packaged AI completes a whole round")
		if engine.state.phase == "finished":
			check(engine.state.result.scores.reduce(func(total, score): return total + score, 0) == 0, "packaged score is zero sum")
	var app = load("res://scenes/main.tscn").instantiate()
	app.qa_mode = true
	root.add_child(app)
	app._open_doudizhu()
	await process_frame
	check(app.current_screen == "doudizhu" and app.session.paused and not app.table.visible, "packaged entry isolates Mahjong")
	check(app.doudizhu.table.hand_cards.size() == 17, "packaged table shows physical hand")
	check(app.doudizhu.table.recorder.counts.size() == 15 and app.doudizhu.table.recorder.total == 37, "packaged recorder includes undealt bottom without exposing hidden hands")
	check(app.doudizhu.voice.clips.size() == 60, "all sixty offline voice clips load from PCK")
	app.doudizhu.set_voice_profile("female")
	check(app.doudizhu.voice.profile == "female" and app.doudizhu.voice.clips.size() == 60, "female voice also loads completely from PCK")
	check(app.doudizhu.table.voice_profile_button.text == "女声报牌", "packaged voice picker reflects its selection")
	app.doudizhu.set_voice_profile("male")
	for clip in app.doudizhu.voice.clips.values():
		check(clip.get_length() >= 0.15 and clip.get_length() <= 8.0, "packaged speech is nonempty")
	app.doudizhu._leave()
	await process_frame
	check(app.current_screen == "lobby", "packaged return to lobby works")
	app.free()
	await process_frame
	print("DDZ_PACKAGE_RESULT: %d failures; %d checks" % [failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
