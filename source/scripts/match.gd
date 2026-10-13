extends Node3D
signal quality_change(report: Dictionary)
@export var tuning: FootballControlTuning = preload("res://config/ball_control.tres")
@export var training_configuration: Resource
@export_enum("5:5", "6:6", "9:9", "11:11") var match_players_per_team:int=11
@export var small_training_pitch:bool=false
const SmallSides=preload("res://scripts/small_sided_profile.gd")
func formation_label()->String:
	if training_configuration!=null:return "1–2"
	return SmallSides.spec(team_size).formation if team_size in [5,6,9] else "4–3–3"
var training_mode: Node
const PlayerScene := preload("res://scenes/football_player.tscn")
const AgentScript := preload("res://scripts/football_shared_agent.gd")
const KeeperAgentScript := preload("res://addons/football_keeper/keeper_dive_agent.gd")
const BallScript := preload("res://scripts/football.gd")
const KeeperBallScript := preload("res://addons/football_keeper/keeper_ball.gd")
const KeeperInstall := preload("res://addons/football_keeper/install.gd")
const StadiumScript := preload("res://scripts/integration_arena.gd")
const HudScript := preload("res://scripts/hud.gd")
const HubScript := preload("res://scripts/integration_contact_hub.gd")
const InputScript := preload("res://scripts/integration_input_bridge.gd")
const InteractionScript := preload("res://addons/football_interaction/slide_interaction.gd")
const ProfileScript := preload("res://addons/football_physics/physics_profile.gd")
const WorldScript := preload("res://addons/football_physics/physics_world.gd")
const KickMapping := preload("res://addons/football_physics/kick_mapping.gd")
const ServicesScript := preload("res://addons/football_match_services/match_services.gd")
const ImpactAudioB := preload("res://addons/football_recorded_impact/install.gd")
const MaterialsB := preload("res://addons/football_materials_b/material_patch.gd")
const SeatingPalette := preload("res://addons/modern_stadium/seating_palette_adapter.gd")
const StadiumQuality := preload("res://addons/modern_stadium/stadium_quality.gd")
const DaylightProfile := preload("res://addons/stadium_presentation/daylight_profile.gd")
const NightProfile := preload("res://addons/stadium_night/night_profile.gd")
const AppearancePalette := preload("res://addons/stadium_presentation/appearance_palette.gd")
const FarSeats := preload("res://addons/stadium_far_clarity/far_seats.gd")
const RulesConfig := preload("res://addons/football_match_services/rules/rules_config.gd")
const Rules := preload("res://addons/football_match_services/rules/rules_engine.gd")
const RuleHub := preload("res://addons/football_match_services/contact_hub_adapter.gd")
const Roles := preload("res://scripts/tactics/role_catalog.gd")
const Director := preload("res://scripts/tactics/tactical_director.gd")
const TacticHub := preload("res://scripts/tactics/contact_adapter.gd")
const TacticsBridge := preload("res://scripts/integration_tactics.gd")
const RenderQuality := preload("res://scripts/render_quality.gd")
enum Phase { MENU, COUNTDOWN, PLAY, GOAL, RESTART, PAUSED, FINISHED }
var phase := Phase.MENU
var resume_phase := Phase.PLAY
var state_clock := 0.0
var field_half_width := 34.0
var field_half_length := 52.5
var team_size := 11
var goal_width := 7.32
var goal_height := 2.44
var field_layout: Dictionary = {}
var stadium: Node3D
@export var match_length := 1200.0 # Two real 600-second halves; training remains round-based.
var time_left := 120.0
var practice := false
var duel_mode := false
var scores := [0,0]
var players: Array[Node3D] = []
var agents: Array[FootballAgent] = []
var player: CharacterBody3D
var ball: MatchFootball
var receive_ab := "B"
var hud: CanvasLayer
var contact_hub: FootballContactHub
var input_bridge: FootballMatchInputBridge
var physics_world: FootballPhysicsWorld
var physics_profile: FootballPhysicsProfile
var services: FBMatchServices
var render_quality := "fast"
var settings_menu:Node
var rule_contact_adapter: FBMatchContactHubAdapter
var tactical_director: FootballTacticalDirector
var tactical_contact_adapter: FootballTacticsContactAdapter
var tactics_bridge: Node
var roster_configuration: Array[Dictionary] = []
const Selection=preload("res://scripts/roster_selection.gd")
var rule_snapshot: Dictionary = {}
var restart_plan: Dictionary = {}
var restart_taker: Node3D
var restart_team := 0
var restart_position := Vector3.ZERO
var restart_message := ""
var formation_serial := 0
var match_generation := 0
var pass_receiver: Node3D
var pass_receiver_timer := 0.0
var chasers: Array[Node3D] = [null,null]
var call_timer := 0.0
var assist := true
var status_message := ""
var status_timer := 0.0
var test_mode := false
var ai_enabled := true
var throw_requests: Dictionary = {}
var foul_evidence: Array[Dictionary] = []
var detail_update_clock := 0.0
var stats := {"passes":0,"shots":0,"tackles":0,"outs":0,"ai_passes":0,"ai_shots":0,"ai_tackles":0}

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg=="--receive-ab=A": receive_ab = "A"
	if "--release-spin-check" in OS.get_cmdline_user_args() and not get_tree().root.has_meta("release_spin_active"):
		get_tree().root.set_meta("release_spin_active",true)
		get_tree().root.call_deferred("add_child",preload("res://addons/publisher_checks/native_spin.gd").new())
		queue_free()
		return
	if "--release-body-check" in OS.get_cmdline_user_args() and not get_tree().root.has_meta("release_body_active"):
		get_tree().root.set_meta("release_body_active",true)
		get_tree().root.call_deferred("add_child",preload("res://addons/publisher_checks/native_body_eye.gd").new())
		queue_free()
		return
	if "--release-far-check" in OS.get_cmdline_user_args() and not get_tree().root.has_meta("release_far_active"):
		get_tree().root.set_meta("release_far_active",true)
		get_tree().root.call_deferred("add_child",preload("res://addons/publisher_checks/native_far_stands.gd").new())
		queue_free()
		return
	if "--release-night-check" in OS.get_cmdline_user_args() and not get_tree().root.has_meta("release_night_active"):
		get_tree().root.set_meta("release_night_active",true)
		get_tree().root.call_deferred("add_child",preload("res://addons/publisher_checks/native_night.gd").new())
		queue_free()
		return
	# Opt-in release probe, unused by ordinary gameplay.
	var tree_root := get_tree().root
	if "--release-dribble-check" in OS.get_cmdline_user_args() and not tree_root.has_meta("release_dribble_active"):
		tree_root.set_meta("release_dribble_active",true)
		tree_root.call_deferred("add_child",preload("res://addons/publisher_checks/native_dribble.gd").new())
		queue_free()
		return
	if "--release-perf-check" in OS.get_cmdline_user_args() and not tree_root.has_meta("release_perf_active"):
		tree_root.set_meta("release_perf_active",true)
		tree_root.call_deferred("add_child",preload("res://addons/stadium_presentation/qa/native_daylight.gd").new())
		queue_free()
		return
	process_physics_priority = 40
	_setup_input()
	render_quality = RenderQuality.from_cmdline()
	RenderQuality.apply(get_window(), render_quality)
	physics_profile = ProfileScript.playable()
	contact_hub = HubScript.new()
	contact_hub.name = "ContactHub"
	add_child(contact_hub)
	if training_configuration != null:
		team_size = 3
	else:
		assert(match_players_per_team in [5,6,9,11])
		team_size=match_players_per_team
	stadium = StadiumScript.attach(self)
	player = PlayerScene.instantiate()
	player.match_controller = self
	player.profile = physics_profile
	add_child(player)
	players.append(player)
	var blue_ids: Array = []
	var red_ids: Array = []
	var jerseys := [1,3,4,5,2,14,8,10,7,9,11]
	var human_role_index := 7
	if team_size in [5,6,9]:
		jerseys=SmallSides.spec(team_size).jerseys
		human_role_index=SmallSides.spec(team_size).human
	if training_configuration != null:
		jerseys = [10,7,11]
		human_role_index = 0
	for team in range(2):
		for role_index in range(team_size):
			if team==0 and role_index==human_role_index:
				blue_ids.append(0)
				continue
			var agent: FootballAgent = KeeperAgentScript.new() if training_configuration == null and role_index == 0 else AgentScript.new()
			agent.name = ("Blue" if team==0 else "Yellow")+"_%d" % jerseys[role_index]
			agent.team = team
			agent.jersey = jerseys[role_index]
			agent.is_goalkeeper = training_configuration == null and role_index == 0
			agent.match_controller = self
			agent.profile = physics_profile
			add_child(agent)
			agents.append(agent)
			(blue_ids if team==0 else red_ids).append(players.size())
			players.append(agent)
	if training_configuration != null:
		roster_configuration = training_configuration.roster(0,blue_ids,0)
		roster_configuration.append_array(training_configuration.roster(1,red_ids))
	elif team_size in [5,6,9]:
		roster_configuration=SmallSides.roster(team_size,0,blue_ids,0)
		roster_configuration.append_array(SmallSides.roster(team_size,1,red_ids))
	else:
		roster_configuration = Roles.default_eleven(0,blue_ids,0)
		roster_configuration.append_array(Roles.default_eleven(1,red_ids))
	for row in roster_configuration:
		var actor: Node3D = players[int(row.id)]
		actor.role = row.role
		actor.lane = row.lane
		actor.is_goalkeeper = row.is_goalkeeper
	Selection.initialize(self)
	preload("res://scripts/player_abilities.gd").apply_roster(self)
	ball = KeeperBallScript.new() if training_configuration == null else BallScript.new()
	ball.receive_ab_legacy = (receive_ab=="A")
	ball.match_controller = self
	ball.profile = physics_profile
	add_child(ball)
	physics_world = WorldScript.new()
	physics_world.name = "FootballPhysicsWorld"
	physics_world.profile = physics_profile
	add_child(physics_world)
	for actor in players:
		physics_world.register_actor(actor)
		actor.body_contact.connect(_on_actor_body_contact.bind(actor))
	physics_world.register_ball(ball)
	services = ServicesScript.new()
	services.name = "MatchServices"
	services.configuration = RulesConfig.new()
	services.configuration.apply_stadium_layout(field_layout)
	services.configuration.team_size=team_size
	services.configuration.half_seconds = match_length*.5
	if training_configuration != null:
		services.rules_factory = preload("res://scripts/training/training_rules.gd")
		services.configuration.team_size = 3
		services.configuration.half_seconds = 86400.0
		services.configuration.celebration_seconds = 10.0
		services.configuration.stoppage_seconds = 10.0
		services.referee_enabled = false
		services.restart_marker_enabled = false
	if team_size==5 or small_training_pitch:services.rules_factory=preload("res://scripts/five_side_rules.gd")
	elif team_size==11 and training_configuration==null:services.rules_factory=preload("res://scripts/offside_rules.gd")
	services.overlay_enabled = false
	services.auto_ai_restart = false
	add_child(services)
	if services.rules.has_method("refresh_contact_roster"):
		services.rules.live_roster_provider=Callable(self,"offside_roster")
		var officials=preload("res://art/match_officials.gd").new();officials.game=self;add_child(officials)
	services.audio.local_actor_id = player.get_instance_id()
	services.ball_command.connect(_on_ball_command)
	services.rules_event.connect(_on_rules_event)
	services.restart_plan.connect(_on_restart_plan)
	services.materials.apply_modern_stadium(stadium)
	services.materials.bind_ball_surfaces(ball.visual)
	MaterialsB.install(stadium,services.materials,ball.visual,true,"balanced")
	SeatingPalette.apply(stadium,services.materials.slots.seat_navy,services.materials.slots.seat_blue)
	if training_configuration != null:
		get_node("MatchEnvironment").set_meta("stadium_lighting_mode", "daylight")
	elif tree_root.has_meta("release_perf_active") and bool(tree_root.get_meta("release_visual_baseline",false)):
		StadiumQuality.apply(stadium,get_node("MatchEnvironment").environment,get_node("MatchSun"),"balanced",get_viewport())
	else:
		AppearancePalette.apply(stadium,services.materials)
		NightProfile.apply(stadium,get_node("MatchEnvironment"),get_node("MatchSun"),"night","low",get_viewport(),services.materials)
	# Lighting sets its presentation; selected image quality owns final AA/atlas.
	RenderQuality.apply(get_window(), render_quality)
	RenderQuality.apply_shadow_range(get_node_or_null("MatchSun") as DirectionalLight3D, render_quality)
	RenderQuality.tune_surface_filtering(stadium)
	rule_contact_adapter = RuleHub.new(services,ball)
	contact_hub.contact_resolved.connect(rule_contact_adapter.consume)
	contact_hub.body_contact.connect(rule_contact_adapter.consume)
	ImpactAudioB.install(services,contact_hub,ball)
	tactical_director = Director.new()
	tactical_director.configure(roster_configuration,{0:Director.SHORT_PASS,1:Director.SHORT_PASS})
	tactical_contact_adapter = TacticHub.new(tactical_director,func(actor): return players.find(actor))
	contact_hub.contact_resolved.connect(tactical_contact_adapter.on_contact_resolved)
	tactics_bridge = TacticsBridge.new()
	tactics_bridge.game = self
	add_child(tactics_bridge)
	if training_configuration != null:
		training_mode = preload("res://scripts/training/training_mode.gd").new()
		training_mode.game = self
		add_child(training_mode)
		hud = preload("res://scripts/training/training_hud.gd").new()
	else:
		hud = HudScript.new()
	hud.match_controller = self
	add_child(hud)
	input_bridge = InputScript.new()
	input_bridge.game = self
	add_child(input_bridge)
	var interaction := InteractionScript.new()
	interaction.setup(self)
	add_child(interaction)
	show_menu()
	settings_menu=preload("res://scripts/play_settings.gd").new()
	settings_menu.game=self
	add_child(settings_menu)
	if training_configuration == null:
		FarSeats.install(stadium)
	stadium.update_detail_for_camera(player.camera.global_position)
	if training_configuration == null:
		KeeperInstall.attach(self)
		var spike_watch=preload("res://scripts/frame_spike_watch.gd").new()
		spike_watch.game=self
		add_child(spike_watch)
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--perf11-output="):
				var observer=preload("res://scripts/perf11_probe.gd").new()
				observer.game=self
				add_child(observer)
				break

