extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
 var game=load("res://scenes/match.tscn").instantiate();root.add_child(game)
 await process_frame;await process_frame
 assert(game.players.size()==22)
 assert(game.services.rules.has_method("mark_phase"))
 var officials:Node
 for child in game.get_children():
  if child.get_script()==load("res://art/match_officials.gd"):officials=child
 assert(officials!=null and officials.assistants.size()==2 and officials.board_labels.size()==2)
 assert(not game.services.referee._placeholder.visible)
 for actor in officials.bodies:assert(actor.skeleton.get_bone_count()==32)
 game.services.rules.scores.assign([2,1]);game.services.rules.half=2;game.services.rules.half_elapsed=75.;officials.update_board()
 assert("2 : 1" in officials.board_text and "第2半场" in officials.board_text)
 game.services.rules._emit("assistant_flag",{"attack_sign":-1,"point":Vector3.ZERO})
 assert(officials.flag_age[0]>0.)
 var roster=game.offside_roster();assert(roster.size()==22)
 for actor in roster:assert(actor.offside_points.size()==4)
 game.start_match()
 for i in 360:await physics_frame
 for assistant in officials.assistants:assert(absf(assistant.position.x)>game.field_half_width)
 # Exercise the actual host -> services -> rules -> ball hold and assistant event chain.
 var rows:Array[Dictionary]=[{"id":1,"team":0,"position":Vector3(0,0,-10),"active":true},{"id":2,"team":0,"position":Vector3(0,0,-35),"active":true},{"id":3,"team":1,"position":Vector3(0,0,-40),"active":true,"goalkeeper":true},{"id":4,"team":1,"position":Vector3(0,0,-30),"active":true}]
 var rules=game.services.rules;rules.live_roster_provider=func()->Array[Dictionary]:return rows
 rules.state=rules.State.LIVE;rules._restart_origin.clear();rules._second_touch_actor=-1
 assert(game.services.report_ball_contact({"event_id":"scene-pass","actor_id":1,"team":0,"position":Vector3(0,.11,-10),"kind":"pass"}))
 assert(not game.services.report_ball_contact({"event_id":"scene-receive","actor_id":2,"team":0,"position":Vector3(0,.11,-35),"kind":"receive"}))
 assert(rules.restart.reason=="offside" and game.ball.held and officials.flag_age[0]>0.)
 rules.live_roster_provider=Callable()
 print("OFFICIALS_SCENE_PASS 22 players, 3 faceless officials, 2 scoreboards, flag event, eligible body samples, 360 physics frames")
 game.shutdown_audio();game.queue_free();await process_frame;quit()
