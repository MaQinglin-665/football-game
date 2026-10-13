extends "res://tests/three_turn038_short.gd"
class CompletedPhysicsRecorder:
	extends Node
	var probe:Variant
	func _physics_process(_dt:float)->void:
		if probe.trace_enabled:probe.sample_completed()
var trace_enabled:bool=false
var input_physics_frame:int=-1
var socket_ids:Dictionary={}
var metadata:Dictionary={}
var observer_epoch_changes:int=0
var probe_rows:Array=[]
func start()->void:
	game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game);current_scene=game
	for i in 4:await process_frame
	game.hud.menu.get_node("StartMatch").pressed.emit()
	for i in 24:await physics_frame
	await reset_case("fast_90","B",Vector2(0,.28),true)
	var sk:Skeleton3D=game.player.avatar.skeleton
	socket_ids={"L_INSIDE":sk.find_bone("contact_inner.L"),"R_OUTSIDE":sk.find_bone("contact_outer.R")}
	var profile=game.player.profile
	metadata={"brake_deceleration_mps2":profile.brake_deceleration_mps2,"start_acceleration_mps2":profile.start_acceleration_mps2,"turn_acceleration_mps2":profile.turn_acceleration_mps2,"ball_mass_kg":game.physics_profile.ball_mass_kg,"roll_deceleration_mps2":game.physics_profile.roll_deceleration_mps2,"low_speed_roll_extra_mps2":game.physics_profile.low_speed_roll_extra_mps2,"source_sha256":{}}
	for path in ["res://scripts/ordinary_touch_scheduler.gd","res://addons/football_motion/football_motion_avatar.gd","res://addons/football_character/football_character.gd","res://addons/football_character/football_character_base.gd","res://addons/football_physics/physics_profile.gd","res://addons/football_physics/foot_contact_response.gd","res://scripts/control_tuning.gd","res://scripts/football.gd"]:
		if FileAccess.file_exists(path):metadata.source_sha256[path]=FileAccess.get_sha256(path)
	var recorder:=CompletedPhysicsRecorder.new()
	recorder.probe=self;recorder.process_physics_priority=1000000;root.add_child(recorder)
	set_keys([KEY_SHIFT,KEY_W]);await ticks(178)
	trace_enabled=true;await ticks(2)
	input_physics_frame=Engine.get_physics_frames();set_keys([KEY_SHIFT,KEY_D])
	var touch_frame:int=-1
	for i in 360:
		await ticks(1)
		if touch_frame<0:
			for c in contacts:
				if c.event.success and c.event.action=="TURN" and c.plan.get("turn_stage","")=="EXIT":touch_frame=int(c.event.physics_frame)
		if touch_frame>=0 and Engine.get_physics_frames()>=touch_frame+60:break
	# Finish the last normal physics callback before stopping/serializing.
	await process_frame
	set_keys([])
	check("single near-human trace and required both directional sockets",not probe_rows.is_empty() and probe_rows.all(func(r):return r.shoes.size()==2 and r.shoes.has("L_INSIDE") and r.shoes.has("R_OUTSIDE")))
	var consecutive:bool=true
	for i in range(1,probe_rows.size()):
		if int(probe_rows[i].physics_frame)-int(probe_rows[i-1].physics_frame)!=1:consecutive=false
	check("strict consecutive120Hz completed physics frames",consecutive)
	check("queries never advance pose epoch or solve counter",observer_epoch_changes==0)
	check("actual EXIT contact observed",touch_frame>=0)
	check("actual half-second post-contact observed",touch_frame>=0 and Engine.get_physics_frames()>=touch_frame+60)
	var report:String=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):report=arg.trim_prefix("--output=")
	var ok:bool=checks.all(func(c):return c.passed)
	FileAccess.open(report,FileAccess.WRITE).store_string(JSON.stringify({"passed":ok,"checks":checks,"physics120":Engine.physics_ticks_per_second,"input_physics_frame":input_physics_frame,"input_tick":180,"touch_physics_frame":touch_frame,"input_to_actual_touch_seconds":float(touch_frame-input_physics_frame)/120.0 if touch_frame>=0 else -1.0,"original_two_second_window_passed":touch_frame>=0 and touch_frame-input_physics_frame<=240,"observer_epoch_changes":observer_epoch_changes,"metadata":metadata,"rows":probe_rows,"contacts":contacts,"steps":steps,"scope":"One diagnostic only, existing044+absolute-safety044 production source unchanged. Original isolated training3v3 ShiftW180ticks→ShiftD, two pre-input completed frames then through realcontact+60ticks. Only current human observed; other5actors use unchanged original isolatedfixture. Strict120Hz Node observer priority1000000 after normal physics nodes, no per-frame awaitprocess synchronization, reads completed cache and four globalbone queries (2hips+2socketpoints), no ensure/force/solver/reserve/stable_direction shadow calls, no full skeletal snapshot. Ordinary original2s acceptance not changed; this diagnostic is not a gameplay fix."},"\t"))
	trace_enabled=false;recorder.set_physics_process(false);recorder.queue_free()
	game.shutdown_audio();game.queue_free()
	for i in 4:await process_frame
	quit(0 if ok else 1)
