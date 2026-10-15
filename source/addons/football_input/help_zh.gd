class_name FootballInputHelpZH
extends RefCounted
## Text follows host capabilities; unimplemented physics is never a live button.
const Catalog := preload("res://addons/football_input/action_catalog.gd")
static var _cached_default_catalog: RefCounted

static func _default_catalog() -> RefCounted:
	if _cached_default_catalog == null:
		_cached_default_catalog = Catalog.new()
	return _cached_default_catalog

static func text(context: Dictionary, catalog: RefCounted = null) -> String:
	if catalog == null:
		catalog = _default_catalog()
	var rows: Array[String] = [
		"足球操作 / 键鼠",
		"Q：内扣；Q + A/D：向左/右外拨或内扣（自动选脚）",
		"WASD / 方向键：跑动；Ctrl 慢走 / 近控；单击 Shift 切换加速 / 双击大趟",
		"有球：行走稳定近控；冲刺中换向准备扣球；关闭冲刺后跟上球踩拉收回",
		"触球后先跟球：方向键按镜头方向准备下一脚，可小幅调整重心；Q 主动扣球保留",
		"C：有球护球，无球压迫；C + A/D 移动护球方向",
		"Space：有球停球／无球准备接球；按住 Z：自动跟压、贴身干扰、可达时捅球；松开恢复手动",
		"Ctrl + 方向 + Space：短距离拨球；Shift + Space：显式大趟",
		"右键：按住蓄力，松开传球；短按快速地滚球",
		"F + 右键：高球；F + 滚轮调高球仰角（镜头不用抬高）",
		"左键：按住蓄力，松开射门；滚轮调射门仰角",
		"G / X + 传球或射门：左 / 右旋转；G + X 同按为零旋转",
		"E：无球向队友要球；V：无球飞铲",
		"门将无球：Space + 方向扑救，左键按住接球准备",
		"门将手持球：右键出球，F 改为高抛；仍由规则层审核手球合法性",
		"右键在射门蓄力期间：取消；须松开再按才会传球",
		"中键：取消传射蓄力 / 75毫秒微缓冲，移动继续且不打开菜单",
		"Esc：取消并暂停；F1：操作帮助；F11：全屏",
		"Ctrl / C 优先于 Shift；同一时刻只有一组传射蓄力",
		"暂停、失焦、换人后松开再重按；球权变化取消旧传射，不缓存开球",
		"电梯球：禁用，尚无经验证的低旋转尾流与下坠物理"
	]
	var disabled: Array[String] = []
	for action in catalog.all_actions():
		if action == "shoot_knuckle":
			continue
		var state: Dictionary = catalog.availability(action, context)
		if not state.enabled and state.code == "unsupported":
			disabled.append(catalog.label(action))
	if not disabled.is_empty():
		rows.append("当前禁用（宿主未支持）：" + "、".join(disabled))
	if context.get("phase", "menu") == "dead_ball":
		rows.append("死球优先：仅指定罚球队员可传射；站抢、飞铲、护球和要球暂停")
	return "\n".join(rows)

