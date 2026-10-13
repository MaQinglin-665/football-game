extends SceneTree
const Scheduler=preload("res://scripts/ordinary_touch_scheduler.gd")
class Avatar:
	extends Node3D
	var right_unreachable:=false
	var phases:Dictionary={"L":{"state":"PLANTED","sole_near_ground":true,"leg_margin_m":.02},"R":{"state":"PLANTED","sole_near_ground":true,"leg_margin_m":.02}}
	func side_suffix(side:int)->String:return "L" if side<0 else "R"
	func get_control_support_snapshot()->Dictionary:return {"support_phase":phases,"pose_tick":19}
	func get_foot_contact(side:int,_surface:String)->Dictionary:
		return {"point":Vector3(2.0 if side>0 and right_unreachable else .10*side,.11,-.28),"valid":true}
class Actor:
	extends Node3D
	var velocity:=Vector3.ZERO
	var sprinting:=false
	var body_facing:=Vector3.FORWARD
	var team:=0
	var is_human:=true
	var avatar:Avatar
	var match_controller:Node
class Tuning:
	extends RefCounted
	var foot_reach:=.96
class Ball:
	extends Node3D
	var velocity:=Vector3.ZERO
	var radius:=.11
	var tuning:=Tuning.new()
class Game:
	extends Node
	var players:Array=[]
var checks:Array=[]
var evidence:=""
func _initialize()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="):evidence=arg.trim_prefix("--evidence=")
	call_deferred("run")
func check(label:String,ok:bool)->void:
	checks.append({"check":label,"passed":ok});print("PASS " if ok else "FAIL ",label)
func run()->void:
	var actor:=Actor.new();var avatar:=Avatar.new();var ball:=Ball.new();var game:=Game.new()
	actor.avatar=avatar;actor.match_controller=game;game.players=[actor]
	root.add_child(game);root.add_child(actor);root.add_child(avatar);root.add_child(ball)
	ball.position=Vector3(-.26,.11,-.28)
	var scheduler=Scheduler.new()
	var chosen:Dictionary=scheduler.consider(actor,ball,Vector3.LEFT,"TURN",true)
	if scheduler.dominant_control_enabled:
		check("right dominant left near control chooses right inside",chosen.ready and chosen.side==1 and chosen.surface=="INSIDE")
		avatar.right_unreachable=true
		chosen=scheduler.consider(actor,ball,Vector3.LEFT,"TURN",true)
		check("unreachable dominant foot immediate reachable fallback",chosen.ready and chosen.side==-1 and chosen.surface=="OUTSIDE")
		avatar.right_unreachable=false
		var opponent:=Actor.new();opponent.team=1;opponent.position=ball.position+Vector3.RIGHT*.20;root.add_child(opponent);game.players.append(opponent)
		chosen=scheduler.consider(actor,ball,Vector3.LEFT,"TURN",true)
		check("exposed dominant side under close pressure fallback",chosen.ready and chosen.side==-1)
		game.players.erase(opponent);opponent.queue_free()
		actor.set_meta("dominant_foot_side",-1);ball.position.x=.26
		chosen=scheduler.consider(actor,ball,Vector3.RIGHT,"TURN",true)
		check("explicit left dominant mirrors inside intent",chosen.ready and chosen.side==-1 and chosen.surface=="INSIDE")
		actor.set_meta("dominant_foot_side",1);ball.position.x=-.26
		avatar.phases.L={"state":"SWING","sole_near_ground":false,"leg_margin_m":.02}
		chosen=scheduler.consider(actor,ball,Vector3.LEFT,"TURN",true)
		check("support step preparation supplies no early contact",not chosen.ready and chosen.position_first and chosen.reason=="position_for_dominant_inside")
		actor.sprinting=true
		chosen=scheduler.consider(actor,ball,Vector3.LEFT,"TURN",true)
		check("sprint branch retained",chosen.ready and not chosen.cadence_managed)
		actor.sprinting=false;actor.is_human=false
		avatar.phases.L={"state":"PLANTED","sole_near_ground":true,"leg_margin_m":.02}
		chosen=scheduler.consider(actor,ball,Vector3.LEFT,"TURN",true)
		check("AI selection retains released geometry policy",chosen.ready and chosen.side==-1 and chosen.intent=="DIRECTIONAL_CONTROL")
	else:
		check("explicit control A restores geometry left outside",chosen.ready and chosen.side==-1 and chosen.surface=="OUTSIDE" and chosen.intent=="DIRECTIONAL_CONTROL")
		var real=load("res://scenes/training_3v3.tscn").instantiate();real.test_mode=true;root.add_child(real)
		for i in 4:await process_frame
		real.hud.menu.get_node("StartMatch").pressed.emit()
		for i in 24:await physics_frame
		key(KEY_R,true);key(KEY_R,false)
		for i in 3:await physics_frame
		real.player.foot.cancel();real.ball.position=real.player.position+Vector3(-.26,.111,-.28);real.ball.velocity=Vector3.ZERO;real.ball.spin_rads=Vector3.ZERO;real.ball.touch_timer=0.0
		key(KEY_CTRL,true);key(KEY_A,true)
		var touched:=false;var actual_side:=0;var actual_surface:=""
		for i in 60:
			await physics_frame
			if real.player.foot.hit and real.player.foot.kind=="TURN":
				touched=true;actual_side=real.player.foot.side;actual_surface=real.player.foot.surface;break
		key(KEY_A,false);key(KEY_CTRL,false)
		check("control A real original left outside contact",touched and actual_side==-1 and actual_surface=="OUTSIDE")
		check("control A preserves F7 B turf",real.physics_profile.low_speed_roll_extra_mps2==.75)
		var body_phase:Dictionary=real.player.foot.ordinary_scheduler.body_control_snapshot(real.player)
		check("readonly body phase supplies actual shoe and support",body_phase.surface==actual_surface and body_phase.touch_side==actual_side and body_phase.has("support_knee_flexion_deg") and not body_phase.active)
		real.shutdown_audio();real.queue_free()
	game.queue_free();actor.queue_free();avatar.queue_free();ball.queue_free()
	for i in 4:await process_frame
	DirAccess.make_dir_recursive_absolute(evidence)
	FileAccess.open(evidence.path_join("CONTRACT.json"),FileAccess.WRITE).store_string(JSON.stringify({"enabled":scheduler.dominant_control_enabled,"checks":checks,"passed":checks.all(func(c):return c.passed)},"\t"))
	quit(0 if checks.all(func(c):return c.passed) else 1)
func key(code:int,pressed:bool)->void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed
	Input.parse_input_event(event);Input.flush_buffered_events()
