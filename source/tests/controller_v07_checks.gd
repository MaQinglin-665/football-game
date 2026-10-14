extends SceneTree
var failed:=0
func check(label:String,ok:bool,info:Variant=null)->void:
 if not ok:failed+=1
 print("PASS " if ok else "FAIL ",label," ",info)
func _initialize()->void:
 var m:=FootballMovementMotor.new()
 var dt:=1.0/120
 var v:=Vector3.ZERO
 for i in 60:v=m.step(v,Vector3.FORWARD*m.jog_speed,0,dt)
 check("start reaches jog in .5s",v.length()>=3.8 and v.length()<=4.2,v.length())
 for i in 60:v=m.step(v,Vector3.FORWARD*m.jog_speed,0,dt)
 check("one second reaches target without oscillation",absf(v.length()-5)<.001,v.length())
 v=Vector3.FORWARD*8;var seconds:=0.;var distance:=0.
 while v.length()>.02 and seconds<2:
  v=m.step(v,Vector3.ZERO,0,dt);seconds+=dt;distance+=v.length()*dt
 check("8mps release stops within .5-.8s",seconds>=.5 and seconds<=.8,{"time":seconds,"distance":distance})
 v=Vector3.FORWARD*8
 var first:=m.step(v,Vector3.RIGHT*8.5,1,dt)
 check("90 degree cut brakes immediately without snapping",first.length()<8 and first.angle_to(v)<.1,first)
 for i in 30:v=m.step(v,Vector3.RIGHT*8.5,1,dt)
 check("90 degree turn sheds speed",v.length()<7.0 and v.x>0,v)
 v=Vector3.FORWARD*8;var reversed_at:=-1.;var min_speed:=8.
 for i in 180:
  v=m.step(v,Vector3.BACK*8.5,1,dt);min_speed=minf(min_speed,v.length())
  if v.z>0 and reversed_at<0:reversed_at=i*dt
 check("reverse brakes before restarting, no fixed timer",min_speed<.2 and reversed_at>.3 and reversed_at<1,{"min_speed":min_speed,"reverse_time":reversed_at})
 var yaw:=m.turn_body(0,PI,8,dt)
 check("body cannot rotate 180 in one tick",absf(yaw)<.1 and absf(yaw)>0,yaw)
 v=Vector3.FORWARD*4;var expected:=m.predict_velocity(v,Vector3.RIGHT*4,1,dt)
 check("prediction matches integration",expected.is_equal_approx(m.step(v,Vector3.RIGHT*4,1,dt)))
 m.observe_velocity(Vector3.ZERO)
 check("animation reports collision-resolved stop",m.animation_speed==0 and m.current_speed==0)
 var sprint:=preload("res://Player/Sprint.gd").new();var stamina:=100.;var locked:=false
 for i in 1200:
  var r:=sprint.update_state(true,8,false,stamina,locked,false,dt);stamina=r.stamina;locked=r.locked
 check("ten seconds of sprint consumes energy and locks",stamina<2.1 and locked,stamina)
 m.free();sprint.free()
 print("RESULT ","PASS" if failed==0 else "FAIL")
 quit(1 if failed else 0)
