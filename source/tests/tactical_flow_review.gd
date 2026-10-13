extends "res://tests/ai_match_review.gd"
# Observe real game execution. No gameplay state is written after ordinary kickoff.
var flow_rows:Array=[]
var flow_contacts:Array=[]
var flow_events:Array=[]
var seen_events:Dictionary={}
var epoch:int=0
var previous_clock:float=0
var flow_sample:float=-1
func begin()->void:
	super.begin()
	game.contact_hub.contact_resolved.connect(func(e):
		if not e.get("success",false):return
		var a=e.get("actor")
		if not is_instance_valid(a):return
		var plan:Dictionary=game.tactical_director.team_attack.plans.get(int(a.team),{})
		flow_contacts.append({"t":elapsed,"actor":game.players.find(a),"team":a.team,"action":e.get("action",""),"owner":game.players.find(game.ball.carrier),"ball":game.ball.position,"speed":game.ball.velocity.length(),"reason":a.tactical_intent.get("reason",""),"plan_id":plan.get("id",-1),"mode":plan.get("mode",""),"stage":plan.get("stage",""),"receiver":game.players.find(a.foot.receiver),"cut_style":a.foot.touch_plan.get("cut_style",""),"foot_sequence":a.foot.sequence if "sequence" in a.foot else -1})
	)
func observe(dt:float)->void:
	if finished:return
	var director=game.tactical_director
	if director.clock<previous_clock:epoch+=1
	previous_clock=director.clock
	for event in director.team_attack.events:
		var key:String=str(epoch)+JSON.stringify(event)
		if seen_events.has(key):continue
		seen_events[key]=true
		var copy:Dictionary=event.duplicate(true);copy.match_time=elapsed;copy.epoch=epoch;flow_events.append(copy)
	if elapsed-flow_sample>=.2:
		flow_sample=elapsed
		var players:Array=[]
		for a in game.players:
			players.append({"id":game.players.find(a),"team":a.team,"jersey":a.jersey,"position":a.position,"velocity":a.velocity,"facing":a.facing,"target":a.target,"pace":a.tactical_pace,"reason":a.tactical_intent.get("reason",""),"action":a.tactical_intent.get("action","NONE"),"duty":a.tactical_intent.get("attack_duty",""),"plan":a.tactical_intent.get("shared_plan_id",-1),"foot":a.foot.kind,"phase":a.foot.phase,"hit":a.foot.hit,"failure":a.foot.contact_failure,"pending":not a.pending_kick.is_empty(),"cut":a.tactical_intent.get("carry_cut",false)})
		flow_rows.append({"t":elapsed,"live":game.services.rules.state_name()=="LIVE","ball":game.ball.position,"ball_velocity":game.ball.velocity,"owner":game.players.find(game.ball.carrier),"last_touch":game.players.find(game.ball.last_contact_actor),"touch_age":game.ball.touch_age,"players":players})
	# Write the detailed evidence before parent schedules quit / final screenshot.
	if elapsed+dt>=duration or full_match and game.services.rules.state_name()=="FULL_TIME":
		FileAccess.open(output+".flow.json",FileAccess.WRITE).store_string(JSON.stringify({"seed":seed_value,"rows":flow_rows,"contacts":flow_contacts,"events":flow_events,"scope":"Observed movement, actual contacts and plan lifecycle; selection events alone are not successful tactics."}))
	super.observe(dt)
