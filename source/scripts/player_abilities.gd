extends RefCounted
# Designed capabilities, not learned cheats. Identity is jersey/team, not array index
# or the currently selected formation slot. Human and goalkeeper stay unchanged.
const BALANCED={"role":"balanced","pace":1.0,"accel":1.0,"turn":1.0,"brake":1.0,"endurance":1.0,"touch":1.0,"pass_error_deg":.75,"mass":1.0}
const TYPES={
	"breaker":{"role":"breaker","pace":1.08,"accel":1.12,"turn":1.10,"brake":1.04,"endurance":1.15,"touch":1.04,"pass_error_deg":1.0,"mass":.97},
	"conductor":{"role":"conductor","pace":.95,"accel":.97,"turn":1.03,"brake":1.0,"endurance":.98,"touch":1.06,"pass_error_deg":.28,"mass":.98},
	"sweeper":{"role":"sweeper","pace":1.0,"accel":1.02,"turn":1.04,"brake":1.10,"endurance":.84,"touch":.94,"pass_error_deg":1.05,"mass":1.04}}

static func identity(jersey:int,count:int)->String:
	if count==3:return "conductor" if jersey==10 else "sweeper" if jersey==7 else "breaker" if jersey==11 else "balanced"
	if jersey==8:return "conductor"
	if jersey==(4 if count==6 else 14):return "sweeper"
	if jersey==(9 if count==6 else 11 if count==9 else 7):return "breaker"
	return "balanced"

static func attach(actor:Node,base:Resource,count:int,disabled:bool=false)->void:
	if actor.is_human or actor.is_goalkeeper or disabled:
		actor.profile=base;actor.set_meta("abilities",{});actor.remove_meta("ability_movement");return
	var kind:String=identity(int(actor.jersey),count)
	var spec:Dictionary=TYPES.get(kind,BALANCED).duplicate(true)
	actor.set_meta("abilities",spec)
	var p:Resource=base.duplicate(true)
	p.sprint_speed_mps*=float(spec.pace)
	p.start_acceleration_mps2*=float(spec.accel);p.sprint_acceleration_mps2*=float(spec.accel)
	p.turn_acceleration_mps2*=float(spec.turn);p.brake_deceleration_mps2*=float(spec.brake)
	p.player_mass_kg*=float(spec.mass)
	p.set_meta("ability_brake",spec.brake);p.set_meta("ability_turn",spec.turn)
	p.set_meta("ability_base_profile",base)
	actor.profile=p
	var movement:Resource=actor.match_controller.tuning.duplicate(true)
	movement.running_move_speed*=float(spec.pace)
	movement.set_meta("endurance",spec.endurance)
	actor.set_meta("ability_movement",movement)

static func apply_roster(game:Node)->void:
	var disabled:bool="--abilities=off" in OS.get_cmdline_user_args()
	for actor in game.players:attach(actor,game.physics_profile,game.team_size,disabled)

static func value(actor:Node,key:String,fallback:float=1.0)->float:
	return float(actor.get_meta("abilities",{}).get(key,fallback))

static func observation(actor:Node)->Dictionary:
	var spec:Dictionary=actor.get_meta("abilities",{})
	if spec.is_empty():return {}
	var pace:float=5.6*float(spec.get("pace",1.0))
	return {"archetype":spec.get("role","balanced"),"ability_speed":pace,"ability_acceleration":actor.profile.start_acceleration_mps2,
		"ability_touch":float(spec.get("touch",1.0)),"ability_pass_error":float(spec.get("pass_error_deg",0)),
		"motor_profile":actor.profile,"movement_cfg":actor.get_meta("ability_movement",actor.match_controller.tuning),
		"endurance":float(spec.get("endurance",1.0))}

static func pass_intent(actor:Node,intent:Dictionary,sequence:int,ball_position:Vector3,players:Array)->Dictionary:
	if actor.is_human or actor.is_goalkeeper or actor.get_meta("abilities",{}).is_empty():return intent
	if not String(intent.get("action","")).begins_with("pass_"):return intent
	# Error sampled deterministically once for this contact sequence. A retry has
	# the same error. No mutation of shared intent, receiver or ball position.
	var pressure:float=0
	for opponent in players:
		if opponent.team==actor.team or not opponent.visible:continue
		pressure=maxf(pressure,1.0-clampf(opponent.position.distance_to(ball_position)/3.0,0,1))
	var fatigue:float=1.0-float(actor.get("stamina"))/100.0 if actor.get("stamina")!=null else 0.0
	var amplitude:float=value(actor,"pass_error_deg",0)*(.45+pressure*.7+fatigue*.35)
	var noise:float=sin(float(sequence*47+actor.jersey*131+actor.team*19)*12.9898)
	var result:Dictionary=intent.duplicate(true)
	result.direction=Vector3(result.direction).rotated(Vector3.UP,deg_to_rad(amplitude*noise)).normalized()
	result.ability_contact_error_deg=amplitude*noise
	return result
