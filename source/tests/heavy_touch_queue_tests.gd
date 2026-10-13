extends SceneTree
const Router := preload("res://addons/football_shift_tiers/shift_tier_router.gd")
const Queue := preload("res://addons/football_shift_tiers/heavy_touch_host_queue.gd")
var checks: Array[Dictionary] = []
var context := {"actor_id":"blue-10","role":"outfield","phase":"live","possession":"foot",
	"paused":false,"focused":true,"ui_captured":false,"ball_generation":7,"restart_id":"r1",
	"capabilities":{"push_ball":true,"close_control":true},"allowed_actions":[],
	"action_ready":false,"action_exclusive":false,"close_override":false}
var request: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var producer := Router.new({"deliberate_touch_dispatch":"host_next_contact","next_contact_wait_ms":350})
	var produced: Array[Dictionary] = []
	producer.intent_emitted.connect(func(intent: Dictionary): produced.append(intent.duplicate(true)))
	producer.set_context(context,0)
	producer.set_direction(Vector3.RIGHT)
	producer.feed_shift(true,"shift",false,0)
	producer.feed_shift(false,"shift",false,40000)
	producer.feed_shift(true,"shift",false,100000)
	_check("忙于近控时双击立即提交一次明确命令", produced.size()==1 and produced[0].phase=="commit" and produced[0].emitted_at_usec==100000)
	request = produced[0].duplicate(true)
	_check("下一脚命令与75ms输入槽分离", request.request_mode=="next_foot_window" and request.next_contact_wait_ms==350 and producer.snapshot().pending.is_empty())
	producer.tick(180000)
	_check("输入不会把明确命令75ms超时撤销", produced.size()==1)
	var queue := Queue.new()
	_check("宿主接受连续近控中的命令", queue.offer(request,context,100100))
	_check("忙时不给出执行指令", queue.take_ready(context,180000).is_empty())
	var ready := context.duplicate(true)
	ready.action_ready = true
	var dispatch: Dictionary = queue.take_ready(ready,276000)
	_check("175ms以后下个空闲脚位能接收命令", not dispatch.is_empty() and is_equal_approx(dispatch.host_wait_ms,176.0))
	_check("延迟执行保持方向力度和gesture", dispatch.direction==Vector3.RIGHT and dispatch.power==request.power and dispatch.gesture_id==request.gesture_id)
	_check("取出一次后后续tick不会再踢", queue.take_ready(ready,290000).is_empty())
	_check("相同gesture重复提交不能续期或重踢", not queue.offer(request,ready,300000))
	var cancellations: Array[Dictionary] = []
	queue = Queue.new()
	queue.command_cancelled.connect(func(intent: Dictionary): cancellations.append(intent.duplicate(true)))
	queue.offer(request,context,100000)
	_check("350ms截止点包含", not queue.take_ready(ready,450000).is_empty())
	queue = Queue.new()
	queue.command_cancelled.connect(func(intent: Dictionary): cancellations.append(intent.duplicate(true)))
	queue.offer(request,context,100000)
	_check("超过350ms不发远程延迟命令", queue.take_ready(ready,450001).is_empty() and queue.snapshot().pending.is_empty())
	_check("截止超时给同gesture取消证据", cancellations.size()==1 and cancellations[0].reason=="command_expired" and cancellations[0].gesture_id==request.gesture_id)
	for patch in [{"possession":"none"},{"paused":true},{"focused":false},{"ui_captured":true},{"phase":"dead_ball"},{"actor_id":"blue-6"},{"role":"goalkeeper"},{"ball_generation":8},{"restart_id":"r2"},{"action_exclusive":true},{"close_override":true},{"capabilities":{}},{"allowed_actions":["move"]}]:
		queue = Queue.new()
		queue.offer(request,context,100000)
		var changed: Dictionary = context.duplicate(true)
		changed.merge(patch,true)
		queue.observe_context(changed,200000)
		_check("等待时屏障取消并且恢复后不复活 "+str(patch), queue.snapshot().pending.is_empty() and queue.take_ready(ready,210000).is_empty())
	queue = Queue.new()
	_check("过期命令即便首次送达也不重新计时", not queue.offer(request,ready,500000) and queue.take_ready(ready,500001).is_empty())
	queue = Queue.new()
	queue.offer(request,context,100000)
	var second: Dictionary = request.duplicate(true)
	second.gesture_id = "second"
	second.requested_at_usec = 200000
	_check("单槽不被新请求覆盖", not queue.offer(second,context,200000) and queue.snapshot().pending.intent.gesture_id==request.gesture_id)
	queue.cancel("host_reset",210000)
	_check("宿主reset清空下一脚预约", queue.snapshot().pending.is_empty())
	var long_request: Dictionary = request.duplicate(true)
	long_request.next_contact_wait_ms = 9999
	queue = Queue.new()
	queue.offer(long_request,context,100000)
	_check("宿主将预约期限硬封顶400ms", queue.snapshot().pending.expires_at_usec==500000)
	var failed: int = checks.filter(func(item: Dictionary): return not item.passed).size()
	var evidence := ProjectSettings.globalize_path("res://../verification/after")
	FileAccess.open(evidence.path_join("heavy_touch_queue_tests.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":checks.size()-failed,"failed":failed,"checks":checks,"scope":"semantic host reservation; no ball physics in this test"},"\t"))
	print("HEAVY_QUEUE_RESULT ",checks.size()-failed,"/",checks.size())
	quit(0 if failed==0 else 1)

func _check(label: String, passed: bool) -> void:
	checks.append({"name":label,"passed":passed})
	print("PASS " if passed else "FAIL ",label)
