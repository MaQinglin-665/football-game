extends SceneTree
var game:Node
func _initialize()->void:call_deferred("run")
func run()->void:
 game=load("res://scenes/match_5v5.tscn").instantiate();root.add_child(game)
 await process_frame
 game.settings_menu.values.volume=0;game.settings_menu.apply_values(false)
 assert(game.players.size()==10)
 assert(game.agents.size()==9)
 assert(game.team_size==5)
 assert(game.field_half_width==12 and game.field_half_length==18)
 for team in [0,1]:
  var count:int=0;var keepers:int=0
  for actor in game.players:
   if actor.team==team:
    count+=1
    if actor.is_goalkeeper:keepers+=1
  assert(count==5 and keepers==1)
 # Exercise actual swept-boundary classification for both last-touch teams.
 for touched in [0,1]:
  for side in [-1,1]:
   var rules=preload("res://scripts/five_side_rules.gd").new(game.services.configuration)
   rules.last_touch={"team":touched}
   assert(rules._check_crossing({"previous_position":Vector3(0,.3,0),"position":Vector3(side*13,.3,3)}))
   assert(rules.restart.kind=="throw_in" and rules.restart.team==1-touched)
   rules=preload("res://scripts/five_side_rules.gd").new(game.services.configuration)
   rules.last_touch={"team":touched}
   assert(rules._check_crossing({"previous_position":Vector3(4,.3,0),"position":Vector3(4,.3,side*19)}))
   assert(rules.restart.kind=="goal_kick" and rules.restart.team==rules.defending_team(side))
 var goal_rules=preload("res://scripts/five_side_rules.gd").new(game.services.configuration)
 goal_rules.last_touch={"team":0}
 assert(goal_rules._check_crossing({"previous_position":Vector3(0,.3,0),"position":Vector3(0,.3,-19)}))
 assert(goal_rules.scores[0]+goal_rules.scores[1]==1)
 print("FIVE_BOUNDARIES passed 8 exits and normal goal")
 game.start_match()
 for i in 900:
  if game.is_restart_taker(game.player):
   var event:=InputEventKey.new();event.physical_keycode=KEY_Q;event.pressed=(i%30<15);Input.parse_input_event(event)
   game.input_bridge.focused=true
  await physics_frame
 print("FIVE_CHECK players=",game.players.size()," keepers=2 pitch=36x24 phase=",game.phase," ball=",game.ball.position)
 assert(game.phase==game.Phase.PLAY)
 if DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../evidence/5v5/native.png"))
 game.shutdown_audio();quit()
