extends RefCounted
## Scalar cadence/support handoff only. Real action time/side/target owns touch.
var eligible:=false
var direction_eligible:=false
var active:=false
var rate:=0.0
var fraction:=.58
var blend:=0.0
var held_base:=""
var last_speed:=0.0
var window_locked:=false
var sequence:=-1
var _initialized:=false

func prepare(dt:float,state:Dictionary,action:Dictionary)->void:
	var velocity:Vector3=state.get("velocity",Vector3.ZERO)
	last_speed=Vector2(velocity.x,velocity.z).length()
	var interaction:Dictionary=state.get("interaction",{})
	var mode:String=String(state.get("locomotion","")).to_lower()
	var tier:String=String(state.get("control_tier","")).to_upper()
	var ordinary:bool=action.is_empty() or String(action.get("kind","")).to_upper() in ["CARRY","CLOSE","SHIELD","TURN","SPRINT"] and String(action.get("surface","")).to_upper() in ["INSIDE","OUTSIDE","INSTEP"]
	direction_eligible=last_speed>=.08 and (mode=="dribble" or mode in ["retreat","shield","jockey"] and tier in ["CLOSE","CRUISE","KNOCK_CHASE"]) and ordinary and bool(state.get("grounded",true)) and not bool(interaction.get("mobility_busy",false)) and not bool(interaction.get("airborne",false)) and float(interaction.get("crouch",0))<=0 and float(interaction.get("header_weight",0))<=0
	eligible=direction_eligible and mode=="dribble"
	window_locked=not action.is_empty() and String(action.get("phase","")).to_upper() in ["PREPARE","CONTACT"]
	sequence=int(action.get("sequence",-1))
	if not eligible:
		active=false;held_base="";_initialized=false
	elif last_speed>2.10:
		active=true
	# The normal low Dribble branch is left untouched. A returning Jog keeps
	# its continuous clock until it can hand back to Dribble outside contact.
	elif held_base=="Dribble" and not window_locked:
		active=false;_initialized=false
	if dt<=0:return
	if not active:return
	var wanted_blend:float=smoothstep(2.10,3.40,last_speed)
	var slow_rate:float=minf(last_speed,2.10)*.58/.46
	var fast_rate:float=_running_cycles(last_speed)*1.18
	var target_rate:float=lerpf(slow_rate,fast_rate,wanted_blend)
	var distance:float=lerpf(.46,.64,wanted_blend)
	var target_fraction:float=minf(lerpf(.58,.29,wanted_blend),distance*target_rate/maxf(last_speed,.001))
	if not _initialized:
		rate=target_rate;fraction=target_fraction;blend=wanted_blend;_initialized=true
	elif not window_locked:
		var response:float=1.0-exp(-12.0*dt)
		rate=lerpf(rate,target_rate,response)
		fraction=lerpf(fraction,target_fraction,response)
		blend=lerpf(blend,wanted_blend,response)
		# Never hold a planted foot longer than the released distance budget.
		fraction=minf(fraction,distance*rate/maxf(last_speed,.001))

static func _running_cycles(speed:float)->float:
	if speed<3.0:return lerpf(1.95,2.85,smoothstep(1.4,3.0,speed))*.5
	if speed<6.4:return lerpf(2.85,4.35,smoothstep(3.0,6.4,speed))*.5
	return lerpf(4.35,4.70,smoothstep(6.4,8.0,speed))*.5

func select_base(wanted:String)->String:
	if not eligible:
		held_base=""
		return wanted
	if not active:
		held_base=wanted
		return wanted
	if not held_base in ["Dribble","DribbleJog"]:held_base=wanted
	elif not window_locked:
		if wanted=="Dribble" and held_base=="DribbleJog":
			# Return to the exact low branch only after its scalar rate/duty are
			# recovered. Do not turn a deceleration into a one-frame clock jump.
			if absf(rate-last_speed*.58/.46)>.025 or absf(fraction-.58)>.015:return held_base
		held_base=wanted
	return held_base

func hold_support(side:String,action:Dictionary,plants:Dictionary,contacts:Dictionary,ground_y:float)->bool:
	if not active or not window_locked or action.is_empty():return false
	var touch:String="L" if int(action.get("side",1))<=0 else "R"
	if side==touch or not plants.has(side) or bool(plants[side].get("releasing",false)):return false
	if not contacts.get(side) is Vector3:return false
	# This admits only a prior actual near-ground plant; the existing leg solve
	# can still reject/release it. This never certifies future contact permission.
	return absf((contacts[side] as Vector3).y-ground_y)<=.020

func debug()->Dictionary:
	return {"revision":"carry_gait_039","active":active,"base":held_base,"cycles_per_s":rate,"support_fraction":fraction,"blend":blend,"contact_window_locked":window_locked,"action_sequence":sequence}
