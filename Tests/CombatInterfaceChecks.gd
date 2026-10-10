# Checks new key migration, real GUI navigation and physical key rebinding.
extends "res://Tests/MovementChecks.gd"

func key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)

func click(control: Control) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = control.get_global_rect().get_center()
	motion.global_position = motion.position
	root.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.position = motion.position
	event.global_position = motion.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	await frames(1)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await frames(3)

func run_checks() -> void:
	var settings: Node = root.get_node("KeyBindings")
	settings.set("_config_path", "res://.godot/combat_keys_test.cfg")
	var defaults: Dictionary = settings.get("_defaults").duplicate(true)
	var legacy := ConfigFile.new()
	for action: String in defaults:
		if action != "defend":
			legacy.set_value("keys", action, defaults[action])
	legacy.set_value("keys", "jump", [KEY_E, 0])
	legacy.set_value("keys", "dash", [KEY_F, 0])
	legacy.save(settings.get("_config_path"))
	settings.load_bindings()
	check(settings.get_key("jump", 0) == KEY_E and settings.get_key("dash", 0) == KEY_F, "Legacy E/F bindings survive combat upgrade")
	check(settings.get_key("grab", 0) == KEY_CTRL and settings.get_key("defend", 0) != KEY_F and not InputMap.has_action("interact"), "Legacy grab survives and defense receives a free key")
	check(settings.load_message.is_empty(), "Valid legacy controls are migrated without full reset")
	settings.restore_defaults()
	world = load("res://Scenes/World.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	await frames(4)
	var ui: CanvasLayer = world.get_node("GameUI")
	await click(ui.get_node("%ArenaButton"))
	world = current_scene
	player = world.get_node("Player")
	check(world.has_method("is_combat_arena"), "Clicking the gameplay button opens the combat room")
	ui = world.get_node("GameUI")
	await click(ui.get_node("%SettingsButton"))
	var option: OptionButton = ui.get_node("%GrabMode")
	check(option.selected == 0 and settings.grab_mode == "hold", "Settings initially show hold mode")
	await click(option)
	var popup: PopupMenu = option.get_popup()
	check(popup.visible, "Grab behavior dropdown opens with a real mouse click")
	# Native popup input is owned by the OS; exercise its item activation signal headlessly.
	popup.index_pressed.emit(1)
	popup.hide()
	await frames(2)
	settings.load_bindings()
	check(settings.grab_mode == "toggle" and option.selected == 1, "Dropdown selection persists and displays toggle mode")
	settings.set_grab_mode("hold")
	await click(ui.get_node("%OpenBindings"))
	check(ui.get_node("%Rows").get_child_count() == 24, "Eight actions include one shared grab binding")
	var buttons: Dictionary = ui.get("_binding_buttons")
	var scroll: ScrollContainer = ui.get_node("%Rows").get_parent()
	for binding in [["grab", KEY_O], ["defend", KEY_P]]:
		scroll.ensure_control_visible(buttons[binding[0]][0])
		await frames(3)
		await click(buttons[binding[0]][0])
		check(ui.get("_listening_action") == binding[0], "Scrolled new action button accepts real mouse clicks")
		key(binding[1], true)
		await frames(1)
		key(binding[1], false)
		await frames(2)
		check(settings.get_key(binding[0], 0) == binding[1], "New combat action captures and persists a physical key")
	ui.close_settings()
	settings.load_bindings()
	check(settings.get_key("grab", 0) == KEY_O and settings.get_key("defend", 0) == KEY_P, "Both combat bindings survive reload")
	player.position = Vector2(146, 416)
	player.velocity = Vector2.ZERO
	await frames(3)
	key(KEY_O, true)
	await frames(1)
	check(player.combat.carrying(), "Rebound pickup key actually picks up NPC stock")
	key(KEY_F, true)
	await frames(1)
	key(KEY_F, false)
	check(not player.combat.guarding, "Old defense key stops controlling defense")
	key(KEY_P, true)
	await frames(1)
	key(KEY_P, false)
	check(player.combat.guarding and not player.combat.carrying(), "Rebound defense key guards and puts down the bottle")
	key(KEY_O, false)
	await frames(2)
	await click(ui.get_node("%ArenaButton"))
	world = current_scene
	check(not world.has_method("is_combat_arena") and world.get_node("Player").has_node("Combat"), "Return button restores the movement practice scene")
	check(get_nodes_in_group("enemies").is_empty() and get_nodes_in_group("tea_bottles").is_empty(), "Returning cleans up combat bodies")
	world.free()
	print("Combat interface checks complete: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
