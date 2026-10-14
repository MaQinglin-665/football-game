extends Node
## State only: semantic input owns the Shift toggle; motor owns speed, camera owns FOV.
enum State { NORMAL, RUN, SPRINT }
@export var drain_per_second:=10.0
@export var recovery_per_second:=12.0
var state:=State.NORMAL

func update_state(requested:bool,moving_speed:float,shielding:bool,stamina:float,locked:bool,can_recover:bool,dt:float)->Dictionary:
 state=State.SPRINT if requested and moving_speed>.25 and not locked else State.RUN if moving_speed>2.5 else State.NORMAL
 if shielding:stamina=maxf(0,stamina-dt*4.0)
 elif state==State.SPRINT:stamina=maxf(0,stamina-dt*drain_per_second)
 elif can_recover:stamina=minf(100,stamina+dt*recovery_per_second)
 if stamina<2:locked=true
 elif stamina>26:locked=false
 return {"stamina":stamina,"locked":locked,"state":state}
