class_name FootballMatchInputBridge
extends Node
## Owns host context and command scheduling; the addon owns physical key arbitration.
const AdapterScript := preload("res://addons/football_input/input_adapter.gd")
const HelpScript := preload("res://addons/football_input/help_zh.gd")
const ShiftInputScript := preload("res://addons/football_shift_tiers/shift_tier_input.gd")
const ShiftOverlayScript := preload("res://addons/football_shift_tiers/legacy_intent_overlay.gd")
const HeavyQueueScript := preload("res://addons/football_shift_tiers/heavy_touch_host_queue.gd")
const POLICY_ACTIONS := ["close_control", "shield", "push_ball", "pressure", "keeper_ready"]
var game: Node
var adapter: Node
var shift_input: Node
var shift_policy: Dictionary = {}
var shift_overlay: RefCounted = ShiftOverlayScript.new()
var authority_epoch := 0
var heavy_gestures: Dictionary = {}
var heavy_queue: RefCounted = HeavyQueueScript.new()
var pressure:RefCounted=preload("res://scripts/held_pressure.gd").new()
var focused := true
var last_sequence := 0
var context: Dictionary = {}
var charge_preview: Dictionary = {}
var traces: Array[Dictionary] = []
var rejected_commands := 0
var pending_intents: Array[Dictionary] = []
var capabilities := {
	"cut_ball":true, "close_control":true, "shield":true, "stop_ball":true, "nudge":true,
	"push_ball":true, "receive":true, "pass_ground":true,
	"shoot_straight":true, "pressure":true, "tackle_stand":true,
	"pass_high":true, "pass_spin":true, "shoot_curve":true,
	"tackle_slide":true, "keeper_ready":false,
	"keeper_dive":false, "keeper_distribute":false
}

func _ready() -> void:
	name = "SemanticInput"
	process_physics_priority = -50
	adapter = AdapterScript.new()
	adapter.automatic_tick = false
	adapter.intent_emitted.connect(_on_legacy_intent)
	adapter.ui_requested.connect(_on_ui)
	adapter.notice_emitted.connect(func(notice: Dictionary): game.message(String(notice.message_zh),2.0))
	add_child(adapter)
	shift_input = ShiftInputScript.new()
	shift_input.observe_input = false
	shift_input.automatic_tick = false
	shift_input.policy_changed.connect(_on_shift_policy)
	shift_input.intent_emitted.connect(func(intent: Dictionary): _on_intent(shift_overlay.route_shift(intent)))
	shift_input.notice_emitted.connect(func(notice: Dictionary): game.message(String(notice.message_zh),1.5))
	heavy_queue.command_cancelled.connect(func(intent: Dictionary): _on_intent(shift_overlay.route_shift(intent)))
	add_child(shift_input)
	sync_context()

func _input(event: InputEvent) -> void:
	if not is_instance_valid(shift_input) or not event.is_action("ff_sprint",false): return
	sync_context()
	_sync_shift_direction()
	shift_input.feed_event(event)

func _sync_shift_direction() -> void:
	var axes := Input.get_vector("ff_left","ff_right","ff_forward","ff_back")
	var forward: Vector3 = -game.player.global_basis.z
	var movement: Vector3 = game.player.global_basis.x*axes.x-forward*axes.y
	shift_input.set_direction(movement,forward)

func _on_shift_policy(policy: Dictionary) -> void:
	shift_policy = policy.duplicate(true)
	if is_instance_valid(game.player): game.player.set_shift_policy(shift_policy)

func _on_legacy_intent(intent: Dictionary) -> void:
	var routed: Dictionary = shift_overlay.route_legacy(intent,shift_policy)
	if not routed.is_empty(): _on_intent(routed)

