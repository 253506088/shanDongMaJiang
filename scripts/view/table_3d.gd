class_name Table3D
extends Node3D
signal tile_inspected(tile: int, screen_position: Vector2)
var camera: Camera3D
var pieces: Dictionary={}
var shadows: Dictionary={}
var used: Dictionary={}
var face_materials: Dictionary={}
var body_material: StandardMaterial3D
var back_material: StandardMaterial3D
var back_face_material: StandardMaterial3D
var cap_mesh: ArrayMesh
var base_mesh: ArrayMesh
var face_mesh: PlaneMesh
var shadow_mesh: PlaneMesh
var shadow_material: StandardMaterial3D
var count_label: Label3D
var round_label: Label3D
var head_marker: MeshInstance3D
var last_marker: MeshInstance3D
var last_revision=-1
var last_round=-1
var dice_nodes: Array=[]
var dice_faces: Array=[]
var dice_time=0.0
var seat_lights: Array=[]
var seat_labels: Array=[]
var courtyard_layer: CanvasLayer
const TILE_BATCH_CAPACITY=144
var tile_batches: Dictionary={}
var tile_tweens: Dictionary={}

func material(color: Color, metallic: float=0.0) -> StandardMaterial3D:
	var mat=StandardMaterial3D.new();mat.albedo_color=color
	mat.roughness=0.52;mat.metallic=metallic;mat.metallic_specular=0.28
	return mat

func rounded_box(width: float,height: float,depth: float,radius: float) -> ArrayMesh:
	return TileGeometry.rounded_box(width,height,depth,radius)

func round_plate(radius: float,height: float) -> CylinderMesh:
	var plate=CylinderMesh.new();plate.top_radius=radius;plate.bottom_radius=radius
	plate.height=height;plate.radial_segments=96
	return plate

func mesh_node(mesh: Mesh,mat: Material,pos: Vector3,parent: Node=null) -> MeshInstance3D:
	var node=MeshInstance3D.new();node.mesh=mesh;node.material_override=mat;node.position=pos
	(parent if parent!=null else self).add_child(node)
	return node

func _ready() -> void:
	_build_environment()
	_build_table()
	_build_tile_assets()
	_build_dice()

func _build_environment() -> void:
	_build_courtyard()
	var env=WorldEnvironment.new();env.environment=Environment.new()
	# Only the negative canvas layer is the 3D background. The playing HUD
	# remains on layer 1, so it is never drawn behind the physical table.
	env.environment.background_mode=Environment.BG_CANVAS
	env.environment.background_canvas_max_layer=-1
	env.environment.background_color=Color("182a26")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color("e6e7d8")
	env.environment.ambient_light_energy=0.44
	env.environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	add_child(env)
	var key=DirectionalLight3D.new();key.rotation_degrees=Vector3(-65,-32,0)
	key.light_color=Color("fff4df");key.light_energy=0.39;key.shadow_enabled=true
	key.directional_shadow_max_distance=40;key.shadow_bias=0.10;key.shadow_normal_bias=0.4;add_child(key)
	var fill=DirectionalLight3D.new();fill.rotation_degrees=Vector3(-42,132,0)
	fill.light_color=Color("c8e3d9");fill.light_energy=0.12;add_child(fill)
	# A long lens and a 67-degree elevation keep the far tiles legible and the
	# table comfortably open, without the distorted near edge of a low camera.
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_PERSPECTIVE;camera.fov=36
	camera.position=Vector3(0,23.5,10.6);add_child(camera);camera.look_at(Vector3(0,0,0.65));camera.current=true