const DistantPoseQueue:=preload("res://scripts/distant_pose_queue.gd")
var distant_pose_queue:=DistantPoseQueue.new()
func _process(delta: float) -> void:
	distant_pose_queue.advance(self)
	detail_update_clock -= delta
	if detail_update_clock<=0 and is_instance_valid(stadium) and is_instance_valid(player):
		detail_update_clock = .25
		stadium.update_detail_for_camera(player.camera.global_position)

func _physics_process(delta: float) -> void:
	status_timer = maxf(0,status_timer-delta)
	if phase in [Phase.MENU,Phase.PAUSED,Phase.FINISHED]: return
	call_timer = maxf(0,call_timer-delta)
	pass_receiver_timer = maxf(0,pass_receiver_timer-delta)
	if pass_receiver_timer<=0 or is_instance_valid(ball.carrier): pass_receiver = null
	services.step(delta,ball_snapshot(),rule_roster())
	rule_snapshot = services.rules.snapshot()
	scores = rule_snapshot.scores.duplicate()
	time_left = float(rule_snapshot.time_remaining)
	_sync_rule_phase()
	_update_throw_requests(delta)
	for actor in players:
		if not actor.visible: continue
		if actor.is_human or actor.foot.idle() or actor._visual_pose_tick39!=Engine.get_physics_frames():actor.refresh_pose(0)
		else:preload("res://scripts/frame_spike_watch.gd").post_pose_reused+=1
		var step: Dictionary = services.step_tracker.observe(actor.get_instance_id(),actor.position,Vector2(actor.velocity.x,actor.velocity.z).length(),actor.position.y<.03,delta)
		if not step.is_empty(): services.report_footstep(step)
	sync_input_context()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_F4:
		toggle_stadium_lighting()
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_F2:
		toggle_render_quality()
	if event.is_action_pressed("restart_match") and phase==Phase.FINISHED: restart_current()

