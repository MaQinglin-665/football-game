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
