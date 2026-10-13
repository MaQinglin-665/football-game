extends RefCounted
## Local GK-only overlay. Original mesh influence AABBs conservatively protect turf.
const PROFILE := "res://addons/football_keeper/dive_floor_profile.json"
const FLOOR_CLEARANCE := .015
const ROLL_RADIANS := 1.32
# Side dive leads with the arms. Forward pitch put the real torso capsule
# in front of the -.42 m hand plane and legitimately intercepted reachable balls.
# Keep the roll, floor protection and actual capsule; do not bypass body hits.
const PITCH_RADIANS := 0.0
const WRITES := ["root","hips","chest","neck","head","thigh.L","thigh.R","shin.L","shin.R","foot.L","foot.R","toe.L","toe.R"]
var avatar: Node3D
var skeleton: Skeleton3D
var driver: RefCounted
var bounds: Array[Dictionary] = []
var saved: Array[Dictionary] = []
var applied := false
var saved_visual := Transform3D.IDENTITY
var skeleton_to_visual := Transform3D.IDENTITY
var hip := Vector3.ZERO
var head := Vector3.ZERO
var hips_id := -1
var head_id := -1
var shoulder_ids: Dictionary = {}
var shoulders: Dictionary = {}
var arm_lengths: Dictionary = {}
var last_floor := INF
var floor_correction := 0.0
var samples := 0

func bind(view: Node3D, motion: RefCounted) -> bool:
	avatar = view
	driver = motion
	skeleton = avatar.skeleton
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE))
	if not parsed is Dictionary or skeleton.get_bone_count()!=32: return false
	skeleton_to_visual = avatar.visual.global_transform.affine_inverse()*skeleton.global_transform
	hips_id = skeleton.find_bone("hips")
	head_id = skeleton.find_bone("head")
	hip = skeleton_to_visual*skeleton.get_bone_global_rest(hips_id).origin
	head = skeleton_to_visual*skeleton.get_bone_global_rest(head_id).origin
	for row: Dictionary in parsed.bounds:
		var id := skeleton.find_bone(String(row.name))
		if id<0: return false
		bounds.append({"id":id,"rest":skeleton.get_bone_global_rest(id),"center":Vector3(row.center[0],row.center[1],row.center[2]),"half":Vector3(row.half[0],row.half[1],row.half[2])})
	for name in WRITES:
		var id := skeleton.find_bone(name)
		if id<0: return false
		saved.append({"id":id,"name":name,"position":Vector3.ZERO,"rotation":Quaternion.IDENTITY})
	for side in ["L","R"]:
		shoulder_ids[side] = skeleton.find_bone("upper_arm."+side)
		shoulders[side] = skeleton.get_bone_global_rest(int(shoulder_ids[side])).origin
		arm_lengths[side] = Vector2(skeleton.get_bone_pose_position(skeleton.find_bone("forearm."+side)).length(),skeleton.get_bone_pose_position(skeleton.find_bone("hand."+side)).length())
	return bounds.size()>0

func restore() -> void:
	if not applied or not is_instance_valid(skeleton): return
	for item: Dictionary in saved:
		skeleton.set_bone_pose_position(int(item.id),item.position)
		skeleton.set_bone_pose_rotation(int(item.id),item.rotation)
	avatar.visual.transform = saved_visual
	applied = false

func _low_y(transform: Transform3D, center: Vector3, half: Vector3) -> float:
	return (transform*center).y-absf(transform.basis.x.y)*half.x-absf(transform.basis.y.y)*half.y-absf(transform.basis.z.y)*half.z

