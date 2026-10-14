extends SceneTree
const BodyDirection := preload("res://scripts/player_body_direction.gd")
const Motor := preload("res://Player/MovementMotor.gd")
const SharedMovement := preload("res://scripts/football_shared_movement.gd")
var failures:=0
func check(label:String,ok:bool)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:
	check("retreat prioritizes view at any speed",absf(BodyDirection.target(0,Vector3.BACK,Vector3.FORWARD*5,true))<.0001)
	check("stationary view can turn in world",absf(BodyDirection.target(PI,Vector3.ZERO,Vector3.ZERO,true)-PI)<.0001)
	var left:float=BodyDirection.target(0,Vector3.LEFT,Vector3.LEFT*5,true)
	var right:float=BodyDirection.target(0,Vector3.RIGHT,Vector3.RIGHT*5,true)
	check("strafe offsets mirror and preserve viewing stance",absf(left+right)<.0001 and absf(left)<=deg_to_rad(35.1))
	check("no body target switch at 2mps",absf(BodyDirection.target(0,Vector3.RIGHT,Vector3.RIGHT*1.99,true)-BodyDirection.target(0,Vector3.RIGHT,Vector3.RIGHT*2.01,true))<.01)
	var motor=Motor.new()
	check("hips do not snap to camera",absf(angle_difference(PI,motor.turn_body(PI,0,4,1.0/120)))<.07)
	var cfg=FootballControlTuning.new()
	var state={"facing":Vector3.LEFT,"movement_facing":Vector3.FORWARD,"owned":true,"stamina":100.0}
	var command={"enabled":true,"move":Vector3.RIGHT,"tier":"run"}
	check("opposite strafe does not become retreat",not SharedMovement.resolve(command,state,cfg,.01).backwards)
	state.facing=Vector3.BACK;command.move=Vector3.BACK
	check("camera back is retreat even with hips reversed",SharedMovement.resolve(command,state,cfg,.01).backwards)
	motor.free()
	quit(0 if failures==0 else 1)