func _build_courtyard() -> void:
	# A screen-aligned painting keeps the supplied perspective intact. A floor
	# plane would stretch it under the high table camera and hide the courtyard.
	courtyard_layer=CanvasLayer.new();courtyard_layer.layer=-1;add_child(courtyard_layer)
	var backdrop=TextureRect.new();backdrop.name="Courtyard"
	backdrop.texture=load("res://assets/backgrounds/courtyard_day.jpg")
	backdrop.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter=Control.MOUSE_FILTER_IGNORE;courtyard_layer.add_child(backdrop)
	# Bring the landscape into the same quiet, warm ambience as the table.
	# This tint leaves the painted leaves and joinery readable at the margins.
	var shade=Gradient.new()
	shade.set_color(0,Color("0d252366"));shade.set_color(1,Color("091e1db3"))
	shade.add_point(0.4,Color("0d25233d"))
	var gradient=GradientTexture2D.new();gradient.gradient=shade
	gradient.fill_from=Vector2(0.5,0);gradient.fill_to=Vector2(0.5,1)
	var veil=TextureRect.new();veil.texture=gradient
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter=Control.MOUSE_FILTER_IGNORE;courtyard_layer.add_child(veil)
	# CanvasLayer visibility does not inherit Node3D visibility automatically.
	visibility_changed.connect(func(): courtyard_layer.visible=is_visible_in_tree())
	courtyard_layer.visible=is_visible_in_tree()

func _build_table() -> void:
	# The contact shadow anchors the real table over the painted stone floor.
	var floor_shadow=material(Color("081912e0"))
	floor_shadow.albedo_texture=load("res://assets/textures/contact_shadow.png")
	floor_shadow.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	floor_shadow.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var floor_plane=PlaneMesh.new();floor_plane.size=Vector2(22.0,20.8)
	mesh_node(floor_plane,floor_shadow,Vector3(0.20,-0.70,0.38))
	mesh_node(rounded_box(17.08,0.39,15.74,0.52),material(Color("30291f")),Vector3(0,-0.24,0))
	var brass=material(Color("b6a075"),0.48);brass.roughness=0.43
	mesh_node(rounded_box(16.98,0.07,15.64,0.49),brass,Vector3(0,-0.075,0))
	var walnut=material(Color.WHITE,0.02);walnut.roughness=0.48;walnut.metallic_specular=0.28
	walnut.albedo_texture=mip_texture("res://assets/textures/walnut.png")
	walnut.uv1_triplanar=true;walnut.uv1_scale=Vector3(0.11,0.11,0.11)
	mesh_node(rounded_box(16.88,0.25,15.54,0.46),walnut,Vector3(0,-0.015,0))
	mesh_node(rounded_box(16.23,0.047,14.89,0.30),brass,Vector3(0,0.086,0))
	mesh_node(rounded_box(16.14,0.036,14.80,0.27),material(Color("142f28")),Vector3(0,0.092,0))
	var felt=material(Color.WHITE);felt.albedo_texture=mip_texture("res://assets/textures/felt_delivered.png")
	felt.roughness=1;felt.metallic_specular=0.08
	# A calibrated cloth pass plus per-tile contact shadows stays consistent on
	# GLES/desktop and avoids shadow-map acne from the closely inset rail layers.
	felt.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	felt.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	felt.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var surface=PlaneMesh.new();surface.size=Vector2(16.03,14.69)
	var cloth=mesh_node(surface,felt,Vector3(0,TableLayout.SURFACE_Y,0))
	cloth.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Small brass joinery accents sit within the timber, away from all tiles.
	for x in [-8.19,8.19]:
		for z in [-5.8,0,5.8]:
			mesh_node(rounded_box(0.025,0.010,0.18,0.010),brass,Vector3(x,0.112,z))
	for z in [-7.53,7.53]:
		for x in [-6.5,0,6.5]:
			mesh_node(rounded_box(0.18,0.010,0.025,0.010),brass,Vector3(x,0.112,z))
	# Keep the instrument inside the first discard rows, with enough room for
	# upright, readable winds instead of tiny text rotated away from the player.
	mesh_node(round_plate(1.075,0.10),material(Color("213d31")),Vector3(0,0.17,0))
	mesh_node(round_plate(1.045,0.060),brass,Vector3(0,0.225,0))
	mesh_node(round_plate(1.010,0.027),material(Color("4d6249"),0.12),Vector3(0,0.257,0))
	var display_mat=material(Color("123a32"));display_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_node(round_plate(0.975,0.018),display_mat,Vector3(0,0.272,0))
	count_label=label_3d("88",130,Vector3(0,0.289,0.035),Color("fff5d9"))
	round_label=label_3d("余牌",30,Vector3(0,0.290,-0.43),Color("d8dfca"))
	for seat in range(4):
		var pos=Vector3(0,0.291,0.79).rotated(Vector3.UP,seat*PI/2)
		var lab=label_3d(["东","南","西","北"][seat],60,pos,Color("d5dfcd"));seat_labels.append(lab)
		var led_mat=material(Color("425f48"));led_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		var led=mesh_node(rounded_box(0.36,0.012,0.032,0.012),led_mat,Vector3(0,0.288,1.005).rotated(Vector3.UP,seat*PI/2))
		led.rotation.y=seat*PI/2;seat_lights.append(led)
	var marker_mat=material(Color("c9b174"));marker_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var marker=PlaneMesh.new();marker.size=Vector2(0.61,0.83)
	head_marker=mesh_node(marker,marker_mat,Vector3.ZERO);head_marker.visible=false
	var last_plane=PlaneMesh.new();last_plane.size=Vector2(0.54,0.75)
	last_marker=mesh_node(last_plane,marker_mat,Vector3.ZERO);last_marker.visible=false