func preview(origin: Vector3, basis: Basis, side: float, weight: float, crouch: float, ground_y: float) -> Transform3D:
	var rotation := Basis(Vector3.FORWARD,side*ROLL_RADIANS*weight)*Basis(Vector3.RIGHT,PITCH_RADIANS*weight)
	var transformed_basis := basis*rotation
	var desired_hip := origin-basis.x*side*.16*weight+Vector3.UP*(lerpf(hip.y,.30,weight)-.10*crouch)
	var result := Transform3D(transformed_basis,desired_hip-transformed_basis*hip)
	var floor_y := INF
	for item: Dictionary in bounds:
		floor_y = minf(floor_y,_low_y(result*skeleton_to_visual*(item.rest as Transform3D),item.center,item.half))
	result.origin.y += maxf(0.0,ground_y+FLOOR_CLEARANCE-floor_y)
	var torso: Dictionary = _torso(result*hip,result*head)
	result.origin.y += maxf(0.0,ground_y+.002-float(torso.bottom))
	return result

func can_reach(target: Vector3, actor_origin: Vector3, basis: Basis, side: float, weight: float, mode: String, radius: float, ground_y: float) -> bool:
	return predicted_hand_count(target,actor_origin,basis,side,weight,mode,radius,ground_y)>0

func predicted_hand_count(target: Vector3, actor_origin: Vector3, basis: Basis, side: float, weight: float, mode: String, radius: float, ground_y: float) -> int:
	var predicted := preview(actor_origin,basis,side,weight,0.0,ground_y)*skeleton_to_visual
	var count := 0
	for arm in ["L","R"]:
		if _arm_reaches(arm,predicted*(shoulders[arm] as Vector3),target,basis,mode,radius): count += 1
	return count

func standing_can_reach(target: Vector3, basis: Basis, mode: String, radius: float) -> bool:
	# Actual current shoulder origins: arm pose does not change them.
	for side in ["L","R"]:
		var shoulder := skeleton.global_transform*skeleton.get_bone_global_pose(int(shoulder_ids[side])).origin
		if _arm_reaches(side,shoulder,target,basis,mode,radius): return true
	return false

func _arm_reaches(side: String, shoulder: Vector3, target: Vector3, basis: Basis, mode: String, radius: float) -> bool:
	var sign_side := -1.0 if side=="L" else 1.0
	var spacing := .07 if mode=="parry" else radius+.039-.0001
	var rotation := basis if mode=="parry" else basis*Basis(Vector3.UP,sign_side*PI*.5)
	var wrist := target+basis.x*sign_side*spacing-rotation*Vector3(sign_side*.004,-.061,-.009)
	var lengths: Vector2 = arm_lengths[side]
	var distance := wrist.distance_to(shoulder)
	return distance>absf(lengths.x-lengths.y)+.006 and distance<lengths.x+lengths.y-.006

func apply() -> void:
	if not driver.active(): return
	if driver.central_block:
		_apply_central_block()
		return
	saved_visual = avatar.visual.transform
	for item: Dictionary in saved:
		item.position = skeleton.get_bone_pose_position(int(item.id))
		item.rotation = skeleton.get_bone_pose_rotation(int(item.id))
		if item.name=="root": skeleton.set_bone_pose_position(int(item.id),skeleton.get_bone_rest(int(item.id)).origin)
		var angle := 0.0
		if String(item.name).begins_with("thigh."): angle = -.35*driver.crouch_weight()+.12*driver.weight()
		elif String(item.name).begins_with("shin."): angle = .70*driver.crouch_weight()+.10*driver.weight()
		elif String(item.name).begins_with("foot."): angle = -.35*driver.crouch_weight()-.22*driver.weight()
		skeleton.set_bone_pose_rotation(int(item.id),Quaternion(Vector3.RIGHT,angle))
	applied = true
	avatar.visual.global_transform = preview(driver.actor.global_position,driver.facing_basis,driver.side,driver.weight(),driver.crouch_weight(),driver.ground_y)
	skeleton.force_update_all_bone_transforms()
	samples += 1
	enforce_floor()

