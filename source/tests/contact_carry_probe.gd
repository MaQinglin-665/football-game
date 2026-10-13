extends "res://tests/integration_checks.gd"
var a:Node3D
var rows:Array=[]
var successful:Array=[]
var stage_name:String="receive"
var previous_ankles:Dictionary={}
var previous_steps:Dictionary={}
var previous_bones:Dictionary={}
var reference_ready:=false
func observe(n:int)->void:
	if not reference_ready:
		reference_ready=true
		if "--motion-before" in OS.get_cmdline_user_args():
			a.avatar._body=load("res://tests/contact_reference/body_motion.gd").new()
			a.avatar.ai_body_presentation=load("res://tests/contact_reference/ai_body_presentation.gd").new()
			a.avatar.ai_run_ankles=load("res://tests/contact_reference/ai_run_ankles.gd").new()
			a.avatar._carry_run07=load("res://tests/contact_reference/carry_run_07.gd").new()
	for i in n:
		await physics_frame
		var jumps:Dictionary={}
		for side in ["L","R"]:
			var sk:Skeleton3D=a.avatar.skeleton
			var point:Vector3=sk.to_global(sk.get_bone_global_pose(sk.find_bone("foot."+side)).origin)-a.position
			var step:Vector3=point-previous_ankles.get(side,point)
			var previous:Vector3=previous_steps.get(side,Vector3.ZERO)
			jumps[side]=step.length()
			jumps[side+"_reversal"]=step.length()>.008 and previous.length()>.008 and step.normalized().dot(previous.normalized())<-.35
			previous_steps[side]=step;previous_ankles[side]=point
		var body_delta:Dictionary={}
		for bone in ["hips","chest","upper_arm.L","upper_arm.R","forearm.L","forearm.R"]:
			var q:Quaternion=a.avatar.skeleton.get_bone_pose_rotation(a.avatar.cached_bone_id(bone))
			body_delta[bone]=q.angle_to(previous_bones.get(bone,q));previous_bones[bone]=q
		rows.append({"body_delta":body_delta,"hip_position":a.avatar.skeleton.get_bone_pose_position(a.avatar.cached_bone_id("hips")),"ankle_delta":jumps,"sequence":a.foot.sequence,"side":a.foot.side,"stage":stage_name,"frame":Engine.get_physics_frames(),"owned":game.ball.carrier==a,"rhythm":a.ai_ordinary_rhythm(),"position":a.position,"speed":a.velocity.length(),"ball":game.ball.position,"ball_velocity":game.ball.velocity,"kind":a.foot.kind,"phase":a.foot.phase,"failure":a.foot.contact_failure})
func run()->void:
	seed(61906)
	game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game)
	await ticks(6);game.hud.menu.get_node("StartMatch").pressed.emit();await ticks(8)
	game.tactics_bridge.set_physics_process(false)
	for actor in game.players:
		actor.set_physics_process(false);actor.foot.cancel("fixture");actor.velocity=Vector3.ZERO;actor.set_move_intent(Vector3.ZERO)
		actor.position=Vector3(10+actor.team*2,.002,10+actor.jersey*.1)
		if actor!=game.player and actor.team==game.player.team and a==null:a=actor
	a.position=Vector3(0,.002,4);a.target=a.position;a.facing=Vector3.FORWARD;a.body_facing=Vector3.FORWARD;a.face_target=Vector3.FORWARD;a.active=true;a.action_cooldown=0;a.pending_kick.clear()
	a.avatar._plants.clear();a.avatar._last_contacts.clear();a.refresh_pose(1.0/120.0)
	game.ball.clear_control();game.ball.set_held(false);game.ball.reset(a.position+Vector3(0,game.ball.radius+.001,-.48));game.ball.pickup_block=0
	a.set_physics_process(true)
	game.contact_hub.contact_resolved.connect(func(e):
		if e.get("actor")==a and e.get("success",false):successful.append({"frame":Engine.get_physics_frames(),"kind":e.get("action",""),"sequence":e.get("action_sequence",-1),"reach_error":e.get("reach_error",-1),"before":e.get("before_velocity"),"after":e.get("after_velocity")}))
	check("free ball does not qualify as owned normal carry",not a.ai_ordinary_rhythm())
	check("actual reception request starts",a.foot.begin("RECEIVE",Vector3.FORWARD,Vector3.ZERO,0,.18))
	await observe(65)
	check("real RECEIVE contact establishes AI control",game.ball.carrier==a and successful.any(func(e):return e.kind=="RECEIVE"))
	a.tactical_intent={"reason":"carry_open_channel","close_control":true};a.tactical_pace=2.8;a.close_control=true;a.target=a.position+Vector3.FORWARD*12
	stage_name="close_carry"
	await observe(240)
	var carry_rows:Array=rows.slice(65)
	var control:bool="--ai-dribble-rhythm=A" in OS.get_cmdline_user_args()
	check("normal owned carry rhythm matches A/B flag",not carry_rows.any(func(r):return r.rhythm) if control else carry_rows.any(func(r):return r.rhythm))
	check("normal carry makes actual finite shoe contacts",successful.filter(func(e):return e.kind in ["CLOSE","CARRY","TURN"]).size()>=2)
	check("shared motor advances during owned carry",carry_rows.any(func(r):return r.owned and r.speed>1.0))
	stage_name="run_carry";a.tactical_intent.close_control=false;a.close_control=false;a.target=a.position+Vector3.FORWARD*12
	await observe(180)
	if not control:check("normal run carry crosses2.1mps with real ownership",rows.any(func(r):return r.stage=="run_carry" and r.owned and r.rhythm and r.speed>2.1))
	stage_name="turn45"
	a.target=a.position+Vector3(8,0,-8);a.face_target=Vector3(1,0,-1).normalized()
	await observe(180)
	var turning:Array=rows.filter(func(r):return r.stage=="turn45")
	check("AI45degree turn keeps the real rolling ball within next-touch distance",turning.all(func(r):return r.owned and (r.ball as Vector3).distance_to(r.position)<.85))
	check("all resulting motor and ball velocities remain finite",rows.all(func(r):return (r.ball_velocity as Vector3).is_finite() and is_finite(r.speed)))
	var ids:Dictionary={};var duplicate:=false
	for e in successful:
		var id:String=str(e.sequence)+":"+e.kind
		if ids.has(id):duplicate=true
		ids[id]=true
	check("actual action contacts do not duplicate sequence",not duplicate)
	var ok:bool=checks.all(func(c):return c.passed)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify({"passed":ok,"checks":checks,"rows":rows,"contacts":successful,"scope":"Same-scene body comparison with --motion-before selecting frozen old presentation modules. Isolated 3v3 declared starting free ball; actual RECEIVE then original AI/shared motor/foot/World carry and45degree target. Planner disabled; no assigned carrier/forced contact. Not natural planner selection or native feel."},"\t"))
	game.pause_match();game.shutdown_audio();game.queue_free();game=null
	for i in 4:await process_frame
	quit(0 if ok else 1)
