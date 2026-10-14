class_name FootballMovementMotor
extends Node
## V0.7: horizontal response only. The existing swept motor owns collision/position.
@export var walk_speed:=2.5
@export var jog_speed:=5.0
@export var sprint_speed:=8.5
@export var acceleration:=8.0
@export var deceleration:=12.0
@export var rotation_speed:=7.0
@export var fast_rotation_speed:=2.8
@export var lateral_acceleration:=5.5
var current_speed:=0.0
var target_speed:=0.0
var movement_intent:=Vector3.ZERO
var movement_direction:=Vector3.ZERO
var facing_direction:=Vector3.FORWARD
var animation_speed:=0.0
var actual_acceleration:=Vector3.ZERO
var controlled:=false
var motion_state:="IDLE"

# Pure integration also used by the short-horizon dribble prediction.
func predict_velocity(flat:Vector3,desired:Vector3,sprint:float,dt:float,guard:bool=false)->Vector3:
 if not flat.is_finite() or not desired.is_finite() or dt<=0:return flat
 desired=Vector3(desired.x,0,desired.z).limit_length(3.0 if guard else sprint_speed)
 var speed:=flat.length()
 var brake:=18.0 if controlled else deceleration
 if guard:brake=18.0
 var accel:=lerpf(12.0,6.0,sprint) if controlled else acceleration
 if desired.length_squared()<.0001:return flat.move_toward(Vector3.ZERO,brake*dt)
 if speed<1.3:
  return flat.move_toward(desired,(brake if flat.dot(desired)<0 else accel)*dt)
 var axis:=flat/speed
 var alignment:=axis.dot(desired.normalized())
 # A reversal first spends momentum; it never waits for a fixed animation timer.
 if alignment<-.35:return flat.move_toward(Vector3.ZERO,brake*dt)
 var along:=desired.dot(axis)
 var side:=desired-axis*along
 var forward_rate:=brake if along<speed else accel
 var lateral_rate:=lerpf(12.0,lateral_acceleration,smoothstep(1.3,8.5,speed))
 if guard:lateral_rate=14.0
 var next:=axis*move_toward(speed,along,forward_rate*dt)+side.limit_length(lateral_rate*dt)
 return next.limit_length(maxf(speed,desired.length()))

func step(flat:Vector3,desired:Vector3,sprint:float,dt:float,guard:bool=false)->Vector3:
 movement_intent=desired
 target_speed=desired.length()
 var next:=predict_velocity(flat,desired,sprint,dt,guard)
 actual_acceleration=(next-flat)/maxf(dt,.000001)
 current_speed=next.length()
 movement_direction=next.normalized() if current_speed>.03 else Vector3.ZERO
 animation_speed=clampf(current_speed/sprint_speed,0,1)
 motion_state="IDLE" if current_speed<.05 else "BRAKE" if desired.length()<.05 or flat.dot(desired)<0 else "TURN" if flat.length()>1.3 and flat.normalized().dot(desired.normalized())<.7 else "SPRINT" if sprint>.5 else "RUN" if current_speed>walk_speed else "WALK"
 return next

func turn_body(yaw:float,target_yaw:float,speed:float,dt:float)->float:
 var rate:=lerpf(rotation_speed,fast_rotation_speed,smoothstep(2.0,sprint_speed,speed))
 var result:=yaw+clampf(angle_difference(yaw,target_yaw),-rate*dt,rate*dt)
 facing_direction=Vector3(-sin(result),0,-cos(result))
 return result

func observe_velocity(velocity:Vector3)->void:
 # Actual post-collision speed, rather than requested speed, drives animation.
 var flat:=Vector3(velocity.x,0,velocity.z)
 current_speed=flat.length()
 movement_direction=flat.normalized() if current_speed>.03 else Vector3.ZERO
 animation_speed=clampf(current_speed/sprint_speed,0,1)
 if current_speed<.05:motion_state="IDLE"

func animation_state()->Dictionary:
 return {"speed":current_speed,"normalized_speed":animation_speed,"movement_direction":movement_direction,"facing_direction":facing_direction,"state":motion_state}

func reset()->void:
 current_speed=0;target_speed=0;animation_speed=0;actual_acceleration=Vector3.ZERO
 movement_intent=Vector3.ZERO;movement_direction=Vector3.ZERO;motion_state="IDLE"
