extends "res://scripts/integration_player_motor.gd"
class_name MovementController
## FirstPersonStarter scene/Head/Sprint API retained; the verified motor is the
## only movement integrator. Host input is supplied through semantic commands.
@export var speed := 5.6
@export var input_enabled := true
@export var external_input := true
var external_direction := Vector3.ZERO
var direction := Vector3.ZERO
var input_axis := Vector2.ZERO

@export var controller_v07_enabled:=true
var movement_motor:FootballMovementMotor

func _ready()->void:
 movement_motor=FootballMovementMotor.new()
 movement_motor.name="MovementMotor"
 add_child(movement_motor)
 super._ready()

func integrate_horizontal(flat:Vector3,desired:Vector3,dt:float,guard:bool)->Vector3:
 if not controller_v07_enabled:return super.integrate_horizontal(flat,desired,dt,guard)
 return movement_motor.step(flat,desired,sprint_intent,dt,guard)

func predict_controller_velocity(flat:Vector3,desired:Vector3,sprint:float,dt:float)->Vector3:
 return movement_motor.predict_velocity(flat,desired,sprint,dt,bool(get_meta("motor_guard",false)))

var _controller_tuning:Resource
func controller_tuning(base:Resource)->Resource:
 if _controller_tuning==null:_controller_tuning=base.duplicate()
 # Gameplay tuning can change at runtime; only override free locomotion targets.
 for key in ["normal_ball_speed","sprint_ball_speed","shield_speed","close_speed","retreat_close_speed","retreat_fast_speed","retreat_speed"]:_controller_tuning.set(key,base.get(key))
 _controller_tuning.normal_move_speed=movement_motor.jog_speed
 _controller_tuning.running_move_speed=movement_motor.sprint_speed
 _controller_tuning.big_chase_speed=movement_motor.sprint_speed
 return _controller_tuning

func motor_speed_limit(sprint:float)->float:
 if not controller_v07_enabled:return super.motor_speed_limit(sprint)
 return lerpf(maxf(profile.jog_speed_mps,movement_motor.jog_speed),movement_motor.sprint_speed,sprint)