func _physics_process(delta: float) -> void:
	sync_context()
	adapter.set_aim(-game.player.global_basis.z,game.player.global_basis.x)
	adapter.tick(delta)
	sync_context()
	_sync_shift_direction()
	shift_input.tick()
	# NEXT emits on key edges as well as tick. Actual host requests are consumed
	# exactly here, before actors/feet/World, never in a native input callback.
	var queued := pending_intents.duplicate()
	pending_intents.clear()
	for intent in queued: _consume_intent(intent)
	_dispatch_heavy_touch()
	pressure.step(game,adapter.router,delta)

func _dispatch_heavy_touch() -> void:
	# Reserve the next idle slot before the player's automatic light carry.
	# This schedules the existing host foot action; it does not touch the ball.
	var intent: Dictionary = heavy_queue.take_ready(authoritative_context())
	if intent.is_empty(): return
	var accepted: bool = game.player.foot.request_heavy_touch(intent.direction,authority_epoch)
	heavy_queue.dispatch_result(intent,accepted)
	if not accepted:
		rejected_commands += 1

func sync_context() -> void:
	if not is_instance_valid(game) or not is_instance_valid(game.player) or not is_instance_valid(adapter):
		return
	var next := authoritative_context()
	if not context.is_empty():
		for barrier in ["possession","restart_id","phase","paused","focused","ui_captured","ball_generation"]:
			if context.get(barrier)!=next.get(barrier):
				pending_intents.clear()
				authority_epoch += 1
				if game.player.foot.has_receive_pass():
					game.player.foot.clear_buffer("receive_pass_context_changed")
					if game.player.foot.kind=="PASS" and not game.player.foot.hit and game.player.foot.kick_intent.get("one_touch_pass",false) and game.player.foot.phase!=FootballFootAction.Phase.CONTACT: game.player.foot.cancel("receive_pass_context_changed")
				break
	if not context.is_empty() and (context.possession != next.possession or context.restart_id != next.restart_id):
		game.player.foot.clear_buffer("possession_changed" if context.possession!=next.possession else "restart_changed")
		if game.player.foot.kind in ["PASS","SHOT"] and not game.player.foot.hit and game.player.foot.phase != FootballFootAction.Phase.CONTACT:
			game.player.foot.cancel("possession_changed")
	context = next
	# Deliberate charging can wait through an ordinary carry recovery.
	# Shift and its next-foot queue retain the actual idle-slot context.
	var charge_context := context.duplicate(true)
	charge_context["host_kick_queue"] = true
	charge_context["action_ready"] = game.player.action_cooldown<=.24 and (not game.player.foot.has_buffer() or game.player.foot.has_receive_pass()) and (game.player.foot.kind not in ["PASS","SHOT","TACKLE"] or (game.player.foot.kind in ["PASS","SHOT"] and game.player.foot.hit)) and (not is_instance_valid(game.player.interaction) or game.player.interaction.permits_foot_action())
	adapter.set_context(charge_context)
	if is_instance_valid(shift_input): shift_input.set_context(context)
	heavy_queue.observe_context(context)
	var allow_view: bool = context.phase != "menu" and not context.paused and context.focused and not context.ui_captured
	game.player.head.enabled = allow_view

