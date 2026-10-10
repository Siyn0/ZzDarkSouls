extends Node

# 菜单的 Esc 不参与改键，始终可以返回。
signal bindings_changed

const ACTION_LABELS: Dictionary = {
	"move_left": "向左",
	"move_right": "向右",
	"aim_up": "向上（冲刺 / 攀爬）",
	"aim_down": "向下（冲刺 / 攀爬 / 快落）",
	"jump": "跳跃",
	"dash": "冲刺",
	"grab": "抓取（墙壁 / 冰红茶）",
	"defend": "防御 / 精准防御",
}

var load_message: String = ""
var _config_path: String = "user://keybindings.cfg"
var _defaults: Dictionary = {}
var _bindings: Dictionary = {}
var grab_mode: String = "hold"
var input_reset_serial: int = 0
var _grab_latched: bool = false


func _physics_process(_delta: float) -> void:
	if grab_mode == "toggle" and Input.is_action_just_pressed("grab"):
		_grab_latched = not _grab_latched


func is_grabbing() -> bool:
	return _grab_latched if grab_mode == "toggle" else Input.is_action_pressed("grab")


func resume_carried_grab() -> void:
	if grab_mode == "toggle":
		_grab_latched = not Input.is_action_just_pressed("grab")


func _ready() -> void:
	# 默认键位始终取自项目设置，恢复默认不会覆盖用户的项目文件。
	for action: String in ACTION_LABELS:
		var keys: Array = [0, 0]
		var events: Array = ProjectSettings.get_setting("input/" + action)["events"]
		for slot in range(mini(events.size(), 2)):
			keys[slot] = events[slot].physical_keycode
		_defaults[action] = keys
	load_bindings()


func load_bindings() -> void:
	var config := ConfigFile.new()
	var candidate := _defaults.duplicate(true)
	load_message = ""
	grab_mode = "hold"
	var error := config.load(_config_path)
	if error == OK:
		var saved_mode: Variant = config.get_value("controls", "grab_mode", "hold")
		if saved_mode is String and saved_mode in ["hold", "toggle"]:
			grab_mode = saved_mode
		for action: String in ACTION_LABELS:
			candidate[action] = config.get_value("keys", action, _defaults[action])
		# 只迁移后续新增的动作；基础移动配置缺损仍按原有校验恢复。
		var added_actions := ["grab", "defend"]
		var used: Array = []
		for action: String in ACTION_LABELS:
			if (config.has_section_key("keys", action) or action not in added_actions) and candidate[action] is Array:
				used.append_array(candidate[action])
		for action: String in ACTION_LABELS:
			if config.has_section_key("keys", action) or action not in added_actions:
				continue
			var choices: Array = [_defaults[action][0], KEY_CTRL, KEY_C, KEY_E, KEY_F, KEY_G, KEY_V, KEY_B, KEY_N, KEY_M, KEY_Q, KEY_R, KEY_T, KEY_Y, KEY_U, KEY_I, KEY_O, KEY_P, KEY_H, KEY_J, KEY_K, KEY_L]
			for code: int in choices:
				if code != 0 and code not in used:
					candidate[action] = [code, 0]
					used.append(code)
					break
		if not _is_valid(candidate):
			candidate = _defaults.duplicate(true)
			load_message = "保存的键位无效，已使用默认键位。"
	elif error != ERR_FILE_NOT_FOUND:
		load_message = "无法读取键位文件，已使用默认键位。"
	_apply(candidate)


func get_key(action: String, slot: int) -> int:
	return _bindings[action][slot]


func key_label(code: int) -> String:
	match code:
		0: return "未设置"
		KEY_SPACE: return "空格"
		KEY_LEFT: return "←"
		KEY_RIGHT: return "→"
		KEY_UP: return "↑"
		KEY_DOWN: return "↓"
	return OS.get_keycode_string(code)


func action_label(action: String) -> String:
	var names := PackedStringArray()
	for code: int in _bindings[action]:
		if code != 0:
			names.append(key_label(code))
	return " / ".join(names)


func rebind(action: String, slot: int, code: int) -> String:
	if not ACTION_LABELS.has(action) or slot < 0 or slot > 1:
		return "无效的动作。"
	if code == KEY_ESCAPE:
		return "Esc 用于返回，不能绑定到游戏动作。"
	if code <= 0 or OS.get_keycode_string(code).is_empty():
		return "请选择一个键盘按键。"
	for other_action: String in ACTION_LABELS:
		for other_slot in range(2):
			if other_action == action and other_slot == slot:
				continue
			if get_key(other_action, other_slot) == code:
				return "这个按键已用于「%s」，请换一个。" % ACTION_LABELS[other_action]
	var candidate := _bindings.duplicate(true)
	candidate[action][slot] = code
	return _save_and_apply(candidate)


func restore_defaults() -> String:
	return _save_and_apply(_defaults.duplicate(true))


func set_grab_mode(mode: String) -> String:
	if mode not in ["hold", "toggle"]:
		return "无效的抓取方式。"
	return _save_and_apply(_bindings.duplicate(true), mode)


func release_gameplay_inputs() -> void:
	_grab_latched = false
	input_reset_serial += 1
	for action: String in ACTION_LABELS:
		Input.action_release(action)


func _save_and_apply(candidate: Dictionary, mode: String = "") -> String:
	var config := ConfigFile.new()
	var next_mode := grab_mode if mode.is_empty() else mode
	config.set_value("controls", "grab_mode", next_mode)
	for action: String in ACTION_LABELS:
		config.set_value("keys", action, candidate[action])
	if config.save(_config_path) != OK:
		return "保存失败，键位未更改。请检查用户目录是否可写。"
	load_message = ""
	grab_mode = next_mode
	_apply(candidate)
	return ""


func _apply(candidate: Dictionary) -> void:
	release_gameplay_inputs()
	_bindings = candidate
	for action: String in ACTION_LABELS:
		InputMap.action_erase_events(action)
		for code: int in _bindings[action]:
			if code == 0:
				continue
			var event := InputEventKey.new()
			event.physical_keycode = code
			InputMap.action_add_event(action, event)
	bindings_changed.emit()


func _is_valid(candidate: Dictionary) -> bool:
	var used_keys: Array[int] = []
	for action: String in ACTION_LABELS:
		var keys: Variant = candidate[action]
		if not keys is Array or keys.size() != 2:
			return false
		if keys[0] == 0 and keys[1] == 0:
			return false
		for code: Variant in keys:
			if not code is int or code < 0 or code == KEY_ESCAPE:
				return false
			if code == 0:
				continue
			if OS.get_keycode_string(code).is_empty() or code in used_keys:
				return false
			used_keys.append(code)
	return true
