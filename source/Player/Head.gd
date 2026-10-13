extends Node3D


@export_node_path("Camera3D") var cam_path := NodePath("Camera")
@onready var cam: Camera3D = get_node(cam_path)

@export var mouse_sensitivity := 2.0
@export var y_limit := 90.0
## R004 camera comfort
const PITCH_DOWN_LIMIT_DEG := 55.0
const PAD_DEADZONE := 0.12
const PAD_EXPONENT := 2.0 # quadratic response
const PAD_SPEED := 1000.0
var enabled := true
var mouse_axis := Vector2()
var rot := Vector3()


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	mouse_sensitivity = mouse_sensitivity / 1000
	y_limit = deg_to_rad(minf(y_limit,PITCH_DOWN_LIMIT_DEG))


# Called when there is an input event
func _input(event: InputEvent) -> void:
	# Mouse look (only if the mouse is captured).
	if enabled and event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		mouse_axis = event.relative
		camera_rotation()


# R004: gamepad look per rendered frame with radial deadzone + quadratic curve.
func _process(delta: float) -> void:
	var raw := Vector2(Input.get_axis(&"look_left", &"look_right"), Input.get_axis(&"look_down", &"look_up"))
	var shaped := pad_curve(raw)
	if enabled and shaped != Vector2.ZERO:
		mouse_axis = shaped * PAD_SPEED * delta
		camera_rotation()

static func pad_curve(raw: Vector2) -> Vector2:
	var m := minf(raw.length(), 1.0)
	if m <= PAD_DEADZONE: return Vector2.ZERO
	var t := (m - PAD_DEADZONE) / (1.0 - PAD_DEADZONE)
	return raw.normalized() * pow(t, PAD_EXPONENT)


func camera_rotation() -> void:
	# Horizontal mouse look.
	rot.y -= mouse_axis.x * mouse_sensitivity
	# Vertical mouse look.
	rot.x = clamp(rot.x - mouse_axis.y * mouse_sensitivity, -y_limit, deg_to_rad(38.0))
	
	var actor=get_owner()
	var visual:Node3D=actor.avatar.visual if actor.avatar!=null else null
	var saved_basis:Basis=visual.global_basis if visual!=null else Basis.IDENTITY
	actor.rotation.y = rot.y
	if visual!=null:visual.global_basis=saved_basis
	rotation.x = rot.x
