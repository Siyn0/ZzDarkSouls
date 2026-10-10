extends CanvasLayer

var _binding_buttons: Dictionary = {}
var _listening_action: String = ""
var _listening_slot: int = 0
var _was_paused: bool = false

@onready var overlay: Control = %Overlay
@onready var main_page: Control = %MainPage
@onready var bindings_page: Control = %BindingsPage
@onready var status_label: Label = %Status
@onready var player: CharacterBody2D = get_parent().get_node("Player")


func _ready() -> void:
	%SettingsButton.pressed.connect(open_settings)
	%CloseButton.pressed.connect(close_settings)
	%ResumeButton.pressed.connect(close_settings)
	%OpenBindings.pressed.connect(show_bindings)
	%BackButton.pressed.connect(show_main_page)
	%RestoreButton.pressed.connect(_restore_defaults)
	%GrabMode.add_item("按住抓取（默认）")
	%GrabMode.add_item("按一下切换")
	%GrabMode.item_selected.connect(_change_grab_mode)
	%ArenaButton.pressed.connect(_switch_arena)
	%ArenaButton.text = "返回练习场" if get_parent().has_method("is_combat_arena") else "战斗试验场"
	if get_parent().has_method("is_combat_arena"):
		$Screen/Title.text = "ICED TEA / 冰红茶试验场"
	for action: String in KeyBindings.ACTION_LABELS:
		var label := Label.new()
		label.text = KeyBindings.ACTION_LABELS[action]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		%Rows.add_child(label)
		var buttons: Array[Button] = []
		for slot in range(2):
			var button := Button.new()
			button.custom_minimum_size = Vector2(132, 34)
			button.pressed.connect(_listen_for_key.bind(action, slot))
			%Rows.add_child(button)
			buttons.append(button)
		_binding_buttons[action] = buttons
	KeyBindings.bindings_changed.connect(_refresh_bindings)
	_refresh_bindings()


func _process(_delta: float) -> void:
	%Stamina.max_value = player.max_stamina
	%Stamina.value = player.stamina
	var tired: bool = player.stamina < player.tired_threshold
	%Stamina.modulate = Color(1.0, 0.45, 0.3) if tired else Color(0.5, 0.9, 0.8)
	%StaminaLabel.text = "体力  %d / %d%s" % [ceili(maxf(0.0, player.stamina)), ceili(player.max_stamina), "  · 即将力竭" if tired else ""]
	%DashStatus.text = "◇ 放下冰红茶才能冲刺" if player.combat.carrying() else "◆ 冲刺就绪" if player.dash_available() else "◇ 冲刺恢复中" if player.is_on_floor() else "◇ 落地恢复冲刺"


func _switch_arena() -> void:
	KeyBindings.release_gameplay_inputs()
	get_tree().change_scene_to_file("res://Scenes/World.tscn" if get_parent().has_method("is_combat_arena") else "res://Scenes/CombatArena.tscn")


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	# 在 GUI 接收空格、回车、方向键之前捕获改键输入。
	if not _listening_action.is_empty():
		get_viewport().set_input_as_handled()
		if event.echo:
			return
		if event.keycode == KEY_ESCAPE:
			_stop_listening()
			_set_status("已取消，原键位保持不变。")
			return
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		var error := KeyBindings.rebind(_listening_action, _listening_slot, code)
		if not error.is_empty():
			_set_status(error + "  Esc 取消。", true)
			return
		_stop_listening()
		_set_status("键位已保存。")
	elif event.keycode == KEY_ESCAPE and not event.echo:
		get_viewport().set_input_as_handled()
		if not overlay.visible:
			open_settings()
		elif bindings_page.visible:
			show_main_page()
		else:
			close_settings()


func open_settings() -> void:
	if overlay.visible:
		return
	_was_paused = get_tree().paused
	get_tree().paused = true
	KeyBindings.release_gameplay_inputs()
	overlay.show()
	%SettingsButton.hide()
	show_main_page()


func close_settings() -> void:
	if not overlay.visible:
		return
	_stop_listening()
	overlay.hide()
	%SettingsButton.show()
	_release_focus()
	KeyBindings.release_gameplay_inputs()
	get_tree().paused = _was_paused


