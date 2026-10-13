extends RefCounted
const Cadence:=preload("res://scripts/visual_pose_cadence39.gd")
const Watch:=preload("res://scripts/frame_spike_watch.gd")
var due:Array[Node3D]=[]
func advance(game:Node)->void:
	due.clear()
	var now:int=Time.get_ticks_usec()
	for actor in game.agents:
		if not is_instance_valid(actor.avatar) or not Cadence.far_visual(actor):continue
		if actor._visual_next_draw_usec_perf==0:actor._visual_next_draw_usec_perf=now+int(actor.get_instance_id()%17)*1900
		if now>=actor._visual_next_draw_usec_perf and actor.pending_pose_delta>0:due.append(actor)
	due.sort_custom(func(a:Node3D,b:Node3D)->bool:return a._visual_next_draw_usec_perf<b._visual_next_draw_usec_perf)
	var began:int=Time.get_ticks_usec()
	# Only distant display work is budgeted. Urgent contact never enters this queue.
	var heavy:bool=Watch.tactics_us>2500 or Watch.pose_us>3500
	var budget:int=450 if heavy else 1400
	# Defer only distant presentation by at most one 60 Hz interval.
	# Semantic/near-ball actors never enter this queue; physics/AI are unchanged.
	if heavy and not due.is_empty() and now-due[0]._visual_next_draw_usec_perf<16667:return
	var count:=0
	for actor in due:
		if count>0 and (Time.get_ticks_usec()-began>=budget or count>=8):break
		actor._visual_pose_forcing39=true
		actor._display_gait_only=true
		actor.refresh_pose()
		actor._visual_pose_forcing39=false
		actor._display_gait_only=false
		var period:int=33333 if actor.position.distance_squared_to(game.player.position)>2025.0 else 16667
		# Keep original phase offsets. 'now + period' made independent actors
		# converge on the same rendered frame after a long frame.
		var skipped:int=maxi(1,int((now-actor._visual_next_draw_usec_perf)/period)+1)
		actor._visual_next_draw_usec_perf+=skipped*period
		count+=1
	Watch.far_us+=Time.get_ticks_usec()-began
	Watch.far_count+=count
