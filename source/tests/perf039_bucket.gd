extends RefCounted
static var enabled:bool=false
static var totals:Dictionary={}
static func finish(start:int,label:String)->void:
 if not enabled:return
 var v:Array=totals.get(label,[0,0])
 v[0]+=Time.get_ticks_usec()-start;v[1]+=1;totals[label]=v
static func value_array(start:int,label:String,v:Array)->Array:
 finish(start,label);return v
static func value_bool(start:int,label:String,v:bool)->bool:
 finish(start,label);return v
static func value_dict(start:int,label:String,v:Dictionary)->Dictionary:
 finish(start,label);return v

static var shadow_size:int=-1
static var shadow_setters:Array=[]
static func shadow(size:int,source:String)->void:
 shadow_size=size;shadow_setters.append({"size":size,"source":source})

static func count(label:String)->void:
 if not enabled:return
 var v:Array=totals.get(label,[0,0]);v[1]+=1;totals[label]=v
static func force(sk:Skeleton3D)->void:
 var start:int=Time.get_ticks_usec();sk.force_update_all_bone_transforms();finish(start,"body.force_all")