func ticks(count:int)->void:
	for i in count:
		await physics_frame
		case_tick+=1
func sample_completed()->void:
	var actor=game.player
	var avatar=actor.avatar
	var foot=actor.foot
	var scheduler=foot.ordinary_scheduler
	var before:Dictionary=avatar.get_pose_refresh_debug()
	var clock:Dictionary=avatar.ordinary_gait_clock040(true)
	var shoes:Dictionary={"L_INSIDE":read_completed_socket(avatar,-1,"INSIDE","L_INSIDE"),"R_OUTSIDE":read_completed_socket(avatar,1,"OUTSIDE","R_OUTSIDE")}
	var after:Dictionary=avatar.get_pose_refresh_debug()
	if before.pose_tick!=after.pose_tick or before.pose_world_step!=after.pose_world_step or before.solves!=after.solves:observer_epoch_changes+=1
	probe_rows.append(pack({"tick":case_tick,"physics_frame":Engine.get_physics_frames(),"pose_tick":before.pose_tick,"pose_world_step":before.pose_world_step,"world_step":game.physics_world.step_serial,"epoch_before":before,"epoch_after":after,"actor":actor.position,"actor_velocity":actor.velocity,"ball":game.ball.position,"ball_velocity":game.ball.velocity,"motor_target":actor.shared_last_result.get("motion",Vector3.ZERO),"owned":game.ball.carrier==actor,"foot_phase":foot.phase,"foot_kind":foot.kind,"foot_sequence":foot.sequence,"foot_side":foot.side,"foot_surface":foot.surface,"foot_elapsed":foot.elapsed,"hit":foot.hit,"failure":foot.contact_failure,"direct_scheduler":{"turn_stage":scheduler.turn_stage,"turn_incoming":scheduler.turn_incoming,"turn_aim":scheduler.turn_aim,"brake_contact":scheduler._brake_contact,"turn_request":scheduler._turn_request,"raw_direction":actor.get_ball_direction(),"accepted_direction":scheduler._accepted_direction,"accepted_direction_tick":scheduler._direction_tick,"exit_root_target_valid":scheduler._exit_root_target_valid043,"exit_root_target":scheduler._exit_root_target043},"gait_clock":clock,"shoes":shoes,"support_cache":avatar._plants,"body_debug":avatar.get_full_body_debug(),"last_decision":scheduler.last_decision}))
func read_completed_socket(avatar,side:int,surface:String,key:String)->Dictionary:
	# Read the same completed bone pose directly. Unlike production getter,
	# observer does not ensure_contact_pose_current or ensure_loaded.
	var suffix:String=avatar.side_suffix(side)
	var id:int=int(socket_ids[key])
	if id<0:return {"side":side,"surface":surface,"valid":false,"reach_error":INF}
	var sk:Skeleton3D=avatar.skeleton
	var point:Vector3=sk.to_global(sk.get_bone_global_pose(id).origin)
	var error:float=avatar._reach_error
	var valid:bool=true
	var action:Dictionary=avatar._action
	if not action.is_empty() and avatar.side_suffix(int(action.get("side",side)))==suffix:
		valid=not avatar._unreachable
		if action.has("world_target"):
			error=maxf(error,point.distance_to(action.world_target));valid=valid and error<=.035
	return {"side":side,"surface":surface,"point":point,"valid":valid,"reach_error":error}
func on_contact(event:Dictionary)->void:
	if event.actor!=game.player or event.get("kind","") not in ["FOOT_TOUCH","FOOT_ACTION_FAILED"]:return
	# Actual natural event only; use cached plan/state, no observer support refresh.
	contacts.append(pack({"tick":case_tick,"event":event,"sequence":game.player.foot.sequence,"side":game.player.foot.side,"surface":game.player.foot.surface,"plan":game.player.foot.touch_plan,"direct_stage":game.player.foot.ordinary_scheduler.turn_stage,"actor":game.player.position,"ball":game.ball.position}))
