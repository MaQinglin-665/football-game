class_name FootballInputActionCatalog
extends RefCounted

const PROFILE_PATH := "res://addons/football_input/action_profile.json"
var profile: Dictionary = {}
var error := ""

func _init(path: String = PROFILE_PATH) -> void:
	if not FileAccess.file_exists(path):
		error = "动作配置不存在: " + path
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1:
		error = "动作配置 schema_version 必须为 1"
		return
	profile = parsed
	if not profile.get("actions", {}) is Dictionary or not profile.actions.has("move"):
		error = "动作配置缺少 actions/move"
		profile = {}

func value(key: String, fallback: float) -> float:
	return float(profile.get(key, fallback))

func definition(action: String) -> Dictionary:
	return profile.get("actions", {}).get(action, {})

func label(action: String) -> String:
	return definition(action).get("label_zh", action)

func availability(action: String, context: Dictionary) -> Dictionary:
	var row := definition(action)
	if not error.is_empty():
		return {"enabled": false, "code": "invalid_profile", "reason": error}
	if row.is_empty():
		return {"enabled": false, "code": "unknown_action", "reason": "未知动作: " + action}
	if row.has("disabled_reason"):
		return {"enabled": false, "code": "unverified_physics", "reason": row.disabled_reason}
	if row.has("role") and context.get("role", "outfield") != row.role:
		return {"enabled": false, "code": "role_denied", "reason": label(action) + "仅门将可请求"}
	var allowed: Variant = context.get("allowed_actions", [])
	if not allowed.is_empty() and not allowed.has(action):
		return {"enabled": false, "code": "position_denied", "reason": "当前位置权限未开放" + label(action)}
	if action == "move" or action == "call_ball":
		return {"enabled": true, "code": "ok", "reason": ""}
	if context.get("capabilities", {}).get(action, false) != true:
		return {"enabled": false, "code": "unsupported", "reason": "当前游戏尚未支持" + label(action)}
	return {"enabled": true, "code": "ok", "reason": ""}

func all_actions() -> Array:
	return profile.get("actions", {}).keys()
