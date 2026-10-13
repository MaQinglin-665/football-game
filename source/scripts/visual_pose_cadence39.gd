extends RefCounted
# Visual LOD only. Player input, AI, motors, body sweeps and ball stay at 120 Hz.
# Semantic/near-ball queries force a current pose through the existing interface.
static var _args_read:=false
static var _disabled:=false
static func far_visual(actor:Node3D)->bool:
	if not _args_read:
		_disabled="--visual-cadence=A" in OS.get_cmdline_user_args();_args_read=true
	if _disabled:return _full(actor)
	if actor.is_human or not actor.active:return _full(actor)
	var game:Node=actor.match_controller
	if not is_instance_valid(game) or game.phase in [game.Phase.MENU,game.Phase.PAUSED,game.Phase.FINISHED] or not is_instance_valid(game.ball):return _full(actor)
	if not actor.foot.idle() or not actor.pending_kick.is_empty() or not actor.avatar._action.is_empty():return _full(actor)
	if is_instance_valid(actor.down_state) and actor.down_state.blocked():return _full(actor)
	if actor.is_goalkeeper and (actor.keeper_dive_allowed() or game.ball.held and is_instance_valid(game.ball.keeper_host.hand_owner) and game.ball.keeper_host.hand_owner==actor):return _full(actor)
	if actor.is_goalkeeper and actor.position.distance_to(game.ball.position)<12.0+game.ball.velocity.length()*.3:return _full(actor)
	if game.ball.carrier==actor or game.pass_receiver==actor:return _full(actor)
	var tick:int=Engine.get_physics_frames()
	if actor._visual_policy_tick_perf==tick:return actor._visual_far39
	actor._visual_policy_tick_perf=tick
	var was_far:bool=actor._visual_far39
	# Conservative incoming-ball horizon is longer than one visual sample.
	# Body/player collisions use independent live motor capsules, not these soles.
	var margin:float=(7.0 if was_far else 9.0)+(game.ball.velocity.length()+actor.velocity.length())*.12
	if actor.global_position.distance_squared_to(game.ball.global_position)<=margin*margin:return _full(actor)
	if actor.global_position.distance_squared_to(game.player.global_position)<=pow(7.0 if was_far else 9.0,2):return _full(actor)
	actor._visual_far39=true
	return true
static func _full(actor:Node3D)->bool:
	if not actor.is_human:
		if actor._visual_far39:preload("res://scripts/frame_spike_watch.gd").promoted+=1
		actor._visual_far39=false
	return false

static func needs_exact_contact_pose(actor:Node3D)->bool:
	if actor.is_human or not actor.active:return true
	var game:Node=actor.match_controller
	if not is_instance_valid(game.ball) or game.phase!=game.Phase.PLAY:return true
	if not actor.foot.idle() or not actor.pending_kick.is_empty() or not actor.avatar._action.is_empty():return true
	if is_instance_valid(actor.down_state) and actor.down_state.blocked():return true
	if actor.is_goalkeeper and (actor.keeper_dive_allowed() or actor.position.distance_to(game.ball.position)<12.0+game.ball.velocity.length()*.3):return true
	if game.ball.carrier==actor or game.pass_receiver==actor:return true
	# More than a complete 60 Hz interval plus collision/foot reach, including incoming speed.
	var horizon:float=3.0+(game.ball.velocity.length()+actor.velocity.length())*.06
	if actor.global_position.distance_squared_to(game.ball.global_position)<horizon*horizon:return true
	return actor.global_position.distance_squared_to(game.player.global_position)<6.25

static func defer_mid_pose(actor:Node3D)->bool:
	if _disabled or needs_exact_contact_pose(actor):return false
	# Extra physics catch-up steps do not need additional distant display solves.
	# Real nearby contacts bypass this branch and still run at physics cadence.
	var draw:int=Engine.get_process_frames()
	if actor._visual_mid_draw_frame==draw:return true
	if (Engine.get_physics_frames()+actor.get_instance_id())%2!=0:return true
	actor._visual_mid_draw_frame=draw
	return false
