class_name FootballSemanticInputMap
extends RefCounted
## Only namespaced actions are created; legacy actions are never rewritten.
const PREFIX := "ff_"
const KEY_BINDINGS := {
	"forward": [KEY_W, KEY_UP], "back": [KEY_S, KEY_DOWN],
	"left": [KEY_A, KEY_LEFT], "right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT], "close": [KEY_CTRL], "stance": [KEY_C],
	"context": [KEY_SPACE], "cut": [KEY_Q], "call": [KEY_E],
	"high": [KEY_F], "stand_intercept": [KEY_Z], "spin_left": [KEY_G], "spin_right": [KEY_X],
	"slide": [KEY_V], "pause": [KEY_ESCAPE], "help": [KEY_F1],
	"fullscreen": [KEY_F11]
}
const MOUSE_BINDINGS := {
	"shot": [MOUSE_BUTTON_LEFT], "pass": [MOUSE_BUTTON_RIGHT],
	"cancel": [MOUSE_BUTTON_MIDDLE],
	"loft_up": [MOUSE_BUTTON_WHEEL_UP], "loft_down": [MOUSE_BUTTON_WHEEL_DOWN]
}
const UI_ACTIONS := ["pause", "help", "fullscreen"]

static func action_names() -> Array[String]:
	var names: Array[String] = []
	for token in KEY_BINDINGS:
		names.append(token)
	for token in MOUSE_BINDINGS:
		if not names.has(token):
			names.append(token)
	return names

static func install_defaults() -> void:
	# Preserve user remaps. Only missing actions receive defaults, including
	# all aliases in one transaction. Calling this twice adds no extra events.
	for token in action_names():
		var action := StringName(PREFIX + token)
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.2)
		for keycode in KEY_BINDINGS.get(token, []):
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			InputMap.action_add_event(action, event)
		for button in MOUSE_BINDINGS.get(token, []):
			var event := InputEventMouseButton.new()
			event.button_index = button
			InputMap.action_add_event(action, event)

static func token_for_event(event: InputEvent) -> String:
	if not (event is InputEventKey or event is InputEventMouseButton or event is InputEventAction):
		return ""
	for token in action_names():
		# false permits Shift/Ctrl modifiers on ordinary keys. Chords are
		# resolved by the semantic router, never by overlapping InputMap keys.
		if event.is_action(StringName(PREFIX + token), false):
			return token
	return ""

static func source_for_event(event: InputEvent) -> String:
	if event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		return "key:%s:%s" % [code, event.location]
	if event is InputEventMouseButton:
		return "mouse:%s" % event.button_index
	if event is InputEventAction:
		return "action:%s:%s" % [event.action, event.device]
	return ""

static func conflicts() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var owned: Dictionary = {}
	for token in action_names():
		var action := StringName(PREFIX + token)
		for event in InputMap.action_get_events(action):
			var source := source_for_event(event)
			if source.is_empty():
				found.append({"type": "unsupported_device", "action": action})
			elif owned.has(source) and owned[source] != token:
				found.append({"type": "duplicate", "source": source, "first": owned[source], "second": token})
			else:
				owned[source] = token
	return found
