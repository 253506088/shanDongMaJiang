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
var head_label: Label3D
var head_marker: MeshInstance3D
var last_marker: MeshInstance3D
var last_revision=-1
var last_round=-1
var dice_nodes: Array=[]
var dice_faces: Array=[]
var dice_time=0.0
var seat_lights: Array=[]
var seat_labels: Array=[]

func material(color: Color, metallic: float=0.0) -> StandardMaterial3D:
	var mat=StandardMaterial3D.new();mat.albedo_color=color
	mat.roughness=0.52;mat.metallic=metallic;mat.metallic_specular=0.28
	return mat

func rounded_box(width: float,height: float,depth: float,radius: float) -> ArrayMesh:
	return TileGeometry.rounded_box(width,height,depth,radius)

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
	var env=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color("edf3f2")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color("e9f2f4")
	env.environment.ambient_light_energy=0.45
	env.environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	add_child(env)
	var key=DirectionalLight3D.new();key.rotation_degrees=Vector3(-65,-32,0)
	key.light_color=Color("fffaf1");key.light_energy=0.36;key.shadow_enabled=true
	key.directional_shadow_max_distance=40;key.shadow_bias=0.10;key.shadow_normal_bias=0.4;add_child(key)
	var fill=DirectionalLight3D.new();fill.rotation_degrees=Vector3(-42,132,0)
	fill.light_color=Color("dcebf0");fill.light_energy=0.10;add_child(fill)
	# A long lens and a 67-degree elevation keep the far tiles legible and the
	# table comfortably open, without the distorted near edge of a low camera.
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_PERSPECTIVE;camera.fov=36
	camera.position=Vector3(0,23.5,10.6);add_child(camera);camera.look_at(Vector3(0,0,0.65));camera.current=true

func _build_table() -> void:
	# Porcelain surround, brushed silver reveal, and a soft inset textile.
	# The dark teal seam gives the rail depth without a heavy black/gold slab.
	var floor_shadow=material(Color("43616f60"))
	floor_shadow.albedo_texture=load("res://assets/textures/contact_shadow.png")
	floor_shadow.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	floor_shadow.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var floor_plane=PlaneMesh.new();floor_plane.size=Vector2(20.8,19.6)
	mesh_node(floor_plane,floor_shadow,Vector3(0.12,-0.63,0.18))
	mesh_node(rounded_box(17.08,0.35,15.74,0.52),material(Color("32616b")),Vector3(0,-0.22,0))
	mesh_node(rounded_box(16.96,0.11,15.62,0.49),material(Color("bed6d6"),0.38),Vector3(0,-0.075,0))
	var lacquer=material(Color("e0e9e5"),0.05);lacquer.roughness=0.28
	mesh_node(rounded_box(16.82,0.25,15.48,0.45),lacquer,Vector3(0,-0.015,0))
	mesh_node(rounded_box(16.18,0.055,14.84,0.30),material(Color("346e77"),0.20),Vector3(0,0.085,0))
	var felt=material(Color.WHITE);felt.albedo_texture=mip_texture("res://assets/textures/felt.png")
	felt.roughness=1;felt.metallic_specular=0.08
	# A calibrated cloth pass plus per-tile contact shadows stays consistent on
	# GLES/desktop and avoids shadow-map acne from the closely inset rail layers.
	felt.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	felt.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	felt.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var surface=PlaneMesh.new();surface.size=Vector2(16.03,14.69)
	var cloth=mesh_node(surface,felt,Vector3(0,TableLayout.SURFACE_Y,0))
	cloth.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Flush teal rail inlays repeat the short marks on the centre instrument.
	for x in [-8.19,8.19]:
		for z in [-5.8,0,5.8]:
			mesh_node(rounded_box(0.035,0.016,0.24,0.012),material(Color("659da5"),0.25),Vector3(x,0.112,z))
	for z in [-7.53,7.53]:
		for x in [-6.5,0,6.5]:
			mesh_node(rounded_box(0.24,0.016,0.035,0.012),material(Color("659da5"),0.25),Vector3(x,0.112,z))
	mesh_node(rounded_box(2.02,0.10,1.98,0.20),material(Color("c4dcdb"),0.3),Vector3(0,0.17,0))
	mesh_node(rounded_box(1.92,0.06,1.88,0.16),material(Color("4b929a"),0.1),Vector3(0,0.23,0))
	var display_mat=material(Color("163c48"));display_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_node(rounded_box(1.79,0.018,1.75,0.12),display_mat,Vector3(0,0.269,0))
	count_label=label_3d("88",110,Vector3(0,0.289,0.02),Color("f3fcfa"))
	round_label=label_3d("余 牌",24,Vector3(0,0.290,-0.43),Color("9fc9cf"))
	for seat in range(4):
		var pos=Vector3(0,0.291,0.63).rotated(Vector3.UP,seat*PI/2)
		var lab=label_3d(["东","南","西","北"][seat],25,pos,Color("7ea0aa"));lab.rotation.y=seat*PI/2;seat_labels.append(lab)
		var led_mat=material(Color("47717a"));led_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		var led=mesh_node(rounded_box(0.56,0.012,0.035,0.016),led_mat,Vector3(0,0.287,0.80).rotated(Vector3.UP,seat*PI/2))
		led.rotation.y=seat*PI/2;seat_lights.append(led)
	var marker_mat=material(Color("ecb092"));marker_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var marker=PlaneMesh.new();marker.size=Vector2(0.61,0.83)
	head_marker=mesh_node(marker,marker_mat,Vector3.ZERO);head_marker.visible=false
	head_label=label_3d("杠头",25,Vector3.ZERO,Color("fff7eb"));head_label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;head_label.rotation=Vector3.ZERO
	head_label.outline_size=4;head_label.outline_modulate=Color("815b49");head_label.visible=false
	var last_plane=PlaneMesh.new();last_plane.size=Vector2(0.54,0.75)
	last_marker=mesh_node(last_plane,marker_mat,Vector3.ZERO);last_marker.visible=false

