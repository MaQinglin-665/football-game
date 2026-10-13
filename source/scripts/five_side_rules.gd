extends "res://addons/football_match_services/rules/rules_engine.gd"
# Local 5v5 house rule: all non-goal end-line exits restart as defending goal kicks.
func _queue_restart(kind:String,team:int,at:Vector3,reason:String,immediate:bool=false,side_override:int=0)->void:
 if reason=="goal_line" or kind=="corner":
  side_override=side_override if side_override!=0 else (1 if at.z>=0 else -1)
  kind="goal_kick"
  team=defending_team(side_override)
 elif reason=="touchline" and kind=="dropped_ball":
  kind="throw_in"
 super._queue_restart(kind,team,at,reason,immediate,side_override)