## Live image-quality switch; visual settings only, no gameplay state is touched.
func toggle_render_quality() -> void:
	if is_instance_valid(settings_menu):
		settings_menu.cycle_quality()
		return
	render_quality = RenderQuality.next_level(render_quality)
	var report := RenderQuality.apply(get_window(), render_quality)
	RenderQuality.apply_shadow_range(get_node_or_null("MatchSun") as DirectionalLight3D, render_quality)
	message("画质：" + RenderQuality.label(render_quality), 2.5)
	quality_change.emit(report)

func toggle_stadium_lighting() -> void:
	if is_instance_valid(settings_menu):
		settings_menu.cycle_lighting()
		return
	if not is_instance_valid(stadium) or not is_instance_valid(services):return
	if training_configuration != null:
		message("训练场使用日场光照", 1.5)
		return
	var world: WorldEnvironment = get_node("MatchEnvironment")
	var next := "daylight" if world.get_meta("stadium_lighting_mode","")=="night" else "night"
	var report := NightProfile.apply(stadium,world,get_node("MatchSun"),next,"low",get_viewport(),services.materials)
	RenderQuality.apply(get_window(), render_quality)
	RenderQuality.apply_shadow_range(get_node("MatchSun") as DirectionalLight3D, render_quality)
	if not report.has("error"):message("日场 · F4 切换夜场" if next=="daylight" else "夜场 · F4 切换日场",2.0)

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready() and not test_mode and phase in [Phase.PLAY,Phase.COUNTDOWN,Phase.RESTART,Phase.GOAL]: pause_match()

func start_match(_is_practice := false) -> void:
	practice = false
	duel_mode = false
	match_generation += 1
	formation_serial += 1
	stats = {"passes":0,"shots":0,"tackles":0,"outs":0,"ai_passes":0,"ai_shots":0,"ai_tackles":0}
	contact_hub.reset()
	tactical_director.reset()
	tactical_contact_adapter.reset()
	foul_evidence.clear()
	throw_requests.clear()
	restart_plan.clear()
	call_timer = 0
	pass_receiver = null
	pass_receiver_timer = 0
	player.stamina = 100
	player.sprint_locked = false
	_reset_initial_formation()
	set_phase(Phase.COUNTDOWN)
	if is_instance_valid(training_mode):
		training_mode.begin_round()
		rule_snapshot = services.rules.snapshot()
		scores = rule_snapshot.scores.duplicate()
		_sync_rule_phase()
		return
	services.configuration.team_size=team_size
	services.configuration.half_seconds = match_length*.5
	services.start_match(rule_roster(),0)
	rule_snapshot = services.rules.snapshot()
	_sync_rule_phase()
	message(Selection.caption(self)+"；F1 查看操作。",4)

func restart_current() -> void:
	if is_instance_valid(training_mode):
		training_mode.reset_repetition()
		return
	start_match(false)

func start_duel() -> void:
	start_match(false)

func show_menu() -> void:
	throw_requests.clear()
	ball.clear_control()
	ball.set_held(true)
	_reset_initial_formation()
	player.position = Vector3(5.5,.002,16)
	if training_configuration != null:
		player.position = Vector3(0,.002,field_half_length * .32)
	player.reset_view(.10)
	ball.reset(player.position+Vector3(0,0,-.54))
	set_phase(Phase.MENU)

func set_phase(next: int) -> void:
	phase = next
	var movable := phase in [Phase.PLAY,Phase.COUNTDOWN,Phase.RESTART,Phase.GOAL]
	player.set_match_active(movable)
	for agent in agents: agent.set_match_active(movable and ai_enabled and agent.visible)
	physics_world.set_physics_process(movable)
	if not test_mode and DisplayServer.get_name()!="headless": Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if movable else Input.MOUSE_MODE_VISIBLE
	sync_input_context()

func pause_match() -> void:
	if phase in [Phase.MENU,Phase.FINISHED,Phase.PAUSED]: return
	resume_phase = phase
	set_phase(Phase.PAUSED)

func resume_match() -> void:
	if phase==Phase.PAUSED: set_phase(resume_phase)

func quit_game() -> void:
	set_phase(Phase.PAUSED)
	shutdown_audio()
	# Normal desktop time lets the mixer retire stopped playback references.
	await get_tree().create_timer(.10,true,false,true).timeout
	get_tree().quit()

func shutdown_audio() -> void:
	if not is_instance_valid(services) or not is_instance_valid(services.audio): return
	services.audio.set_process(false)
	for voice in services.audio.get_children():
		if voice is AudioStreamPlayer or voice is AudioStreamPlayer3D:
			voice.stop()
			voice.stream = null

func _exit_tree() -> void:
	shutdown_audio()

func _reset_initial_formation() -> void:
	var homes := [Vector2(0,49),Vector2(-23,36),Vector2(-9,40),Vector2(9,40),Vector2(23,36),Vector2(0,26),Vector2(-12,17),Vector2(8,12),Vector2(-23,8),Vector2(0,3),Vector2(23,8)]
	if training_configuration != null:
		homes.assign(training_configuration.homes())
	elif team_size in [5,6,9]:
		homes.assign(SmallSides.spec(team_size).homes)
	if small_training_pitch and team_size==6:
		homes=[Vector2(0,16.5),Vector2(-4,11),Vector2(4,11),Vector2(-5,6),Vector2(5,6),Vector2(0,2)]
	var row_count := [0,0]
	for row in roster_configuration:
		var actor: Node3D = players[int(row.id)]
		var home: Vector2 = homes[row_count[int(row.team)]]
		row_count[int(row.team)] += 1
		var own_side := 1.0 if int(row.team)==0 else -1.0
		actor.position = Vector3(home.x*own_side,.002,home.y*own_side)
		actor.velocity = Vector3.ZERO
		actor.reset_physics_interpolation()
		actor.visible = true
		actor.collision_layer = 2
		actor.collision_mask = 3
		actor.foot.cancel()
		actor.action_cooldown = 0
		actor.tackle_cooldown = 0
		actor.facing = Vector3(0,0,-own_side)
		actor.body_facing = actor.facing
		if not actor.is_human:
			actor.target = actor.position
			actor.home = actor.position
			actor.face_target = actor.facing
			actor.pending_kick.clear()
	player.reset_view(atan2(-player.facing.x,-player.facing.z))

