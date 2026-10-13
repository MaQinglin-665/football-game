extends RefCounted

# Truncated icosahedron: 12 black pentagons and 20 white hexagons.
static func make(radius: float) -> ArrayMesh:
	var phi := (1.0+sqrt(5.0))/2.0
	var vertices: Array[Vector3] = []
	for a in [-1.0,1.0]:
		for b in [-1.0,1.0]:
			vertices.append(Vector3(a,b*phi,0).normalized())
			vertices.append(Vector3(0,a,b*phi).normalized())
			vertices.append(Vector3(b*phi,0,a).normalized())
	var shortest := 100.0
	for i in range(vertices.size()):
		for j in range(i+1,vertices.size()):
			shortest = minf(shortest,vertices[i].distance_to(vertices[j]))
	var neighbors: Array[Array] = []
	for i in range(vertices.size()):
		var connected: Array[int] = []
		for j in range(vertices.size()):
			if i != j and absf(vertices[i].distance_to(vertices[j])-shortest) < 0.01:
				connected.append(j)
		neighbors.append(connected)
	var black := SurfaceTool.new()
	var white := SurfaceTool.new()
	var seams := SurfaceTool.new()
	seams.begin(Mesh.PRIMITIVE_TRIANGLES)
	black.begin(Mesh.PRIMITIVE_TRIANGLES)
	white.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(vertices.size()):
		var pentagon: Array[Vector3] = []
		for j in neighbors[i]:
			pentagon.append((vertices[i]*2+vertices[j]).normalized()*radius)
		face(black,seams,pentagon,radius)
	for a in range(vertices.size()):
		for b in neighbors[a]:
			if b <= a:
				continue
			for c in neighbors[a]:
				if c <= b or c not in neighbors[b]:
					continue
				var hexagon: Array[Vector3] = []
				for pair in [[a,b],[b,a],[b,c],[c,b],[c,a],[a,c]]:
					hexagon.append((vertices[pair[0]]*2+vertices[pair[1]]).normalized()*radius)
				face(white,seams,hexagon,radius)
	var black_material := ShaderMaterial.new()
	black_material.shader=preload("res://art/v1_scripts/baseline_ball.gdshader")
	black_material.set_shader_parameter("panel_color",Color("192d42"))
	var white_material := ShaderMaterial.new()
	white_material.shader=black_material.shader
	white_material.set_shader_parameter("panel_color",Color("eeeade"))
	var seam_material:=StandardMaterial3D.new()
	seam_material.albedo_color=Color("373c40");seam_material.roughness=.94
	black.set_material(black_material);white.set_material(white_material);seams.set_material(seam_material)
	black.generate_tangents();white.generate_tangents();seams.generate_tangents()
	var mesh := black.commit()
	white.commit(mesh);seams.commit(mesh)
	return mesh

static func face(surface:SurfaceTool,seams:SurfaceTool,points:Array[Vector3],radius:float)->void:
	var center:=Vector3.ZERO
	for point in points:center+=point
	center/=points.size()
	var normal:=center.normalized()
	var bx:Vector3=(points[0]-center).normalized()
	var by:Vector3=normal.cross(bx).normalized()
	points.sort_custom(func(a:Vector3,b:Vector3):return atan2((a-center).dot(by),(a-center).dot(bx))<atan2((b-center).dot(by),(b-center).dot(bx)))
	for i in range(points.size()):
		var a:Vector3=points[i];var b:Vector3=points[(i+1)%points.size()]
		var ia:Vector3=center.lerp(a,.982).normalized()*radius
		var ib:Vector3=center.lerp(b,.982).normalized()*radius
		patch(surface,center.normalized()*radius,ia,ib,radius,bx,by,center,4)
		patch(seams,ia,a.normalized()*(radius-.0012),b.normalized()*(radius-.0012),radius-.0009,bx,by,center,2)
		patch(seams,ia,b.normalized()*(radius-.0012),ib,radius-.0009,bx,by,center,2)
static func patch(surface:SurfaceTool,a:Vector3,b:Vector3,c:Vector3,radius:float,bx:Vector3,by:Vector3,center:Vector3,depth:int)->void:
	if depth>0:
		var ab:Vector3=(a+b).normalized()*radius;var bc:Vector3=(b+c).normalized()*radius;var ca:Vector3=(c+a).normalized()*radius
		patch(surface,a,ab,ca,radius,bx,by,center,depth-1);patch(surface,ab,b,bc,radius,bx,by,center,depth-1)
		patch(surface,ca,bc,c,radius,bx,by,center,depth-1);patch(surface,ab,bc,ca,radius,bx,by,center,depth-1)
		return
	for v in [a,c,b]:
		surface.set_normal(v.normalized());surface.set_uv(Vector2((v-center).dot(bx),(v-center).dot(by))/radius)
		surface.add_vertex(v)