func _build_tile_assets() -> void:
	body_material=material(Color("f4f1e8"));body_material.roughness=0.30;body_material.metallic_specular=0.46
	back_material=material(Color("248d9a"));back_material.roughness=0.28;back_material.metallic_specular=0.38
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
	var label=Label3D.new();label.font=UI.font();label.text=text;label.font_size=size;label.pixel_size=0.006
	label.modulate=color;label.outline_size=0;label.no_depth_test=false
	label.rotation.x=-PI/2;label.position=pos;add_child(label);return label

func _piece(key: String,tile: int,pos: Vector3,yaw: float=0,animate: bool=false,pose: String="face",scale_factor: float=1) -> void:
	used[key]=true
	var piece: Node3D
	if pieces.has(key): piece=pieces[key]
	else:
		piece=Node3D.new();add_child(piece);pieces[key]=piece
		var model=Node3D.new();model.name="Model";piece.add_child(model)
		mesh_node(base_mesh,back_material,Vector3(0,-0.115,0),model)
		mesh_node(cap_mesh,body_material,Vector3(0,0.055,0),model)
		var front=mesh_node(face_mesh,body_material,Vector3(0,0.171,0),model);front.name="Face"
		var back=mesh_node(face_mesh,back_face_material,Vector3(0,-0.171,0),model);back.rotation.x=PI
		var shadow=mesh_node(shadow_mesh,shadow_material,Vector3.ZERO)
		shadow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;shadows[key]=shadow
		piece.position=pos+Vector3(0,0.42,0) if animate else pos
	var model=piece.get_node("Model")
	model.get_node("Face").material_override=face_materials[tile] if tile>=0 else body_material
	model.rotation.x=PI/2 if pose=="standing" else (PI if pose=="back" else 0.0)
	piece.rotation.y=yaw;piece.scale=Vector3.ONE*scale_factor
	piece.set_meta("tile",tile);piece.set_meta("pose",pose)
	var shadow=shadows[key]
	shadow.position=Vector3(pos.x+0.04,TableLayout.SURFACE_Y+0.002,pos.z-0.05)
	shadow.rotation.y=yaw;shadow.scale=Vector3(scale_factor,1,scale_factor*(0.56 if pose=="standing" else 1.0))
	if animate and piece.position.distance_to(pos)>0.01:
		create_tween().tween_property(piece,"position",pos,0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
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
		seat_lights[seat].material_override.albedo_color=Color("8ce2d5") if active else Color("3c6570")
		seat_labels[seat].modulate=Color("d1fff4") if active else Color("7ea0aa")
	if last_round!=view.round:
		last_round=view.round;dice_time=1.8
		for i in range(2):
			var die=dice_nodes[i];die.get_child(1).material_override=dice_faces[int(view.dice[i])-1]
			die.position=Vector3(-0.34 if i==0 else 0.34,1.6,0)
			die.rotation=Vector3(PI*3,PI*5,PI*2);die.visible=true
			var tween=create_tween().set_parallel()
			tween.tween_property(die,"position:y",0.50,0.9).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			tween.tween_property(die,"rotation",Vector3(0,0.15,0),0.9)
	var slots: Array=view.get("wall_slots",[])
	if slots.size()!=view.wall_count: slots=range(144-view.wall_count,144) # synthetic view fixtures
	var tail=int(slots.back()) if not slots.is_empty() else -1
	for index in slots:
		var is_head=index==tail and view.gang_head>=0
		_piece("w%d"%index,view.gang_head if is_head else -1,TableLayout.wall(index,slots),-(index/36)*PI/2,false,"face" if is_head else "back")
	head_marker.visible=tail>=0 and view.gang_head>=0;head_label.visible=head_marker.visible
	if head_marker.visible:
		var pos=TableLayout.wall(tail,slots)
		head_marker.position=Vector3(pos.x,TableLayout.SURFACE_Y+0.006,pos.z);head_marker.rotation.y=-(tail/36)*PI/2
		head_label.position=pos+Vector3(0,0.38,0.48).rotated(Vector3.UP,-(tail/36)*PI/2)
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
			pieces[key].queue_free();pieces.erase(key);shadows[key].queue_free();shadows.erase(key)
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
