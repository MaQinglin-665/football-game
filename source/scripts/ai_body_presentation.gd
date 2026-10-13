extends RefCounted
# AI-only style in the existing pre-support pose stage. No second action clock.
# Existing foot target/plant IK and floor correction always execute after this.
var weights:=Vector3.ZERO # run, carry, close
var moving:=0.0
var guard_weight:=0.0
var call_weight:=0.0
var running:=false
var close_control:=false
var enabled:=false
var style:="IDLE"
var updates:=0
var ids:Dictionary={}
var balance:=Vector3.ZERO # longitudinal acceleration, lateral acceleration, speed
var brace:=0.0
func restore(_avatar)->void:pass # Base sample resets bones; no post-IK overlay to undo.
func prepare(avatar,delta:float,state:Dictionary,action:Dictionary)->void:
	var actor:Node=avatar.get_parent()
	enabled=not actor.is_human and not actor.is_goalkeeper and bool(state.get("grounded",true)) and state.get("interaction",{}).is_empty()
	if not enabled:return
	var velocity:Vector3=state.get("velocity",Vector3.ZERO)
	var speed:float=Vector2(velocity.x,velocity.z).length()
	var kind:String=String(action.get("kind",""))
	var carry:bool=String(state.get("locomotion",""))=="dribble" or String(state.get("control_tier","FREE")) in ["CLOSE","CRUISE","KNOCK_CHASE"]
	running=speed>(1.85 if running else 2.10)
	close_control=carry and (String(state.get("control_tier",""))=="CLOSE" or speed<(2.25 if close_control else 1.85))
	style=kind if kind in ["PASS","SHOT"] else "CLOSE" if close_control else "CARRY" if carry else "RUN" if running else "WALK" if speed>.08 else "IDLE"
	if delta>0:
		var blend:float=1.0-exp(-12.0*delta)
		weights=weights.lerp(Vector3(smoothstep(1.65,3.7,speed) if not carry else 0.0,1 if carry and not close_control else 0,1 if close_control else 0),blend)
		moving=lerpf(moving,smoothstep(.04,.32,speed),blend)
		var facing:Vector3=-avatar.visual.global_basis.z
		var right:=Vector3(-facing.z,0,facing.x)
		var accel:Vector3=state.get("acceleration",Vector3.ZERO)
		var target:=Vector3(clampf(accel.dot(facing)/9.0,-1,1),clampf(accel.dot(right)/9.0,-1,1),speed)
		balance=balance.lerp(target,1.0-exp(-9.0*delta))
		brace=lerpf(brace,clampf((-balance.x+absf(balance.y))*.6,0,1)*smoothstep(.1,1.0,speed),blend)
		call_weight=lerpf(call_weight,float(actor.tactical_intent.get("call_weight",0.0)) if action.is_empty() else 0.0,blend)
		guard_weight=lerpf(guard_weight,1.0 if bool(state.get("ai_guard",false)) and action.is_empty() else 0.0,blend)
func _id(avatar,name:String)->int:
	if not ids.has(name):ids[name]=avatar.cached_bone_id(name)
	return int(ids[name])
func _rotate(avatar,name:String,v:Vector3)->void:
	var id:int=_id(avatar,name)
	if id>=0:avatar.skeleton.set_bone_pose_rotation(id,Quaternion.from_euler(v)*avatar.skeleton.get_bone_pose_rotation(id))
