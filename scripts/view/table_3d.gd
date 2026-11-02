class_name Table3D
extends Node3D
var camera: Camera3D
var pieces: Dictionary = {}
var used: Dictionary = {}
var face_materials: Dictionary = {}
var body_material: StandardMaterial3D
var body_mesh: ArrayMesh
var face_mesh: PlaneMesh
var count_label: Label3D
var round_label: Label3D
var last_revision = -1
var dice_nodes: Array = []
var dice_faces: Array = []
var last_round = -1

func material(color: Color, metallic: float = 0.0) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color; m.roughness = 0.65; m.metallic = metallic
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON; m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m

func rounded_box(width: float, height: float, depth: float, radius: float) -> ArrayMesh:
	var st = SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring: Array = []
	for corner in range(4):
		var center = Vector2((width / 2 - radius) * (1 if corner in [0, 3] else -1), (depth / 2 - radius) * (1 if corner in [0, 1] else -1))
		for step in range(7):
			var a = float(corner) * PI / 2 + float(step) / 6 * PI / 2
			ring.append(center + Vector2(cos(a), sin(a)) * radius)
	# Corners ordered around XZ; generate explicit normals for quiet flat faces.
	var rings = []
	for layer in range(4):
		var inset = 0.018 if layer in [0, 3] else 0.0
		var y = [-height/2, -height/2 + 0.018, height/2 - 0.018, height/2][layer]
		var row = []
		for p in ring: row.append(Vector3(p.x * (1 - inset / width * 2), y, p.y * (1 - inset / depth * 2)))
		rings.append(row)
	for layer in range(3):
		for i in range(ring.size()):
			var j = (i + 1) % ring.size()
			_triangle(st, rings[layer][i], rings[layer + 1][i], rings[layer + 1][j])
			_triangle(st, rings[layer][i], rings[layer + 1][j], rings[layer][j])
	for i in range(ring.size()):
		var j = (i + 1) % ring.size()
		_triangle(st, Vector3(0,height/2,0), rings[3][j], rings[3][i])
		_triangle(st, Vector3(0,-height/2,0), rings[0][i], rings[0][j])
	st.generate_normals()
	return st.commit()

func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.set_smooth_group(-1)
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)

