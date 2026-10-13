extends RefCounted
## One surface per named material. Clockwise indices face their supplied normals.
var vertices := PackedVector3Array()
var normals := PackedVector3Array()
var uvs := PackedVector2Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()

func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv_scale := Vector2.ONE, tint := Color.WHITE) -> void:
	var offset := vertices.size()
	var normal := (b - a).cross(c - a).normalized()
	if normal.is_zero_approx(): normal=(c-a).cross(d-a).normalized()
	vertices.append_array(PackedVector3Array([a, b, c, d]))
	for i in range(4):
		normals.append(normal)
		colors.append(tint)
	uvs.append_array(PackedVector2Array([Vector2.ZERO, Vector2(uv_scale.x, 0), uv_scale, Vector2(0, uv_scale.y)]))
	indices.append_array(PackedInt32Array([offset, offset + 2, offset + 1, offset, offset + 3, offset + 2]))

func top_rect(x0: float, x1: float, z0: float, z1: float, y: float, tint := Color.WHITE) -> void:
	quad(Vector3(x0,y,z0), Vector3(x0,y,z1), Vector3(x1,y,z1), Vector3(x1,y,z0), Vector2(absf(x1-x0), absf(z1-z0)), tint)

func box(size: Vector3, center: Vector3, basis := Basis.IDENTITY, tint := Color.WHITE) -> void:
	var h := size * 0.5
	var p: Array[Vector3] = []
	for v in [Vector3(-h.x,-h.y,-h.z),Vector3(h.x,-h.y,-h.z),Vector3(h.x,h.y,-h.z),Vector3(-h.x,h.y,-h.z),Vector3(-h.x,-h.y,h.z),Vector3(h.x,-h.y,h.z),Vector3(h.x,h.y,h.z),Vector3(-h.x,h.y,h.z)]:
		p.append(basis * v + center)
	for f in [[0,3,2,1],[4,5,6,7],[0,4,7,3],[1,2,6,5],[3,7,6,2],[0,1,5,4]]:
		quad(p[f[0]],p[f[1]],p[f[2]],p[f[3]],Vector2.ONE,tint)

func rod(a: Vector3, b: Vector3, radius: float, sides := 6) -> void:
	var axis := (b-a).normalized()
	var guide := Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT
	var u := axis.cross(guide).normalized()
	var v := axis.cross(u).normalized()
	for i in range(sides):
		var p := u * cos(TAU*i/sides) * radius + v * sin(TAU*i/sides) * radius
		var q := u * cos(TAU*(i+1)/sides) * radius + v * sin(TAU*(i+1)/sides) * radius
		quad(a+p,a+q,b+q,b+p)

func ring(cx: float, cz: float, outer_radius: float, width: float, y: float, start: float, end: float, segments: int) -> void:
	for i in range(segments):
		var a := lerpf(start,end,float(i)/segments)
		var b := lerpf(start,end,float(i+1)/segments)
		var inn := outer_radius-width
		quad(Vector3(cx+cos(a)*inn,y,cz+sin(a)*inn), Vector3(cx+cos(b)*inn,y,cz+sin(b)*inn), Vector3(cx+cos(b)*outer_radius,y,cz+sin(b)*outer_radius), Vector3(cx+cos(a)*outer_radius,y,cz+sin(a)*outer_radius))

func smooth_rod(a: Vector3, b: Vector3, radius: float, sides := 6) -> void:
	var axis := (b-a).normalized()
	var guide := Vector3.UP if absf(axis.y)<.95 else Vector3.RIGHT
	var u := axis.cross(guide).normalized()
	var v := axis.cross(u).normalized()
	for i in range(sides):
		var p := u*cos(TAU*i/sides)+v*sin(TAU*i/sides)
		var q := u*cos(TAU*(i+1)/sides)+v*sin(TAU*(i+1)/sides)
		var offset := vertices.size()
		vertices.append_array(PackedVector3Array([a+p*radius,a+q*radius,b+q*radius,b+p*radius]))
		normals.append_array(PackedVector3Array([p,q,q,p]))
		uvs.append_array(PackedVector2Array([Vector2.ZERO,Vector2(1,0),Vector2.ONE,Vector2(0,1)]))
		for j in range(4): colors.append(Color.WHITE)
		indices.append_array(PackedInt32Array([offset,offset+2,offset+1,offset,offset+3,offset+2]))

func disk(x: float, z: float, radius: float, y: float, segments := 24) -> void:
	# Thin annular quads with inner radius zero are valid single triangles after culling.
	ring(x,z,radius,radius,y,0.0,TAU,segments)

func mesh(material: Material = null) -> ArrayMesh:
	var result := ArrayMesh.new()
	if vertices.is_empty(): return result
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	if material: result.surface_set_material(0,material)
	return result