func apply_before_support(avatar,state:Dictionary,action:Dictionary)->void:
	if not enabled:return
	var kind:String=String(action.get("kind",""))
	if not kind in ["","CLOSE","TURN","CARRY","SHIELD","SPRINT","PASS","SHOT"]:return
	if kind in ["PASS","SHOT"]:return # Shared kick layers own human and AI articulation.
	var kick:bool=kind in ["PASS","SHOT"]
	var phase:float=avatar._phase
	var wave:float=sin(TAU*phase)
	var run:float=weights.x*moving*(1.0-guard_weight)
	var carry:float=weights.y*moving
	var close:float=weights.z
	var walk:float=maxf(0,1-weights.x-weights.y-weights.z)*moving*(1.0-guard_weight)
	var side:float=float(action.get("side",1))
	var t:float=float(action.get("normalized_time",0))
	var load:float=smoothstep(0,.22,t) if kick else 0.0
	var release:float=1.0-smoothstep(.67,1.0,t) if kick else 1.0
	var envelope:float=load*release
	# The unwind follows the existing backswing->strike path, not an invented beat.
	var stroke:float=smoothstep(.16,.50,t)
	var kick_mix:float=envelope if kick else 0.0
	var gait:float=1.0-kick_mix
	var guard:float=guard_weight if action.is_empty() else 0.0
	var hips:int=_id(avatar,"hips")
	var hip_position:Vector3=avatar.skeleton.get_bone_pose_position(hips)
	# Small COM change bends the knees through final fixed-foot support IK.
	hip_position.y-=.075*guard+.015*brace
	hip_position+=Vector3(wave*.006*walk,-.027*close+.005*cos(TAU*phase*2)*run,0)*gait
	if kind=="PASS":hip_position+=Vector3(-side*.012,-.012,-.008)*envelope
	avatar.skeleton.set_bone_pose_position(hips,hip_position)
	_rotate(avatar,"hips",Vector3(0,wave*(.020*walk+.025*run),-.010*wave*walk)*gait)
	# Pelvis lean is already owned by BodyMotion. Articulate the trunk above it:
	# upright walk, modest jog, more forward chest at sprint/acceleration.
	var sprint:float=smoothstep(3.0,6.0,balance.z)
	var trunk_lean:float=lerpf(.025,.045,sprint)*run+.04*sprint*carry
	trunk_lean+=.035*maxf(0,balance.x)*moving*(1.0-guard_weight)
	_rotate(avatar,"spine",Vector3(-.055*close-.028*carry-trunk_lean-.045*guard,0,0)*gait)
	_rotate(avatar,"chest",Vector3(-trunk_lean*.35,0,0)*gait)
	_rotate(avatar,"head",Vector3(trunk_lean*.70,0,0)*gait)
	_rotate(avatar,"chest",Vector3(.025*close,-wave*(.028*walk+.045*run),0)*gait)
	_rotate(avatar,"head",Vector3(.028*close+.016*carry,0,0)*gait)
	# Full poses already have acceleration lean from BodyMotion. Distant display
	# omits that layer; add a bounded matching lean only on that path.
	if avatar._display_gait_active:
		var pitch:float=-.15*smoothstep(1.4,5.6,balance.z)-.09*maxf(0,balance.x)+.05*maxf(0,-balance.x)
		var bank:float=-.10*balance.y
		_rotate(avatar,"hips",Vector3(pitch,0,bank))
		_rotate(avatar,"head",Vector3(-pitch*.65,0,-bank*.65))
	_rotate(avatar,"chest",Vector3(.015*brace,-.065*balance.y,-.025*balance.y))
	_rotate(avatar,"head",Vector3(0,.035*balance.y,.018*balance.y))
	# Joint articulation is swing-only; planted shoe and real touch leg stay owned by IK.
	var fraction:float=avatar._stance_fraction039 if avatar._stance_fraction039>0 else float(avatar._profiles.get(avatar._base_clip,{}).get("stance_fraction",.58))
	for suffix in ["L","R"]:
		var sign_side:float=-1 if suffix=="L" else 1
		var p:float=fposmod(phase+(.5 if suffix=="R" else 0),1)
		var swing:float=sin(PI*clampf((p-fraction)/maxf(.01,1-fraction),0,1))
		if not avatar.ai_run_ankles.active and (action.is_empty() or sign_side!=side):
			_rotate(avatar,"shin."+suffix,Vector3((.15*run+.06*carry+.045*close)*swing*gait,0,0))
			_rotate(avatar,"thigh."+suffix,Vector3(-(.055*run+.018*carry)*swing*gait,0,0))
			_rotate(avatar,"foot."+suffix,Vector3(-.055*run*swing*gait,0,0))
		var counter:float=-sign_side*sin(TAU*phase-.16)
		_rotate(avatar,"upper_arm."+suffix,Vector3(counter*(.035*walk+.16*run+.055*carry),0,sign_side*(.07*carry+.16*close+.18*guard+.12*brace))*gait)
		_rotate(avatar,"forearm."+suffix,Vector3(.20*run+.10*run*(.5+.5*counter)+.12*carry+.13*close+.16*guard+.08*brace,0,0)*gait)
	# Resolve shoulder/elbow/wrist as one chain. Replacing only the humerus
	# while retaining donor forearm rotations produced straight or bent-back arms.
	if action.is_empty() or kind in ["CLOSE","TURN","CARRY","SHIELD","SPRINT"]:
		var pace:float=smoothstep(.65,3.8,balance.z)
		var sk:Skeleton3D=avatar.skeleton
		var chest_basis:Basis=sk.get_bone_global_pose(_id(avatar,"chest")).basis.orthonormalized()
		for suffix in ["L","R"]:
			var sign_side:float=-1.0 if suffix=="L" else 1.0
			var wave_arm:float=sign_side*sin(TAU*phase-.12)
			var shoulder:float=(wave_arm*lerpf(.20,.60,pace)*(1.0-.72*guard)+.08*pace*absf(wave_arm))*moving
			var flex:float=lerpf(.32,1.15,pace)-.30*pace*wave_arm+.18*guard
			var upper_direction:Vector3=chest_basis*Vector3(sign_side*(.09+.045*pace+.18*guard),-cos(shoulder),sin(shoulder)).normalized()
			var lower_direction:Vector3=chest_basis*Vector3(sign_side*.055,-cos(shoulder-flex),sin(shoulder-flex)).normalized()
			_aim_segment(avatar,"upper_arm."+suffix,"forearm."+suffix,upper_direction)
			_aim_segment(avatar,"forearm."+suffix,"hand."+suffix,lower_direction)
			# Neutral wrist follows the forearm; no accumulated donor wrist kink.
			sk.set_bone_pose_rotation(_id(avatar,"hand."+suffix),Quaternion.IDENTITY)
	if action.is_empty() and call_weight>.01:
		# One right arm only; sampled before final foot IK, no foot action or clock.
		_raise_call_arm(avatar,call_weight)
	updates+=1