func _build_tile_assets() -> void:
	body_material=material(Color("f4f1e8"));body_material.roughness=0.30;body_material.metallic_specular=0.46
	back_material=material(Color("246c6c"));back_material.roughness=0.30;back_material.metallic_specular=0.36
	cap_mesh=rounded_box(0.515,0.23,0.735,0.062)
	base_mesh=rounded_box(0.52,0.11,0.74,0.065)
	face_mesh=PlaneMesh.new();face_mesh.size=Vector2(0.456,0.668)
	for tile in range(43):
		var face=material(Color("faf9f5"))
		face.albedo_texture=mip_texture(Tiles.texture_path(tile),tile<34)
		face.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		face.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		face_materials[tile]=face
	back_face_material=material(Color.WHITE)
	back_face_material.albedo_texture=mip_texture("res://assets/textures/tile_back.png")
	back_face_material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	back_face_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_mesh=PlaneMesh.new();shadow_mesh.size=Vector2(0.71,0.94)
	shadow_material=material(Color.WHITE);shadow_material.albedo_texture=load("res://assets/textures/contact_shadow.png")
	shadow_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_material.depth_draw_mode=BaseMaterial3D.DEPTH_DRAW_DISABLED
	# The Lotus renderer instances the repeated tile parts. Keep the same source
	# meshes and textures here, but submit one batch per material instead of five
	# draw calls per tile (plus their repeated directional-shadow passes).
	_tile_batch("base",base_mesh,back_material,true)
	_tile_batch("cap",cap_mesh,body_material,true)
	_tile_batch("back",face_mesh,back_face_material)
	_tile_batch("shadow",shadow_mesh,shadow_material)

func _tile_batch(key: String,mesh: Mesh,mat: Material,cast: bool=false) -> MultiMesh:
	if tile_batches.has(key):return tile_batches[key].multimesh
	var batch=MultiMeshInstance3D.new();batch.name="TileBatch_"+key
	batch.multimesh=MultiMesh.new();batch.multimesh.transform_format=MultiMesh.TRANSFORM_3D
	batch.multimesh.mesh=mesh;batch.multimesh.instance_count=maxi(TILE_BATCH_CAPACITY,pieces.size())
	batch.multimesh.visible_instance_count=0;batch.material_override=mat
	batch.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# All 144 physical pieces stay inside these table-local bounds, including the
	# short discard lift. Avoid recalculating a union every animated frame.
	batch.multimesh.custom_aabb=AABB(Vector3(-9,-1,-9),Vector3(18,4,18))
	add_child(batch);tile_batches[key]=batch
	return batch.multimesh

