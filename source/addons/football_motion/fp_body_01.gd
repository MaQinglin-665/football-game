extends RefCounted
## Setup-only mesh selection. No pose, camera, contact or per-frame operations.
const FPBody:=preload("res://addons/football_motion/assets/fp_body_01.res")
var originals:Dictionary={}

func apply(avatar,first_person:bool)->void:
	if not first_person and originals.is_empty():return
	for node in avatar.mesh_nodes:
		if String(node.name)!="BodyCore":continue
		var id:int=node.get_instance_id()
		if not originals.has(id):originals[id]=node.mesh
		var wanted:ArrayMesh=FPBody if first_person else originals[id]
		if node.mesh!=wanted:node.mesh=wanted
		if not node.visible:node.visible=true
		# Super.setup() already creates the current team palette. Reuse it.
		var cache:Dictionary=avatar._tint_cache[avatar._preset]
		for surface in node.mesh.get_surface_count():
			var name:String=node.mesh.surface_get_material(surface).resource_name
			if cache.has(name):node.set_surface_override_material(surface,cache[name])
