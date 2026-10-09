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
	"grab": "抓墙（按住）",
}

var load_message: String = ""
var _config_path: String = "user://keybindings.cfg"
var _defaults: Dictionary = {}
var _bindings: Dictionary = {}


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
	var error := config.load(_config_path)
	if error == OK:
		for action: String in ACTION_LABELS:
			candidate[action] = config.get_value("keys", action, _defaults[action])
		# 旧存档没有抓墙键。若 Ctrl 已被用户使用，为新增动作选一个空闲键，
		# 避免一次功能升级把用户的整套自定义键位重置。
		if not config.has_section_key("keys", "grab"):
			var used: Array = []
			for action: String in ACTION_LABELS:
				if action != "grab" and candidate[action] is Array:
					used.append_array(candidate[action])
			for code: int in [KEY_CTRL, KEY_C, KEY_E, KEY_G, KEY_F, KEY_V, KEY_B, KEY_N, KEY_M, KEY_Q, KEY_R, KEY_T, KEY_Y, KEY_U]:
				if code not in used:
					candidate["grab"] = [code, 0]
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


func release_gameplay_inputs() -> void:
	for action: String in ACTION_LABELS:
		Input.action_release(action)


func _save_and_apply(candidate: Dictionary) -> String:
	var config := ConfigFile.new()
	for action: String in ACTION_LABELS:
		config.set_value("keys", action, candidate[action])
	if config.save(_config_path) != OK:
		return "保存失败，键位未更改。请检查用户目录是否可写。"
	load_message = ""
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