func enforce_floor() -> float:
	if not applied: return 0.0
	last_floor = INF
	for item: Dictionary in bounds:
		var world := skeleton.global_transform*skeleton.get_bone_global_pose(int(item.id))
		last_floor = minf(last_floor,_low_y(world,item.center,item.half))
	floor_correction = maxf(0.0,driver.ground_y+FLOOR_CLEARANCE-last_floor)
	var torso: Dictionary = _actual_torso()
	floor_correction = maxf(floor_correction,driver.ground_y+.002-float(torso.bottom))
	if floor_correction>0.0:
		avatar.visual.global_position += Vector3.UP*floor_correction
		last_floor += floor_correction
	return floor_correction

func _torso(hips_world: Vector3, head_world: Vector3) -> Dictionary:
	var axis := (head_world-hips_world).normalized()
	var radius: float = driver.actor.profile.player_radius_m
	var height := clampf(hips_world.distance_to(head_world)+2.0*radius,2.0*radius,driver.actor.profile.player_height_m)
	var center := (hips_world+head_world)*.5
	var extent := radius+(height*.5-radius)*absf(axis.y)
	return {"axis":axis,"height":height,"center":center,"bottom":center.y-extent}

func _actual_torso() -> Dictionary:
	var hips_world := skeleton.global_transform*skeleton.get_bone_global_pose(hips_id).origin
	var head_world := skeleton.global_transform*skeleton.get_bone_global_pose(head_id).origin
	return _torso(hips_world,head_world)

func sync_volume() -> void:
	if not applied or not driver.owns_low_state(): return
	# Reuse the existing low capsule, align it with the actual tilted torso.
	var torso: Dictionary = _actual_torso()
	if not is_equal_approx(driver.actor.down_state.volume.shape.height,float(torso.height)):
		driver.actor.down_state.volume.shape.height = torso.height
	driver.actor.down_state.volume.global_transform = Transform3D(Basis(Quaternion(Vector3.UP,torso.axis)),torso.center)

func hold_target() -> Vector3:
	var a := skeleton.global_transform*skeleton.get_bone_global_pose(int(shoulder_ids.L)).origin
	var b := skeleton.global_transform*skeleton.get_bone_global_pose(int(shoulder_ids.R)).origin
	return (a+b)*.5+driver.facing_basis*Vector3(0,-.10,-.26)

func _apply_central_block()->void:
	saved_visual=avatar.visual.transform
	for item:Dictionary in saved:
		item.position=skeleton.get_bone_pose_position(int(item.id));item.rotation=skeleton.get_bone_pose_rotation(int(item.id))
	applied=true
	var w:float=driver.weight()
	# The generic low-state slide is replaced by this keeper-owned squat.
	avatar.visual.global_transform=Transform3D(driver.facing_basis,driver.actor.global_position)
	for item:Dictionary in saved:
		skeleton.set_bone_pose_position(int(item.id),skeleton.get_bone_rest(int(item.id)).origin)
		skeleton.set_bone_pose_rotation(int(item.id),Quaternion.IDENTITY)
	skeleton.set_bone_pose_position(hips_id,skeleton.get_bone_pose_position(hips_id)+Vector3.DOWN*driver.block_drop*w)
	skeleton.set_bone_pose_rotation(hips_id,Quaternion(Vector3.RIGHT,-.72*w))
	var chest_id:int=avatar.cached_bone_id("chest")
	skeleton.set_bone_pose_rotation(chest_id,skeleton.get_bone_pose_rotation(chest_id)*Quaternion(Vector3.RIGHT,-.18*w))
	skeleton.force_update_all_bone_transforms()
	var rotation:Quaternion=driver.facing_basis.get_rotation_quaternion()
	for side in ["L","R"]:
		var sign_side:float=-1.0 if side=="L" else 1.0
		var goal:Vector3=driver.actor.global_position+driver.facing_basis.x*sign_side*lerpf(.15,.26,w)
		goal.y=driver.ground_y+.006-avatar._minimum_offset(side,rotation)
		avatar._solve_leg(side,skeleton.to_local(goal),skeleton.global_basis.get_rotation_quaternion().inverse()*rotation,skeleton.global_basis.inverse()*(-driver.facing_basis.z))
	skeleton.force_update_all_bone_transforms()
	samples+=1
	enforce_floor()


