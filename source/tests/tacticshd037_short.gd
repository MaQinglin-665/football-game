extends SceneTree
var game:Node
var mode:="small"
var output:=""
var checks:Array=[]
var samples:Array=[]
func _initialize()->void:
 for a in OS.get_cmdline_user_args():
  if a.begins_with("--mode="):mode=a.trim_prefix("--mode=")
  if a.begins_with("--output="):output=a.trim_prefix("--output=")
 seed(3701);call_deferred("run")
func check(label:String,ok:bool)->void:
 checks.append({"check":label,"passed":ok});print("PASS " if ok else "FAIL ",label)
func key(code:int)->void:
 for pressed in [true,false]:
  var e:=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=pressed
  Input.parse_input_event(e);Input.flush_buffered_events()
func sample(label:String)->void:
 var actors:Array=[]
 for a in game.agents:
  actors.append({"id":game.players.find(a),"team":a.team,"position":str(a.position),"foot_kind":a.foot.kind,"foot_hit":a.foot.hit,"intent":a.tactical_intent.duplicate(true),"pace":a.tactical_pace})
 samples.append({"label":label,"frame":Engine.get_physics_frames(),"ball":str(game.ball.position),"owner":game.players.find(game.ball.carrier),"actors":actors,"defense":game.tactical_director.defense_debug_snapshot()})
func ticks(n:int)->void:
 for i in n:await physics_frame
func run()->void:
 var scene:String="res://scenes/training_3v3.tscn" if mode=="small" else "res://scenes/match.tscn"
 game=load(scene).instantiate();game.test_mode=true;root.add_child(game);current_scene=game
 for i in 8:await process_frame
 check("direct ultra startup shadow110m",game.render_quality=="ultra" and is_equal_approx(game.get_node("MatchSun").directional_shadow_max_distance,110.0))
 var cycle:Array=[]
 for i in 3:
  key(KEY_F2);await process_frame;cycle.append(game.render_quality)
 check("F2 ultra->fast->sharp->ultra",cycle==["fast","sharp","ultra"])
 # Headless settings checks only: no native resolution/GPU/FPS acceptance.
 game.hud.menu.get_node("StartMatch").pressed.emit()
 await ticks(8)
 if mode=="eleven":
  # Declared QA LIVE fixture, not acceptance of natural kickoff preparation.
  game.services.rules.restart.clear()
  game.services.rules._become_live()
  game.set_phase(game.Phase.PLAY)
  game.ball.set_held(false)
 check("real host LIVE",game.services.rules.state==game.Rules.State.LIVE)
 # One declared fixture, then real actors/World/rules without fixture writes.
 game.ball.reset(game.player.position+game.player.facing*.50);game.ball.take(game.player)
 if mode=="small":
  check("small six actors and eleven branch off",game.players.size()==6 and not game.tactical_director.eleven_duties)
  var roles:Array=[]
  for row in game.tactical_director.roster.values():
   if int(row.team)==0:roles.append(String(row.role))
  roles.sort()
  check("small AM CB striker roster",roles==["attacking_midfielder","center_back","striker"])
  await ticks(30);sample("initial_low")
  check_low("initial low live intents",samples[-1])
  key(KEY_F5);await ticks(30);sample("ordinary")
  check("F5 ordinary live intents restored",not game.training_mode.low_pressure and samples[-1].actors.any(func(a):return a.team==1 and not a.intent.has("training_pressure")))
  key(KEY_F5);await ticks(30);sample("low_again")
  check_low("F5 low live intents reapplied",samples[-1])
 else:
  check("explicit match22 roster11+11 duties on",game.scene_file_path==scene and game.players.size()==22 and game.tactical_director.eleven_duties and game.training_configuration==null)
  await ticks(60);sample("eleven_live")
  var duties:Dictionary={}
  for a in samples[-1].actors:
   if not a.intent.is_empty():duties[String(a.intent.get("duty",""))]=true
  check("live actor intents consume duty fields",["overlap","cover","hold","support","link","width","finish"].all(func(d):return duties.has(d)))
  check("live duty targets finite",game.agents.all(func(a):return a.target.is_finite() and a.tactical_intent.get("move_target",Vector3.ZERO).is_finite()))
 # Both checks observe actual planner slots in the live bridge, not copied unit planners.
 var tasks:Dictionary=game.tactical_director.defense_debug_snapshot().get("tasks",{})
 var presser:int=-1;var cover:int=-1;var pc:int=0;var cc:int=0
 for t in tasks.values():
  if int(t.team)!=1:continue
  if t.task=="PRESS":presser=int(t.owner);pc+=1
  if t.task=="COVER":cover=int(t.owner);cc+=1
 check("one live PRESS and distinct COVER",pc==1 and cc==1 and presser!=cover)
 if mode=="eleven" and cover>=0:
  var ct:Vector3=tasks[cover].target
  var goal:Vector3=Vector3(0,0,-game.field_half_length)
  check("eleven COVER goal-side target",(ct-game.ball.position).dot((goal-game.ball.position).normalized())>0)
 var passed:bool=checks.all(func(c):return c.passed)
 FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"mode":mode,"scene":scene,"checks":checks,"passed":passed,"samples":samples,"quality_cycle":cycle,"scope":"One declared initial possession fixture; eleven also declares LIVE bypassing kickoff preparation. Real bridge actor targets/intents and World. F5/live roles/PRESS-COVER and directultra shadow/F2 settings only. No natural kickoff/passrate/fullmatch/nativevisual/FPS/pressure-regression acceptance."},"\t"))
 game.shutdown_audio();game.queue_free()
 for i in 4:await process_frame
 quit(0 if passed else 1)
func check_low(label:String,s:Dictionary)->void:
 var yellow:Array=s.actors.filter(func(a):return a.team==1)
 check(label,game.training_mode.low_pressure and not yellow.is_empty() and yellow.all(func(a):return a.intent.get("training_pressure","")=="low" and a.pace<=2.6 and a.intent.get("action","")!="TACKLE"))
