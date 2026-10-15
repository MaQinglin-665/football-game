extends "res://tests/r023_touch_order.gd"

# Same real input/contact fixtures, with a longer steady walking observation.
# No forced runtime ball/actor movement, support phase, or successful contact.
func ticks(count:int)->void:
	await super.ticks(maxi(count,600))
	var sample:Array=rows.filter(func(r):return r.case==case_name and int(r.tick)>=120)
	var total:float=0.0
	var minimum:float=INF
	for row in sample:
		var pace:float=absf(float(row.actor_velocity[0]))
		total+=pace
		minimum=minf(minimum,pace)
	check(case_name+" no recurring walking stall",minimum>1.15)
	check(case_name+" sustained walking pace",total/float(sample.size())>1.45)
	print("LATERAL_WALK ",case_name," average=",total/float(sample.size())," minimum=",minimum)
