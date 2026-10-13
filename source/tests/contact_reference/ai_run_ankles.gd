extends RefCounted
# Final free-locomotion ankle owner. Existing phase is the only clock; contacts keep original IK.
var active:=false
var guard:=false
var motion:=Vector3.ZERO
var weight:=0.0
var speed:=0.0
var duty:=.68
var travel:=.4
var lift:=.055
var running:=false
var pose_delta:=0.0
var drive:=0.0
var braking:=0.0
var run_blend:=0.0
var guard_blend:=0.0
const Rhythm=preload("res://addons/football_motion/locomotion_intent_039.gd")
var turn:=0.0
var turn_sign:=1.0
var previous_forward:=Vector3.ZERO
var swings:Dictionary={}
var style:="IDLE"
var endpoints:Dictionary={}
var previous_root:=Vector3.ZERO
var has_root:=false
var debug_feet:Dictionary={}
var lateral_load:=0.0
var cut_load:=0.0
func prepare(avatar,delta:float,state:Dictionary,action:Dictionary)->void:
 pose_delta=maxf(0,delta)
 var actor:Node=avatar.get_parent()
 if has_root and avatar.global_position.distance_to(previous_root)>.75:
  avatar._plants.clear();swings.clear();endpoints.clear()
 previous_root=avatar.global_position;has_root=true
 var velocity:Vector3=state.get("velocity",Vector3.ZERO)
 motion=Vector3(velocity.x,0,velocity.z);speed=motion.length()
 guard=bool(state.get("ai_guard",false))
 var eligible:bool=not actor.is_human and not actor.is_goalkeeper and action.is_empty() and bool(state.get("grounded",true)) and state.get("interaction",{}).is_empty() and String(state.get("control_tier","FREE"))=="FREE" and String(state.get("locomotion",""))!="dribble"
 var forward:Vector3=state.get("forward",Vector3.FORWARD)
 if delta>0:
  var angle:float=previous_forward.signed_angle_to(forward,Vector3.UP) if previous_forward.length_squared()>.1 else 0.0
  var turn_rate:float=absf(angle)/maxf(delta,.001)
  if absf(angle)>.001:turn_sign=-signf(angle)
  turn=lerpf(turn,smoothstep(.45,2.7,turn_rate),1.0-exp(-10.0*delta));previous_forward=forward
 if not eligible:
  if active:avatar._plants.clear()
  weight=0.0;active=false;lateral_load=0.0;cut_load=0.0;swings.clear();endpoints.clear();return
 running=speed>(1.85 if running else 2.10) and not guard
 style="GUARD" if guard else "TURN" if turn>.28 else "RUN" if running else "WALK" if speed>.08 else "IDLE"
 if delta>0:
  var response:float=1.0-exp(-10.0*delta)
  var acceleration:Vector3=state.get("acceleration",Vector3.ZERO)
  var travel_axis:Vector3=motion.normalized() if speed>.1 else forward
  var travel_right:=Vector3(-travel_axis.z,0,travel_axis.x)
  var lateral:float=clampf(acceleration.dot(travel_right)/12.0,-1.0,1.0)*smoothstep(1.2,3.2,speed)
  lateral_load=lerpf(lateral_load,lateral,1.0-exp(-8.0*delta))
  if absf(lateral_load)>.08:turn_sign=signf(lateral_load)
  var outside:String="R" if lateral_load<0 else "L"
  var supported:bool=avatar._plants.has(outside) and not bool(avatar._plants[outside].get("releasing",false))
  cut_load=lerpf(cut_load,absf(lateral_load)*(1.0 if supported else .25),1.0-exp(-12.0*delta))
  var along:float=acceleration.dot(travel_axis)
  drive=lerpf(drive,clampf(along/9.0,0,1),response)
  braking=lerpf(braking,clampf(-along/9.0,0,1),response)
  run_blend=lerpf(run_blend,smoothstep(1.65,3.7,speed),response)
  guard_blend=lerpf(guard_blend,1.0 if guard else 0.0,response)
  weight=lerpf(weight,1.0,1.0-exp(-12.0*delta))
 if not active:avatar._plants.clear();swings.clear();endpoints.clear()
 active=true
func cadence()->float:
 if speed<.08:return .85 if turn>.15 else 0.0
 # Shared continuous speed curve: no cadence halving at the walk/run threshold.
 return Rhythm.cycles(speed)
