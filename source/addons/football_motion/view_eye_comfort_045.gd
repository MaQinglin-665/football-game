extends RefCounted
## Presentation-only relative eye height. Never feeds skeleton, motor, head
## collider, ball authority, contact snapshots or camera orientation.
var initialized:=false
var height:=0.0
var raw_height:=0.0
var last_tick:=-1

func update(target:float,dt:float,tick:int)->float:
	raw_height=target
	if not initialized:
		initialized=true;height=target;last_tick=tick
	elif dt>0 and tick!=last_tick:
		var step:float=clampf(dt,0,.05)
		var wanted:float=lerpf(height,target,1.0-exp(-24.0*step))
		height=move_toward(height,wanted,.65*step)
		last_tick=tick
	# Large intentional head/actor changes stay nearby instead of being
	# hidden by a long delayed camera. Small safety impulses retain comfort.
	height=clampf(height,target-.05,target+.05)
	return height

func debug()->Dictionary:
	return {"revision":"visual_eye_comfort045","raw_relative_y":raw_height,"visual_relative_y":height,"visual_offset_y":height-raw_height,"max_offset_m":.05,"last_physics_tick":last_tick}
