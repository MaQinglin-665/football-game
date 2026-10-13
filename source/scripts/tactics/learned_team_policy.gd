extends RefCounted
# Small CPU policy: strategic preferences only. Existing legal actions and contact
# code remain authoritative. No player input, pose, speed or ball writes here.
const INPUTS=30
const HIDDEN=24
const ACTIONS=7
const GAMMA=.995
var models:Dictionary={}
var states:Dictionary={}
var traces:Dictionary={0:[],1:[]}
var rng:=RandomNumberGenerator.new()
var training:bool=false
var enabled:bool=false
var time:float=0
var latest:Dictionary={}
var decision_counts:Dictionary={0:[0,0,0,0,0,0,0],1:[0,0,0,0,0,0,0]}

func _init()->void:
	rng.randomize()
	var path:String=""
	var side:int=-1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--policy="):path=arg.trim_prefix("--policy=")
		if arg.begins_with("--learn-team="):side=int(arg.trim_prefix("--learn-team="))
	if not path.is_empty():
		for team in [0,1]:
			if side<0 or side==team:load_model(team,path)

func load_model(team:int,path:String)->bool:
	if not FileAccess.file_exists(path):return false
	var data=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or data.get("schema","") not in ["football_team_ppo_v1","football_role_ppo_v2"]:return false
	var input_count:int=16 if data.get("schema","")=="football_team_ppo_v1" else INPUTS
	for spec in [["w1",HIDDEN,input_count],["w2",ACTIONS,HIDDEN]]:
		var matrix=data.get(spec[0],[])
		if not matrix is Array or matrix.size()!=spec[1]:return false
		for row in matrix:
			if not row is Array or row.size()!=spec[2]:return false
			for v in row:
				if not (v is float or v is int) or not is_finite(float(v)):return false
	for spec in [["b1",HIDDEN],["b2",ACTIONS]]:
		var row=data.get(spec[0],[])
		if not row is Array or row.size()!=spec[1]:return false
		for v in row:
			if not (v is float or v is int) or not is_finite(float(v)):return false
	models[team]=data;enabled=true
	return true

func reset()->void:
	# A restart cancels strategic commitment, but does not discard training credit.
	for team in states:states[team].until=-1.0

func features(snapshot:Dictionary,team:int)->Array:
	var attack:float=-1.0 if team==0 else 1.0
	var width:float=maxf(1,float(snapshot.get("field_half_width",34)))
	var length:float=maxf(1,float(snapshot.get("field_half_length",52.5)))
	var ball:Vector3=snapshot.get("ball_position",Vector3.ZERO)
	var vel:Vector3=snapshot.get("ball_velocity",Vector3.ZERO)
	var owner:Dictionary={}
	var own_near:float=30;var opp_near:float=30
	var own_depth:float=0;var opp_depth:float=0
	var own_wide:float=0;var opp_wide:float=0
	var own_count:float=0;var opp_count:float=0
	for p in snapshot.get("players",[]):
		if not p.get("active",true):continue
		if int(p.id)==int(snapshot.get("carrier_id",-1)):owner=p
		var pos:Vector3=p.position
		var distance:float=Vector2(pos.x-ball.x,pos.z-ball.z).length()
		if int(p.team)==team:
			own_near=minf(own_near,distance);own_depth+=pos.z*attack/length;own_wide+=absf(pos.x)/width;own_count+=1
		else:
			opp_near=minf(opp_near,distance);opp_depth+=pos.z*attack/length;opp_wide+=absf(pos.x)/width;opp_count+=1
	var ours:bool=not owner.is_empty() and int(owner.team)==team
	var theirs:bool=not owner.is_empty() and int(owner.team)!=team
	var speed:float=Vector3(owner.get("velocity",Vector3.ZERO)).length()/6.0
	var values:Array=[ball.x/width,ball.z*attack/length,ball.y/5.0,vel.x/20.0,vel.z*attack/20.0,vel.y/15.0,1.0 if ours else 0.0,1.0 if theirs else 0.0,own_near/20.0,opp_near/20.0,own_depth/maxf(1,own_count),opp_depth/maxf(1,opp_count),own_wide/maxf(1,own_count),opp_wide/maxf(1,opp_count),speed,own_count/11.0]
	for i in range(values.size()):values[i]=clampf(float(values[i]),-2,2)
	values.append_array(role_features(snapshot,team))
	return values

func probabilities(obs:Array,model:Dictionary)->Array:
	var hidden:Array=[]
	for i in range(HIDDEN):
		var value:float=float(model.b1[i])
		for j in range(model.w1[i].size()):value+=float(model.w1[i][j])*float(obs[j])
		hidden.append(tanh(value))
	var logits:Array=[]
	var maximum:float=-INF
	for i in range(ACTIONS):
		var value:float=float(model.b2[i])
		for j in range(HIDDEN):value+=float(model.w2[i][j])*float(hidden[j])
		# In-possession strategy and out-of-possession strategy have separate masks.
		if (float(obs[7])>.5 and i in [1,2,3,4]) or (float(obs[6])>.5 and i in [5,6]):value=-10000
		logits.append(value);maximum=maxf(maximum,value)
	var total:float=0
	for i in range(ACTIONS):logits[i]=exp(float(logits[i])-maximum);total+=float(logits[i])
	for i in range(ACTIONS):logits[i]=float(logits[i])/total
	return logits