func _sync_rule_phase() -> void:
	if phase in [Phase.MENU,Phase.PAUSED]: return
	var state: int = services.rules.state
	var next := Phase.PLAY
	if state==Rules.State.FULL_TIME: next = Phase.FINISHED
	elif state in [Rules.State.GOAL_CELEBRATION,Rules.State.HALF_TIME]: next = Phase.GOAL
	elif state in [Rules.State.STOPPAGE,Rules.State.RESTART_SETUP,Rules.State.RESTART_READY]: next = Phase.RESTART
	elif state==Rules.State.RESTART_IN_FLIGHT: next = Phase.RESTART
	if next!=phase: set_phase(next)
	restart_taker = actor_by_instance(int(services.rules.restart.get("taker_id",-1)))
	if not services.rules.restart.is_empty():
		restart_team = int(services.rules.restart.get("team",0))
		restart_position = services.rules.restart.get("point",Vector3.ZERO)
		restart_message = restart_hint()

func _on_ball_command(command: Dictionary) -> void:
	match String(command.action):
		"hold":
			ball.clear_control()
			ball.set_held(true)
			throw_requests.clear()
			pass_receiver = null
		"place":
			ball.clear_control()
			ball.set_held(true)
			ball.position = command.position
			ball.previous_position = ball.position
			ball.reset_physics_interpolation()
		"release":
			ball.clear_control(false)
			ball.position = command.position
			ball.previous_position = ball.position
			ball.reset_physics_interpolation()
			ball.set_held(false)
			# One finite linear impulse, no second generic kick or old velocity overwrite.
			ball.apply_impulse_ns((command.velocity-ball.velocity)*ball.mass_kg)
			if String(command.get("kind",""))!="throw_in": ball.spin_rads = Vector3.UP.cross(Vector3(ball.velocity.x,0,ball.velocity.z))/ball.radius
			ball.pickup_block = .12
			ball.last_touch_team = int(command.get("team",-1))
			ball.control_mode = "LOOSE"

func _on_restart_plan(plan: Dictionary) -> void:
	restart_plan = plan.duplicate(true)
	formation_serial = match_generation*100000+int(plan.serial)
	restart_taker = actor_by_instance(int(plan.taker_id))
	sync_input_context()

func _on_rules_event(event: Dictionary) -> void:
	var type := String(event.type)
	if type in ["restart_awarded","restart_ready","restart_taken","restart_rejected","ball_in_play"]:
		print("RESTART_EVENT ",type," ",JSON.stringify(event))
	if type=="goal":
		restart_message = "蓝队进球" if int(event.team)==0 else "红队进球"
		contact_hub.publish({"kind":"GOAL","point":event.position,"team":int(event.team),"sequence":int(contact_hub.serial)+1})
	elif type=="restart_awarded":
		if event.restart.get("reason","")=="offside":message("越位 · "+("蓝队" if int(event.restart.team)==0 else "红队")+"间接任意球",3.)
		stats.outs += 1 if event.restart.get("reason","") in ["touchline","goal_line"] else 0
		contact_hub.publish({"kind":"RESTART","point":event.restart.point,"team":int(event.restart.team),"sequence":int(contact_hub.serial)+1})
	elif type=="half_time": restart_message = "半场休息 · 换边后继续"
	elif type=="ends_changed":
		tactical_director.reset()
		tactical_contact_adapter.reset()
		message("下半场换边：蓝队进攻另一端球门",3)
	elif type=="restart_rejected": message("重开球尚未到位："+String(event.reason),1.5)
	rule_snapshot = services.rules.snapshot()
	_sync_rule_phase()

func rule_roster() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for actor in players:
		result.append({"id":actor.get_instance_id(),"team":actor.team,"position":actor.position,"velocity":actor.velocity,"action":str(actor.foot.kind) if actor.foot!=null and not actor.foot.idle() else "","human":actor.is_human,"active":actor.visible,"goalkeeper":actor.is_goalkeeper,"jersey":actor.jersey,"display_name":("蓝队" if actor.team==0 else "红队")+" #%d" % actor.jersey})
	return result

func offside_roster()->Array[Dictionary]:
	var result=rule_roster()
	for i in players.size():
		var avatar=players[i].avatar;var sk:Skeleton3D=avatar.skeleton;var points:Array[Vector3]=[]
		for bone in ["head","chest","foot.L","foot.R"]:
			var index:int=sk.find_bone(bone)
			if index>=0:points.append(to_local(sk.global_transform*sk.get_bone_global_pose(index).origin))
		result[i]["offside_points"]=points
	return result

func ball_snapshot() -> Dictionary:
	return {"position":ball.position,"previous_position":ball.previous_position,"velocity":ball.velocity,"radius":ball.radius}

func actor_by_instance(id: int) -> Node3D:
	for actor in players:
		if actor.get_instance_id()==id: return actor
	return null

func can_touch_ball(actor: Node3D) -> bool:
	return phase==Phase.PLAY and services.can_touch_ball(actor.get_instance_id())

func is_restart_taker(actor: Node3D) -> bool:
	return is_instance_valid(services) and phase not in [Phase.MENU,Phase.PAUSED,Phase.FINISHED] and services.can_take_restart(actor.get_instance_id())

func can_foot_action(actor: Node3D, action: String) -> bool:
	if actor == player and is_instance_valid(player.interaction) and not player.interaction.permits_foot_action(): return false
	if actor is FootballAgent and is_instance_valid(actor.down_state) and actor.down_state.blocked(): return false
	return can_touch_ball(actor) or (action in ["PASS","SHOT"] and is_restart_taker(actor))

func can_reach_ball(actor: Node3D) -> bool:
	var start := actor.position
	start.y = ball.position.y
	var limit:float=start.distance_to(ball.position)-.1
	if limit<=0:return true
	var radius:float=physics_profile.player_radius_m-.02
	for other in players:
		if other==actor or not other.visible: continue
		var center := Vector3(other.position.x,start.y,other.position.z)
		# Same geometric test; avoid segment work and repeated square roots for
		# players outside the only interval that can block this touch.
		if start.distance_squared_to(center)>=limit*limit:continue
		var nearest := Geometry3D.get_closest_point_to_segment(center,start,ball.position)
		if nearest.distance_squared_to(center)<radius*radius:return false
	return true

var intercept_check_remaining:=0.0
func schedule_interceptions(delta:float)->void:
	intercept_check_remaining-=delta
	if intercept_check_remaining>0:return
	intercept_check_remaining=.025
	if phase!=Phase.PLAY or ball.held or is_instance_valid(ball.carrier) or ball.position.y>.46 or ball.velocity.length()<.08 or ball.last_touch_team<0:return
	var known:Dictionary={"position":ball.position,"velocity":ball.velocity,"age_s":0.0,"automatic":true}
	for actor in players:
		if not actor.visible or actor.is_goalkeeper or actor.team==ball.last_touch_team or actor.tackle_cooldown>0 or not actor.foot.idle() or actor.foot.has_buffer() or actor.foot.has_receive_pass():continue
		if actor.is_human:
			if not actor.input_enabled or not input_bridge.adapter.router.snapshot().charge.is_empty():continue
		elif not ai_enabled or not actor.active or not actor.pending_kick.is_empty():continue
		if actor.position.distance_squared_to(ball.position)>9.0:continue
		attempt_tackle(actor,known)

