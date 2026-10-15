extends RefCounted
const START_SECONDS:=.25
const FULL_SECONDS:=1.50
const SAME_DIRECTION_DOT:=.94
var elapsed:=0.0
var axis:=Vector3.ZERO
var had_ball:=false

func update(move:Vector3,enabled:bool,owned:bool,dt:float)->float:
	if not enabled or move.length()<.1:
		elapsed=0.0;axis=Vector3.ZERO;had_ball=owned;return 0.0
	var direction:=move.normalized()
	if owned!=had_ball or axis.dot(direction)<SAME_DIRECTION_DOT:
		elapsed=0.0;axis=direction
	had_ball=owned
	elapsed=minf(FULL_SECONDS,elapsed+dt)
	return smoothstep(START_SECONDS,FULL_SECONDS,elapsed)

static func control_speed(actor:Node3D,base:float)->float:
	if actor.is_human and actor.get("steady_control_speed")!=null:
		return maxf(base,float(actor.steady_control_speed))
	return base
