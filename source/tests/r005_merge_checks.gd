extends SceneTree
var failed:=0
func check(label:String,ok:bool)->void:
 if not ok:failed+=1
 print("PASS " if ok else "FAIL ",label)
func _initialize()->void:
 var motion:=HumanMotion.new()
 var v:=Vector3.FORWARD*6.0
 for i in 36:v=motion.step(v,Vector3.FORWARD*6.0,0,1.0/120)
 for i in 72:v=motion.step(v,Vector3.FORWARD,0,1.0/120)
 motion.step(v,Vector3.RIGHT*6.0,0,1.0/120)
 check("old slowdown cannot grant a fresh burst",not "feint_burst" in motion.events)
 motion.plant_left=.2;motion.burst_left=.2;motion.reset()
 check("restart clears movement memory",motion.plant_left==0 and motion.burst_left==0 and motion.events.is_empty())
 for i in 200:motion.record_event("plant")
 check("motion diagnostics bounded",motion.events.size()==64)
 var foot:=FootballFootAction.new(null,null)
 foot.kind="PASS";foot.kick_intent={"direction":Vector3.FORWARD,"human_error_deg":8.0}
 var first:=foot.contact_kick_intent()
 var second:=foot.contact_kick_intent()
 check("contact retries keep identical sampled aim",first.direction.is_equal_approx(second.direction))
 check("nominal intent is never mutated",foot.kick_intent.direction==Vector3.FORWARD and not first.direction.is_equal_approx(Vector3.FORWARD))
 foot.restarting=true
 check("restart does not receive open-play error",foot.contact_kick_intent().direction==Vector3.FORWARD)
 print("RESULT ","PASS" if failed==0 else "FAIL")
 quit(1 if failed else 0)