func schedule_receiving() -> void:
	if phase!=Phase.PLAY or is_instance_valid(ball.carrier) or ball.pickup_block>0 or ball.position.y>.42: return
	for actor in players:
		if not actor.visible or not actor.foot.idle() or actor.foot.has_receive_pass() or not can_touch_ball(actor): continue
		# Opponent rolls use the shared bounded interception path, not a catch.
		if ball.last_touch_team>=0 and ball.last_touch_team!=actor.team and ball.velocity.length()>=.35 and not actor.is_goalkeeper:continue
		if not actor.is_human and actor.tactical_intent.has("ball_job_owner") and int(actor.tactical_intent.ball_job_owner)!=players.find(actor): continue
		if actor.is_goalkeeper and actor.has_method("keeper_dive_allowed") and actor.keeper_dive_allowed(): continue
		if actor.is_goalkeeper and is_instance_valid(ball.keeper_host) and ball.keeper_host.reserve_slow_capture(actor): continue
		if actor.is_human and not actor.move_requested:
			if ball.receive_ab_legacy: continue
			var to_actor := Vector3(actor.position.x-ball.position.x,0,actor.position.z-ball.position.z).normalized()
			if Vector3(ball.velocity.x,0,ball.velocity.z).dot(to_actor)<1.5: continue
		if not actor.is_human and not actor.tactical_intent.get("receive",false) and not actor.is_goalkeeper: continue
		var offset := ball.position-actor.position
		offset.y = 0
		var relative:Vector3=ball.velocity-actor.velocity;relative.y=0
		var eta:float=clampf(-offset.dot(relative)/maxf(relative.length_squared(),.01),0,.23)
		var projected:Vector3=offset+relative*eta
		var forward_ratio:float=offset.normalized().dot(actor.body_facing)
		var reach:float=1.08 if forward_ratio>-.15 else .88
		if offset.length()>reach+minf(.65,relative.length()*.16) or projected.length()>reach or offset.length()<.12 or not can_reach_ball(actor):continue
		# B requires the player to turn toward a rear ball before receiving.
		# Side contact is resolved by the nearer shoe, not a facing gate.
		actor.foot.begin("RECEIVE",offset,Vector3.ZERO,0,.18,{"receive_eta":eta,"receive_reach":reach})

func get_pass_target(from: Node3D) -> Node3D:
	var best: Node3D
	var cost := INF
	for actor in players:
		if actor==from or actor.team!=from.team or not actor.visible: continue
		var toward := Vector3(actor.position.x-ball.position.x,0,actor.position.z-ball.position.z)
		var distance := toward.length()
		if distance<2 or distance>35 or toward.normalized().dot(from.facing)<cos(deg_to_rad(14.0)): continue
		var value := toward.normalized().angle_to(from.facing)*60.0+distance*.08
		if value<cost:
			best = actor
			cost = value
	return best

func request_player_kick(intent: Dictionary) -> bool:
	var request := intent.duplicate(true)
	var passing := String(request.action).begins_with("pass_")
	var target := get_pass_target(player) if passing else null
	if passing and assist and is_instance_valid(target):
		var toward := Vector3(target.position.x-ball.position.x,0,target.position.z-ball.position.z)
		if request.direction.angle_to(toward)<deg_to_rad(3): request.direction = toward.normalized()
		else: target = null
	return request_actor_kick(player,request,target)

func request_actor_kick(actor: Node3D, intent: Dictionary, target: Node3D = null) -> bool:
	if actor.action_cooldown>0 and not (actor.is_human and actor.action_cooldown<=.24) and not (bool(intent.get("one_touch_pass",false)) and actor.foot.has_receive_pass()): return false
	# Planner IDs index the host roster, while rules IDs are instance IDs. Resolve
	# the real receiver before FootAction so a successful AI pass can notify it.
	var receiver_index := int(intent.get("receiver_id",-1))
	if not is_instance_valid(target) and receiver_index>=0 and receiver_index<players.size():
		var requested: Node3D = players[receiver_index]
		if requested!=actor and requested.team==actor.team: target = requested
	var mapped: Dictionary = KickMapping.from_input_intent(intent,physics_profile)
	if not mapped.get("accepted",false): return false
	if is_restart_taker(actor) and String(services.rules.restart.get("kind",""))=="throw_in":
		throw_requests[actor.get_instance_id()] = {"age":0.0,"intent":intent.duplicate(true),"target":target}
		actor.action_cooldown = .8
		return true
	var incoming_pass: bool = mapped.kind=="pass" and bool(intent.get("one_touch_pass",false)) and not actor.foot.receive_pass_window().is_empty()
	if (not actor.foot.can_schedule_kick() and not incoming_pass) or not can_foot_action(actor,"PASS" if mapped.kind=="pass" else "SHOT"): return false
	if not actor.foot.request_semantic_kick(intent,0,0,target): return false
	# FootAction owns deliberate-kick cooldown at actual action start.
	tactical_contact_adapter.register_action_request(players.find(actor),{"action":intent.get("tactical_action","PASS" if mapped.kind=="pass" else "SHOT"),"receiver_id":players.find(target) if is_instance_valid(target) else int(intent.get("receiver_id",-1))})
	return true