func authoritative_context() -> Dictionary:
	var p: Node3D = game.player
	var live: bool = game.phase == game.Phase.PLAY
	var dead: bool = game.phase in [game.Phase.COUNTDOWN,game.Phase.RESTART,game.Phase.GOAL]
	var ui_capture: bool = is_instance_valid(game.hud) and (game.hud.help.visible or game.hud.credits.visible)
	var possession := "foot" if game.ball.carrier == p else "none"
	var near_free: bool = not is_instance_valid(game.ball.carrier) and game.ball.position.y < 0.40 and game.flat_distance(p.position,game.ball.position) <= game.tuning.pickup_reach and game.can_reach_ball(p)
	return {
		"actor_id":"blue-%d:%s" % [p.jersey,p.get_instance_id()], "role":"outfield", "position":game.Selection.human_row(game).get("slot",""),
		"possession":possession, "phase":"live" if live else "dead_ball" if dead else "menu",
		"paused":game.phase == game.Phase.PAUSED, "focused":focused, "ui_captured":ui_capture,
		"restart_taker":game.is_restart_taker(p), "restart_id":str(game.formation_serial),
		"ball_generation":game.ball.get_instance_id(), "receive_available":near_free, "pass_receive_available":not p.foot.receive_pass_window().is_empty(),
		"action_ready":p.action_cooldown<=0 and not p.foot.has_buffer() and p.foot.idle() and (not is_instance_valid(p.interaction) or p.interaction.permits_foot_action()),
		"close_override":adapter.router.is_held("close") or adapter.router.is_held("stance"),
		"action_exclusive":not adapter.snapshot().charge.is_empty() or p.foot.kind in ["PASS","SHOT","TACKLE"] or (is_instance_valid(p.interaction) and not p.interaction.permits_foot_action()),
		"capabilities":capabilities.duplicate(), "allowed_actions":[]
	}

func _on_intent(intent: Dictionary) -> void:
	pending_intents.append(intent.duplicate(true))

func _consume_intent(intent: Dictionary) -> void:
	var sequence := int(intent.sequence)
	if sequence <= last_sequence:
		return
	last_sequence = sequence
	traces.append(intent.duplicate())
	if traces.size() > 512:
		traces.pop_front()
	var action := String(intent.action)
	var phase := String(intent.phase)
	if intent.has("gesture_id"):
		charge_preview = intent.duplicate() if phase in ["begin","update"] else {}
		if phase=="begin" and action.begins_with("pass_") and bool(game.player.foot.buffer.get("one_touch_pass",false)):
			game.player.foot.clear_buffer("new_pass_command")
		if phase != "commit":
			return
	if action == "move":
		game.player.set_semantic_movement(intent.direction * float(intent.power),String(intent.style))
		return
	if action in POLICY_ACTIONS and phase != "commit":
		game.player.set_semantic_policy(action,phase in ["begin","update"])
		return
	if phase != "commit":
		return
	if context.phase == "dead_ball":
		if context.restart_taker and action in ["pass_ground","pass_high","pass_spin","shoot_straight","shoot_curve"]:
			if not game.request_player_kick(intent): rejected_commands += 1
		else:
			rejected_commands += 1
			game.message("重开准备中，可以移动和观察",1.5)
		return
	if game.phase != game.Phase.PLAY:
		rejected_commands += 1
		return
	var p: Node3D = game.player
	var accepted := false
	match action:
		"cancel_pass_queue":
			if p.foot.has_receive_pass():
				p.foot.clear_buffer("input_cancel")
				if p.foot.kind=="PASS" and not p.foot.hit and p.foot.kick_intent.get("one_touch_pass",false): p.foot.cancel("input_cancel")
			accepted = true
		"call_ball":
			game.call_timer = 3.0
			game.player.request_call_gesture()
			game.message("已呼叫队友传球",1.8)
			if game.ai_enabled:
				game.ai_decisions()
			accepted = true
		"pass_ground", "pass_high", "pass_spin", "shoot_straight", "shoot_curve":
			var request := intent.duplicate(true)
			if action.begins_with("pass_") and game.ball.carrier!=p: request["one_touch_pass"] = true
			accepted = game.request_player_kick(request)
		"stop_ball":
			if game.ball.carrier==p and p.semantic_motion.length()>.1: accepted = p.foot.request_nudge(p.semantic_motion.normalized())
			else: accepted = game.ball.stop_at_foot(p)
		"cut_ball":
			if game.ball.carrier==p:
				accepted=p.foot.request_cut(intent.direction if intent.get("cut_direction_selected",false) else Vector3.ZERO)
		"nudge":
			if game.ball.carrier == p:
				accepted = p.foot.request_nudge(intent.direction)
		"push_ball":
			if intent.get("request_mode","")=="next_foot_window":
				accepted = heavy_queue.offer(intent,authoritative_context())
			elif game.ball.carrier == p and p.foot.idle():
				var gesture := String(intent.get("gesture_id",""))
				var current_scope: bool = int(intent.get("ball_generation",game.ball.get_instance_id()))==game.ball.get_instance_id() and String(intent.get("restart_id",str(game.formation_serial)))==str(game.formation_serial)
				if current_scope and (gesture.is_empty() or not heavy_gestures.has(gesture)):
					accepted = p.foot.request_heavy_touch(intent.direction,authority_epoch)
					if accepted and not gesture.is_empty():
						heavy_gestures[gesture] = true
						if heavy_gestures.size()>32: heavy_gestures.erase(heavy_gestures.keys()[0])
		"receive":
			if p.foot.has_receive_pass():
				p.foot.clear_buffer("explicit_receive")
				if p.foot.kind=="PASS" and not p.foot.hit and p.foot.kick_intent.get("one_touch_pass",false): p.foot.cancel("explicit_receive")
			if context.receive_available and p.foot.idle():
				accepted = p.foot.begin("RECEIVE",game.ball.position-p.position)
		"tackle_stand":
			accepted = game.attempt_tackle(p)
		"tackle_slide":
			accepted = is_instance_valid(p.interaction) and p.interaction.request_slide(intent.direction)
		_:
			game.message("动作尚未接入："+action,1.5)
	if not accepted:
		rejected_commands += 1
		if action in ["shoot_straight","shoot_curve"]:
			var relative: Vector3 = game.ball.position-p.position
			var reason := "cooldown" if p.action_cooldown>0 else "ball_out_of_range" if Vector2(relative.x,relative.z).length()>1.02 else "ball_too_high" if game.ball.position.y>=.46 else "body_blocked" if not game.can_reach_ball(p) else "foot_busy"
			p.foot.trace_stage("inputrejected",reason)
			game.message("球已离脚，靠近后再射" if reason=="ball_out_of_range" else "球太高，落地后再射" if reason=="ball_too_high" else "射门被身体挡住" if reason=="body_blocked" else "出脚恢复中，稍后重按",1.3)
			return
		if action not in ["call_ball"]:
			game.message("出脚尚未就绪，靠近球后重按",1.2)