func _rebuild_tile_batches() -> void:
	# Real games have at most 144 physical tiles. Allow larger synthetic layout
	# fixtures without dropping instances; retain the allocation for later views.
	for batch in tile_batches.values():
		if pieces.size()>batch.multimesh.instance_count:
			batch.multimesh.instance_count=pieces.size()
	var counts={"base":pieces.size(),"cap":pieces.size(),"back":pieces.size(),"shadow":pieces.size()}
	var index=0
	for key in pieces:
		var piece=pieces[key];var tile=int(piece.get_meta("tile"))
		var face_key="face_%d"%tile
		_tile_batch(face_key,face_mesh,face_materials[tile] if tile>=0 else body_material)
		piece.set_meta("batch_index",index);piece.set_meta("face_batch",face_key)
		piece.set_meta("face_index",int(counts.get(face_key,0)))
		counts[face_key]=int(counts.get(face_key,0))+1;index+=1
		_sync_render_piece(key)
	for key in tile_batches:
		tile_batches[key].multimesh.visible_instance_count=int(counts.get(key,0))

func _sync_render_piece(key: String) -> void:
	var piece=pieces[key];var index=int(piece.get_meta("batch_index"))
	var model=piece.transform*piece.get_node("Model").transform
	tile_batches.base.multimesh.set_instance_transform(index,model*Transform3D(Basis.IDENTITY,Vector3(0,-0.115,0)))
	tile_batches.cap.multimesh.set_instance_transform(index,model*Transform3D(Basis.IDENTITY,Vector3(0,0.055,0)))
	tile_batches.back.multimesh.set_instance_transform(index,model*Transform3D(Basis(Vector3.RIGHT,PI),Vector3(0,-0.171,0)))
	tile_batches.shadow.multimesh.set_instance_transform(index,shadows[key].transform)
	tile_batches[piece.get_meta("face_batch")].multimesh.set_instance_transform(int(piece.get_meta("face_index")),model*Transform3D(Basis.IDENTITY,Vector3(0,0.171,0)))

func _animate_piece(position: Vector3,key: String) -> void:
	if not pieces.has(key):return
	pieces[key].position=position
	_sync_render_piece(key)

func _build_dice() -> void:
	for number in range(1,7):
		var image = Image.create(128,128,false,Image.FORMAT_RGBA8);image.fill(Color("f2ead5"))
		var positions = [[Vector2(64,64)], [Vector2(32,32),Vector2(96,96)], [Vector2(32,32),Vector2(64,64),Vector2(96,96)], [Vector2(32,32),Vector2(96,32),Vector2(32,96),Vector2(96,96)], [Vector2(32,32),Vector2(96,32),Vector2(64,64),Vector2(32,96),Vector2(96,96)], [Vector2(32,27),Vector2(96,27),Vector2(32,64),Vector2(96,64),Vector2(32,101),Vector2(96,101)]][number-1]
		for center in positions:
			for x in range(int(center.x)-12,int(center.x)+13):
				for y in range(int(center.y)-12,int(center.y)+13):
					if Vector2(x,y).distance_to(center)<11:image.set_pixel(x,y,Color("a03e32") if number in [1,4] else Color("254e40"))
		image.generate_mipmaps()
		var mat=material(Color.WHITE);mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mat.albedo_texture=ImageTexture.create_from_image(image)
		dice_faces.append(mat)
	for i in range(2):
		var die=Node3D.new();add_child(die);dice_nodes.append(die)
		var body=MeshInstance3D.new();body.mesh=rounded_box(0.43,0.43,0.43,0.04);body.material_override=body_material;die.add_child(body)
		for face in range(3):
			var quad=MeshInstance3D.new();var plane=PlaneMesh.new();plane.size=Vector2(0.405,0.405);quad.mesh=plane;quad.material_override=dice_faces[(i+face)%6]
			if face==0:quad.position.y=0.217
			elif face==1:quad.position.z=0.217;quad.rotation.x=PI/2
			else:quad.position.x=0.217;quad.rotation.z=-PI/2
			die.add_child(quad)