func on_kick_contact(actor: Node3D, kind: String, intent: Dictionary, receiver: Node3D, restarting: bool, at: Vector3, action_sequence: int) -> bool:
	if kind=="PASS" and not restarting:
		intent=preload("res://scripts/player_abilities.gd").pass_intent(actor,intent,action_sequence,ball.position,players)
	var mapped: Dictionary = KickMapping.from_input_intent(intent,physics_profile)
	if not mapped.get("accepted",false): return false
	if restarting:
		if not is_restart_taker(actor): return false
		var lower := physics_profile.shot_min_speed_mps if mapped.kind=="shot" else physics_profile.pass_min_speed_mps
		var upper := physics_profile.shot_max_speed_mps if mapped.kind=="shot" else physics_profile.pass_max_speed_mps
		var speed := lerpf(lower,upper,pow(mapped.power_01,physics_profile.power_curve_exponent))
		if mapped.kind=="pass":
			if mapped.lift_degrees>5:speed=physics_profile.loft_pass_speed(mapped.power_01)
			elif physics_profile.ground_pass_distance_mapping_enabled:
				var distance:float=lerpf(physics_profile.ground_pass_min_distance_m,physics_profile.ground_pass_max_distance_m,pow(mapped.power_01,physics_profile.ground_pass_distance_exponent))
				speed=preload("res://addons/football_ground_pass/ground_pass_solution.gd").launch_speed(distance,physics_profile)
			if intent.get("contact_surface","")=="HEEL":speed=minf(speed,physics_profile.heel_max_speed_mps)
		var angle := deg_to_rad(mapped.lift_degrees)
		var event_id := "restart-foot:%d:%d:%d" % [match_generation,actor.get_instance_id(),action_sequence]
		var incoming:Vector3=ball.velocity
		var result: Dictionary = services.request_restart(actor.get_instance_id(),mapped.direction_world,speed*cos(angle),speed*sin(angle),event_id)
		if not result.get("ok",false): return false
		ball.record_touch(actor,incoming,.14,kind,at)
		ball.spin_rads += mapped.spin_world
	else:
		var one_touch_contact: bool = kind=="PASS" and bool(intent.get("one_touch_pass",false)) and not is_instance_valid(ball.carrier) and actor.foot.kind=="PASS" and actor.foot.phase==FootballFootAction.Phase.CONTACT and actor.foot.sequence==action_sequence and actor.foot.kick_intent.get("one_touch_pass",false) and not actor.foot.hit and (actor.foot.actual_contact.get("valid",false) or not actor.foot.physical_contact_sample.is_empty()) and at.distance_to(ball.position)<=ball.radius+.065 and can_foot_action(actor,"PASS")
		if not can_touch_ball(actor) or (ball.carrier!=actor and not one_touch_contact): return false
		var incoming:Vector3=ball.velocity
		var loft_speed:float=float(intent.get("ai_loft_speed",-1.0)) if not actor.is_human and kind=="PASS" and mapped.lift_degrees>10 and intent.has("plan_kick_id") else -1.0
		var result: Dictionary = ball.kick(mapped.direction_world,mapped.power_01,mapped.lift_degrees,mapped.spin_world,mapped.kind,loft_speed,String(intent.get("contact_surface","INSTEP")))
		if not result.get("accepted",false): return false
		ball.record_touch(actor,incoming,.10,kind,at)
		ball.detach()
		ball.pickup_block = .075 if kind=="PASS" else .22
	ball.last_kick_intent = intent.duplicate(true)
	ball.last_touch_team = actor.team
	ball.last_foot_position = at
	stats[("passes" if kind=="PASS" else "shots") if actor.is_human else ("ai_passes" if kind=="PASS" else "ai_shots")] += 1
	if kind=="PASS" and (actor.is_human or not is_instance_valid(receiver)) and not restarting:
		# A human's released direction is authoritative. Resolve the recipient from
		# the actual flight, rather than retaining a teammate near the view axis.
		receiver=tactics_bridge.infer_receive_target(actor)
		actor.foot.receiver=receiver
		tactical_contact_adapter.register_action_request(players.find(actor),{"action":"PASS","receiver_id":players.find(receiver) if is_instance_valid(receiver) else -1})
	if kind=="PASS" and is_instance_valid(receiver):
		pass_receiver = receiver
		pass_receiver_timer = 3
	return true

const DefenseContact:=preload("res://scripts/defense_contact.gd")
func standing_tackle_prediction(actor: Node3D, observation: Dictionary) -> Dictionary:
	return DefenseContact.plan(actor,ball,observation)

func attempt_tackle(actor: Node3D, tackle_observation: Dictionary = {}) -> bool:
	if not can_touch_ball(actor) or actor.tackle_cooldown>0 or ball.carrier==actor:return false
	if is_instance_valid(ball.carrier) and ball.carrier.team==actor.team:return false
	var known:Dictionary=tackle_observation
	if actor.is_human:known={"position":ball.position,"velocity":ball.velocity,"age_s":0.0,"automatic":bool(tackle_observation.get("automatic",false))}
	elif known.is_empty():return false
	var preparation:Dictionary=standing_tackle_prediction(actor,known)
	var aim:Vector3=actor.facing
	if preparation.is_empty():return false
	aim=Vector3(preparation.tackle_center.x-actor.position.x,0,preparation.tackle_center.z-actor.position.z).normalized()
	if actor.foot.begin("TACKLE",aim,Vector3.ZERO,3.5,.22,preparation):
		actor.tackle_cooldown=.38
		return true
	return false

func standing_tackle_contact_sample(action:FootballFootAction)->Dictionary:
	return DefenseContact.sample(action,ball)

func standing_tackle_motion_clear(action: FootballFootAction, planned_finish:Variant=null) -> bool:
	# Real final-IK shoe travel, including PREPARE. Never a root-to-ball ray.
	var actor: Node3D = action.actor
	var start: Vector3 = action.toe_world if planned_finish is Vector3 else action.previous_toe
	var finish: Vector3 = planned_finish if planned_finish is Vector3 else action.toe_world
	if not start.is_finite() or not finish.is_finite(): return false
	var excluded: Array[RID] = [actor.get_rid()]
	var space: PhysicsDirectSpaceState3D = actor.get_world_3d().direct_space_state
	# Detect embedded start/end points as well as a traversed thin wall/torso.
	# Same layers 1|2 as settlement; no ball/proxy layer and no extra radius.
	var overlap := PhysicsPointQueryParameters3D.new()
	overlap.collision_mask = 3
	overlap.exclude = excluded
	for point in [start,finish]:
		overlap.position = point
		if not space.intersect_point(overlap,1).is_empty(): return false
	if start.distance_squared_to(finish)>.000001:
		var query := PhysicsRayQueryParameters3D.create(start,finish,3,excluded)
		query.hit_from_inside = true
		if not space.intersect_ray(query).is_empty(): return false
	# A boot cannot pass through a rendered shin during preparation and then
	# claim a later legal touch. CONTACT retains its existing ball-first order.
	if planned_finish is Vector3 or action.phase==FootballFootAction.Phase.PREPARE:
		for other in players:
			if other==actor or not other.visible: continue
			var nearest := Geometry3D.get_closest_point_to_segment(other.position,start,finish)
			if nearest.distance_to(other.position)>1.2: continue
			var skeleton: Skeleton3D = other.avatar.skeleton
			for suffix in ["L","R"]:
				var foot_index: int = other.avatar.cached_bone_id("foot."+suffix)
				var shin_index: int = other.avatar.cached_bone_id("shin."+suffix)
				if foot_index<0 or shin_index<0: continue
				var a: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(foot_index).origin)
				var b: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(shin_index).origin)
				var pairs := Geometry3D.get_closest_points_between_segments(start,finish,a,b)
				if pairs[0].distance_to(pairs[1])<=.11: return false
	return true

func standing_tackle_path_clear(action: FootballFootAction) -> bool:
	if action.tackle_motion_blocked: return false
	# Inspect only a contact-eligible active boot, never 22 tactical scans per frame.
	var actor: Node3D = action.actor
	var sweep_start: Vector3 = action.previous_toe
	var point: Vector3 = action.toe_world
	var excluded: Array[RID] = [actor.get_rid()]
	var space: PhysicsDirectSpaceState3D = actor.get_world_3d().direct_space_state
	# Turf/walls and raised player torsos. Ball layer 4 and proxy layer 8 excluded;
	# rendered shins below handle proxies disabled while the opponent controls it.
	var contact_center:Vector3=action.touch_plan.get("tackle_contact_center",ball.position)
	for span in [[sweep_start,point],[point,contact_center]]:
		if span[0].distance_squared_to(span[1])<.000001: continue
		var query := PhysicsRayQueryParameters3D.create(span[0],span[1],3,excluded)
		query.hit_from_inside = true
		if not space.intersect_ray(query).is_empty(): return false
	var travel: Vector3 = point-sweep_start
	var length_squared: float = travel.length_squared()
	# Compare ENTRY to the contact shell, rather than the ball centre projection.
	var ball_fraction: float = 0.0
	if length_squared>.000001:
		var projection: float = (contact_center-sweep_start).dot(travel)/length_squared
		var nearest: Vector3 = sweep_start+travel*projection
		var shell_radius: float = ball.radius+.055
		var entry_offset: float = sqrt(maxf(0.0,shell_radius*shell_radius-nearest.distance_squared_to(contact_center))/length_squared)
		ball_fraction = clampf(projection-entry_offset,0,1)
	for other in players:
		if other==actor or not other.visible or flat_distance(other.position,point)>1.2: continue
		var skeleton: Skeleton3D = other.avatar.skeleton
		for suffix in ["L","R"]:
			var foot_index: int = other.avatar.cached_bone_id("foot."+suffix)
			var shin_index: int = other.avatar.cached_bone_id("shin."+suffix)
			if foot_index<0 or shin_index<0: continue
			var a: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(foot_index).origin)
			var b: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(shin_index).origin)
			var pairs := Geometry3D.get_closest_points_between_segments(sweep_start,point,a,b)
			if pairs[0].distance_to(pairs[1])>.11: continue
			# Do not reject a ball-first touch merely because a shin is beyond it.
			var shin_fraction: float = (pairs[0]-sweep_start).dot(travel)/maxf(length_squared,.000001)
			var shin_offset: float = sqrt(maxf(0.0,.11*.11-pairs[0].distance_squared_to(pairs[1]))/maxf(length_squared,.000001))
			var shin_entry: float = clampf(shin_fraction-shin_offset,0,1)
			if length_squared<.000001 or shin_entry<=ball_fraction+.0001: return false
	return true

