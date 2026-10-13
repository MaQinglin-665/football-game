extends Node3D
# Officials have no collision bodies. Rules own decisions; these actors report/present them.
var game:Node
var assistants:Array[Node3D]=[]
var bodies:Array[Node3D]=[]
var flags:Array[Node3D]=[]
var flag_age:Array[float]=[0.,0.]
var board_labels:Array[Label3D]=[]
var main_body:Node3D
var clock:float=0.
var board_age:float=0.
var main_previous=Vector3.ZERO
var board_text:String=""
func _ready()->void:
 process_priority=100
 call_deferred("build")
func body(parent:Node3D)->Node3D:
 var n=preload("res://art/official_body.gd").new();parent.add_child(n);n.build(Color("e5ce39"),0,false);return n
func build()->void:
 if is_instance_valid(game.services.referee):
  main_body=body(game.services.referee);game.services.referee.bind_avatar(main_body);main_previous=game.services.referee.global_position
 for i in 2:
  var official=Node3D.new();official.name="AssistantReferee%d"%i;add_child(official);assistants.append(official);bodies.append(body(official))
  official.position=Vector3((1 if i==0 else -1)*(game.field_half_width+1.2),0,0)
  var sk:Skeleton3D=bodies[i].skeleton
  var attachment=BoneAttachment3D.new();attachment.bone_name="hand.R";sk.add_child(attachment)
  var flag=Node3D.new();attachment.add_child(flag);flags.append(flag)
  var rod=CylinderMesh.new();rod.top_radius=.012;rod.bottom_radius=.012;rod.height=.45
  var shaft=MeshInstance3D.new();shaft.mesh=rod;shaft.position.y=-.20;flag.add_child(shaft)
  var stick=StandardMaterial3D.new();stick.albedo_color=Color("30343a");shaft.material_override=stick
  for x in 2:
   for y in 2:
    var patch=MeshInstance3D.new();var mesh=BoxMesh.new();mesh.size=Vector3(.15,.13,.004);patch.mesh=mesh
    patch.position=Vector3(.08+x*.15,-.27-y*.13,0);var mat=StandardMaterial3D.new();mat.albedo_color=Color("ffc928") if (x+y)%2==0 else Color("f16924");mat.roughness=.9;patch.material_override=mat;flag.add_child(patch)
 game.services.rules_event.connect(observe)
 for side in [-1.,1.]:make_board(Vector3(0,14,side*(game.field_half_length+8.)),side)
 update_board()
func make_board(at:Vector3,side:float)->void:
 var board=Node3D.new();board.position=at;board.rotation.y=PI if side>0 else 0.;add_child(board)
 var frame=MeshInstance3D.new();var mesh=BoxMesh.new();mesh.size=Vector3(12.,3.6,.32);frame.mesh=mesh;board.add_child(frame)
 var mat=StandardMaterial3D.new();mat.albedo_color=Color("101c28");mat.roughness=.65;frame.material_override=mat
 for x in [-4.,4.]:
  var support=MeshInstance3D.new();var column=BoxMesh.new();column.size=Vector3(.24,at.y,.30);support.mesh=column;support.position=Vector3(x,-at.y*.5,.40);support.material_override=mat;board.add_child(support)
 var label=Label3D.new();label.position.z=.18;label.rotation.y=0.;label.font_size=96;label.pixel_size=.013;label.outline_size=2;label.no_depth_test=false;board.add_child(label);board_labels.append(label)
 var font=SystemFont.new();font.font_names=PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei","Arial"]);label.font=font
func update_board()->void:
 var rules=game.services.rules
 var seconds:int=maxi(0,int(rules.config.half_seconds-rules.half_elapsed))
 board_text="蓝队   %d : %d   红队\n第%d半场   %02d:%02d"%[rules.scores[0],rules.scores[1],rules.half,seconds/60,seconds%60]
 for label in board_labels:
  if label.text!=board_text:label.text=board_text
func observe(event:Dictionary)->void:
 if event.get("type","")=="assistant_flag":
  var index=0 if int(event.get("attack_sign",-1))<0 else 1
  flag_age[index]=3.5
 elif event.get("type","")=="restart_awarded" and event.restart.kind in ["throw_in","goal_kick","corner"]:
  flag_age[0 if event.restart.point.x>0 else 1]=2.5
func _process(delta:float)->void:
 if assistants.size()!=2:return
 # Menu/pause freezes official movement too.
 if game.phase in [game.Phase.MENU,game.Phase.PAUSED]:
  for actor in bodies:actor.player.pause()
  if is_instance_valid(main_body):main_body.player.pause()
  return
 clock+=delta;board_age+=delta
 if board_age>.25:board_age=0.;update_board()
 var roster=game.rule_roster()
 for i in 2:
  var sign_z=-1 if i==0 else 1;var defenders:Array[float]=[]
  var attacking_team=0 if game.services.rules.attack_signs[0]==sign_z else 1
  for actor in roster:
   if actor.team!=attacking_team:defenders.append(actor.position.z*sign_z)
  defenders.sort()
  var depth:float=maxf(game.ball.position.z*sign_z,defenders[-2]) if defenders.size()>1 else 0.
  var target=Vector3((1 if i==0 else -1)*(game.field_half_width+1.2),0,clampf(depth,0,game.field_half_length)*sign_z)
  var old:Vector3=assistants[i].position
  if flag_age[i]<=0.:assistants[i].position=old.move_toward(target,7.*delta)
  var toward:Vector3=game.ball.position-assistants[i].position;toward.y=0
  if toward.length()>.1:assistants[i].rotation.y=lerp_angle(assistants[i].rotation.y,atan2(-toward.x,-toward.z),minf(8.*delta,1.))
  bodies[i].animate_official(assistants[i].position.distance_to(old)/maxf(delta,.001),"offside",flag_age[i],clock)
  flag_age[i]=maxf(0.,flag_age[i]-delta)
 if is_instance_valid(main_body):
  var ref=game.services.referee;var speed=ref.global_position.distance_to(main_previous)/maxf(delta,.001);main_previous=ref.global_position
  ref._target.x=clampf(ref._target.x,-game.field_half_width+1.,game.field_half_width-1.)
  ref._target.z=clampf(ref._target.z,-game.field_half_length+1.,game.field_half_length-1.)
  var rules=game.services.rules
  if rules._restart_origin.get("kind","")=="indirect_free_kick" or (rules.restart.get("kind","")=="indirect_free_kick" and rules.state in [rules.State.STOPPAGE,rules.State.RESTART_SETUP,rules.State.RESTART_READY]):
   ref.current_gesture="indirect_free_kick";ref._gesture_age=.3
  main_body.animate_official(speed,ref.current_gesture,ref._gesture_age,clock)
