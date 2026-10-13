class_name FBMatchContactHubAdapter
extends RefCounted

# Read-only adapter for the main integration contract's FootballContactHub dictionaries.
# This class receives notifications; it never applies physics or edits another module.
var services: FBMatchServices
var ball_body: Node3D
var _sequence: int = 0

func _init(target: FBMatchServices = null, match_ball: Node3D = null) -> void:
	services = target
	ball_body = match_ball

func consume(event: Dictionary) -> bool:
	if services == null or not bool(event.get("success", true)):
		return false
	var kind := str(event.get("kind", "")).to_upper()
	var actor: Node = event.get("actor")
	var actor_id := int(event.get("actor_id", actor.get_instance_id() if is_instance_valid(actor) else -1))
	var team := int(event.get("team", actor.get("team") if is_instance_valid(actor) else -1))
	var source_id := str(event.get("event_id", event.get("contact_id", "")))
	if source_id.is_empty() and event.has("serial"):
		source_id = "hub:%s" % str(event["serial"])
	# Without a source sequence, each publish call is one distinct contact. The publisher must
	# NOT republish the same dictionary; physics_frame alone cannot identify multiple contacts.
	if source_id.is_empty():
		_sequence += 1
		source_id = "hub-local:%d" % _sequence
	var point: Vector3 = event.get("point", event.get("position", Vector3.ZERO))
	var impulse_value: Variant = event.get("impulse", 1.0)
	var impulse: float = impulse_value.length() if impulse_value is Vector3 else float(impulse_value)
	if kind == "FOOT_TOUCH" or kind == "BALL_BODY_CONTACT":
		var action := str(event.get("action", "RECEIVE")).to_lower()
		return services.report_ball_contact({"event_id": source_id, "actor_id": actor_id, "team": team,
			"position": point, "kind": "body" if kind == "BALL_BODY_CONTACT" else action,
			"impulse": impulse, "physics_frame": event.get("physics_frame", 0),
			"time": event.get("time", 0.0), "surface": event.get("surface", ""),
			"restart_contact": event.get("restart_contact", false),
			"strength01": event.get("strength01", clampf(impulse / 10.0, .12, 1.0))})
	if kind == "FOOTSTEP":
		return services.report_footstep({"event_id": source_id, "actor_id": actor_id, "position": point,
			"speed": event.get("speed", 0.0), "grounded": event.get("grounded", false)})
	if kind in ["CHALLENGE", "BODY_CONTACT"]:
		# BODY_CONTACT means actor/actor unless ball_contact=true is explicit. Do not make every
		# body collision a last touch or a foul. The main physics layer supplies classified evidence.
		if bool(event.get("ball_contact", false)) or (is_instance_valid(ball_body) and event.get("other") == ball_body):
			# The release shoe can also publish its solver callback. Same action,
			# same contacting shoe, two ticks: not a new restart second touch.
			if is_instance_valid(actor) and "foot" in actor and actor.foot!=null:
				var foot:RefCounted=actor.foot
				if foot.restarting and foot.hit and foot.kind in ["PASS","SHOT"] and foot.contact_tick>=Engine.get_physics_frames()-2 and point.distance_to(foot.toe_world)<.18:return false
			return services.report_ball_contact({"event_id": source_id, "actor_id": actor_id, "team": team,
				"position": point, "kind": "header" if event.get("surface", "") == "HEAD" and event.get("action", "") == "HEADER" else "body", "impulse": impulse,
				"surface": event.get("surface", ""), "physics_frame": event.get("physics_frame", 0), "time": event.get("time", 0.0)})
		var other: Node = event.get("other")
		var proof: Dictionary = event.get("foul_evidence", {})
		if proof.is_empty():
			return false
		var challenge := proof.duplicate(true)
		challenge["event_id"] = str(proof.get("event_id",source_id))
		challenge["offender_id"] = actor_id
		challenge["offender_team"] = team
		challenge["victim_id"] = event.get("other_id", other.get_instance_id() if is_instance_valid(other) else -1)
		challenge["victim_team"] = event.get("other_team", other.get("team") if is_instance_valid(other) else -1)
		challenge["position"] = point
		return services.report_challenge(challenge)
	# GOAL/RESTART from the old match controller are deliberately not consumed: this engine
	# owns those decisions and publishes one result; callers remove the old boundary handler.
	return false
