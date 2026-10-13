class_name ShaderWarmup
extends Node
## R004: compile every material in the match once before kickoff by drawing tiny
## quads right in front of the active camera for a few frames, then freeing them.
## Avoids first-sight shader-compile hitches (GL Compatibility has no ubershader).
const FRAMES := 3
const QUAD_SIZE := 0.002
const MAX_MATERIALS := 512
var materials_warmed := 0
var usec := 0

static func collect(root: Node) -> Array[Material]:
	var seen := {}
	var out: Array[Material] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children(): stack.append(c)
		var mats: Array = []
		if n is GeometryInstance3D:
			mats.append(n.material_override)
			mats.append(n.material_overlay)
		if n is MeshInstance3D and n.mesh != null:
			for i in n.mesh.get_surface_count():
				mats.append(n.get_surface_override_material(i))
				mats.append(n.mesh.surface_get_material(i))
		elif n is MultiMeshInstance3D and n.multimesh != null and n.multimesh.mesh != null:
			for i in n.multimesh.mesh.get_surface_count(): mats.append(n.multimesh.mesh.surface_get_material(i))
		for m in mats:
			if m != null and not seen.has(m.get_rid()):
				seen[m.get_rid()] = true
				out.append(m)
				if out.size() >= MAX_MATERIALS: return out
	return out

func run(root: Node, camera: Camera3D) -> void:
	if camera == null or not is_instance_valid(camera): return
	var began := Time.get_ticks_usec()
	var holder := Node3D.new()
	holder.name = "ShaderWarmupQuads"
	camera.add_child(holder)
	holder.position = Vector3(0, 0, -camera.near * 2.0 - 0.01)
	var quad := QuadMesh.new()
	quad.size = Vector2(QUAD_SIZE, QUAD_SIZE)
	var mats := collect(root)
	for m in mats:
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
	materials_warmed = mats.size()
	for i in FRAMES: await get_tree().process_frame
	holder.queue_free()
	usec = Time.get_ticks_usec() - began