func _aim_segment(avatar,name:String,child_name:String,direction:Vector3)->void:
	var sk:Skeleton3D=avatar.skeleton
	var bone:int=_id(avatar,name)
	var child:int=_id(avatar,child_name)
	var axis:Vector3=sk.get_bone_rest(child).origin.normalized()
	var parent:Quaternion=sk.get_bone_global_pose(sk.get_bone_parent(bone)).basis.get_rotation_quaternion()
	sk.set_bone_pose_rotation(bone,parent.inverse()*Quaternion(axis,direction.normalized()))

func _raise_call_arm(avatar,weight:float)->void:
	# Aim only arm bones in skeleton space; avoid adding Euler turns to a bent running elbow.
	var human:bool=avatar.get_parent().is_human
	for pair in [["upper_arm.R","forearm.R",Vector3(.12,.38,-.92) if human else Vector3(.25,.96,-.08)],["forearm.R","hand.R",Vector3(.02,.72,-.69) if human else Vector3(.08,.99,-.08)]]:
		var bone:int=_id(avatar,pair[0]);var child:int=_id(avatar,pair[1])
		if bone<0 or child<0:continue
		var pose:Transform3D=avatar.skeleton.get_bone_global_pose(bone)
		var axis:Vector3=avatar.skeleton.get_bone_global_pose(child).origin-pose.origin
		if axis.length_squared()<.00001:continue
		var correction:=Quaternion(axis.normalized(),(pair[2] as Vector3).normalized())
		pose.basis=Basis(Quaternion.IDENTITY.slerp(correction,weight))*pose.basis
		avatar.skeleton.set_bone_global_pose(bone,pose)