static func contextual_hint(context: Dictionary, snapshot: Dictionary = {}) -> String:
	if not context.get("focused", true):
		return "窗口失焦，动作已取消；回到窗口后松开再重按"
	if context.get("paused", false) or context.get("ui_captured", false) or context.get("phase", "menu") == "menu":
		return "菜单中暂停球场输入；Esc 返回"
	if context.get("phase", "live") == "dead_ball" and not context.get("restart_taker", false):
		return "死球：等待指定罚球队员开球，移动与看向目标继续"
	var buffer: Dictionary = snapshot.get("buffer", {})
	if not buffer.is_empty():
		var remaining := maxf(0.0, float(buffer.expires_at) - float(snapshot.get("now", 0.0))) * 1000.0
		return "传射等待当前动作完成（剩余 %.0f毫秒） · 中键取消 · 不跨丢球 / 暂停缓存" % remaining
	var charge: Dictionary = snapshot.get("charge", {})
	if not charge.is_empty():
		var title: String = _default_catalog().label(charge.action)
		if charge.action == "pass_spin" and charge.style == "high":
			title = "旋转高球"
		var release := "左键" if charge.token == "shot" else "右键"
		return "%s %.0f%% · 松开%s提交 · 中键取消" % [title, float(charge.power) * 100, release]
	var enabled: Array[String] = []
	for card in cards(context, snapshot):
		if card.enabled:
			enabled.append(card.binding + " " + card.label_zh)
	var prefix := "主罚" if context.get("phase", "live") == "dead_ball" else "手持球" if context.get("possession", "none") == "hands" else "门将" if context.get("role", "outfield") == "goalkeeper" else "有球" if context.get("possession", "none") == "foot" else "无球"
	if not enabled.is_empty():
		return prefix + "：" + " · ".join(enabled)
	return "WASD 移动可用；当前足球动作未开放（F1 查看原因）" if _default_catalog().availability("move", context).enabled else "当前位置暂无可用球场动作（F1 查看权限）"

static func cards(context: Dictionary, snapshot: Dictionary = {}) -> Array[Dictionary]:
	# Data for compact HUD cards. Disabled actions retain their reason for a
	# gray/expanded view, but are omitted from the short active-controls hint.
	var result: Array[Dictionary] = []
	if not context.get("focused", true) or context.get("paused", false) or context.get("ui_captured", false) or context.get("phase", "menu") == "menu":
		return result
	var catalog := _default_catalog()
	var held: Array = snapshot.get("held", [])
	var phase: String = context.get("phase", "live")
	var possession: String = context.get("possession", "none")
	var keeper: bool = context.get("role", "outfield") == "goalkeeper"
	var high := held.has("high")
	var spinning := held.has("spin_left") != held.has("spin_right")
	if phase == "dead_ball" and not context.get("restart_taker", false):
		return result
	if possession in ["foot", "hands"] or phase == "dead_ball":
		if possession == "foot" and phase == "live":
			var direction_held: bool = held.has("left") != held.has("right") or held.has("forward") != held.has("back")
			var space_action := "stop_ball" if held.has("stance") else "nudge" if held.has("close") and direction_held else "push_ball" if held.has("sprint") and not held.has("close") else "stop_ball"
			result.append(_card("Space", space_action, catalog, context))
			result.append(_card("Q + A/D", "cut_ball", catalog, context))
		var pass_action := "keeper_distribute" if possession == "hands" else "pass_spin" if spinning else "pass_high" if high else "pass_ground"
		var pass_card := _card("松开右键", pass_action, catalog, context)
		if pass_action == "pass_spin" and high:
			pass_card.label_zh = "旋转高球"
			var high_status: Dictionary = catalog.availability("pass_high", context)
			if not high_status.enabled:
				pass_card.enabled = false
				pass_card.reason = high_status.reason
		result.append(pass_card)
		if possession != "hands":
			result.append(_card("左键", "shoot_curve" if spinning else "shoot_straight", catalog, context))
	elif keeper:
		result.append(_card("Space + 方向", "keeper_dive", catalog, context))
		result.append(_card("按住左键", "keeper_ready", catalog, context))
	else:
		result.append(_card("Space", "receive", catalog, context))
		result.append(_card("按住 Z 自动跟压／捅球", "pressure", catalog, context))
		result.append(_card("C", "pressure", catalog, context))
		result.append(_card("V", "tackle_slide", catalog, context))
		result.append(_card("E", "call_ball", catalog, context))
	return result

static func _card(binding: String, action: String, catalog: RefCounted, context: Dictionary) -> Dictionary:
	var status: Dictionary = catalog.availability(action, context)
	return {"binding": binding, "action": action, "label_zh": catalog.label(action),
		"enabled": status.enabled, "reason": status.reason}
