extends RefCounted
# Skeleton3D.get_bone_global_pose resolves dirty ancestors immediately (Godot 4.6).
# See source notes in delivery. Full publication at the host boundary serves rendering
# and native attachments; intermediate IK/contact queries always read current bones.
static var read_args:=false
static var verify:=false
static var calls:=0
static var checks:=0
static var max_error:=0.0
static func complete(sk:Skeleton3D)->void:
	if not read_args:verify="--verify-pose-flush" in OS.get_cmdline_user_args();read_args=true
	if not verify:
		sk.force_update_all_bone_transforms()
		return
	calls+=1
	var before:Array[Transform3D]=[]
	if calls%97==0 and checks<120:
		for i in sk.get_bone_count():before.append(sk.get_bone_global_pose(i))
	sk.force_update_all_bone_transforms()
	if not before.is_empty():
		checks+=1
		for i in before.size():
			var after:Transform3D=sk.get_bone_global_pose(i)
			max_error=maxf(max_error,before[i].origin.distance_to(after.origin))
			for axis in 3:max_error=maxf(max_error,before[i].basis[axis].distance_to(after.basis[axis]))
		if max_error>.00001:push_error("Deferred skeleton publication changed queried bone transform")
