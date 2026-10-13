extends SceneTree
var failures: Array[String] = []
var emitted := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, name: String) -> void:
	if not ok:
		failures.append(name)

func run() -> void:
	var hub: Node = load("res://scripts/integration_contact_hub.gd").new()
	root.add_child(hub)
	var actor := CharacterBody3D.new()
	root.add_child(actor)
	var observer := func(_event: Dictionary): emitted += 1
	hub.contact_resolved.connect(observer)
	var resolved := {"kind":"FOOT_TOUCH", "actor":actor, "team":0, "action":"PASS", "surface":"INSIDE", "point":Vector3(0,0.11,-1), "normal":Vector3.FORWARD, "before_velocity":Vector3.ZERO, "after_velocity":Vector3(0,0,-12), "impulse":Vector3(0,0,-5.4), "physics_frame":100}
	check(hub.publish(resolved), "resolved pass accepted")
	check(not hub.publish(resolved), "same contact not emitted twice")
	check(emitted == 1, "single force event single sound event")
	resolved["physics_frame"] = 101
	check(hub.publish(resolved), "next independent contact accepted")
	var bad := resolved.duplicate()
	bad["physics_frame"] = 102
	bad["after_velocity"] = Vector3(INF,0,0)
	check(not hub.publish(bad), "nonfinite response rejected")
	bad = resolved.duplicate()
	bad["point"] = "local point incorrectly supplied"
	check(not hub.publish(bad), "coordinate type rejected")
	check(actor.velocity == Vector3.ZERO, "report does not apply second physics response")
	var row: Dictionary = hub.export_records()[0]
	check(not row.has("actor") and row["point"] is Array, "audit JSON contains no live node")
	actor.free()
	check(not hub.publish(resolved), "freed actor cannot publish")
	for frame in range(200,800):
		hub.publish({"kind":"RESTART", "physics_frame":frame, "type":"THROW_IN", "team":0})
	check(hub.history.size() == hub.HISTORY_LIMIT, "bounded long match history")
	hub.reset()
	check(hub.history.is_empty() and hub.serial == 0, "new match clears old contacts")
	check(hub.contact_resolved.is_connected(observer), "new match keeps module observers")
	print("INTEGRATION_CONTACT_HUB ", JSON.stringify({"failures":failures,"checks":12}))
	quit(0 if failures.is_empty() else 1)
