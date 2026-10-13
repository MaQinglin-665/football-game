extends "res://tests/shift_release_checks.gd"
## Full-body/C-shape regression on frozen0.6.3; no production input or physics changes.
var shift_edges: Array[Dictionary] = []
var shift_notices: Array[Dictionary] = []
var shift_outputs: Array[Dictionary] = []
var shift_ticks: Array[Dictionary] = []
var queue_events: Array[Dictionary] = []
var heavy_contacts: Array[Dictionary] = []
var linked := false

func _initialize() -> void:
	AudioServer.set_bus_mute(0, true) # This test process only.
	super._initialize()

func key(code: int, pressed: bool) -> void:
	if not linked and is_instance_valid(game) and is_instance_valid(game.input_bridge.shift_input):
		linked = true
		game.input_bridge.shift_input.notice_emitted.connect(func(payload: Dictionary):
			shift_notices.append({"case":current_case,"frame":frames,"wall_usec":Time.get_ticks_usec(),"notice":payload.duplicate(true)}))
		game.input_bridge.shift_input.intent_emitted.connect(func(payload: Dictionary):
			shift_outputs.append({"case":current_case,"frame":frames,"wall_usec":Time.get_ticks_usec(),"intent":payload.duplicate(true)}))
		var host_queue: Variant = game.input_bridge.get("heavy_queue")
		if host_queue != null:
			host_queue.state_changed.connect(func(payload: Dictionary):
				queue_events.append({"case":current_case,"frame":frames,"wall_usec":Time.get_ticks_usec(),"state":payload.duplicate(true),"foot_kind":game.player.foot.kind,"foot_phase":game.player.foot.phase}))
		game.contact_hub.contact_resolved.connect(func(event: Dictionary):
			if event.actor==game.player and event.action=="SPRINT":
				heavy_contacts.append({"case":current_case,"frame":frames,"wall_usec":Time.get_ticks_usec(),
					"success":event.success,"point":event.point,"reach_error":event.get("reach_error",-1),
					"action_sequence":event.get("action_sequence",-1),"before_velocity":event.before_velocity,
					"after_velocity":event.after_velocity,"actual_shoe":game.player.foot.actual_contact.duplicate(true),
					"impact_audio_records":game.services.audio.recent_mix.filter(func(m): return m.get("event_id","")=="impact-foot:%d:%d" % [game.player.get_instance_id(),int(event.get("action_sequence",0))]).duplicate(true)}))
	var before: Dictionary = {}
	if code == KEY_SHIFT and is_instance_valid(game) and is_instance_valid(game.input_bridge.shift_input):
		before = game.input_bridge.shift_input.snapshot()
	super.key(code,pressed)
	if code == KEY_SHIFT and is_instance_valid(game) and is_instance_valid(game.input_bridge.shift_input):
		shift_edges.append({"case":current_case,"frame":frames,"wall_usec":Time.get_ticks_usec(),
			"pressed":pressed,"keycode":code,"source":"key:%d:0:0" % code,"echo":false,
			"before":before,"after":game.input_bridge.shift_input.snapshot(),
			"host_context":game.input_bridge.context.duplicate(true),"foot_kind":game.player.foot.kind,
			"foot_phase":game.player.foot.phase,"foot_elapsed":game.player.foot.elapsed,
			"foot_idle":game.player.foot.idle(),"pending_host_commands":game.input_bridge.pending_intents.size()})

func ticks(count: int, interval := 0, tag := "play") -> void:
	for index in count:
		await super.ticks(1,interval,tag)
		if current_case == "double_shift" and is_instance_valid(game.input_bridge.shift_input):
			var state: Dictionary = game.input_bridge.shift_input.snapshot()
			shift_ticks.append({"frame":frames,"wall_usec":Time.get_ticks_usec(),"state":state,
				"foot_kind":game.player.foot.kind,"foot_phase":game.player.foot.phase,
				"foot_elapsed":game.player.foot.elapsed,"foot_idle":game.player.foot.idle()})

func check(label: String, ok: bool, details: Variant = null) -> void:
	super.check(label,ok,details)
	var file := FileAccess.open(evidence.path_join("shift_host_diagnostic.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"edges":shift_edges,"notices":shift_notices,"outputs":shift_outputs,
		"host_queue_events":queue_events,"heavy_contacts":heavy_contacts,
		"ticks":shift_ticks,"checks":checks,"input_clock":"Time.get_ticks_usec",
		"engine":Engine.get_version_info().string,"headless":not native,"build":"B v0.6.4 motion/C-shape on frozen0.6.3",
		"audio_driver":AudioServer.get_driver_name(),"master_muted":true},"\t"))
	file.close()
