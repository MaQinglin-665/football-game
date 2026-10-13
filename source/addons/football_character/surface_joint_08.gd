extends RefCounted
## One pose-only surface/ankle/knee policy. No actor/ball/input/timer writes.
var mode:="B"

func _init()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--joint-foot08="):
			var selected:String=arg.trim_prefix("--joint-foot08=").to_upper()
			if selected in ["A","B"]:mode=selected

func eligible(avatar,side:String,surface:String)->bool:
	var action:Dictionary=avatar._action
	if avatar.has_method("_update_support") and not bool(avatar._grounded):return false
	if avatar.has_method("get_full_body_debug"):
		var interaction:Dictionary=avatar._motion_state.get("interaction",{})
		if bool(interaction.get("mobility_busy",false)) or bool(interaction.get("airborne",false)) or float(interaction.get("crouch",0.0))>0 or float(interaction.get("header_weight",0.0))>0:return false
	return mode=="B" and String(action.get("kind","")).to_upper() in ["CARRY","CLOSE","TURN","SPRINT"] and surface in ["INSIDE","OUTSIDE"] and side==avatar.side_suffix(int(action.get("side",1)))

func envelope(avatar)->float:
	var nt:float=clampf(float(avatar._action.get("normalized_time",0)),0,1)
	return smoothstep(0,.45,nt)*(1.0-smoothstep(.65,1.0,nt))

func surface_direction(avatar,fallback:Vector3)->Vector3:
	var supplied:Variant=avatar._action.get("contact_surface_direction",null)
	var wanted:Vector3=supplied if supplied is Vector3 else fallback
	if not supplied is Vector3:
		var actor:Node=avatar.get_parent()
		if actor!=null and actor.has_method("get_ball_direction"):
			var foot:RefCounted=actor.get("foot") as RefCounted
			if is_instance_valid(foot) and int(foot.get("sequence"))==int(avatar._action.get("sequence",-1)):
				# Same requested sphere side as current FootAction.ball_surface:
				# aim/bias is distinct from the shoe heading during a lateral TURN.
				wanted=foot.get("direction")
				var bias:Vector3=foot.get("bias")
				if bias.length()>.2 and not String(foot.get("kind")).to_upper() in ["PASS","SHOT","TACKLE"]:wanted=Vector3(bias.x,0,bias.z)
	wanted.y=0
	return wanted.normalized() if wanted.length_squared()>.00001 else Vector3.FORWARD

func rotation(avatar,side:int,surface:String,target:Vector3,world_heading:Vector3)->Quaternion:
	var direction:Vector3=avatar.skeleton.global_basis.inverse()*world_heading
	direction.y=0
	if direction.length_squared()<.00001:direction=Vector3.FORWARD
	var yaw:float=atan2(-direction.x,-direction.z)
	var side_sign:float=-1.0 if side<=0 else 1.0
	var passing:bool=String(avatar._action.get("kind",""))=="PASS"
	if surface=="INSIDE":yaw-=side_sign*(1.05 if passing else .64)
	elif surface=="OUTSIDE":yaw+=side_sign*(.55 if passing else .32)
	var pitch:float=(.40 if target.y>avatar.global_position.y+.035 else 0.0) if surface=="SOLE" else -.03 if surface=="INSTEP" else 0.0
	var legacy:Quaternion=Quaternion(Vector3.UP,yaw)*Quaternion(Vector3.RIGHT,pitch)
	var suffix:String=avatar.side_suffix(side)
	if not eligible(avatar,suffix,surface):return legacy
	var socket:String="contact_"+String(avatar.SURFACES[surface])+"."+suffix
	var normal:Vector3=avatar._socket_normals.get(socket,Vector3.FORWARD)
	var desired:Vector3=avatar.skeleton.global_basis.inverse()*surface_direction(avatar,world_heading)
	desired.y=0
	var current:Vector3=legacy*normal
	current.y=0
	if current.length_squared()<.00001 or desired.length_squared()<.00001:return legacy
	var correction:float=current.normalized().signed_angle_to(desired.normalized(),Vector3.UP)
	var load:float=envelope(avatar)
	# Restrict the extra opening, so a centrally placed ball does not demand
	# a 90-degree crossed-leg pose merely to make the normal perfectly parallel.
	yaw+=clampf(correction,-.24,.24)*load
	# Raise the selected outside edge with a small ankle inversion; inside
	# uses a much smaller opposing roll. The true socket/sole geometry is used.
	var roll:float=side_sign*(.12 if surface=="OUTSIDE" else -.035)*load
	return Quaternion(Vector3.UP,yaw)*Quaternion(Vector3.RIGHT,pitch)*Quaternion(Vector3.BACK,roll)

