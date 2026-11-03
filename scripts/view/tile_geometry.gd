class_name TileGeometry
extends RefCounted
## Rounded XY silhouettes plus circular top/bottom bevels, with analytic normals.
## Unlike flat per-triangle normals, the highlight follows the entire curved edge.
static func rounded_box(width: float, height: float, depth: float, radius: float) -> ArrayMesh:
	var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bevel=minf(height*0.24,radius*0.60)
	var layers: Array=[]
	for i in range(5):
		var a=-PI/2+i*PI/8
		layers.append(Vector3(-height/2+bevel+sin(a)*bevel,bevel*(1-cos(a)),a))
	for i in range(5):
		var a=i*PI/8
		layers.append(Vector3(height/2-bevel+sin(a)*bevel,bevel*(1-cos(a)),a))
	var rings: Array=[]
	var normals: Array=[]
	for layer in layers:
		var ring: Array=[];var normal: Array=[]
		for corner in range(4):
			var center=Vector2((width/2-radius)*(1 if corner in [0,3] else -1),(depth/2-radius)*(1 if corner in [0,1] else -1))
			for step in range(9):
				var a=corner*PI/2+step*PI/16
				var radial=Vector2(cos(a),sin(a))
				var point=center+radial*(radius-layer.y)
				ring.append(Vector3(point.x,layer.x,point.y))
				normal.append(Vector3(radial.x*cos(layer.z),sin(layer.z),radial.y*cos(layer.z)))
		rings.append(ring);normals.append(normal)
	for layer in range(layers.size()-1):
		for i in range(36):
			var j=(i+1)%36
			_triangle(st,[rings[layer][i],rings[layer+1][i],rings[layer+1][j]],[normals[layer][i],normals[layer+1][i],normals[layer+1][j]])
			_triangle(st,[rings[layer][i],rings[layer+1][j],rings[layer][j]],[normals[layer][i],normals[layer+1][j],normals[layer][j]])
	for i in range(36):
		var j=(i+1)%36
		_triangle(st,[Vector3(0,height/2,0),rings[-1][j],rings[-1][i]],[Vector3.UP,Vector3.UP,Vector3.UP])
		_triangle(st,[Vector3(0,-height/2,0),rings[0][i],rings[0][j]],[Vector3.DOWN,Vector3.DOWN,Vector3.DOWN])
	st.index()
	return st.commit()

static func _triangle(st: SurfaceTool, vertices: Array, normals: Array) -> void:
	# Godot's front faces are clockwise. Keep each analytic normal attached to
	# its vertex while reversing winding, so the solid is viewed from outside.
	for i in [0,2,1]:
		st.set_normal(normals[i]);st.add_vertex(vertices[i])
