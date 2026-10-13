extends RefCounted
# Actor IDs and jerseys remain stable; selection swaps formation-slot occupants only.
const LABELS={"CB":"中后卫","GK":"门将","LB":"左后卫","LCB":"左中卫","RCB":"右中卫","RB":"右后卫","DM":"后腰","LCM":"左中场","RCM":"右中场","LW":"左边锋","CF":"中锋","RW":"右边锋","LF":"左前","BACK":"后场","RF":"右前"}
static func initialize(game:Node)->void:
 for row in game.roster_configuration:row.jersey=game.players[int(row.id)].jersey
static func human_row(game:Node)->Dictionary:
 for row in game.roster_configuration:
  if int(row.id)==0:return row
 return {}
static func caption(game:Node)->String:
 var row:Dictionary=human_row(game)
 return "蓝队 #%d · %s" % [game.player.jersey,LABELS.get(row.get("slot",""),row.get("slot",""))]
static func choose(game:Node,slot:String)->bool:
 if game.phase!=game.Phase.MENU:return false
 var previous:Dictionary=human_row(game);var selected:Dictionary={}
 for row in game.roster_configuration:
  if int(row.team)==0 and row.get("slot","")==slot and not row.is_goalkeeper:selected=row;break
 if selected.is_empty():return false
 if selected==previous:return true
 var other:int=int(selected.id)
 selected.id=0;selected.human=true;previous.id=other;previous.human=false
 for row in [selected,previous]:
  var actor:Node=game.players[int(row.id)]
  row.jersey=actor.jersey
  actor.role=row.role;actor.lane=row.lane
  actor.avatar.setup(actor.team,actor.jersey,actor.is_human)
  actor.foot.cancel("roster_selection")
  actor.avatar.invalidate_pose_snapshot()
  if not actor.is_human:actor.pending_kick.clear()
 game.tactical_director.configure(game.roster_configuration,{0:game.Director.SHORT_PASS,1:game.Director.SHORT_PASS})
 game.tactical_contact_adapter.reset()
 game.show_menu()
 game.sync_input_context()
 return true
static func menu(hud:Node)->void:
 var game:Node=hud.match_controller
 var caption:=Label.new();caption.position=Vector2(33,187);caption.size=Vector2(426,58);caption.add_theme_font_size_override("font_size",17);hud.menu.add_child(caption)
 var chart=load("res://scripts/formation_picker.gd").new();chart.name="FormationPicker";chart.game=game;chart.caption=caption;chart.position=Vector2(512,0);hud.menu.add_child(chart)