func potential(obs:Array)->float:return float(obs[1])*.4+(float(obs[6])-float(obs[7]))*.15

func tick(snapshot:Dictionary,delta:float)->Dictionary:
	if not enabled:return {}
	time+=delta
	latest=snapshot
	var actions:Dictionary={}
	for team in models:
		var obs:Array=features(snapshot,int(team))
		var old:Dictionary=states.get(team,{})
		var changed:bool=not old.is_empty() and (int(old.get("focus_id",-1))!=focus_id(snapshot,int(team)) or float(old.obs[6])!=float(obs[6]) or float(old.obs[7])!=float(obs[7]))
		# Short free rolling gaps do not repeatedly flip strategy.
		if old.is_empty() or time>=float(old.until) or (changed and time-float(old.at)>.65):
			close_transition(int(team),obs,false)
			var probs:Array=probabilities(obs,models[team])
			var action:int=0
			if training or String(models[team].get("selection","greedy"))=="sample":
				var sample:float=rng.randf()
				for i in range(ACTIONS):
					sample-=float(probs[i]);action=i
					if sample<=0:break
			else:
				for i in range(ACTIONS):
					if float(probs[i])>float(probs[action]):action=i
			states[team]={"obs":obs,"action":action,"logp":log(maxf(1e-20,float(probs[action]))),"reward":0.0,"focus_id":focus_id(snapshot,int(team)),"at":time,"until":time+2.0}
			decision_counts[team][action]+=1
			actions[team]=action
		else:actions[team]=int(old.action)
	return actions

func credit(team:int,reward:float)->void:
	if states.has(team):states[team].reward+=pow(GAMMA,(time-float(states[team].at))/2.0)*reward

func close_transition(team:int,obs:Array,terminal:bool)->void:
	if not states.has(team):return
	var row:Dictionary=states[team].duplicate(true)
	row.dt=maxf(.01,time-float(row.at))
	row.discount=0.0 if terminal else pow(GAMMA,float(row.dt)/2.0)
	row.reward+=float(row.discount)*potential(obs)-potential(row.obs)
	row.next_obs=obs;row.terminal=terminal
	if training:traces[team].append(row)

func finish(terminal:bool)->void:
	for team in states:close_transition(int(team),features(latest,int(team)),terminal)
	states.clear()

static func bias(action:int,kind:String)->float:
	match action:
		1:return 1.0 if kind in ["CARRY","CUT_IN","WIDE"] else -.25
		2:return 1.2 if kind in ["ONE_TWO","PASS","CUTBACK"] else -.2
		3:return 1.2 if kind in ["THROUGH","LONG"] else -.2
		4:return 1.2 if kind in ["SWITCH","SWITCH_RELAY","CROSS","WIDE"] else -.2
	return 0.0

func focus_id(snapshot:Dictionary,team:int)->int:
	var selected:int=-1;var cost:float=INF
	for p in snapshot.get("players",[]):
		if int(p.team)!=team or not p.get("active",true) or p.get("goalkeeper",false):continue
		if int(p.id)==int(snapshot.get("carrier_id",-1)):return int(p.id)
		var distance:float=Vector3(p.position).distance_squared_to(snapshot.ball_position)
		if distance<cost:cost=distance;selected=int(p.id)
	return selected

func role_features(snapshot:Dictionary,team:int)->Array:
	var id:int=focus_id(snapshot,team)
	var focus:Dictionary={}
	for p in snapshot.get("players",[]):
		if int(p.id)==id:focus=p;break
	if focus.is_empty():return [0.,0.,0.,0.,0.,0.,0.,0.,0.,0.,0.,0.,0.,0.]
	var role:String=focus.get("archetype","balanced")
	var facing:Vector3=focus.get("facing",Vector3.FORWARD);facing.y=0;facing=facing.normalized()
	var right:Vector3=Vector3(-facing.z,0,facing.x)
	var offset:Vector3=snapshot.ball_position-focus.position;offset.y=0
	var opponent_gap:float=15;var frontal:float=0;var outlets:float=0
	for other in snapshot.get("players",[]):
		if not other.get("active",true) or int(other.id)==id:continue
		var relative:Vector3=other.position-focus.position;relative.y=0
		if int(other.team)==team:
			if relative.length()<15 and relative.dot(facing)>1:outlets+=1
		else:
			opponent_gap=minf(opponent_gap,relative.length())
			if relative.dot(facing)>.0:frontal=maxf(frontal,1.0-clampf(relative.length()/6.,0,1))
	return [1.0 if role=="breaker" else 0.0,1.0 if role=="conductor" else 0.0,1.0 if role=="sweeper" else 0.0,
		clampf(offset.dot(right)/5.,-2,2),clampf(offset.dot(facing)/5.,-2,2),Vector3(focus.get("velocity",Vector3.ZERO)).length()/7.,
		float(focus.get("stamina",100))/100.,float(focus.get("ability_speed",5.6))/7.,
		(float(focus.get("ability_touch",1))-1.)/.15,float(focus.get("ability_pass_error",0))/2.,frontal,
		opponent_gap/15.,1.0 if focus.get("can_kick",false) else 0.0,minf(1.,outlets/3.)]
