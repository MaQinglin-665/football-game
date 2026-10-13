extends RefCounted
## FP elbow/forearm/hand subset built once; the original GLB stays untouched.
static var mesh_cache:Dictionary={}
var originals:Dictionary={}

func apply(avatar,first_person:bool)->void:
	for node in avatar.mesh_nodes:
		var name:=String(node.name).replace("_",".")
		if not name.begins_with("RobotArm."):continue
		var instance:int=node.get_instance_id()
		if not originals.has(instance):originals[instance]=node.mesh
		var source:ArrayMesh=originals[instance]
		if not first_person:node.mesh=source;node.visible=true;continue
		var key:=str(source.get_instance_id())+name
		if not mesh_cache.has(key):mesh_cache[key]=subset(source,node.skin,avatar.skeleton)
		node.mesh=mesh_cache[key];node.visible=true
		node.extra_cull_margin=.55 # Raised hand leaves the standing rest-pose bounds.

func subset(source:ArrayMesh,skin:Skin,sk:Skeleton3D)->ArrayMesh:
	var result:=ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays:Array=source.surface_get_arrays(surface).duplicate(true)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var bones:PackedInt32Array=arrays[Mesh.ARRAY_BONES]
		var weights:PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
		var original_indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		var selected:=PackedByteArray();selected.resize(vertices.size())
		var influences:int=weights.size()/vertices.size()
		for v in vertices.size():
			for slot in influences:
				var k:=v*influences+slot
				if weights[k]<.25:continue
				var bind_id:=bones[k]
				var bone_name:=String(skin.get_bind_name(bind_id))
				if bone_name=="":bone_name=String(sk.get_bone_name(skin.get_bind_bone(bind_id)))
				if bone_name.begins_with("forearm.") or bone_name.begins_with("hand."):selected[v]=1
		var indices:=PackedInt32Array()
		for t in range(0,original_indices.size(),3):
			var a:=original_indices[t];var b:=original_indices[t+1];var c:=original_indices[t+2]
			if selected[a] and selected[b] and selected[c]:indices.append_array(PackedInt32Array([a,b,c]))
		if indices.is_empty():continue
		arrays[Mesh.ARRAY_INDEX]=indices
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		result.surface_set_material(result.get_surface_count()-1,source.surface_get_material(surface))
	result.custom_aabb=source.get_aabb()
	return result