func resolve_tackle_contact(actor: Node3D, _aim: Vector3, point: Vector3) -> bool:
	var action: FootballFootAction = actor.foot
	if not can_foot_action(actor,"TACKLE") or ball.carrier==actor: return false
	if action.kind!="TACKLE" or action.phase!=FootballFootAction.Phase.CONTACT or action.hit or action.tackle_contact_consumed or action.foul_reported: return false
	if not point.is_finite() or not action.previous_toe.is_finite() or not ball.velocity.is_finite(): return false
	var contact:Dictionary=standing_tackle_contact_sample(action)
	if contact.is_empty() or point.distance_to(action.toe_world)>.001:return false
	action.touch_plan["tackle_contact_center"]=contact.center
	if is_instance_valid(ball.carrier) and ball.carrier.team==actor.team: return false
	# Preserve physical shoe limits; no root-angle veto after an actual side contact.
	if ball.position.y>.46:return false
	if flat_distance(actor.position,ball.position)>tuning.tackle_reach+ball.radius: return false
	if not standing_tackle_path_clear(action):
		action.contact_failure = "body_blocked"
		return false
	var normal:Vector3=contact.normal
	if normal.length_squared()<.000001: return false
	normal = normal.normalized()
	var before: Vector3 = ball.velocity
	var incoming:=Vector3(before.x,0,before.z)
	var running:=Vector3(actor.velocity.x,0,actor.velocity.z)
	var intercept:bool=bool(action.touch_plan.get("intercept",false))
	var desired:Vector3
	var relative_speed:float=(incoming-running).length()
	var budget:float=3.0
	if intercept:
		# World callbacks and swept shoe contact settle with the same normal and law.
		if relative_speed<4.0:
			desired=running.limit_length(2.0)*.7+(incoming-running)*.18
			budget=4.0
		else:
			var response:Dictionary=FootballContactMath.sphere_response(incoming,ball.spin_rads,running*.3,normal,actor.physics_mass_kg(),.20,.35,ball.profile,true)
			desired=response.velocity
			budget=(desired-incoming).length()
	else:desired=(normal*tuning.tackle_poke+running*.30+incoming*.12).limit_length(3.2)
	var change:Vector3=(desired-incoming).limit_length(budget)
	var impulse_ns: Vector3 = change*ball.mass_kg
	if not impulse_ns.is_finite() or impulse_ns.length_squared()<.000001: return false
	# Consume before callbacks: this action id cannot settle twice, even re-entrantly.
	action.tackle_contact_consumed = true
	if not ball.apply_impulse_ns(impulse_ns,point-ball.position):
		action.tackle_contact_consumed = false
		return false
	actor.receive_body_impulse_ns(-impulse_ns)
	ball.record_touch(actor,before,.18,"TACKLE",point)
	ball.detach()
	ball.pickup_block = .055 if Vector2(ball.velocity.x,ball.velocity.z).length()<2.5 else .10
	action.touch_plan["defense_follow_receive"]=Vector2(ball.velocity.x,ball.velocity.z).length()<3.0
	stats["tackles" if actor.is_human else "ai_tackles"] += 1
	return true

func observe_tackle_leg_contact(action: FootballFootAction, delta: float) -> bool:
	# Only a real swept boot striking a shin before contacting the ball is evidence.
	# Ordinary shoulder/body collisions never become a foul by proximity or speed.
	if not can_touch_ball(action.actor): return false
	for other in players:
		if other==action.actor or other.team==action.actor.team or not other.visible or flat_distance(other.position,action.toe_world)>1.4: continue
		var skeleton: Skeleton3D = other.avatar.skeleton
		for suffix in ["L","R"]:
			var a := skeleton.to_global(skeleton.get_bone_global_pose(other.avatar.cached_bone_id("foot."+suffix)).origin)
			var b := skeleton.to_global(skeleton.get_bone_global_pose(other.avatar.cached_bone_id("shin."+suffix)).origin)
			var pairs := Geometry3D.get_closest_points_between_segments(action.previous_toe,action.toe_world,a,b)
			# A passing overlap is not automatically a trip. Require a new entry
			# into the actual shoe/shin shell and appreciable closing motion.
			if pairs[0].distance_to(pairs[1])>.085:continue
			var victim_velocity:Vector3=Vector3(other.velocity.x,0,other.velocity.z)
			var old_a:Vector3=a-victim_velocity*delta
			var old_b:Vector3=b-victim_velocity*delta
			var old_nearest:Vector3=Geometry3D.get_closest_point_to_segment(action.previous_toe,old_a,old_b)
			var prior_gap:float=action.previous_toe.distance_to(old_nearest)
			var leg_velocity:Vector3=(action.toe_world-action.previous_toe)/maxf(delta,.0001)
			var normal:Vector3=(old_nearest-action.previous_toe).normalized()
			var closing:float=maxf(0.0,(leg_velocity-victim_velocity).dot(normal))
			var entered:bool=prior_gap>.086
			var separation:float=pairs[0].distance_to(pairs[1])
			var core_contact:bool=separation<=.060 # .033 shin + .0325 shoe half-width, with edge allowance removed.
			var strike_velocity:Vector3=leg_velocity-Vector3(action.actor.velocity.x,0,action.actor.velocity.z)
			var directness:float=closing/maxf(.01,(leg_velocity-victim_velocity).length())
			var running_trip:bool=victim_velocity.length()>=2.2 and closing>=1.6 and entered and core_contact and directness>.45
			var kicked_leg:bool=strike_velocity.length()>=2.5 and closing>=2.4 and entered and core_contact and directness>.55 and action.elapsed>=.025
			var dangerous:bool=closing>=4.5 and strike_velocity.length()>=3.0 and entered and separation<=.045 and directness>.65
			if not (running_trip or kicked_leg or dangerous):continue
			var travel:Vector3=action.toe_world-action.previous_toe
			var length_sq:float=maxf(travel.length_squared(),.000001)
			# Compare first surface entries, not projections to the sphere centre.
			var ball_projection:float=(ball.position-action.previous_toe).dot(travel)/length_sq
			var ball_gap:float=(action.previous_toe+travel*ball_projection).distance_to(ball.position)
			var ball_shell:float=ball.radius+.045
			var ball_entry:float=ball_projection-sqrt(maxf(0.0,ball_shell*ball_shell-ball_gap*ball_gap)/length_sq)
			var shin_projection:float=(pairs[0]-action.previous_toe).dot(travel)/length_sq
			var shin_gap:float=pairs[0].distance_to(pairs[1])
			var shin_entry:float=shin_projection-sqrt(maxf(0.0,.085*.085-shin_gap*shin_gap)/length_sq)
			var ball_first:bool=action.hit or (ball_gap<=ball_shell and ball_entry<=1.0 and ball_projection>=0.0 and maxf(0,ball_entry)<maxf(0,shin_entry))
			if ball_first and not dangerous:continue
			var evidence := {"event_id":"leg:%d:%d:%d:%d" % [match_generation,action.actor.get_instance_id(),action.sequence,other.get_instance_id()],"offender_id":action.actor.get_instance_id(),"offender_team":action.actor.team,"victim_id":other.get_instance_id(),"victim_team":other.team,"position":pairs[1],"confirmed":true,"offence":"trip","severity":"reckless" if dangerous else "careless","contact":true,"disruptive":true,"dangerous":dangerous,"closing_speed":closing,"shin_separation":separation,"normal_fraction":directness,"limb_strike_speed":strike_velocity.length(),"new_contact_entry":entered,"ball_first":ball_first,"ball_in_play_at_contact":true,"body_contact_time":Engine.get_physics_frames()/120.0,"ball_contact_time":-1.0,"source":"swept_rendered_boot_to_rendered_shin"}
			apply_contact_fall(other,String(evidence.event_id),{"cause":"extended_leg","contact":true,"speed":Vector2(other.velocity.x,other.velocity.z).length()})
			foul_evidence.append(evidence)
			contact_hub.publish({"kind":"BODY_CONTACT","actor":action.actor,"other":other,"point":pairs[1],"normal":(action.toe_world-pairs[1]).normalized(),"impulse":Vector3.ZERO,"action":"LEG_CHALLENGE","sequence":action.sequence,"event_id":evidence.event_id,"foul_evidence":evidence})
			return true
	return false

