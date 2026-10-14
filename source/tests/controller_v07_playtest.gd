extends "res://tests/integration_checks.gd"
var mode:="training_3v3"
var output_folder:=""
var rows:Array=[]
var label:=""
var previous_velocity:=Vector3.ZERO
func sample()->void:
 var p=game.player
 var flat:=Vector3(p.velocity.x,0,p.velocity.z)
 rows.append({"case":label,"position":[p.position.x,p.position.y,p.position.z],"velocity":[flat.x,flat.y,flat.z],"speed":flat.length(),"facing":[p.body_facing.x,0,p.body_facing.z],"stamina":p.stamina,"sprint":p.sprinting,"locomotion":p.locomotion,"phase":game.phase,"bank":p.avatar.get_full_body_debug().get("locomotion039",{}),"dt":1.0/Engine.physics_ticks_per_second})
func reset_case(name:String,initial:Vector3=Vector3.ZERO)->void:
 key(KEY_W,false);key(KEY_S,false);key(KEY_D,false);key(KEY_SHIFT,false)
 game.input_bridge.shift_input.router.reset("controller_fixture")
 game.player.foot.cancel("controller_fixture");game.player.position=Vector3(0,.002,5);game.player.reset_view(0)
 game.player.velocity=initial;game.player.stamina=100;game.player.sprint_locked=false
 game.ball.clear_control();game.ball.reset(Vector3(7,.11,7));game.ball.set_held(true)
 label=name
 game.services.rules.state=game.Rules.State.LIVE;game._sync_rule_phase()
 game.input_bridge.sync_context()
 await ticks(2)
func observe(count:int,capture_tag:String="")->void:
 for i in count:
  await physics_frame
  sample()
  if native and i==count/2 and capture_tag!="":await capture(capture_tag)
func run()->void:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--scene="):mode=arg.trim_prefix("--scene=")
  if arg.begins_with("--folder="):output_folder=arg.trim_prefix("--folder=")
 if output_folder=="":output_folder=ProjectSettings.globalize_path("res://../verification/v07_"+mode)
 DirAccess.make_dir_recursive_absolute(output_folder);evidence=output_folder
 seed(391014)
 game=load("res://scenes/"+mode+".tscn").instantiate();game.test_mode=true;root.add_child(game);current_scene=game
 await ticks(8)
 game.start_match(false);await ticks(4)
 game.services.rules.state=game.Rules.State.LIVE;game._sync_rule_phase()
 game.tactics_bridge.set_physics_process(false)
 for p in game.players:
  if p!=game.player:p.set_physics_process(false);p.foot.cancel("fixture");p.position=Vector3(25+p.team*2,.002,20+p.jersey*.1);p.velocity=Vector3.ZERO;p.set_move_intent(Vector3.ZERO)
 if native:
  root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1280,720)
  await ticks(120)
 await reset_case("start")
 key(KEY_W,true);await observe(120,"jog")
 var start_rows:=rows.filter(func(r):return r.case=="start")
 check("actual W input reaches running pace",float(start_rows[-1].speed)>(4.9 if game.player.get("controller_v07_enabled")==true else 3.1), start_rows[-1].speed)
 await reset_case("stop",Vector3.FORWARD*8)
 await observe(120,"braking")
 var stop_rows:=rows.filter(func(r):return r.case=="stop")
 check("actual collision motor stops",float(stop_rows[-1].speed)<.05,stop_rows[-1].speed)
 await reset_case("turn90",Vector3.FORWARD*8)
 key(KEY_D,true);await observe(90,"turn90")
 await reset_case("reverse",Vector3.FORWARD*8)
 key(KEY_S,true);await observe(150,"reverse")
 await reset_case("turn180",Vector3.FORWARD*8)
 game.player.head.mouse_axis=Vector2(-PI/game.player.head.mouse_sensitivity,0)
 game.player.head.camera_rotation()
 key(KEY_W,true);await observe(180,"turn180")
 await reset_case("sprint_turn90",Vector3.FORWARD*8)
 key(KEY_D,true);key(KEY_SHIFT,true);await ticks(1);key(KEY_SHIFT,false)
 await observe(120,"sprint_turn90")
 await reset_case("sprint")
 key(KEY_W,true);key(KEY_SHIFT,true);await ticks(1);key(KEY_SHIFT,false)
 await observe(180,"sprint")
 key(KEY_W,false)
 await observe(100,"sprint_stop")
 FileAccess.open(output_folder+"/motion.json",FileAccess.WRITE).store_string(JSON.stringify({"mode":mode,"native":native,"rows":rows,"checks":checks,"scope":"Actual keyboard input and swept movement; isolated fixture. Native captures when enabled, not human feel acceptance or natural AI evidence."}))
 if native:await create_timer(2.0).timeout
 game.shutdown_audio();game.queue_free()
 for i in 8:await process_frame
 quit(1 if checks.any(func(r):return not r.passed) else 0)