func pole_direction(avatar,side:String,foot_rotation:Quaternion,body_direction:Vector3)->Vector3:
	var surface:String=String(avatar._action.get("surface","")).to_upper()
	if not eligible(avatar,side,surface):return body_direction
	var body:Vector3=body_direction
	if is_instance_valid(avatar.visual):body=avatar.skeleton.global_basis.inverse()*(-avatar.visual.global_basis.z)
	body.y=0
	if body.length_squared()<.00001:body=Vector3.FORWARD
	body=body.normalized()
	var shoe:Vector3=foot_rotation*Vector3.FORWARD
	shoe.y=0
	if shoe.length_squared()<.00001:return body
	# Mostly anatomical/body-forward, modestly toe-forward; never flip a knee
	# just because the intended ball direction reversed behind the body.
	return body.lerp(shoe.normalized(),(.28 if surface=="INSIDE" else .18)*envelope(avatar)).normalized()

func support_ready(avatar,active:String)->bool:
	if not avatar.has_method("_update_support"):return false
	var support:String="R" if active=="L" else "L"
	var plant:Dictionary=avatar._plants.get(support,{})
	if plant.is_empty() or bool(plant.get("releasing",false)):return false
	var previous:Dictionary=avatar._last_ankles.get(support,{})
	if not previous.get("point") is Vector3 or not previous.get("rotation") is Quaternion:return false
	var sole_y:float=(previous.point as Vector3).y+avatar._minimum_offset(support,previous.rotation)
	return absf(sole_y-float(avatar._ground_y))<=.012

func knee_margin(avatar,side:String,surface:String)->float:
	if not eligible(avatar,side,surface) or not support_ready(avatar,side):return .012
	# Same bounded pelvis-transfer solver, 6mm extra reserve only with a real
	# existing support. No imposed knee angle, forced plant or enlarged reach.
	return .012+.006*envelope(avatar)

func snapshot(avatar)->Dictionary:
	var sk:Skeleton3D=avatar.skeleton
	if not is_instance_valid(sk):return {"mode":mode,"ready":false}
	var surface:String=String(avatar._action.get("surface","INSIDE")).to_upper()
	var wanted:Vector3=surface_direction(avatar,avatar._action.get("direction",Vector3.FORWARD))
	var feet:Dictionary={}
	for side in [-1,1]:
		var suffix:String=avatar.side_suffix(side)
		var hip:Vector3=sk.to_global(sk.get_bone_global_pose(sk.find_bone("thigh."+suffix)).origin)
		var knee:Vector3=sk.to_global(sk.get_bone_global_pose(sk.find_bone("shin."+suffix)).origin)
		var ankle:Vector3=sk.to_global(sk.get_bone_global_pose(sk.find_bone("foot."+suffix)).origin)
		var pose:Transform3D=sk.get_bone_global_pose(sk.find_bone("foot."+suffix))
		var rotation:Quaternion=sk.global_basis.get_rotation_quaternion()*pose.basis.get_rotation_quaternion()
		var contact:Dictionary=avatar.get_foot_contact(side,surface)
		var a:float=sk.get_bone_rest(sk.find_bone("shin."+suffix)).origin.length()
		var b:float=sk.get_bone_rest(sk.find_bone("foot."+suffix)).origin.length()
		var floor_gap:float=ankle.y+avatar._minimum_offset(suffix,rotation)-float(avatar._ground_y) if avatar.has_method("_minimum_offset") else INF
		feet[suffix]={"hip":hip,"knee":knee,"ankle":ankle,"knee_flexion_deg":180.0-rad_to_deg((hip-knee).angle_to(ankle-knee)),"leg_margin_m":a+b-hip.distance_to(ankle),"foot_rotation":rotation,"shoe_heading":rotation*Vector3.FORWARD,"sole_gap_m":floor_gap,"surface_point":contact.get("point",ankle),"surface_normal":contact.get("normal",Vector3.ZERO),"surface_alignment":(contact.get("normal",Vector3.ZERO) as Vector3).dot(wanted),"valid":bool(contact.get("valid",false)),"reach_error":contact.get("reach_error",INF)}
	var active:String=avatar.side_suffix(int(avatar._action.get("side",1)))
	return {"revision":"joint_contact_08","mode":mode,"sequence":int(avatar._action.get("sequence",-1)),"phase":avatar._action.get("phase","IDLE"),"surface":surface,"active_foot":active,"contact_confirmed":bool(avatar._action.get("contact_confirmed",false)),"contact_tick":int(avatar._action.get("contact_tick",-1)),"contact_surface_direction":wanted,"actual_support_ready":support_ready(avatar,active),"feet":feet,"physics_tick":Engine.get_physics_frames(),"source_stage":"read_only_completed_or_current_model_pose","scheduling_gate":false}