func on_ball_body_contact(collider: Object, point: Vector3, impulse: Vector3) -> void:
	if not collider is FootballPlayerMotor or not can_touch_ball(collider): return
	ball.last_touch_team = collider.team
	contact_hub.publish({"kind":"BODY_CONTACT","actor":collider,"other":ball,"point":point,"normal":impulse.normalized(),"impulse":impulse,"ball_contact":true,"action":"BALL_BODY","sequence":ball.body_collision_count})

func _on_actor_body_contact(other: CharacterBody3D, normal: Vector3, impulse: Vector3, actor: CharacterBody3D) -> void:
	if not other is FootballPlayerMotor or actor.get_instance_id()>other.get_instance_id(): return
	contact_hub.publish({"kind":"BODY_CONTACT","actor":actor,"other":other,"point":(actor.position+other.position)*.5+Vector3.UP*.9,"normal":normal,"impulse":impulse,"action":"SHOULDER","sequence":other.get_instance_id()})

func report_foot_contact(actor: Node3D, action: String, point: Vector3, surface: String, before: Vector3, after: Vector3, success := true, extra: Dictionary = {}) -> void:
	var event := extra.duplicate()
	event.merge({"kind":"FOOT_TOUCH" if success else "FOOT_ACTION_FAILED","actor":actor,"team":actor.team,"action":action,"surface":surface,"point":point,"normal":(after-before).normalized(),"before_velocity":before,"after_velocity":after,"impulse":(after-before)*ball.mass_kg,"success":success,"physics_frame":Engine.get_physics_frames(),"sequence":extra.get("action_sequence",0)},true)
	if extra.get("contact_normal") is Vector3: event.normal = extra.contact_normal
	contact_hub.publish(event)

func _update_throw_requests(delta: float) -> void:
	for id in throw_requests.keys():
		var request: Dictionary = throw_requests[id]
		if not services.can_take_restart(id):
			throw_requests.erase(id)
			continue
		request.age += delta
		if request.age<.30: continue
		var mapped: Dictionary = KickMapping.from_input_intent(request.intent,physics_profile)
		var speed := lerpf(4,14,float(request.intent.power))
		services.request_restart(id,mapped.direction_world,speed,3.2,"throw:%d:%d:%d" % [match_generation,id,Engine.get_physics_frames()])
		throw_requests.erase(id)

func constrained_human_intent(intended: Vector3) -> Vector3:
	if services.rules.state not in [Rules.State.RESTART_SETUP,Rules.State.RESTART_READY]: return intended
	var actor := {"id":player.get_instance_id(),"team":player.team,"position":player.position}
	var legal := services.constrain_restart_position(actor,player.position)
	var correction := Vector3(legal.x-player.position.x,0,legal.z-player.position.z)
	if correction.length()>.04:
		# Referee distance/half restrictions use the same bounded physical motor.
		# No transform/view reset; tangential and outward human movement remain possible.
		var outward := correction.normalized()
		var tangent := intended-outward*minf(0,intended.dot(outward))
		return (tangent+outward*.55).limit_length(1)
	var projected := services.constrain_restart_position(actor,player.position+intended*.10)
	if flat_distance(projected,player.position+intended*.10)>.04: return Vector3.ZERO
	return intended

func restart_hint() -> String:
	var restart: Dictionary = services.rules.restart
	var labels := {"kickoff":"开球","throw_in":"界外球","corner":"角球","goal_kick":"球门球","direct_free_kick":"直接任意球","indirect_free_kick":"间接任意球","penalty":"点球","dropped_ball":"坠球"}
	var label := String(labels.get(restart.get("kind",""),"重开球"))
	var actor := actor_by_instance(int(restart.get("taker_id",-1)))
	var taker := "等待球员" if not is_instance_valid(actor) else ("你" if actor.is_human else ("蓝队" if actor.team==0 else "红队")+" #%d" % actor.jersey)
	return label+" · "+taker+(" · 按住 Q / 右键，松开传球" if is_instance_valid(actor) and actor.is_human and services.can_take_restart(actor.get_instance_id()) else " · 球员正在到位")

func attack_direction(team: int) -> float:
	return float(services.rules.attack_signs[team]) if is_instance_valid(services) else -1.0 if team==0 else 1.0

func target_goal(team: int) -> Vector3:
	return Vector3(0,.3,attack_direction(team)*(field_half_length+.6))

func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x-b.x,a.z-b.z).length()

func message(text: String, duration := 2.0) -> void:
	status_message = text
	status_timer = duration

func sync_input_context() -> void:
	if is_instance_valid(input_bridge): input_bridge.sync_context()

func ai_decisions() -> void:
	if is_instance_valid(tactics_bridge): tactics_bridge.refresh_now()

func _setup_input() -> void:
	if not InputMap.has_action("restart_match"):
		InputMap.add_action("restart_match")
		var key := InputEventKey.new()
		key.physical_keycode = KEY_R
		InputMap.action_add_event("restart_match",key)

func apply_contact_fall(victim:Node3D,id:String,proof:Dictionary)->void:
	var down:Node=victim.down_state if victim is FootballAgent else victim.interaction.low_body
	if not is_instance_valid(down):
		down=preload("res://addons/football_interaction/low_body_state.gd").new()
		down.setup(self,victim)
		victim.down_state=down
		victim.add_child(down)
	down.enter_hit(id,victim.facing,.45,proof)
