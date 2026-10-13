extends SceneTree
const Rules=preload("res://scripts/offside_rules.gd")
var serial:int=0
var assertions:int=0
func _initialize()->void:call_deferred("run")
func check(value:bool)->void:
 assertions+=1
 assert(value,"offside case %d"%assertions)
func roster()->Array[Dictionary]:
 return [{"id":1,"team":0,"position":Vector3(0,0,-10),"active":true},{"id":2,"team":0,"position":Vector3(0,0,-35),"active":true},{"id":3,"team":1,"position":Vector3(0,0,-40),"active":true,"goalkeeper":true},{"id":4,"team":1,"position":Vector3(0,0,-30),"active":true}]
func fresh()->RefCounted:
 var r=Rules.new();r.state=r.State.LIVE;r.set_roster(roster());return r
func touch(r:RefCounted,id:int,team:int,at:Vector3,kind:String="pass")->bool:
 serial+=1;return r.report_ball_contact({"event_id":"test:%d"%serial,"actor_id":id,"team":team,"position":at,"kind":kind})
func run()->void:
 var r=fresh();check(touch(r,1,0,Vector3(0,0,-10)));check(r.state==r.State.LIVE)
 check(r.offside_phases[0].candidates.has(2));check(not touch(r,2,0,Vector3(0,0,-36),"receive"))
 check(r.restart.kind=="indirect_free_kick" and r.restart.team==1 and r.restart.reason=="offside")
 r=fresh();var rows=roster();rows[1].position.z=-30;r.set_roster(rows);touch(r,1,0,Vector3(0,0,-10));check(not r.offside_phases[0].candidates.has(2))
 r=fresh();touch(r,1,0,Vector3(0,0,-36));check(not r.offside_phases[0].candidates.has(2))
 r=fresh();rows=roster();rows[1].position.z=2;r.set_roster(rows);touch(r,1,0,Vector3(0,0,-10));check(not r.offside_phases[0].candidates.has(2))
 r=fresh();touch(r,1,0,Vector3(0,0,-10));touch(r,4,1,Vector3(0,0,-31),"body");check(r.offside_phases[0].candidates.has(2))
 r=fresh();touch(r,1,0,Vector3(0,0,-10));touch(r,3,1,Vector3(0,1,-39),"keeper_hand");check(r.offside_phases[0].candidates.has(2))
 r=fresh();touch(r,1,0,Vector3(0,0,-10));touch(r,4,1,Vector3(0,0,-31),"pass");check(r.offside_phases[0].is_empty())
 r=fresh();touch(r,1,0,Vector3(0,0,-10));rows=roster();rows[1].position.z=-20;r.set_roster(rows);check(not touch(r,2,0,Vector3(0,0,-20),"receive"))
 # Clear all phases on a stoppage. Direct exempt restarts do not arm a new phase.
 for kind in ["goal_kick","throw_in","corner"]:
  r=fresh();touch(r,1,0,Vector3(0,0,-10));r._queue_restart(kind,0,Vector3(20,0,-40),"test");check(r.offside_phases[0].is_empty())
  # Put a complete legal ready plan around the taker, with opponents beyond clearance.
  r.restart["taker_id"]=1;r.restart["taker_target"]=Vector3.ZERO;r.restart["ball_position"]=Vector3(0,.11,0);r.restart["point"]=Vector3.ZERO;r.restart["clearance"]=0.;r.restart["inward"]=Vector3.FORWARD
  rows=roster();rows[0].position=Vector3.ZERO;r.set_roster(rows);r.state=r.State.RESTART_READY
  var result=r.request_restart(1,Vector3.FORWARD,10.,3.);check(result.get("ok",false));check(r.offside_phases[0].is_empty())
 r=fresh();touch(r,1,0,Vector3(0,0,-10));rows=roster();rows[1].position=Vector3(0,0,-35);rows[1].velocity=Vector3(0,0,-2);rows[3].position=Vector3(.3,0,-35.4);r.set_roster(rows)
 check(r.involvement(rows[1],0,Vector3(0,.2,-35.5),Vector3(0,0,-5))=="challenging_opponent")
 rows[1].velocity=Vector3.ZERO;check(r.involvement(rows[1],0,Vector3(0,.2,-35.5),Vector3(0,0,-5)).is_empty())
 r=fresh();rows=roster();rows[1].position=Vector3(0,0,-37);r.set_roster(rows)
 check(r.involvement(rows[1],0,Vector3(0,1,-30),Vector3(0,0,-10))=="blocking_keeper_view")
 # Mirrored ends and eligible-point data (no hands/arms used).
 r=fresh();r.attack_signs.assign([1,-1]);rows=roster()
 for row in rows:row.position.z*=-1
 r.set_roster(rows);touch(r,1,0,Vector3(0,0,10));check(r.offside_phases[0].candidates.has(2))
 # Position is frozen at the teammate's touch, not taken from the reception frame.
 r=fresh();rows=roster();rows[1].position.z=-29;r.set_roster(rows);touch(r,1,0,Vector3(0,0,-10));rows[1].position.z=-38;r.set_roster(rows)
 check(touch(r,2,0,Vector3(0,0,-38),"receive"));check(r.state==r.State.LIVE)
 r=fresh();touch(r,1,0,Vector3(0,0,-10));var saved=r.offside_phases[0].duplicate(true)
 check(not r.report_ball_contact({"event_id":"test:%d"%serial,"actor_id":1,"team":0,"position":Vector3(0,0,-40),"kind":"pass"}));check(r.offside_phases[0]==saved)
 r=fresh();rows=roster();rows[1].position.z=-29.9;rows[1]["offside_points"]=[Vector3(0,1.5,-30.2)];r.set_roster(rows);touch(r,1,0,Vector3(0,0,-10));check(r.offside_phases[0].candidates.has(2))
 r=fresh();touch(r,1,0,Vector3(0,0,-10));r._ball={"velocity":Vector3(0,0,-10)}
 touch(r,4,1,Vector3(0,1,-40),"header");check(r.offside_phases[0].candidates.has(2))
 r=fresh();touch(r,1,0,Vector3(0,0,-10));rows=roster();rows[1].velocity=Vector3(0,0,-2);rows[3].position=Vector3(.3,0,-35.4)
 r.step(.01,{"position":Vector3(0,.2,-35.5),"previous_position":Vector3(0,.2,-35),"velocity":Vector3(0,0,-5)},rows)
 check(r.restart.get("reason","")=="offside" and r.restart.team==1)
 print("OFFSIDE_R8_PASS checks=",assertions)
 quit()
