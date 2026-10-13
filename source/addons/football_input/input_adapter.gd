class_name FootballInputAdapter
extends Node
## Host supplies context before gameplay input; only semantic signals go out.
signal intent_emitted(intent: Dictionary)
signal notice_emitted(notice: Dictionary)
signal ui_requested(command: String)

const Registry := preload("res://addons/football_input/input_map.gd")
const Router := preload("res://addons/football_input/intent_router.gd")
@export var enabled := true
@export var automatic_tick := true
@export var profile_path := "res://addons/football_input/action_profile.json"
var router: RefCounted

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Registry.install_defaults()
	_ensure_router()
	for conflict in Registry.conflicts():
		notice_emitted.emit({"code": "input_conflict", "message_zh": "输入映射冲突，请修正: " + str(conflict)})

func _ensure_router() -> void:
	if router != null:
		return
	router = Router.new(profile_path)
	router.intent_emitted.connect(func(intent: Dictionary) -> void: intent_emitted.emit(intent))
	router.notice_emitted.connect(func(notice: Dictionary) -> void: notice_emitted.emit(notice))
	router.ui_requested.connect(func(command: String) -> void: ui_requested.emit(command))

func set_context(context: Dictionary) -> void:
	_ensure_router()
	router.set_context(context)

func set_aim(forward: Vector3, right: Vector3 = Vector3.RIGHT) -> void:
	_ensure_router()
	router.set_aim(forward, right)

func tick(delta: float) -> void:
	_ensure_router()
	if not enabled:
		router.reset("adapter_disabled")
		return
	router.step(delta)

func _physics_process(delta: float) -> void:
	if automatic_tick:
		tick(delta)

func feed_event(event: InputEvent) -> bool:
	_ensure_router()
	var token := Registry.token_for_event(event)
	if token.is_empty():
		return false
	var echo: bool = event is InputEventKey and event.echo
	if not enabled and not Registry.UI_ACTIONS.has(token):
		router.reset("adapter_disabled")
		return false
	return router.feed(token, event.is_pressed(), Registry.source_for_event(event), echo)

func _input(event: InputEvent) -> void:
	var token := Registry.token_for_event(event)
	if token.is_empty():
		return
	if Registry.UI_ACTIONS.has(token):
		feed_event(event)
		get_viewport().set_input_as_handled()
	elif not event.is_pressed():
		# Releases must reach the router even if a GUI widget consumes them.
		feed_event(event)
	elif not router.gameplay_allowed():
		# Observe menu-time holds without consuming the widget's click/key.
		feed_event(event)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if feed_event(event):
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		set_context({"focused": false})
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		set_context({"focused": true})
	elif what == NOTIFICATION_EXIT_TREE and router != null:
		router.reset("adapter_removed")

func reset(reason: String = "host_reset") -> void:
	_ensure_router()
	router.reset(reason)

func snapshot() -> Dictionary:
	_ensure_router()
	return router.snapshot()

func availability(action: String) -> Dictionary:
	_ensure_router()
	return router.availability(action)
