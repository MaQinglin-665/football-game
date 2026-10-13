extends SceneTree
## Isolated QA only: same normal 3v3 opening and real input in A/B.
class Tick:
	extends Node
	var runner: SceneTree
	func _physics_process(_delta:float)->void: runner.call("sample_tick")
const STAGES := [
	{"name":"low_cruise","ticks":240,"keys":[KEY_CTRL,KEY_W]},
	{"name":"low_inside_left","ticks":108,"keys":[KEY_CTRL,KEY_W,KEY_A],"reset":true},
	{"name":"low_cut_right","ticks":108,"keys":[KEY_CTRL,KEY_D],"reset":true},
	{"name":"low_left_again","ticks":108,"keys":[KEY_CTRL,KEY_A],"reset":true},
	{"name":"run","ticks":168,"keys":[KEY_SHIFT,KEY_W],"reset":true},
	{"name":"release_stop","ticks":60,"keys":[]},
	{"name":"pass_input","ticks":2,"keys":[KEY_Q],"reset":true},
	{"name":"pass_release","ticks":96,"keys":[]},
	{"name":"AI_defensive","ticks":180,"keys":[],"defensive":true}]
var game: Node3D
var tick: Tick
var evidence := ""
var tag := ""
var stage := 0
var stage_tick := 0
var keys: Array = []
var rows: Array = []
var contacts: Array = []
var checks: Array = []
func _initialize()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="): evidence=arg.trim_prefix("--evidence=")
		elif arg.begins_with("--tag="): tag=arg.trim_prefix("--tag=")
	if evidence.is_empty(): quit(2);return
	seed(61906)
	call_deferred("start")
func start()->void:
	game=(load("res://scenes/training_3v3.tscn") as PackedScene).instantiate()
	root.add_child(game);current_scene=game
	game.test_mode=true
	game.set_meta("cadence_commits",[])
	for i in 4: await process_frame
	game.contact_hub.contact_resolved.connect(on_contact)
	game.hud.menu.get_node("StartMatch").pressed.emit()
	for i in 24: await physics_frame
	check("normal6actors5AI enabled",game.players.size()==6 and game.agents.size()==5 and game.ai_enabled)
	check("actual shared actor scripts",("shared_last_result" in game.player) and game.agents.all(func(a):return "shared_last_result" in a))
	check("normal training assigned opening owner",game.ball.carrier==game.player and game.phase==game.Phase.PLAY)
	tick=Tick.new();tick.runner=self;tick.process_physics_priority=60;root.add_child(tick)
	set_keys(STAGES[0].keys)
func set_keys(wanted:Array)->void:
	for code in keys:
		if not wanted.has(code): key_event(code,false)
	for code in wanted:
		if not keys.has(code): key_event(code,true)
	keys=wanted.duplicate()
func key_event(code:int,pressed:bool)->void:
	var e:=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=pressed
	Input.parse_input_event(e);Input.flush_buffered_events()
func sample_tick()->void:
	if stage>=STAGES.size():return
	var foot=game.player.foot
	var snapshot:Dictionary=game.player.avatar.get_control_support_snapshot()
	var decision:Dictionary={}
	if "ordinary_scheduler" in foot:decision=foot.ordinary_scheduler.last_decision
	rows.append(pack({"frame":Engine.get_physics_frames(),"stage":STAGES[stage].name,"stage_tick":stage_tick,"phase":game.phase,"owned":game.ball.carrier==game.player,"kind":foot.kind,"foot_phase":foot.phase,"foot_elapsed":foot.elapsed,"sequence":foot.sequence,"side":foot.side,"surface":foot.surface,"hit":foot.hit,"plan":foot.touch_plan,"decision":decision,"support":snapshot,"actor":game.player.position,"actor_velocity":game.player.velocity,"ball":game.ball.position,"ball_velocity":game.ball.velocity,"gap":game.flat_distance(game.player.position,game.ball.position),"semantic_motion":game.player.semantic_motion,"repetitions":game.training_mode.repetitions}))
	stage_tick+=1
	if stage_tick>=int(STAGES[stage].ticks):
		stage+=1;stage_tick=0
		if stage>=STAGES.size():tick.set_physics_process(false);set_keys([]);call_deferred("finish")
		else:
			tick.set_physics_process(false)
			call_deferred("switch_stage")
