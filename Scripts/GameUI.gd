extends CanvasLayer

## 练习场使用的跳转入口；正式关卡默认隐藏，入口只出现在暂停菜单。
@export var show_practice_link: bool = false
## 默认使用简洁的条形显示；需要精确读数时可开启。
@export var show_resource_numbers: bool = false
var _binding_buttons: Dictionary = {}
var _listening_action: String = ""
var _listening_slot: int = 0
var _was_paused: bool = false

@onready var overlay: Control = %Overlay
@onready var main_page: Control = %MainPage
@onready var bindings_page: Control = %BindingsPage
@onready var status_label: Label = %Status
var player: CharacterBody2D


func _ready() -> void:
	%HealthLabel.visible = show_resource_numbers
	%StaminaLabel.visible = show_resource_numbers
	%CloseButton.pressed.connect(close_settings)
	%ResumeButton.pressed.connect(close_settings)
	%OpenBindings.pressed.connect(show_bindings)
	%BackButton.pressed.connect(show_main_page)
	%RestoreButton.pressed.connect(_restore_defaults)
	%GrabMode.add_item("按住抓取（默认）")
	%GrabMode.add_item("按一下切换")
	%GrabMode.item_selected.connect(_change_grab_mode)
	%ArenaButton.pressed.connect(_switch_arena)
	%ArenaButton.visible = show_practice_link
	%ArenaButton.text = "返回练习场" if get_parent().has_method("is_combat_arena") else "战斗试验场"
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
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	%Vitals.visible = is_instance_valid(player)
	if not is_instance_valid(player):
		%RegionHint.hide()
		return
	%Health.max_value = player.combat.max_health
	%Health.value = player.combat.health
	%HealthLabel.text = "生命  %d / %d" % [player.combat.health, player.combat.max_health]
	%Stamina.max_value = player.max_stamina
	%Stamina.value = player.stamina
	var tired: bool = player.stamina < player.tired_threshold
	%StaminaLabel.text = "体力  %d / %d%s" % [ceili(maxf(0.0, player.stamina)), ceili(player.max_stamina), "  · 即将力竭" if tired else ""]
	
	_update_region_hint()


func _update_region_hint() -> void:
	var chosen: Area2D
	for area: Area2D in get_tree().get_nodes_in_group("text_hint_areas"):
		if not area.enabled or area.message.strip_edges().is_empty() or not area.overlaps_body(player):
			continue
		if chosen == null or area.hint_priority > chosen.hint_priority or (area.hint_priority == chosen.hint_priority and area.entered_frame >= chosen.entered_frame):
			chosen = area
	%RegionHint.visible = chosen != null
	%HintText.text = chosen.message if chosen != null else ""


func _switch_arena() -> void:
	close_settings()
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
	show_main_page()


func close_settings() -> void:
	if not overlay.visible:
		return
	_stop_listening()
	overlay.hide()
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


func _change_grab_mode(index: int) -> void:
	var error := KeyBindings.set_grab_mode("toggle" if index == 1 else "hold")
	%GrabModeStatus.text = "抓取方式已保存，抓墙与冰红茶共用。" if error.is_empty() else error
	%GrabModeStatus.modulate = Color(0.85, 0.79, 0.61) if error.is_empty() else Color(1.0, 0.68, 0.58)
	%GrabMode.select(1 if KeyBindings.grab_mode == "toggle" else 0)


func _set_status(message: String, is_error: bool = false) -> void:
	status_label.text = message
	status_label.modulate = Color(1.0, 0.68, 0.58) if is_error else Color(0.85, 0.79, 0.61)


func _release_focus() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused:
		focused.release_focus()
