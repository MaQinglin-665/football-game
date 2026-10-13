class_name FootballShiftTierInput
extends Node
## Observes Shift only, never consumes WASD or GUI events.
signal policy_changed(policy: Dictionary)
signal intent_emitted(intent: Dictionary)
signal notice_emitted(notice: Dictionary)

const Router := preload("res://addons/football_shift_tiers/shift_tier_router.gd")
@export var automatic_tick := true
@export var observe_input := true
@export var profile_path := "res://addons/football_shift_tiers/shift_profile.json"
var router: RefCounted

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	install_shift_default()
	_ensure_router()

static func install_shift_default() -> void:
	if InputMap.has_action("ff_sprint"):
		return
	InputMap.add_action("ff_sprint")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_SHIFT
	InputMap.action_add_event("ff_sprint", event)

func _ensure_router() -> void:
	if router != null:
		return
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(profile_path)) if FileAccess.file_exists(profile_path) else {}
	router = Router.new(config if config is Dictionary else {})
	router.policy_changed.connect(func(payload: Dictionary) -> void: policy_changed.emit(payload))
	router.intent_emitted.connect(func(payload: Dictionary) -> void: intent_emitted.emit(payload))
	router.notice_emitted.connect(func(payload: Dictionary) -> void: notice_emitted.emit(payload))

func set_context(context: Dictionary, timestamp_usec: int = -1) -> void:
	_ensure_router()
	router.set_context(context, timestamp_usec)

func set_direction(move_direction: Vector3, aim_forward: Vector3 = Vector3.FORWARD) -> void:
	_ensure_router()
	router.set_direction(move_direction, aim_forward)

func feed_event(event: InputEvent, timestamp_usec: int = -1) -> bool:
	_ensure_router()
	if not event.is_action("ff_sprint", false):
		return false
	var source := ""
	if event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		source = "key:%d:%d:%d" % [code, event.location, event.device]
	elif event is InputEventAction:
		source = "action:%s:%d" % [event.action, event.device]
	elif event is InputEventMouseButton:
		source = "mouse:%d:%d" % [event.button_index, event.device]
	if source.is_empty():
		return false
	return router.feed_shift(event.is_pressed(), source, event is InputEventKey and event.echo, timestamp_usec)

func tick(timestamp_usec: int = -1) -> void:
	_ensure_router()
	router.tick(timestamp_usec)

func _physics_process(_delta: float) -> void:
	if automatic_tick:
		tick()

func _input(event: InputEvent) -> void:
	if observe_input:
		feed_event(event)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		set_context({"focused": false})
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		set_context({"focused": true})
	elif what == NOTIFICATION_EXIT_TREE and router != null:
		router.reset("adapter_removed")

func reset(reason: String = "host_reset", timestamp_usec: int = -1) -> void:
	_ensure_router()
	router.reset(reason, timestamp_usec)

func snapshot() -> Dictionary:
	_ensure_router()
	return router.snapshot()

