class_name FBMatchServices
extends Node3D

const EngineScript = preload("rules/rules_engine.gd")
const ConfigScript = preload("rules/rules_config.gd")
const AudioScript = preload("audio/audio_director.gd")
const RefereeScript = preload("presentation/referee_presenter.gd")
const OverlayScript = preload("presentation/match_overlay.gd")
const MaterialsScript = preload("materials/material_library.gd")
const StepsScript = preload("audio/step_tracker.gd")
const RestartMarkerScript = preload("presentation/restart_marker.gd")

signal rules_event(event: Dictionary)
signal ball_command(command: Dictionary)
signal restart_plan(plan: Dictionary)
@export var configuration: FBMatchRulesConfig
@export var rules_factory: Script = EngineScript
@export var referee_enabled: bool = true
@export var overlay_enabled: bool = true
@export var auto_ai_restart: bool = true
@export var restart_marker_enabled: bool = true
var restart_marker: FBMatchRestartMarker
var rules: FBMatchRulesEngine
var audio: FBMatchAudioDirector
var referee: FBMatchRefereePresenter
var overlay: FBMatchOverlay
var materials: FBMatchMaterialLibrary
var step_tracker: FBMatchStepTracker
var _roster: Array[Dictionary] = []
var _ai_ready_age: float = 0.0

func _ready() -> void:
	if configuration == null:
		configuration = ConfigScript.new()
	var issues := configuration.validate()
	assert(issues.is_empty(), "; ".join(issues))
	rules = rules_factory.new(configuration)
	materials = MaterialsScript.new()
	step_tracker = StepsScript.new()
	audio = AudioScript.new()
	audio.name = "MatchAudio"
	add_child(audio)
	if referee_enabled:
		referee = RefereeScript.new()
		referee.name = "RefereeVisual"
		add_child(referee)
	if overlay_enabled:
		overlay = OverlayScript.new()
		add_child(overlay)
	if restart_marker_enabled:
		restart_marker = RestartMarkerScript.new()
		add_child(restart_marker)
	rules.rules_event.connect(_on_rule_event)
	rules.ball_command.connect(func(command: Dictionary) -> void: ball_command.emit(command))
	rules.restart_plan.connect(func(plan: Dictionary) -> void: restart_plan.emit(plan))

func start_match(roster: Array[Dictionary], kickoff_team: int = 0) -> void:
	audio.reset_events()
	_roster = roster.duplicate(true)
	rules.set_roster(_roster)
	rules.start(kickoff_team)

func step(delta: float, ball_snapshot: Dictionary, roster: Array[Dictionary]) -> void:
	_roster = roster.duplicate(true)
	rules.step(delta, ball_snapshot, roster)
	if referee != null:
		referee.observe_ball(ball_snapshot.get("position", Vector3.ZERO), rules.is_ball_live())
	if overlay != null:
		overlay.update_snapshot(rules.snapshot())
	if restart_marker != null:
		restart_marker.update_snapshot(rules.snapshot())
	if auto_ai_restart and rules.state == EngineScript.State.RESTART_READY:
		_ai_ready_age += delta
		if _ai_ready_age >= 0.45:
			for actor in roster:
				if int(actor["id"]) == int(rules.restart.get("taker_id", -1)) and not bool(actor.get("human", false)):
					var kind: String = str(rules.restart.get("kind", ""))
					var direction: Vector3 = rules.restart.get("inward", Vector3.FORWARD)
					var power := 24.0 if kind == "penalty" else 11.0
					var lift := 0.45 if kind == "penalty" else 3.2 if kind == "throw_in" else 0.3
					rules.request_restart(int(actor["id"]), direction, power, lift)
					break
	else:
		_ai_ready_age = 0.0

func can_touch_ball(actor_id: int) -> bool:
	return rules.can_touch_ball(actor_id)

func can_take_restart(actor_id: int) -> bool:
	return rules.can_take_restart(actor_id)

func request_restart(actor_id: int, direction: Vector3, power: float = 12.0, lift: float = 0.3, contact_event_id: String = "") -> Dictionary:
	return rules.request_restart(actor_id, direction, power, lift, contact_event_id)

func constrain_restart_position(actor: Dictionary, desired: Vector3) -> Vector3:
	return rules.constrain_restart_position(actor, desired)

func report_ball_contact(event: Dictionary) -> bool:
	var accepted := rules.report_ball_contact(event)
	if accepted:
		audio.contact(event)
	return accepted

func report_footstep(event: Dictionary) -> bool:
	return audio.footstep(event)

func report_challenge(event: Dictionary) -> bool:
	return rules.report_challenge(event)

func _on_rule_event(event: Dictionary) -> void:
	audio.rule_event(event)
	if referee != null:
		referee.present(event)
	rules_event.emit(event)
