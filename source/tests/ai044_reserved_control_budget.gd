extends SceneTree
const Movement := preload("res://scripts/football_shared_movement.gd")
const Tuning := preload("res://scripts/control_tuning.gd")
var checks: Array = []
func check_case(label: String, result: Dictionary, expected: float) -> void:
	checks.append({"name":label,"ok":absf(float(result.speed)-expected)<.0001,"speed":result.speed,"expected":expected})
func _initialize() -> void:
	var cfg = Tuning.new()
	var tracking := Vector3(-2,0,3)
	var cmd := {"enabled":true,"move":tracking.normalized(),"close_control":true,"requested_pace":tracking.length(),"prepared_motion":tracking,"control_setup_tracking":true}
	var state := {"owned":true,"facing":tracking.normalized(),"gap":.68,"foot_cap":100.0,"velocity":Vector3.ZERO}
	check_case("released setup follows moving ball above CLOSE pace",Movement.resolve(cmd,state,cfg,.008333),tracking.length())
	checks.append({"name":"CLOSE touch intent retained","ok":Movement.resolve(cmd,state,cfg,.008333).close_control})
	state.gap = .85
	check_case("finite setup tracking does not inherit ordinary distant-ball brake",Movement.resolve(cmd,state,cfg,.008333),tracking.length())
	state.foot_cap = 1.3
	check_case("real PASS contact movement cap preserved",Movement.resolve(cmd,state,cfg,.008333),1.3)
	state.foot_cap = 100.0
	state.stop_requested = 1.0
	check_case("explicit braking retained",Movement.resolve(cmd,state,cfg,.008333),0.0)
	state.stop_requested = 0.0
	state.facing = -tracking.normalized()
	check_case("backward physical speed retained",Movement.resolve(cmd,state,cfg,.008333),2.1)
	state.facing = tracking.normalized()
	state.gap = .68
	cmd.shield = true
	check_case("shield speed retained",Movement.resolve(cmd,state,cfg,.008333),cfg.shield_speed)
	cmd.shield = false
	cmd.control_setup_tracking = false
	check_case("other reserved receptions unchanged",Movement.resolve(cmd,state,cfg,.008333),cfg.close_speed)
	cmd.erase("prepared_motion")
	cmd.control_setup_tracking = true
	check_case("tag alone cannot bypass ordinary CLOSE",Movement.resolve(cmd,state,cfg,.008333),cfg.close_speed)
	cmd.erase("control_setup_tracking")
	state.gap = .85
	check_case("ordinary distant-ball brake unchanged",Movement.resolve(cmd,state,cfg,.008333),1.6)
	var failed := 0
	for item in checks:
		if not item.ok: failed += 1
	print(JSON.stringify({"scope":"pure shared movement budget; not natural ABC proof","checks":checks,"failed":failed}))
	quit(0 if failed==0 else 1)
