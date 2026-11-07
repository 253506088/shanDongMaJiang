extends SceneTree
## Standalone probe: --path build/windows --main-pack <absolute EXE>.
var checks=0
var failures: Array=[]
var app
var directory=""

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message);printerr("CHARACTERS PACKAGE FAIL: ",message)

func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless":return
	var args=OS.get_cmdline_user_args();var index=args.find("--capture-dir")
	if index<0:return
	for frame in range(4):await process_frame
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(args[index+1].path_join(name+".png"))==OK,"capture packaged role UI")

func run() -> void:
	Engine.max_fps=60
	directory="user://qa-characters-package-%d/"%Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	app=load("res://scenes/main.tscn").instantiate();app.qa_mode=true;app.preferences_path=directory+"preferences.json";root.add_child(app)
	app.session.set_process(false);app.session.storage_root=directory;app.muted=true
	check(ProjectSettings.get_setting("application/config/version")=="0.10.4","package version current")
	check(app.character_id=="female_03" and app.character_button.text=="角色 · 望舒","packaged app defaults to Wangshu")
	check(not FileAccess.file_exists("res://头像生成/avatar_02_male_18.jpg") and not FileAccess.file_exists("res://tools/prepare_character_art.py"),"raw images and preparation scripts excluded")
	for id in Characters.IDS:
		var avatar=load(Characters.info(id).avatar) as Texture2D
		check(avatar!=null and avatar.get_size()==Vector2(512,512),"packaged avatar decodes: "+id)
	var manifest=JSON.parse_string(FileAccess.get_file_as_string("res://assets/licenses/character-art-manifest.json"))
	check(manifest.pending_replacements.has("female_03") and manifest.pending_replacements.has("male_04"),"package retains explicit pending replacement map")
	for value in range(34):
		var clip=app.voice.clip_for(str(value))
		check(clip is AudioStreamMP3 and clip.resource_path=="res://assets/audio/voice/%02d.mp3"%value,"packaged Mahjong tile uses Lotus MP3")
	for action in ["chi","peng","gang","hu","zimo"]:
		check(app.voice.clip_for(action).resource_path=="res://assets/audio/voice/%s.mp3"%action,"packaged Mahjong action uses Lotus MP3")
	check(FileAccess.file_exists("res://assets/licenses/lotus-assets.json"),"original speech provenance ships")
	check(not ResourceLoader.exists("res://assets/audio/characters/male/00.wav") and not ResourceLoader.exists("res://assets/audio/characters/female/00.wav"),"inactive synthesized Mahjong voices excluded from package")
	AudioServer.set_bus_mute(0,true)
	for id in Characters.IDS:
		app.voice.stop_all()
		app.voice.announce({"round":1,"revision":Characters.IDS.find(id)+1,"characters":[id],"event":{"kind":"discard","tile":27,"seat":0}},false)
		check(app.voice.stream==app.voice.clip_for("27"),"packaged Mahjong keeps original voice for every role")
	app.voice.stop_all()
	app._show_character_picker();await capture("package-eight-roles");app._close_character_picker()
	app.qa_mode=false;app._set_character("female_02");app.qa_mode=true
	var prefs=JSON.parse_string(FileAccess.get_file_as_string(app.preferences_path))
	check(prefs.character_id=="female_02" and not prefs.has("doudizhu_voice") and not prefs.bluff_settings.has("voice"),"package writes role instead of independent voice settings")
	app.free();await process_frame
	app=load("res://scenes/main.tscn").instantiate();app.qa_mode=false;app.preferences_path=directory+"preferences.json";root.add_child(app)
	app.qa_mode=true;app.session.set_process(false);app.session.storage_root=directory
	check(app.character_id=="female_02","fresh packaged app restores role")
	app._open_doudizhu();app.doudizhu.session.set_process(false)
	check(Characters.voice_for(app.doudizhu.session.current_view(),0)=="female" and app.doudizhu.table.character_button.text=="角色 · 观澜","packaged DDZ uses cached role")
	await capture("package-ddz-character")
	app._show_lobby();await process_frame
	app._open_bluff();app.bluff.session.set_process(false)
	app.bluff.table.start_requested.emit({"players":6})
	check(app.bluff.session.current_view().characters[0]=="female_02" and not app.bluff.table.settings.has("voice"),"packaged bluff shares selected character")
	await capture("package-bluff-character")
	app._show_lobby();await process_frame
	app._start_game(false);app.session.set_process(false)
	var before=JSON.stringify(app.session.engine.snapshot())
	app._set_character("male_03")
	check(JSON.stringify(app.session.engine.snapshot())==before,"packaged role switch leaves Mahjong rules/save untouched")
	var view=Characters.decorate(app.session.engine.view(0),["male_03","male_03","male_03","male_03"])
	for seat in range(4):view.players[seat].name="我" if seat==0 else "玩家%d"%(seat+1)
	app._changed(view)
	var colors: Array=[]
	for seat in range(4):
		var portrait=app.players_ui[seat].portrait
		check(portrait.get_meta("character_id")=="male_03" and portrait.get_meta("border_color") not in colors,"packaged duplicate avatars keep distinct colors")
		colors.append(portrait.get_meta("border_color"))
	await capture("package-duplicate-borders")
	print("CHARACTERS_PACKAGE_RESULT: %d failures; %d checks"%[failures.size(),checks])
	call_deferred("finish",0 if failures.is_empty() else 1)

func finish(code: int) -> void:
	app.queue_free();app=null
	for frame in range(4):await process_frame
	RenderingServer.force_draw(false)
	await create_timer(.2).timeout
	for file in ["preferences.json","current_match.json","current_match.json.bak","current_match.json.tmp"]:
		var path=ProjectSettings.globalize_path(directory+file)
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
	quit(code)
