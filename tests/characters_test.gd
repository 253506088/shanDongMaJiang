extends SceneTree
var checks=0
var failures: Array=[]

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message);printerr("CHARACTER FAIL: ",message)

func catalog_and_views() -> void:
	check(Characters.IDS.size()==8,"eight stable character IDs")
	check(Characters.IDS.filter(func(id):return Characters.info(id).gender=="male").size()==4,"four male characters")
	check(Characters.IDS.filter(func(id):return Characters.info(id).gender=="female").size()==4,"four female characters")
	check(Characters.DEFAULT=="female_03" and Characters.info(Characters.DEFAULT).name=="望舒","fresh preference defaults to Wangshu")
	check(Characters.default_for_seat(0)=="female_03","fallback local portrait also defaults to Wangshu")
	for bad in [null,1,true,[],{},"", "missing", "../portrait.png"]:
		check(Characters.normalize(bad)==Characters.DEFAULT,"invalid character falls back safely")
	for id in Characters.IDS:
		var data=Characters.info(id)
		check(ResourceLoader.exists(data.avatar),"delivered avatar exists: "+id)
		var texture=load(data.avatar) as Texture2D
		check(texture!=null and texture.get_size()==Vector2(512,512),"processed avatar decodes: "+id)
	check(Characters.info("female_03").temporary and Characters.info("male_04").temporary,"two correct slots remain marked temporary")
	var engine=GameEngine.new();engine.start({"field_rules":true,"field_selection":"mutation"},141007)
	var original=JSON.stringify(engine.snapshot())
	var ids=["male_01","female_01","male_01","female_01"]
	var colors: Array=[]
	for seat in range(4):colors.append(Characters.border(Characters.decorate(engine.view(seat),ids),seat))
	check(colors[0]!=colors[2] and colors[1]!=colors[3],"same characters have distinct seat borders")
	for local in range(4):
		var view=SeatView.for_seat(Characters.decorate(engine.view(local),ids),local)
		for relative in range(4):
			var absolute=(relative+local)%4
			check(Characters.at(view,relative)==ids[absolute],"avatar follows rotated player")
			check(Characters.border(view,relative)==colors[absolute],"border stays attached to absolute identity")
		check(Characters.voice_for(view,0)==Characters.info(ids[local]).gender,"voice follows rotated role")
	check(JSON.stringify(engine.snapshot())==original,"cosmetics do not mutate rules, score, pending moves or save")
	var session=LocalSession.new();session.engine=engine
	check(session.set_character("female_03") and session.presentation_view().characters[0]=="female_03","session decorates selected role")
	check(JSON.stringify(engine.snapshot())==original,"changing role leaves Mahjong save bytes unchanged")
	check(not session.set_character("missing") and session.character_id=="female_03","invalid change rejected atomically")
	session.free()

func portraits() -> void:
	var layer=Control.new();root.add_child(layer)
	for index in range(8):
		var portrait=UI.portrait(layer,Vector2(index*70,20),64,index,Characters.IDS[index])
		check(portrait.get_meta("character_id")==Characters.IDS[index] and portrait.texture!=null,"portrait receives exact selected resource")
	await process_frame
	layer.queue_free()
	await process_frame

