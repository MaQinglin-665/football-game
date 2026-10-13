extends SceneTree
var failures:int=0
func check(label:String,ok:bool)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:
	var d=preload("res://scripts/tactics/tactical_director.gd").new()
	d.configure([{"id":1,"team":0,"role":d.Roles.WINGER,"duty":"width"}])
	var p:Dictionary={"id":1,"team":0,"position":Vector3.ZERO,"velocity":Vector3.FORWARD*3,"facing":Vector3.FORWARD,"stamina":100,"cut_ready":false}
	var s:Dictionary={"field_half_width":34.0,"field_half_length":52.5,"ball_velocity":Vector3.FORWARD*3,"ball_position":Vector3(0,.11,-.4)}
	var opponents:Array[Dictionary]=[{"position":Vector3(0,0,-1.6),"velocity":Vector3.BACK*2}]
	var carry:Dictionary=d._open_carry_option(p,opponents,s)
	var gear:Dictionary={"close_control":false,"shield":false,"pace":4.8}
	d._apply_carry_gear(p,gear,carry,opponents,s)
	check("late frontal collision is not called a safe sprint route",carry.is_empty() or absf(carry.point.x)>.5)
	check("cooldown cannot reserve an unavailable cut",not gear.get("carry_cut",false))
	p.cut_ready=true
	d._apply_carry_gear(p,gear,carry,opponents,s)
	check("available foot cannot manufacture an already blocked exit",not gear.get("carry_cut",false))
	if d.carry_routes.has(1):d.carry_routes[1].cut_attempted=true
	d._apply_carry_gear(p,gear,carry,opponents,s)
	check("one route does not reopen its completed cut",not gear.get("carry_cut",false))
	var trailing:Array[Dictionary]=[{"position":Vector3(0,0,1.6),"velocity":Vector3.FORWARD*3}]
	d.carry_routes.clear();carry=d._open_carry_option(p,trailing,s)
	d._apply_carry_gear(p,gear,carry,trailing,s)
	check("near trailing opponent does not force close-control walking",gear.carry_run)
	var slow_ball:Dictionary=s.duplicate();slow_ball.ball_velocity=Vector3.FORWARD*1.5;slow_ball.ball_position=Vector3(.8,.11,.1)
	check("confirmed cut does not authorize sprint past a slow lateral ball",not d._running_touch_reachable(p,Vector3.FORWARD,5.0,slow_ball))
	var edge_player:Dictionary=p.duplicate();edge_player.position=Vector3(29,0,0);edge_player.velocity=Vector3.RIGHT*5
	var edge_scene:Dictionary=s.duplicate();edge_scene.ball_position=Vector3(29.5,.11,0);edge_scene.ball_velocity=Vector3.RIGHT*5
	var edge_intent:Dictionary={"action":"NONE","role":d.Roles.WINGER,"move_target":Vector3(33,0,-4),"pace":5.0,"carry_cut":true}
	d._guard_carry_boundary(edge_player,edge_intent,edge_scene)
	check("edge route budgets the next touch before crossing and cancels unsafe cut",edge_intent.get("reason","")=="keep_ball_inside_before_line" and not edge_intent.carry_cut and edge_intent.move_target.x<edge_player.position.x)
	var owner:Dictionary={"facing":Vector3.FORWARD,"position":Vector3.ZERO,"can_pass":true,"ball_offset":Vector3(.24,.11,-.35),"ball_relative_speed":1,"foot_idle":true}
	check("reachable side-foot pass does not wait for body rotation",d.team_attack._setup(owner,Vector3(6,0,0))<.3)
	owner.ball_offset=Vector3(.15,.11,.15)
	check("near short heel return has a compact preparation",d.team_attack._setup(owner,Vector3(0,0,3))<.3)
	check("long backward pass still requires a full strike setup",d.team_attack._setup(owner,Vector3(0,0,20))>.5)
	var receive=preload("res://scripts/tactics/receive_plan.gd").new()
	receive.configure({0:{"team":0},1:{"team":0},2:{"team":1}})
	receive.consume_contact({"kind":"FOOT_TOUCH","success":true,"action":"PASS","actor_id":0,"receiver_id":1,"serial":1,"ball_position":Vector3(0,.11,0),"after_velocity":Vector3(0,6,-8)},0)
	receive.consume_contact({"kind":"FOOT_TOUCH","success":true,"action":"RECEIVE","actor_id":1,"carrier_id":1,"serial":2,"ball_position":Vector3(0,.25,-8),"after_velocity":Vector3(0,5,-4)},1)
	check("rebounding first touch retains reception responsibility",not receive.active.is_empty() and receive.active.get("unsettled_contact",false))
	receive.consume_contact({"kind":"FOOT_TOUCH","success":true,"action":"RECEIVE","actor_id":1,"carrier_id":1,"serial":3,"ball_position":Vector3(0,.15,-8),"after_velocity":Vector3(0,.1,-3)},1.4)
	check("later controlled rolling touch completes reception",receive.active.is_empty() and receive.last_plan.state=="COMPLETED")
	check("final pass-versus-carry uses anti-repetition adjustment",d._pass_value({"score":2.0,"utility":8.0},{},s)==2.0)
	var attack=d.team_attack
	var stationary:Dictionary={"position":Vector3.ZERO,"velocity":Vector3.ZERO,"facing":Vector3.FORWARD}
	var retreating:Dictionary=stationary.duplicate();retreating.velocity=Vector3.BACK*5
	check("arrival estimate charges actual reverse braking",attack.eta(retreating,Vector3.FORWARD*8)>attack.eta(stationary,Vector3.FORWARD*8)+.5)
	retreating.brake_deceleration=10.5
	check("arrival estimate uses the supplied effective motor brake",attack.eta(retreating,Vector3.FORWARD*8)<attack.eta(stationary,Vector3.FORWARD*8)+.6)
	var offside_snapshot:Dictionary={"ball_position":Vector3(0,.11,-15)}
	var defenders:Array[Dictionary]=[{"position":Vector3(0,0,-25)},{"position":Vector3(0,0,-20)}]
	check("wall-return risk check works before the shared offside cache exists",not d._onside_receiver({"team":0,"position":Vector3(0,0,-22)},defenders,offside_snapshot))
	attack.plans[0]={"id":1,"team":0,"mode":"ONE_TWO","stage":"FLIGHT","owner":1,"runner":1,"delivery":{"receiver":2},"assignments":{}}
	attack.confirm_pass(0,2,1,3.0)
	check("real first-time return advances without fictional control",attack.plans[0].stage=="RETURN_FLIGHT" and attack.plans[0].owner==2 and attack.events[-1].event=="KICK")
	attack.confirm_pass(0,2,3,3.1)
	check("different actual pass releases the obsolete common plan",not attack.plans.has(0))
	var bounce_snapshot:Dictionary={"ball_position":Vector3(0,6,0),"ball_velocity":Vector3(10,-6,0),"field_half_width":34.0,"field_half_length":52.5,"capabilities":{},"roll_samples":[]}
	for i in 30:bounce_snapshot.roll_samples.append({"point":Vector3(12,.12,0),"speed":8.0,"velocity":Vector3(4,5,0),"time":1.0+i*.1})
	var meet:Dictionary=receive._intercept({"id":1,"position":Vector3(12,0,-.38),"facing":Vector3.BACK,"velocity":Vector3.ZERO},bounce_snapshot)
	check("unsettled landing keeps destination instead of chasing airborne origin",meet.reachable and meet.ball_point.x>11.0)
	quit(0 if failures==0 else 1)