func mesh_node(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var node = MeshInstance3D.new(); node.mesh = mesh; node.material_override = mat; node.position = pos
	add_child(node)
	return node

func _ready() -> void:
	var env = WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("0d2424")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("d5e4de")
	env.environment.ambient_light_energy = 0.42
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	add_child(env)
	var light = DirectionalLight3D.new(); light.rotation_degrees = Vector3(-58, -25, 0)
	light.light_color = Color("fff1d8"); light.light_energy = 0.72; light.shadow_enabled = true
	light.directional_shadow_max_distance = 35; light.shadow_bias = 0.08; add_child(light)
	var fill = DirectionalLight3D.new(); fill.rotation_degrees = Vector3(-35, 145, 0); fill.light_color = Color("9cd9ce"); fill.light_energy = 0.15; add_child(fill)
	camera = Camera3D.new(); camera.projection = Camera3D.PROJECTION_PERSPECTIVE; camera.fov = 38
	camera.position = Vector3(0, 14.8, 13); add_child(camera); camera.look_at(Vector3(0, 0, 0.4)); camera.current = true
	mesh_node(rounded_box(13.35, 0.5, 12.35, 0.5), material(Color("0b1918")), Vector3(0,-0.35,0))
	mesh_node(rounded_box(13.15, 0.09, 12.15, 0.46), material(Color("b99252"),0.6), Vector3(0,-0.055,0))
	mesh_node(rounded_box(12.99, 0.13, 11.99, 0.43), material(Color("143e34"),0.15), Vector3(0,0.02,0))
	mesh_node(rounded_box(12.58, 0.03, 11.58, 0.34), material(Color("93815b"),0.45), Vector3(0,0.1,0))
	var felt = StandardMaterial3D.new(); felt.albedo_texture = mip_texture("res://assets/textures/felt.png"); felt.roughness = 1.0; felt.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	felt.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var surface = PlaneMesh.new(); surface.size = Vector2(12.5, 11.5)
	mesh_node(surface, felt, Vector3(0,0.123,0))
	# Center medallion, readable without dominating the four discard rivers.
	var gold_disk = CylinderMesh.new(); gold_disk.top_radius = 0.95; gold_disk.bottom_radius = 0.95; gold_disk.height = 0.065; gold_disk.radial_segments = 64
	mesh_node(gold_disk, material(Color("b19758"),0.35), Vector3(0,0.16,0))
	var disk = CylinderMesh.new(); disk.top_radius = 0.91; disk.bottom_radius = 0.91; disk.height = 0.07; disk.radial_segments = 64
	mesh_node(disk, material(Color("123d34")), Vector3(0,0.18,0))
	count_label = label_3d("余牌", 92, Vector3(0,0.233,0.02), Color("f5db9d"))
	round_label = label_3d("青 玉 台", 28, Vector3(0,0.238,-0.52), Color("bdc8a6"))
	for i in range(4):
		var p = Vector3(0,0.239,0.68).rotated(Vector3.UP,i*PI/2)
		var lab = label_3d(["东","南","西","北"][i],28,p,Color("c3b478")); lab.rotation.y = i*PI/2
	body_material = material(Color("ccc6ae")); body_material.roughness = 0.65
	body_mesh = rounded_box(0.44,0.24,0.62,0.042)
	face_mesh = PlaneMesh.new(); face_mesh.size = Vector2(0.425,0.61)
	for tile in range(43):
		var face = StandardMaterial3D.new(); face.albedo_texture = mip_texture("res://assets/tiles/%02d.png" % tile)
		face.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		face.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR; face.roughness = 0.85; face.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		face_materials[tile] = face
	for number in range(1,7):
		var image = Image.create(128,128,false,Image.FORMAT_RGBA8);image.fill(Color("f2ead5"))
		var positions = [[Vector2(64,64)], [Vector2(32,32),Vector2(96,96)], [Vector2(32,32),Vector2(64,64),Vector2(96,96)], [Vector2(32,32),Vector2(96,32),Vector2(32,96),Vector2(96,96)], [Vector2(32,32),Vector2(96,32),Vector2(64,64),Vector2(32,96),Vector2(96,96)], [Vector2(32,27),Vector2(96,27),Vector2(32,64),Vector2(96,64),Vector2(32,101),Vector2(96,101)]][number-1]
		for center in positions:
			for x in range(int(center.x)-12,int(center.x)+13):
				for y in range(int(center.y)-12,int(center.y)+13):
					if Vector2(x,y).distance_to(center)<11:image.set_pixel(x,y,Color("a03e32") if number in [1,4] else Color("254e40"))
		image.generate_mipmaps()
		var mat=material(Color.WHITE);mat.albedo_texture=ImageTexture.create_from_image(image)
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

func mip_texture(path: String) -> Texture2D:
	var image = load(path).get_image()
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func label_3d(text: String, size: int, pos: Vector3, color: Color) -> Label3D:
	var label = Label3D.new(); label.font = UI.font()
	label.text = text; label.font_size = size; label.pixel_size = 0.006
	label.modulate = color; label.outline_size = 0; label.no_depth_test = false
	label.rotation.x = -PI/2; label.position = pos; add_child(label)
	return label

func _piece(key: String, tile: int, pos: Vector3, yaw: float = 0, animate: bool = false) -> void:
	used[key] = true
	var piece: Node3D
	if pieces.has(key): piece = pieces[key]
	else:
		piece = Node3D.new(); add_child(piece); pieces[key] = piece
		var body = MeshInstance3D.new(); body.mesh = body_mesh; body.material_override = body_material; piece.add_child(body)
		var face = MeshInstance3D.new(); face.mesh = face_mesh; face.position.y = 0.123; piece.add_child(face)
		piece.position = pos + Vector3(0,0.5,0) if animate else pos
	piece.get_child(1).material_override = face_materials[42 if tile < 0 else tile]
	piece.rotation.y = yaw
	if animate and piece.position.distance_to(pos) > 0.01:
		create_tween().tween_property(piece,"position",pos,0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else: piece.position = pos

func update_view(view: Dictionary) -> void:
	used = {}
	var revision = view.revision
	var animate = last_revision >= 0 and revision != last_revision
	last_revision = revision
	count_label.text = str(view.wall_count)
	round_label.text = "剩 余 牌"
	if last_round!=view.round:
		last_round=view.round
		for i in range(2):
			var die=dice_nodes[i]
			die.get_child(1).material_override=dice_faces[int(view.dice[i])-1]
			die.position=Vector3(-1.38 if i==0 else 1.38,1.65,0.2)
			die.rotation=Vector3(PI*3,PI*5,PI*2)
			var tween=create_tween().set_parallel()
			tween.tween_property(die,"position:y",0.365,0.85+i*0.15).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			tween.tween_property(die,"rotation",Vector3(0,0.23 if i==0 else -0.33,0),0.8+i*0.15)
	for index in range(144 - view.wall_count, 144):
		var side = index / 36
		var stack = (index % 36) / 2
		var position = Vector3((stack-8.5)*0.46, 0.265 + (index % 2)*0.245, 4.12).rotated(Vector3.UP,side*PI/2)
		_piece("w%d"%index,-1,position,side*PI/2)
	for p in view.players:
		var angle = p.seat*PI/2
		for i in range(p.discards.size()):
			var pos = Vector3((i%6-2.5)*0.465,0.255,1.47+(i/6)*0.645).rotated(Vector3.UP,angle)
			_piece("d%d-%d"%[p.seat,i],p.discards[i],pos,angle,animate)
		if p.seat != 0:
			for i in range(p.hand_count):
				var pos = Vector3((i-(p.hand_count-1)/2.0)*0.46,0.265,5.08).rotated(Vector3.UP,angle)
				var tile = p.hand[i] if not p.hand.is_empty() else -1
				_piece("h%d-%d"%[p.seat,i],tile,pos,angle)
		var offset = -4.6
		var flowers = 0
		for m in range(p.melds.size()):
			var meld = p.melds[m]
			if meld.type == "flower":
				var pos = Vector3(4.95,0.255,3.7-flowers*0.53).rotated(Vector3.UP,angle)
				_piece("f%d-%d"%[p.seat,flowers],meld.tile,pos,angle); flowers += 1
				continue
			for j in range(meld.tiles.size()):
				var pos = Vector3(offset+j*0.45,0.255,4.91).rotated(Vector3.UP,angle)
				_piece("m%d-%d-%d"%[p.seat,m,j],meld.tiles[j] if meld.type != "angang" or p.seat == 0 or view.phase == "settled" else -1,pos,angle,animate)
			offset += meld.tiles.size()*0.45+0.16
	for key in pieces.keys():
		if not used.has(key): pieces[key].queue_free(); pieces.erase(key)

func quality(low: bool) -> void:
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED if low else Viewport.MSAA_2X
	for node in get_children():
		if node is DirectionalLight3D and node.light_energy > 0.5: node.shadow_enabled = not low
