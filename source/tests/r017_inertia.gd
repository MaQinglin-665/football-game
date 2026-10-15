extends SceneTree
const Motor=preload("res://Player/MovementMotor.gd")
var rows:Array=[]
var checks:Array=[]
func simulate(m:Node,owned:bool,start:Vector3,desired:Vector3,seconds:float)->Dictionary:
	m.controlled=owned;m.sprint_speed=5.6;m.jog_speed=3.2
	var v:=start
	var p:=Vector3.ZERO
	for i in int(round(seconds*120)):
		v=m.predict_velocity(v,desired,1.0,1.0/120.0);p+=v/120.0
	return {"x":v.x,"z":v.z,"speed":v.length(),"distance":p.length()}
func _initialize()->void:
	var reference:=GDScript.new()
	reference.source_code=FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../../candidate-r016/source/Player/MovementMotor.gd")).replace("class_name FootballMovementMotor","")
	if reference.reload()!=OK:quit(1);return
	var old=reference.new();var current=Motor.new()
	for owned in [true,false]:
		for spec in [{"name":"launch","start":Vector3.ZERO,"target":Vector3.FORWARD*5,"time":.2},{"name":"low_side","start":Vector3.FORWARD,"target":Vector3.RIGHT,"time":.1},{"name":"fast_side","start":Vector3.FORWARD*5,"target":Vector3.RIGHT*5,"time":.2},{"name":"fast_reverse","start":Vector3.FORWARD*5,"target":Vector3.BACK*5,"time":.2},{"name":"release","start":Vector3.FORWARD*5,"target":Vector3.ZERO,"time":.6}]:
			var before:=simulate(old,owned,spec.start,spec.target,spec.time)
			var after:=simulate(current,owned,spec.start,spec.target,spec.time)
			var ok:bool=true
			if spec.name=="launch":ok=after.speed>before.speed*1.2 if owned else absf(after.speed-before.speed)<.001
			if spec.name=="low_side":ok=after.x>=before.x-.001 and absf(after.z)<=absf(before.z)+.001 and after.speed<=1.001
			if spec.name=="fast_side":ok=after.x<before.x and after.z<0
			if spec.name=="fast_reverse":ok=after.z<before.z and after.z<0
			if spec.name=="release":ok=after.speed<.01 and absf(after.distance-before.distance)<.001
			rows.append({"controlled":owned,"scenario":spec.name,"before":before,"after":after,"passed":ok})
	old.free();current.free()
	FileAccess.open(ProjectSettings.globalize_path("res://../verification/inertia.json"),FileAccess.WRITE).store_string(JSON.stringify(rows,"\t"))
	print("MOTOR_COMPARISON ",rows.all(func(r):return r.passed))
	quit(0 if rows.all(func(r):return r.passed) else 1)

