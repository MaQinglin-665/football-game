class_name FBMatchRefereePresenter
extends Node3D

@export var follow_speed: float = 6.0
@export var enabled: bool = true
var current_gesture: String = "idle"
var _gesture_age: float = 0.0
var _shirt: Material
var _placeholder: Node3D
var _right_arm: Node3D
var _left_arm: Node3D
var _external_avatar: Node3D
var _ball_point: Vector3 = Vector3.ZERO
var _target: Vector3 = Vector3(6, 0, 3)
var _moving: bool = false
var _walk_time: float = 0.0
var _legs: Array[Node3D] = []
var _marker: Label3D

func _ready() -> void:
	# Deliberately Node3D-only: never blocks or deflects the match ball.
	build_placeholder()
	position = Vector3(6, 0, 3)

func build_placeholder() -> void:
	_placeholder = Node3D.new()
	_placeholder.name = "ReplaceableRefereeVisual"
	add_child(_placeholder)
	_shirt = _material(Color("decb50"))
	var black := _material(Color("202c31"))
	var skin := _material(Color("ad7856"))
	_capsule(_placeholder, Vector3(0, 1.20, 0), 0.20, 0.54, _shirt)
	_capsule(_placeholder, Vector3(0, 0.87, 0), 0.18, 0.30, black)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.135
	sphere.height = 0.28
	head.mesh = sphere
	head.position = Vector3(0, 1.62, 0)
	head.material_override = skin
	_placeholder.add_child(head)
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.10, 0.84, 0)
		_placeholder.add_child(leg)
		_capsule(leg, Vector3(0, -0.30, 0), 0.065, 0.61, black)
		_capsule(leg, Vector3(0, -0.70, -0.055), 0.067, 0.19, black)
		_legs.append(leg)
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.21, 1.40, 0)
		_placeholder.add_child(arm)
		_capsule(arm, Vector3(0, -0.14, 0), 0.068, 0.28, _shirt)
		_capsule(arm, Vector3(0, -0.36, 0), 0.050, 0.27, skin)
		if side > 0:
			_right_arm = arm
		else:
			_left_arm = arm
	_marker = Label3D.new()
	_marker.text = "REF"
	_marker.font_size = 28
	_marker.pixel_size = 0.005
	_marker.outline_size = 4
	_marker.position = Vector3(0, 1.95, 0)
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_placeholder.add_child(_marker)

func bind_avatar(avatar: Node3D) -> void:
	_external_avatar = avatar
	if _placeholder != null:
		_placeholder.visible = avatar == null
	# Replacement visual must also have collision_layer/mask = 0 if it contains physics nodes.

func observe_ball(at: Vector3, live: bool) -> void:
	_ball_point = at
	_target = Vector3(at.x + 5.5, 0, at.z + 3.5)
	_moving = live

func present(event: Dictionary) -> void:
	if str(event.get("type", "")) != "referee_signal":
		return
	current_gesture = str(event.get("gesture", "idle"))
	_gesture_age = 2.6
	var at: Vector3 = event.get("point", _ball_point)
	_ball_point = at
	if current_gesture not in ["period_end", "goal"]:
		_target = Vector3(at.x + 4.0, 0, at.z + 3.0)
	if is_instance_valid(_external_avatar) and _external_avatar.has_method("present_referee_signal"):
		_external_avatar.call("present_referee_signal", event)

func _process(delta: float) -> void:
	visible = enabled
	if not enabled:
		return
	_gesture_age = maxf(0.0, _gesture_age - delta)
	var old := global_position
	global_position = global_position.move_toward(_target, follow_speed * delta)
	global_position.y = 0.0
	var toward := _ball_point - global_position
	toward.y = 0
	if toward.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(-toward.x, -toward.z), minf(delta * 6, 1))
	var walking := global_position.distance_to(old) > 0.001
	_walk_time += delta * 8.0
	for i in range(_legs.size()):
		_legs[i].rotation.x = sin(_walk_time + i * PI) * (0.22 if walking else 0.0)
	var arm_angle := 0.0
	if _gesture_age > 0:
		arm_angle = -2.9 if current_gesture == "indirect_free_kick" else -1.48 if current_gesture == "ready" else -1.05
		if current_gesture == "period_end":
			arm_angle = 0.0
	if _right_arm != null:
		_right_arm.rotation.x = lerpf(_right_arm.rotation.x, arm_angle, minf(delta * 12, 1))
	if _left_arm != null:
		_left_arm.rotation.x = lerpf(_left_arm.rotation.x, -0.60 if _gesture_age > 0 and current_gesture == "penalty" else 0.0, minf(delta * 12, 1))

func _capsule(parent: Node3D, at: Vector3, radius: float, height: float, material: Material) -> void:
	var visual := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height, radius * 2)
	mesh.radial_segments = 10
	mesh.rings = 4
	visual.mesh = mesh
	visual.position = at
	visual.material_override = material
	parent.add_child(visual)

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	return material
