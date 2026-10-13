extends "res://tests/tactical_flow_review.gd"
# Natural headless match telemetry; no state changes beyond parent kickoff fixture.
var defense_rows:Array=[]
var next_defense_sample:=0.0
func observe(dt:float)->void:
	if finished:return
	if elapsed>=next_defense_sample and game.services.rules.state_name()=="LIVE":
		next_defense_sample=elapsed+.2
		var owner=game.ball.carrier
		if is_instance_valid(owner):
			var rows:Array=[]
			for actor in game.agents:
				if actor.team==owner.team or actor.is_goalkeeper:continue
				var intent:Dictionary=actor.tactical_intent
				var offset:Vector3=actor.position-owner.position
				var goalward:Vector3=-game.services.rules.attack_direction(actor.team)
				rows.append({"id":game.players.find(actor),"job":intent.get("defensive_task",{}).get("task",""),"press":intent.get("press",false),"reason":intent.get("reason",""),"gap":offset.length(),"position":[actor.position.x,actor.position.z],"target":[actor.target.x,actor.target.z],"inside":offset.x*owner.position.x<0,"goalside":offset.dot(goalward)>0,"guard":actor.guarding_lane,"speed":actor.velocity.length()})
			defense_rows.append({"t":elapsed,"owner":game.players.find(owner),"owner_position":[owner.position.x,owner.position.z],"defenders":rows})
	if elapsed+dt>=duration:
		FileAccess.open(output+".defense.json",FileAccess.WRITE).store_string(JSON.stringify(defense_rows))
	super.observe(dt)