func switch_stage()->void:
	set_keys([])
	if bool(STAGES[stage].get("defensive",false)):
		key_event(KEY_F6,true);key_event(KEY_F6,false)
		for i in 2:await physics_frame
	elif bool(STAGES[stage].get("reset",false)):
		# Use the game's real R entry, not direct transform/ownership writes.
		key_event(KEY_R,true);key_event(KEY_R,false)
		for i in 2:await physics_frame
	set_keys(STAGES[stage].keys)
	tick.set_physics_process(true)
func on_contact(event:Dictionary)->void:
	if event.get("kind","") not in ["FOOT_TOUCH","FOOT_ACTION_FAILED"]:return
	var f=event.actor.foot
	contacts.append(pack({"frame":Engine.get_physics_frames(),"stage":STAGES[mini(stage,STAGES.size()-1)].name,"human":event.actor.is_human,"actor_name":event.actor.name,"event":event,"action_elapsed":f.elapsed,"plan":f.touch_plan,"support":event.actor.avatar.get_control_support_snapshot()}))
func check(label:String,ok:bool)->void:
	checks.append({"check":label,"passed":ok});print("PASS " if ok else "FAIL ",label)
func pack(value:Variant)->Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Quaternion:return [value.x,value.y,value.z,value.w]
	if value is Node:return str(value.get_path())
	if value is Dictionary:
		var result:Dictionary={}
		for k in value:result[str(k)]=pack(value[k])
		return result
	if value is Array:
		var result:Array=[]
		for item in value:result.append(pack(item))
		return result
	return value
func finish()->void:
	check("all fixed real input stages sampled",rows.size()==1070)
	check("real ordinary human contact",contacts.any(func(e):return e.human and e.event.success and e.event.action in ["CLOSE","TURN","SHIELD"]))
	check("semantic low left andright inputs",rows.any(func(r):return r.stage=="low_inside_left" and (r.semantic_motion as Array)[0]<-.1) and rows.any(func(r):return r.stage=="low_cut_right" and (r.semantic_motion as Array)[0]>.1))
	var commits:Array=game.get_meta("cadence_commits",[])
	check("actual finite commits captured",not commits.is_empty())
	var identifiers:Dictionary={}
	var duplicated:=false
	var after_release:=false
	for c in commits:
		var id:String=str(c.actor)+":"+str(c.sequence)
		if identifiers.has(id):duplicated=true
		identifiers[id]=true
		if c.plan_state=="FREE_ROLL" or c.hit_before:after_release=true
	check("one ordinarycommit peractor action",not duplicated)
	check("no commit after FREE_ROLL",not after_release)
	DirAccess.make_dir_recursive_absolute(evidence)
	var result:Dictionary={"tag":tag,"seed":61906,"physics_hz":Engine.physics_ticks_per_second,"native":DisplayServer.get_name()!="headless","fixed_inputs":STAGES,"rows":rows,"contacts":contacts,"commits":pack(commits),"checks":checks,"passed":checks.all(func(c):return c.passed),"scope":"Normal AI-enabled sixactor3v3, real synthesized keys including identical explicit R between direction cases, no direct actor/ball/ownership writes; QA-only commit observer. No manualfeel/FPS claim."}
	FileAccess.open(evidence.path_join("CADENCE_FIXED_3V3.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t")+"\n")
	print("CADENCE_FIXED_DONE ",result.passed," rows=",rows.size()," commits=",commits.size())
	game.shutdown_audio();game.queue_free()
	for i in 4:await process_frame
	quit(0 if result.passed else 1)
