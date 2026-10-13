extends "res://addons/football_match_services/rules/rules_engine.gd"
# Two independent last-teammate-touch phases. Deflections/saves do not erase an opponent phase.
var offside_phases:Array[Dictionary]=[{},{}]
var live_roster_provider:Callable
func start(kickoff_team:int=0)->void:
 offside_phases=[{},{}];super.start(kickoff_team)
func refresh_contact_roster()->void:
 if live_roster_provider.is_valid():set_roster(live_roster_provider.call())
func eligible_depth(actor:Dictionary,sign_z:int)->float:
 var depth:float=actor.position.z*sign_z
 for point in actor.get("offside_points",[]):depth=maxf(depth,point.z*sign_z)
 return depth
func mark_phase(team:int,actor_id:int,ball_at:Vector3)->void:
 var sign_z:int=attack_signs[team];var defenders:Array[float]=[]
 for actor in _roster:
  if actor.get("active",true) and int(actor.team)!=team:defenders.append(eligible_depth(actor,sign_z))
 defenders.sort()
 if defenders.size()<2:offside_phases[team]={};return
 var line:float=maxf(ball_at.z*sign_z,defenders[-2]);var candidates:Dictionary={}
 for actor in _roster:
  if int(actor.team)!=team or int(actor.id)==actor_id or not actor.get("active",true):continue
  var depth:float=eligible_depth(actor,sign_z)
  if depth>0.001 and depth>line+.01:candidates[int(actor.id)]=actor.position
 offside_phases[team]={"candidates":candidates,"line":line,"passer":actor_id,"ball_at":ball_at}
func penalize_offside(team:int,actor_id:int,at:Vector3,reason:String)->void:
 _emit("assistant_flag",{"team":team,"actor_id":actor_id,"point":at,"reason":reason,"attack_sign":attack_signs[team]})
 _emit("offside",{"team":team,"actor_id":actor_id,"point":at,"reason":reason})
 _queue_restart("indirect_free_kick",1-team,at,"offside")
func report_ball_contact(contact:Dictionary)->bool:
 if state!=State.LIVE:return super.report_ball_contact(contact)
 var id:String=str(contact.get("event_id",""))
 # Let the base class own duplicate diagnostics, without repeating a flag or phase reset.
 if not id.is_empty() and _seen.has("contact:"+id):return super.report_ball_contact(contact)
 var team:int=int(contact.get("team",-1));var actor_id:int=int(contact.get("actor_id",-1))
 if team not in [0,1] or actor_id<0:return super.report_ball_contact(contact)
 refresh_contact_roster()
 if offside_phases[team].get("candidates",{}).has(actor_id):
  if _accept_id(contact,"contact"):
   penalize_offside(team,actor_id,contact.get("position",_actor(actor_id).get("position",Vector3.ZERO)),"playing_ball")
  return false
 var accepted:bool=super.report_ball_contact(contact)
 if not accepted or state!=State.LIVE:return accepted
 var kind:String=str(contact.get("kind","body")).to_lower()
 var deliberate:bool=kind in ["pass","shot","throw","receive","stop","settle","dribble","carry","close","sprint","turn","shield","push","pull","header"]
 if deliberate and not bool(contact.get("deliberate_save",false)) and not likely_save(team,contact):offside_phases[1-team]={}
 mark_phase(team,actor_id,contact.get("position",Vector3.ZERO))
 return true
func likely_save(team:int,contact:Dictionary)->bool:
 if str(contact.get("kind","")) not in ["header","tackle"]:return false
 var incoming:Vector3=_ball.get("velocity",Vector3.ZERO)
 var point:Vector3=contact.get("position",Vector3.ZERO)
 var goal_side:int=-attack_signs[team]
 if incoming.z*goal_side<2. or absf(point.z)<config.half_length-16.:return false
 var t:float=(goal_side*config.half_length-point.z)/incoming.z
 var hit:Vector3=point+incoming*t
 return t>0. and t<2. and absf(hit.x)<config.goal_half_width+.3 and hit.y>-.5 and hit.y<config.goal_height+.3
func request_restart(actor_id:int,direction:Vector3,power:float,lift:float=.3,contact_event_id:String="")->Dictionary:
 refresh_contact_roster()
 var kind:String=str(restart.get("kind",""));var team:int=int(restart.get("team",0));var at:Vector3=restart.get("ball_position",Vector3.ZERO)
 var result:Dictionary=super.request_restart(actor_id,direction,power,lift,contact_event_id)
 if result.get("ok",false) and kind not in ["throw_in","goal_kick","corner","dropped_ball"]:mark_phase(team,actor_id,at)
 return result
func _queue_restart(kind:String,team:int,at:Vector3,reason:String,immediate:bool=false,side_override:int=0)->void:
 offside_phases=[{},{}]
 super._queue_restart(kind,team,at,reason,immediate,side_override)
func step(delta:float,ball_snapshot:Dictionary,roster:Array[Dictionary])->void:
 if state==State.LIVE:
  set_roster(roster)
  var point:Vector3=ball_snapshot.get("position",Vector3.ZERO)
  for team in [0,1]:
   for actor_id in offside_phases[team].get("candidates",{}):
    var actor:Dictionary=_actor(actor_id)
    if actor.is_empty() or not actor.get("active",true):continue
    var reason:String=involvement(actor,team,point,ball_snapshot.get("velocity",Vector3.ZERO))
    if not reason.is_empty():
     penalize_offside(team,actor_id,actor.position,reason);super.step(delta,ball_snapshot,roster);return
 super.step(delta,ball_snapshot,roster)
func involvement(actor:Dictionary,team:int,point:Vector3,ball_velocity:Vector3)->String:
 var toward:Vector3=point-actor.position;toward.y=0.
 var moving:Vector3=actor.get("velocity",Vector3.ZERO)
 var attempting:bool=str(actor.get("action","")) in ["RECEIVE","SHOT","PASS","TACKLE","HEADER"] or (toward.length()>.01 and moving.dot(toward.normalized())>.6)
 for opponent in _roster:
  if int(opponent.team)==team or not opponent.get("active",true):continue
  if attempting and point.y<2.1 and toward.length()<1.0 and _flat_distance(opponent.position,point)<1.2 and _flat_distance(actor.position,opponent.position)<.85:return "challenging_opponent"
  if not opponent.get("goalkeeper",false) or ball_velocity.z*attack_signs[team]<2.:continue
  var keeper:Vector3=opponent.position+Vector3.UP*1.55
  var ray:Vector3=keeper-point;var length_squared:float=ray.length_squared()
  if length_squared<.1 or _flat_distance(actor.position,opponent.position)>5.:continue
  var body:Vector3=actor.position+Vector3.UP*1.1
  var t:float=(body-point).dot(ray)/length_squared
  var closest:Vector3=point+ray*t
  var goal_time:float=(attack_signs[team]*config.half_length-point.z)/ball_velocity.z
  var goal_x:float=point.x+ball_velocity.x*goal_time
  if goal_time>0. and goal_time<3. and absf(goal_x)<config.goal_half_width+.25 and t>.05 and t<.95 and _flat_distance(closest,actor.position)<.30 and closest.y>actor.position.y+.5 and closest.y<actor.position.y+1.85:return "blocking_keeper_view"
 return ""