func mip_texture(path: String,crop_card: bool=false) -> Texture2D:
	var image=load(path).get_image()
	if crop_card: image=image.get_region(Rect2i(12,10,232,312))
	if path.ends_with(".svg"):
		var paper=Image.create(image.get_width(),image.get_height(),false,Image.FORMAT_RGBA8)
		paper.fill(Color("faf8ee"));image.convert(Image.FORMAT_RGBA8)
		paper.blend_rect(image,Rect2i(Vector2i.ZERO,image.get_size()),Vector2i.ZERO);image=paper
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func label_3d(text: String,size: int,pos: Vector3,color: Color) -> Label3D:
	var label=Label3D.new();label.font=UI.font(true);label.text=text;label.font_size=size;label.pixel_size=0.006
	label.modulate=color;label.outline_size=0;label.no_depth_test=false
	label.rotation.x=-PI/2;label.position=pos;add_child(label);return label

func _piece(key: String,tile: int,pos: Vector3,yaw: float=0,animate: bool=false,pose: String="face",scale_factor: float=1) -> void:
	used[key]=true
	var piece: Node3D
	if pieces.has(key): piece=pieces[key]
	else:
		piece=Node3D.new();add_child(piece);pieces[key]=piece
		var model=Node3D.new();model.name="Model";piece.add_child(model)
		# Lightweight transforms retain the existing picking and layout contract;
		# the visible geometry lives in the material batches above.
		var shadow=Node3D.new();add_child(shadow);shadows[key]=shadow
		piece.position=pos+Vector3(0,0.42,0) if animate else pos
	var model=piece.get_node("Model")
	model.rotation.x=PI/2 if pose=="standing" else (PI if pose=="back" else 0.0)
	piece.rotation.y=yaw;piece.scale=Vector3.ONE*scale_factor
	piece.set_meta("tile",tile);piece.set_meta("pose",pose)
	var shadow=shadows[key]
	shadow.position=Vector3(pos.x+0.04,TableLayout.SURFACE_Y+0.002,pos.z-0.05)
	shadow.rotation.y=yaw;shadow.scale=Vector3(scale_factor,1,scale_factor*(0.56 if pose=="standing" else 1.0))
	if tile_tweens.has(key):tile_tweens[key].kill();tile_tweens.erase(key)
	if animate and piece.position.distance_to(pos)>0.01:
		var tween=create_tween();tile_tweens[key]=tween
		tween.tween_method(_animate_piece.bind(key),piece.position,pos,0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.finished.connect(func():tile_tweens.erase(key))
	else: piece.position=pos

func tile_bounds(key: String) -> AABB:
	var piece=pieces[key]
	return piece.global_transform*piece.get_node("Model").transform*AABB(-TableLayout.TILE/2,TableLayout.TILE)

func update_view(view: Dictionary) -> void:
	used={}
	var animate=last_revision>=0 and view.revision!=last_revision and last_round==view.round
	last_revision=view.revision
	count_label.text=str(view.wall_count)
	for seat in range(4):
		var active=seat==view.decision_seat and view.phase!="settled"
		seat_labels[seat].text=["东","南","西","北"][(seat+int(view.get("local_seat",0)))%4]
		seat_lights[seat].material_override.albedo_color=Color("e6c981") if active else Color("425f48")
		seat_labels[seat].modulate=Color("ffdb8f") if active else Color("d5dfcd")
	if last_round!=view.round:
		last_round=view.round;dice_time=1.8 if view.revision==0 else 0.0
		for i in range(2):
			var die=dice_nodes[i];die.visible=dice_time>0
			# Resuming a played round must not roll over existing discards. At a
			# fresh opening, roll in the empty lower-left field, clear of the dial.
			if not die.visible:continue
			die.get_child(1).material_override=dice_faces[int(view.dice[i])-1]
			die.position=Vector3(-3.6 if i==0 else -2.9,1.4,2.4)
			die.rotation=Vector3(PI*3,PI*5,PI*2)
			var tween=create_tween().set_parallel()
			tween.tween_property(die,"position:y",TableLayout.SURFACE_Y+0.225,0.9).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			tween.tween_property(die,"rotation",Vector3(0,0.15,0),0.9)
	var slots: Array=view.get("wall_slots",[])
	if slots.size()!=view.wall_count: slots=range(144-view.wall_count,144) # synthetic view fixtures
	var tail=int(slots.back()) if not slots.is_empty() else -1
	for index in slots:
		var is_head=index==tail and view.gang_head>=0
		_piece("w%d"%index,view.gang_head if is_head else -1,TableLayout.wall(index,slots),-(index/36)*PI/2,false,"face" if is_head else "back")
	head_marker.visible=tail>=0 and view.gang_head>=0
	if head_marker.visible:
		var pos=TableLayout.wall(tail,slots)
		head_marker.position=Vector3(pos.x,TableLayout.SURFACE_Y+0.006,pos.z);head_marker.rotation.y=-(tail/36)*PI/2
	for p in view.players:
		var angle=p.seat*PI/2
		for i in range(p.discards.size()):
			_piece("d%d-%d"%[p.seat,i],p.discards[i],TableLayout.river(p.seat,i),angle,animate,"face",TableLayout.RIVER_SCALE)
		if p.seat!=0:
			var standing=p.hand.is_empty()
			for i in range(p.hand_count):
				_piece("h%d-%d"%[p.seat,i],-1 if standing else p.hand[i],TableLayout.hand(p.seat,i,p.hand_count,p.drawn,standing),angle,false,"standing" if standing else "face")
		var offset=0.0;var flowers=0
		for m in range(p.melds.size()):
			var meld=p.melds[m]
			if meld.type=="flower":
				_piece("f%d-%d"%[p.seat,flowers],meld.tile,TableLayout.flower(p.seat,flowers),angle,false,"face",0.65)
				flowers+=1;continue
			var called=-1 if meld.type=="angang" else [0,2,1,0][(int(meld.get("from",p.seat))-p.seat+4)%4]
			if meld.type=="chi": called=meld.tiles.find(meld.tile)
			var local_offset=0.0;var called_offset=0.0
			for j in range(meld.tiles.size()):
				var added=meld.get("added",false) and j==3
				var sideways=j==called or added
				var span=0.78 if sideways else 0.56
				var center=local_offset+(span-0.56)/2
				if j==called: called_offset=center
				var pos=TableLayout.meld(p.seat,offset+(called_offset if added else center),added)
				var hidden=meld.tiles[j]<0
				_piece("m%d-%d-%d"%[p.seat,m,j],meld.tiles[j],pos,angle+(PI/2 if sideways else 0),animate,"back" if hidden else "face")
				if not added: local_offset+=span
			offset+=local_offset+0.22
	for key in pieces.keys():
		if not used.has(key):
			if tile_tweens.has(key):tile_tweens[key].kill();tile_tweens.erase(key)
			pieces[key].queue_free();pieces.erase(key);shadows[key].queue_free();shadows.erase(key)
	_rebuild_tile_batches()
	last_marker.visible=not view.last_discard.is_empty()
	if last_marker.visible:
		var seat=int(view.last_discard.seat)
		last_marker.position=TableLayout.river(seat,view.players[seat].discards.size()-1)
		last_marker.position.y=TableLayout.SURFACE_Y+0.006;last_marker.rotation.y=seat*PI/2

func _process(delta: float) -> void:
	if dice_time>0:
		dice_time-=delta
		if dice_time<=0:
			for die in dice_nodes: die.visible=false

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT: return
	var origin=camera.project_ray_origin(event.position);var direction=camera.project_ray_normal(event.position)
	var nearest=INF;var tile=-1
	for key in pieces:
		var piece=pieces[key]
		if piece.get_meta("tile",-1)<0: continue
		var inverse=piece.get_node("Model").global_transform.affine_inverse()
		var hit=AABB(-TableLayout.TILE/2,TableLayout.TILE).intersects_ray(inverse*origin,inverse.basis*direction)
		if hit==null: continue
		var distance=origin.distance_to(piece.get_node("Model").global_transform*hit)
		if distance<nearest: nearest=distance;tile=piece.get_meta("tile")
	if tile>=0: tile_inspected.emit(tile,event.position)

func quality(low: bool) -> void:
	get_viewport().msaa_3d=Viewport.MSAA_DISABLED if low else Viewport.MSAA_4X
	for node in get_children():
		if node is DirectionalLight3D and node.light_energy>0.3: node.shadow_enabled=not low
