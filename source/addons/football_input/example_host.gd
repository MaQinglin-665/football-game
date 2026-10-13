extends Node
## Minimal integration boundary. All outputs are semantic requests.
## The main integrator owns scheduling, restart authority, contact and physics.
signal movement_requested(intent: Dictionary)
signal call_ball_requested(intent: Dictionary)
signal policy_requested(intent: Dictionary)
signal foot_action_requested(intent: Dictionary)
signal goalkeeper_action_requested(intent: Dictionary)
signal restart_requested(intent: Dictionary)
signal charge_preview_changed(intent: Dictionary)
signal ui_command_requested(command: String)
signal input_notice(notice: Dictionary)

const Adapter := preload("res://addons/football_input/input_adapter.gd")
const POLICY_ACTIONS := ["close_control", "shield", "push_ball", "pressure", "keeper_ready"]
var input_adapter: Node
var authoritative_context: Dictionary = {"phase": "menu"}

func _ready() -> void:
	input_adapter = Adapter.new()
	input_adapter.automatic_tick = false
	add_child(input_adapter)
	input_adapter.intent_emitted.connect(_on_intent)
	input_adapter.ui_requested.connect(func(command: String) -> void: ui_command_requested.emit(command))
	input_adapter.notice_emitted.connect(func(notice: Dictionary) -> void: input_notice.emit(notice))

func update_input(delta: float, host_context: Dictionary, camera_forward: Vector3, camera_right: Vector3) -> void:
	# Call once from the host's physics tick after fresh context, before action
	# scheduling. If the host calls tick(), automatic_tick must remain false.
	authoritative_context = host_context.duplicate(true)
	input_adapter.set_context(host_context)
	input_adapter.set_aim(camera_forward, camera_right)
	input_adapter.tick(delta)

func apply_context_immediately(patch: Dictionary) -> void:
	# Use this synchronously from pause/help/restart/capability handlers.
	authoritative_context.merge(patch, true)
	input_adapter.set_context(patch)

func _on_intent(intent: Dictionary) -> void:
	if intent.has("gesture_id"):
		charge_preview_changed.emit(intent)
		if intent.phase != "commit":
			return
	if intent.action == "move":
		movement_requested.emit(intent)
	elif intent.action in POLICY_ACTIONS and intent.phase != "commit":
		policy_requested.emit(intent)
	elif intent.phase == "commit":
		if authoritative_context.get("phase", "menu") == "dead_ball":
			restart_requested.emit(intent)
		elif intent.action == "call_ball":
			call_ball_requested.emit(intent)
		elif intent.action.begins_with("keeper_"):
			goalkeeper_action_requested.emit(intent)
		else:
			foot_action_requested.emit(intent)