func show_main_page() -> void:
	_stop_listening()
	main_page.show()
	bindings_page.hide()
	%BackButton.hide()
	%RestoreButton.hide()
	%PageTitle.text = "设置"
	%OpenBindings.grab_focus()


func show_bindings() -> void:
	main_page.hide()
	bindings_page.show()
	%BackButton.show()
	%RestoreButton.show()
	%PageTitle.text = "键位设置"
	_set_status(KeyBindings.load_message if not KeyBindings.load_message.is_empty() else "修改后立即生效，并自动保存。")
	_binding_buttons["move_left"][0].grab_focus()


func _listen_for_key(action: String, slot: int) -> void:
	_listening_action = action
	_listening_slot = slot
	_release_focus()
	_refresh_bindings()
	_set_status("请按下「%s」的新按键。Esc 取消。" % KeyBindings.ACTION_LABELS[action])


func _stop_listening() -> void:
	_listening_action = ""
	KeyBindings.release_gameplay_inputs()
	_refresh_bindings()


func _restore_defaults() -> void:
	_stop_listening()
	var error := KeyBindings.restore_defaults()
	_set_status("已恢复并保存默认键位。" if error.is_empty() else error, not error.is_empty())


func _refresh_bindings() -> void:
	%GrabMode.select(1 if KeyBindings.grab_mode == "toggle" else 0)
	for action: String in _binding_buttons:
		for slot in range(2):
			var button: Button = _binding_buttons[action][slot]
			button.text = "等待按键…" if action == _listening_action and slot == _listening_slot else KeyBindings.key_label(KeyBindings.get_key(action, slot))
	%Controls.text = "移动 %s · %s    跳跃 %s（长按跳更高）    冲刺 %s\n按住 %s 抓墙，%s / %s 上下攀爬；抓墙 + 跳跃向上跳\n方向 + 冲刺：八向闪身    向下：地面蹲下 / 空中达到普通落速后快落    Esc 设置\n技巧：贴墙松开左右起跳，再按回墙面；水平 / 斜下冲刺后延迟起跳" % [
		KeyBindings.action_label("move_left"), KeyBindings.action_label("move_right"),
		KeyBindings.action_label("jump"), KeyBindings.action_label("dash"),
		KeyBindings.action_label("grab"), KeyBindings.action_label("aim_up"),
		KeyBindings.action_label("aim_down"),
	]
	if KeyBindings.grab_mode == "toggle":
		%Controls.text = %Controls.text.replace("按住 %s 抓墙" % KeyBindings.action_label("grab"), "按 %s 切换抓墙" % KeyBindings.action_label("grab"))
	if get_parent().has_method("is_combat_arena"):
		var grab_hint := "按 %s 切换抓取 / 松手；松手时按向下则放下" if KeyBindings.grab_mode == "toggle" else "按住 %s 抓墙 / 抓冰红茶；松开投掷，向下 + 松开放下"
		%Controls.text = "移动 %s · %s    跳跃 %s    冲刺 %s\n%s\n按住 %s 防御；看刀刃落到身上时按下：精准防御\n抱着冰红茶可以跳跃；先抛出再冲刺 / 抓墙。右下角切换小怪与 Boss 战。" % [
			KeyBindings.action_label("move_left"), KeyBindings.action_label("move_right"),
			KeyBindings.action_label("jump"), KeyBindings.action_label("dash"),
			grab_hint % KeyBindings.action_label("grab"),
			KeyBindings.action_label("defend"),
		]


func _change_grab_mode(index: int) -> void:
	var error := KeyBindings.set_grab_mode("toggle" if index == 1 else "hold")
	%GrabModeStatus.text = "抓取方式已保存，抓墙与冰红茶共用。" if error.is_empty() else error
	%GrabModeStatus.modulate = Color(0.55, 0.84, 0.86) if error.is_empty() else Color(1.0, 0.68, 0.58)
	%GrabMode.select(1 if KeyBindings.grab_mode == "toggle" else 0)


func _set_status(message: String, is_error: bool = false) -> void:
	status_label.text = message
	status_label.modulate = Color(1.0, 0.68, 0.58) if is_error else Color(0.55, 0.84, 0.86)


func _release_focus() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused:
		focused.release_focus()
