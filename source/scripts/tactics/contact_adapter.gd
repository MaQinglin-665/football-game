class_name FootballTacticsContactAdapter
extends RefCounted
## Production contact-bus bridge. Does not move actors or apply impulses.
## Connect FootballContactHub.contact_resolved to on_contact_resolved.

var director: FootballTacticalDirector
var actor_to_id: Callable
var accepted_actions: Dictionary = {}

func _init(planner: FootballTacticalDirector, stable_id_lookup: Callable) -> void:
	director = planner
	actor_to_id = stable_id_lookup

func register_action_request(actor_id: int, intent: Dictionary) -> void:
	# Call after the low-level action accepts the request. This is only a
	# receiver/kind hint until a successful real FOOT_TOUCH confirms it.
	accepted_actions[actor_id] = {"action":intent.action,"receiver_id":int(intent.get("receiver_id",-1)),"until":director.clock+3.0}

func on_contact_resolved(event: Dictionary) -> bool:
	var actor: Variant = event.get("actor",null)
	if not is_instance_valid(actor) or not actor_to_id.is_valid():
		return false
	var id := int(actor_to_id.call(actor))
	if event.get("kind","")=="FOOT_ACTION_FAILED":
		accepted_actions.erase(id)
		director.give_go_action_failed(id,String(event.get("action","")))
		return false
	var sanitized := {"kind":event.get("kind",""),"success":event.get("success",false),"action":event.get("action",""),"actor_id":id,"receiver_id":-1,"physics_frame":event.get("physics_frame",-1),"serial":event.get("serial",-1)}
	if accepted_actions.has(id) and event.get("action","") in ["PASS","SHOT"]:
		var pending: Dictionary = accepted_actions[id]
		if director.clock<=float(pending.until):
			sanitized.tactical_action = pending.action
			sanitized.receiver_id = int(pending.receiver_id)
		accepted_actions.erase(id)
	var receiver: Variant = event.get("receiver",null)
	if is_instance_valid(receiver):
		sanitized.receiver_id = int(actor_to_id.call(receiver))
	# Node references stop at this boundary. Capture the actual post-contact
	# ball state and rotate it into the director's same half-time frame.
	var host: Variant = actor.get("match_controller")
	if is_instance_valid(host) and is_instance_valid(host.ball):
		if event.get("action","")=="PASS" and host.ball.last_kick_intent.has("space_target"):sanitized.space_target=host.tactics_bridge.canonical(host.ball.last_kick_intent.space_target)
		if event.get("action","")=="PASS" and host.ball.last_kick_intent.has("ground_pass_solution"):
			var solution:Dictionary=host.ball.last_kick_intent.ground_pass_solution
			sanitized.delivery_target=host.tactics_bridge.canonical(solution.target)
			sanitized.delivery_time=solution.travel_s
		sanitized.ball_position = host.tactics_bridge.canonical(host.ball.position)
		sanitized.after_velocity = host.tactics_bridge.canonical(event.get("after_velocity",host.ball.velocity))
		sanitized.carrier_id = int(actor_to_id.call(host.ball.carrier)) if is_instance_valid(host.ball.carrier) else -1
	else:
		sanitized.ball_position = event.get("point",Vector3.ZERO)
		sanitized.after_velocity = event.get("after_velocity",Vector3.ZERO)
		sanitized.carrier_id = int(event.get("carrier_id",-1))
	sanitized.cut_style=actor.foot.touch_plan.get("cut_style","")
	var handled: bool = director.consume_contact(sanitized)
	var completed:Dictionary=director.receive_plan.last_plan
	if handled and is_instance_valid(host) and not actor.is_human and sanitized.get("carrier_id",-1)==id and completed.get("state","")=="COMPLETED" and int(completed.get("receiver_id",-1))==id and completed.get("completion_contact",{}).get("serial",-2)==sanitized.get("serial",-1):
		host.tactics_bridge.apply_receive_handover(actor,sanitized)
	# Let the next physics frame select the newly confirmed primary action,
	# before any actor motor runs. Do not re-enter motors or tick from a foot.
	if handled and is_instance_valid(host): host.tactics_bridge.contact_refresh_requested = true
	return handled

func reset() -> void:
	accepted_actions.clear()