func apply(avatar,forward:Vector3,delta:float)->bool:
 if not active:return false
 var sk:Skeleton3D=avatar.skeleton
 # The authored Run clip lowers pelvis by ~10 cm. That crouch must not remain
 # underneath a forward sprint lean. Correct only free-running AI, before IK.
 var hip_id:int=avatar.cached_bone_id("hips")
 var hip_position:Vector3=sk.get_bone_pose_position(hip_id)
 var hip_rest:Vector3=sk.get_bone_rest(hip_id).origin
 var upright_run:float=run_blend*(1.0-guard_blend)
 var target_height:float=hip_rest.y-.035-.025*braking-.045*cut_load-.014*cos(TAU*(avatar._phase-.10)*2)
 hip_position.y=lerpf(hip_position.y,target_height,upright_run)
 hip_position.z=lerpf(hip_position.z,hip_rest.z-.04-.025*drive,upright_run)
 hip_position.x=lerpf(hip_position.x,hip_rest.x+signf(lateral_load)*.025*cut_load,upright_run)
 sk.set_bone_pose_position(hip_id,hip_position)
 var pelvis_angles:Vector3=sk.get_bone_pose_rotation(hip_id).get_euler()
 var pitch:float=-.07-.105*smoothstep(2.0,6.0,speed)-.07*drive+.09*braking
 pelvis_angles.x=lerp_angle(pelvis_angles.x,pitch,upright_run)
 pelvis_angles.z=lerp_angle(pelvis_angles.z,-signf(lateral_load)*.24*cut_load,upright_run)
 sk.set_bone_pose_rotation(hip_id,Quaternion.from_euler(pelvis_angles))
 forward=-avatar.visual.global_basis.z
 forward=Vector3(forward.x,0,forward.z).normalized()
 var right:=Vector3(-forward.z,0,forward.x)
 var axis:Vector3=motion.normalized() if speed>.08 else forward
 var cycles:float=maxf(.2,avatar._cadence)
 duty=lerpf(lerpf(.68,.36,run_blend),.62,guard_blend)
 duty=minf(duty,.82*cycles/maxf(speed,.1))
 travel=minf(.82,speed*duty/cycles)
 lift=lerpf(lerpf(.055,.21,run_blend),.045,guard_blend)
 # Foot heading follows the rendered pelvis, not a newer tactical facing.
 forward=-avatar.visual.global_basis.z;forward.y=0;forward=forward.normalized()
 right=Vector3(-forward.z,0,forward.x)
 var yaw:float=atan2(-forward.x,-forward.z)
 var solves:Dictionary={}
 for side in ["L","R"]:
  var sign_side:float=-1.0 if side=="L" else 1.0
  var p:float=fposmod(avatar._phase+(.5 if side=="R" else 0.0),1.0)
  var stationary:bool=speed<.08 and turn<.15
  var stance:bool=stationary or p<duty
  # Complete the current step after a phase/pace change instead of cutting it short.
  if not stationary and swings.has(side) and float(swings[side].get("elapsed",0))<float(swings[side].get("duration",0)):stance=false
  var q:float=clampf((p-duty)/maxf(.01,1-duty),0,1)
  var inner:bool=sign_side==turn_sign
  var width:float=lerpf(.145,.19,guard_blend)+turn*.018+(.11*absf(lateral_load) if not inner else .0)
  var stride:float=travel*(1.0-turn*(.30 if inner else -.10))
  var sweep:float=(.5-p/maxf(duty,.01))*stride if stance else stride*.5
  if stationary:sweep=0
  var rotation:=Quaternion(Vector3.UP,yaw)
  var goal:Vector3=avatar.global_position+right*sign_side*width+axis*sweep
  goal.y=avatar._ground_y+.005-avatar._minimum_offset(side,rotation)
  var id:int=avatar.cached_bone_id("foot."+side)
  var sampled:Transform3D=sk.global_transform*sk.get_bone_global_pose(id)
  var sole:Vector3=avatar._sole_offset(side)
  if avatar._plants.has(side):
   var anchor:Vector3=avatar._plants[side].point
   var offset:Vector3=anchor-avatar.global_position
   # A new spawn or skipped support phase must not stretch a planted leg across the body.
   if Vector2(offset.x,offset.z).length()>.62 or offset.dot(right)*sign_side<.035:
    avatar._plants.erase(side)
   elif absf(angle_difference(float(avatar._plants[side].yaw),yaw))>.65:
    avatar._plants.erase(side)
    stance=false
  # Finish an airborne step after the motor stops instead of teleporting it down.
  var settling:bool=stationary and not avatar._plants.has(side) and endpoints.has(side)
  if settling:
   var last:Dictionary=endpoints[side]
   var rest:Vector3=goal
   var offset:Vector3=(last.point as Vector3)-avatar.global_position
   # Keep the last horizontal step within a comfortable stance; no root movement.
   var planar:Vector3=Vector3(offset.x,0,offset.z).limit_length(.24)
   rest.x=avatar.global_position.x+planar.x;rest.z=avatar.global_position.z+planar.z
   goal=(last.point as Vector3).move_toward(rest,maxf(0,delta)*1.2)
   rotation=(last.rotation as Quaternion).slerp(rotation,1.0-exp(-12.0*maxf(0,delta)))
   settling=goal.distance_to(rest)>.004
   stance=not settling
  if stance:
   if swings.has(side) and endpoints.has(side) and not stationary:
    var landed:Vector3=endpoints[side].point
    landed.y=goal.y
    goal=landed
   swings.erase(side)
   if not avatar._plants.has(side) or bool(avatar._plants[side].get("releasing",false)):
    avatar._plants[side]={"point":goal+rotation*sole,"rotation":rotation,"age":0.0,"yaw":yaw,"releasing":false}
   var plant:Dictionary=avatar._plants[side]
   plant.age+=maxf(0,delta)
   rotation=plant.rotation # Keep planted shoe yaw; torso input is never delayed for it.
   goal=(plant.point as Vector3)-rotation*sole
   # Late stance rolls over the forefoot instead of keeping a flat shoe while
   # the pelvis passes ahead. Contact actions never enter this free-gait owner.
   var toe_off:float=smoothstep(.50,1.0,p/maxf(.01,duty))*run_blend*(1.0-guard_blend) if not stationary else 0.0
   if toe_off>0:
    var toe:=Vector3(0,0,-.10)
    var pivot:Vector3=(plant.point as Vector3)+rotation*toe
    rotation*=Quaternion(Vector3.RIGHT,-.32*toe_off)
    goal=pivot-rotation*(sole+toe)
  elif not settling:
   if not swings.has(side):
    var last:Dictionary=endpoints.get(side,{})
    swings[side]={"origin":last.get("point",sampled.origin),"rotation":last.get("rotation",sampled.basis.get_rotation_quaternion()),"elapsed":0.0,"duration":maxf(.12,(1.0-p)/cycles)}
   avatar._plants.erase(side)
   var start:Dictionary=swings[side]
   start.elapsed+=maxf(0,delta)
   q=clampf(float(start.elapsed)/float(start.duration),0,1)
   var landing:Vector3=goal+motion*minf(.16,maxf(0,float(start.duration)-float(start.elapsed)))
   var local:Vector3=landing-avatar.global_position
   local+=right*(sign_side*maxf(.105,absf(local.dot(right)))-local.dot(right))
   landing=avatar.global_position+local;landing.y=goal.y
   var swing_weight:float=smoothstep(0,1,q)
   goal=(start.origin as Vector3).lerp(landing,swing_weight)
   goal.y+=lift*sin(PI*pow(q,.78 if running else 1.0))
   rotation=(start.rotation as Quaternion).slerp(rotation,swing_weight)
   rotation*=Quaternion(Vector3.RIGHT,(-.18 if running else -.05)*sin(PI*q))
   var lateral:float=(goal-avatar.global_position).dot(right)
   goal+=right*(sign_side*clampf(lateral*sign_side,.07,.32 if not inner else .25)-lateral)
  goal=sampled.origin.lerp(goal,weight)
  rotation=sampled.basis.get_rotation_quaternion().slerp(rotation,weight)
  endpoints[side]={"point":goal,"rotation":rotation}
  debug_feet[side]={"root":avatar.global_position,"goal":goal,"sampled":sampled.origin,"ground":avatar._ground_y,"stance":stance,"settling":settling,"lateral_load":lateral_load,"cut_load":cut_load,"outer":not inner,"width":width,"actual_lateral":(goal-avatar.global_position).dot(right)}
  solves[side]={"goal":goal,"rotation":rotation,"stance":stance}
 # Check both stance legs before solving either. A small, non-accumulating
 # support compression is preferable to floating feet or a permanent crouch.
 var support_drop:float=0.0
 for side in solves:
  if not solves[side].stance:continue
  var ankle:Vector3=sk.to_local(solves[side].goal)
  var hip:Vector3=sk.get_bone_global_pose(avatar.cached_bone_id("thigh."+side)).origin
  var length:float=sk.get_bone_rest(avatar.cached_bone_id("shin."+side)).origin.length()+sk.get_bone_rest(avatar.cached_bone_id("foot."+side)).origin.length()-.012
  var horizontal:float=Vector2(hip.x-ankle.x,hip.z-ankle.z).length()
  var available:float=sqrt(maxf(0,length*length-horizontal*horizontal))
  support_drop=maxf(support_drop,hip.y-ankle.y-available)
 if support_drop>0:
  var loaded:Vector3=sk.get_bone_pose_position(hip_id)
  loaded.y-=minf(.035,support_drop)
  sk.set_bone_pose_position(hip_id,loaded)
 for side in solves:
  var local_goal:Vector3=sk.to_local(solves[side].goal)
  var hip:Vector3=sk.get_bone_global_pose(avatar.cached_bone_id("thigh."+side)).origin
  var maximum:float=sk.get_bone_rest(avatar.cached_bone_id("shin."+side)).origin.length()+sk.get_bone_rest(avatar.cached_bone_id("foot."+side)).origin.length()-.012
  local_goal=hip+(local_goal-hip).limit_length(maximum)
  avatar._solve_leg(side,local_goal,sk.global_basis.get_rotation_quaternion().inverse()*solves[side].rotation,sk.global_basis.inverse()*forward)
 return true
