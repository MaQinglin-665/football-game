extends RefCounted
## Scalar-only visual intent. No skeleton, actor, ball or camera ownership.
var eligible:=false
var state_name:="IDLE"
var pending_state:=""
var age:=0.0
var lean:=0.0
var bank:=0.0
var sink:=0.0
var arm:=0.0
var yaw_offset:=0.0
var _lean_rate:=0.0
var _bank_rate:=0.0
var _last_speed:=0.0
var _plant_left:=false
var _plant_right:=false
var _stance_seen:=false
var support_side:=""
var first_person:=false

static func cycles(speed:float)->float:
	# Artistic targets in steps/s, two alternating steps per cycle. Continuous
	# knots, not population norms. Near zero tends to zero rather than shuffling.
	var v:float=maxf(0,speed)
	if v<1.4:return 1.95*(v/1.4)*(2.0-v/1.4)*.5
	if v<3.0:return lerpf(1.95,2.85,smoothstep(1.4,3.0,v))*.5
	if v<6.4:return lerpf(2.85,4.35,smoothstep(3.0,6.4,v))*.5
	return lerpf(4.35,4.70,smoothstep(6.4,8.0,v))*.5

func update(dt:float,motion:Dictionary,action:Dictionary,plants:Dictionary)->void:
	if dt<=0:return
	var velocity:Vector3=motion.get("velocity",Vector3.ZERO)
	velocity.y=0
	var speed:float=velocity.length()
	var interaction:Dictionary=motion.get("interaction",{})
	eligible=action.is_empty() and String(motion.get("control_tier","")).to_upper()=="FREE" and bool(motion.get("grounded",true)) and not bool(interaction.get("mobility_busy",false)) and not bool(interaction.get("airborne",false)) and float(interaction.get("crouch",0))<=0 and float(interaction.get("header_weight",0))<=0
	if not eligible:
		lean=0;bank=0;sink=0;arm=0;yaw_offset=0
		_lean_rate=0;_bank_rate=0;pending_state="";state_name="IDLE"
		_last_speed=speed;_stance_seen=false
		return
	var forward:Vector3=motion.get("forward",Vector3.FORWARD)
	forward.y=0
	if forward.length_squared()<.0001:forward=Vector3.FORWARD
	forward=forward.normalized()
	var travel:Vector3=velocity/speed if speed>.10 else forward
	var acceleration:Vector3=motion.get("acceleration",Vector3.ZERO)
	acceleration.y=0
	acceleration=acceleration.limit_length(18.0)
	var longitudinal:float=acceleration.dot(travel)
	var travel_right:=Vector3(-travel.z,0,travel.x)
	# The normal component of actual acceleration already measures v^2/r;
	# no unstable radius division at zero speed, and no camera-turn fake bank.
	var lateral:float=acceleration.dot(travel_right)
	var wanted:String="IDLE" if speed<.08 else "MOVE"
	if speed>.25 and longitudinal< -2.0:wanted="BRAKE"
	elif speed>.75 and absf(lateral)>2.5:wanted="CUT"
	elif speed>.08 and longitudinal>2.0 and speed<3.0:wanted="START"
	var left:bool=plants.has("L") and not bool(plants.L.get("releasing",false))
	var right:bool=plants.has("R") and not bool(plants.R.get("releasing",false))
	var landed:bool=left and not _plant_left or right and not _plant_right
	if landed:support_side="L" if left and not _plant_left else "R"
	_plant_left=left;_plant_right=right
	# Use the previous completed actual plant, never an extra support snapshot.
	# A grounded first frame/start/stop can enter immediately; cuts/brakes wait
	# for a new support edge. They never commandeer an airborne/action foot.
	if wanted!=state_name:pending_state=wanted
	else:pending_state=""
	if not pending_state.is_empty() and (landed or not _stance_seen and (left or right) or _last_speed<.08 or speed<.08):
		state_name=pending_state;pending_state="";age=0
	else:age+=dt
	_stance_seen=true;_last_speed=speed
	var turn:float=forward.signed_angle_to(travel,Vector3.UP)
	# Free locomotion faces its travel direction; torso counter-yaw remains
	# bounded to 60 degrees. There are no authored strafe/backpedal clips.
	yaw_offset=lerp_angle(yaw_offset,turn*smoothstep(.10,.60,speed),1.0-exp(-10.0*dt))
	var comfort:float=.30 if first_person else 1.0
	var pitch_target:float=clampf(-atan2(longitudinal,9.81)*.45,-.27,.22)*comfort
	var bank_target:float=clampf(-atan2(lateral,9.81)*.45,-.25,.25)*comfort
	# Exact critically damped scalar spring (5 Hz), stable even on long frames.
	var omega:float=TAU*5.0
	var decay:float=exp(-omega*dt)
	var error:float=lean-pitch_target
	var term:float=_lean_rate+omega*error
	lean=pitch_target+(error+term*dt)*decay
	_lean_rate=(_lean_rate-omega*term*dt)*decay
	error=bank-bank_target;term=_bank_rate+omega*error
	bank=bank_target+(error+term*dt)*decay
	_bank_rate=(_bank_rate-omega*term*dt)*decay
	var load:float=clampf(acceleration.length()/9.0,0,1)
	sink=lerpf(sink,(.020+.045*load)*comfort if state_name in ["START","BRAKE","CUT"] else 0.0,1.0-exp(-12.0*dt))
	arm=lerpf(arm,load if state_name in ["START","BRAKE","CUT"] else 0.0,1.0-exp(-12.0*dt))

func debug()->Dictionary:
	return {"revision":"locomotion_intent_039","eligible":eligible,"state":state_name,"pending":pending_state,"age_s":age,"support_side":support_side,"lean_rad":lean,"bank_rad":bank,"sink_m":sink,"arm_load":arm,"travel_yaw_rad":yaw_offset,"first_person":first_person}