func _on_ui(command: String) -> void:
	if is_instance_valid(game.settings_menu) and game.settings_menu.opened:
		if command=="pause":game.settings_menu.close_menu()
		return
	if command == "pause":
		if game.hud.credits.visible:
			game.hud.credits.hide()
		elif game.hud.help.visible:
			game.hud.help.hide()
		elif game.phase == game.Phase.PAUSED:
			game.resume_match()
		elif game.phase == game.Phase.MENU:
			game.quit_game()
		elif game.phase != game.Phase.FINISHED:
			game.pause_match()
	elif command == "help":
		game.hud.toggle_help()
	elif command == "fullscreen":
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
	sync_context()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		focused = false
		sync_context()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		focused = true
		sync_context()

func help_text() -> String:
	return HelpScript.text(context).replace("WASD / 方向键：跑动；Ctrl 慢走 / 近控；Shift 冲刺 / 大趟","WASD / 方向键：移动；Ctrl 慢走 / 近控")+"\n\n"+shift_input.router.help_text_zh()+"\n\n"+(game.player.interaction.help_text() if is_instance_valid(game.player.interaction) else "")

func hint_text() -> String:
	var hint := HelpScript.contextual_hint(context,adapter.snapshot()).replace(" · V 飞铲","")
	if context.phase=="live" and not context.paused and not context.ui_captured:
		hint += "\n"+("加速已开启 · 单击 Shift 关闭" if shift_policy.get("sprint_toggled",false) else "单击 Shift 开启加速")+" · 双击 Shift：一次大趟"
	return hint