func audio_routing() -> void:
	AudioServer.set_bus_mute(0,true)
	var ids=["male_01","female_01","male_02","female_02"]
	var voice=load("res://scripts/ui/tile_voice.gd").new();root.add_child(voice)
	for id in range(34):
		var clip=voice.clip_for(str(id))
		check(clip is AudioStreamMP3 and clip.get_length()>.15 and clip.resource_path=="res://assets/audio/voice/%02d.mp3"%id,"Mahjong tile uses original Lotus recording")
	for key in ["chi","peng","gang","hu","zimo"]:
		var clip=voice.clip_for(key)
		check(clip is AudioStreamMP3 and clip.get_length()>.15 and clip.resource_path=="res://assets/audio/voice/%s.mp3"%key,"Mahjong action uses original Lotus recording")
	var view={"round":1,"revision":1,"characters":ids.duplicate(),"event":{"kind":"discard","tile":0,"seat":0}}
	voice.announce(view,false);var first=voice.stream
	await process_frame
	view.revision=2;view.event.seat=1
	voice.announce(view,false)
	check(voice.stream==first and first==voice.clip_for("0") and voice.queue==[first],"male and female Mahjong actors queue the same original recording without interruption")
	view.characters[1]="male_03"
	check(voice.announce(view,false)==0 and voice.queue.size()==1,"same event never repeats after role refresh")
	voice.stop_all()
	view.revision=3;view.event={"kind":"win","seat":1};view.result={"win_type":"dihu"};view.last_discard={"revision":3,"tile":0,"seat":0}
	check(voice.calls(view).map(func(call):return call.seat)==[0,1],"discarder and winner retain distinct speaking identities")
	voice.announce(view,false)
	check(voice.stream==voice.clip_for("0") and voice.queue==[voice.clip_for("hu")],"discard and win keep original audio order")
	voice.stop_all();view.revision=4;view.result.win_type="self-draw"
	voice.announce(view,false)
	check(voice.stream==voice.clip_for("zimo"),"self-draw uses Lotus self-draw call")
	for id in Characters.IDS:
		voice.stop_all();view.revision+=1;view.characters[0]=id;view.event={"kind":"discard","tile":27,"seat":0}
		voice.announce(view,false)
		check(voice.stream==voice.clip_for("27"),"all eight Mahjong roles keep the same original East voice")
	view.revision+=1;voice.announce(view,true)
	check(voice.stream==null and voice.queue.is_empty() and not voice.playing,"Mahjong mute clears original voice queue")
	voice.free()
	var ddz=load("res://scripts/doudizhu/audio/voice.gd").new();root.add_child(ddz)
	var poker={"round_id":1,"deal":1,"revision":1,"characters":ids.slice(0,3),"phase":"playing","event":{"type":"play","seat":0,"remaining":3,"combo":{"kind":"single","main":3}}}
	ddz.announce(poker,false);first=ddz.stream
	await process_frame
	poker.revision=2;poker.event.seat=1;poker.event.remaining=2
	ddz.announce(poker,false)
	check(ddz.stream==first and ddz.queue.size()==3 and "/female/" in ddz.queue[1].resource_path and "/female/" in ddz.queue[2].resource_path,"DDZ rank and low-hand notice follow each actual actor")
	ddz.stop_all();ddz.set_profile("female");poker.revision=3;poker.event.seat=0
	ddz.announce(poker,false)
	check(not "/female/" in ddz.stream.resource_path,"legacy voice override cannot override a male character")
	ddz.stop_all();ddz.free()
	var bluff=load("res://scripts/bluff/voice.gd").new();root.add_child(bluff)
	var claim={"round_id":1,"revision":1,"phase":"playing","characters":ids,"event":{"type":"challenge","seat":0,"caller":1,"truthful":false,"report_seat":0}}
	check(bluff.calls(claim).map(func(call):return call.seat)==[1,1,0],"opener voices verdict; low-hand report belongs to its own player")
	bluff.announce(claim,false)
	check("/female/" in bluff.stream.resource_path and "/female/" in bluff.queue[0].resource_path and "/male/" in bluff.queue[1].resource_path,"bluff can queue both genders in one event")
	bluff.stream_paused=true;check(bluff.stream_paused,"pause keeps queued speaker order")
	bluff.announce({"round_id":1,"revision":2},true)
	check(not bluff.playing and bluff.queue.is_empty(),"mute clears all queued speakers")
	bluff.free()
	await create_timer(.15).timeout

func run() -> void:
	Engine.max_fps=60
	catalog_and_views()
	print("Character catalog and rules isolation checked")
	await portraits()
	print("Character portrait lifecycle checked")
	await audio_routing()
	print("CHARACTERS_RESULT: %d failures; %d checks"%[failures.size(),checks])
	call_deferred("quit",0 if failures.is_empty() else 1)
