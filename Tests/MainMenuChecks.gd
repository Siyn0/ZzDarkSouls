extends "res://Tests/MovementChecks.gd"

var storage: Node
var test_save: String

func click_button(button: Button) -> void:
	var at := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	root.push_input(motion, true)
	await frames(1)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
	await frames(1)

func menu() -> Control:
	if is_instance_valid(current_scene):
		current_scene.free()
	var screen: Control = load("res://Scenes/MainMenu.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	return screen

func run_checks() -> void:
	storage = root.get_node("SaveGame")
	test_save = "res://.godot/menu_checks_%s.json" % rate
	storage.save_path = test_save
	storage.auto_save_enabled = true
	if FileAccess.file_exists(test_save):
		DirAccess.remove_absolute(test_save)
	root.get_node("KeyBindings").set("_config_path", "res://.godot/menu_bindings_%s.cfg" % rate)
	var screen := menu()
	await frames(3)
	check(screen.get_node("%Start").text == "开始游戏" and screen.get_node("%Load").disabled, "Fresh main menu offers Start and disables Load without a save")
	check(screen.get_node("%Buttons").get_child_count() == 4, "Main menu has exactly the four requested actions")
	var ui: CanvasLayer = screen.get_node("SettingsUI")
	await click_button(screen.get_node("%Settings"))
	await frames(2)
	check(paused and ui.overlay.visible and not ui.get_node("%Vitals").visible, "Menu settings use the existing settings overlay without gameplay HUD")
	ui.get_node("%GrabMode").item_selected.emit(1)
	ui.show_bindings()
	ui._listen_for_key("jump", 0)
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = KEY_F9
	event.keycode = KEY_F9
	root.push_input(event, true)
	await frames(2)
	check(root.get_node("KeyBindings").get_key("jump", 0) == KEY_F9 and root.get_node("KeyBindings").grab_mode == "toggle", "Main menu settings really update key bindings and grab behavior")
	ui.close_settings()
	await frames(1)
	check(not paused and root.gui_get_focus_owner() == screen.get_node("%Settings"), "Closing settings returns keyboard focus and unpauses the menu")
	await click_button(screen.get_node("%Start"))
	await frames(8)
	world = current_scene
	player = world.get_node("Player")
	check(world.scene_file_path == "res://Scenes/Levels/Tutorial.tscn" and is_instance_valid(player), "Start loads the actual tutorial level")
	check(storage.inspect_save().data.checkpoint == "", "A new game immediately creates an initial-spawn save")
	var game_ui: CanvasLayer = world.get_node("GameUI")
	check(game_ui.get_node("%GrabMode").selected == 1 and game_ui._binding_buttons["jump"][0].text == "F9", "Gameplay settings share the same saved controls as the main menu")
	player.position = Vector2(395, 416)
	await frames(5)
	check(storage.inspect_save().data.checkpoint == "NPC/Checkpoint", "Walking through the first bonfire automatically writes the single save slot")
	player.position = Vector2(4087, 416)
	await frames(5)
	var saved: Dictionary = storage.inspect_save().data
	check(saved.checkpoint == "NPC/Checkpoint2" and saved.spawn[0] == 4087, "Later bonfires overwrite the same save with the latest checkpoint")
	var boss: Node2D = world.get_node("Enemy/IronGuard")
	boss.take_tea_hit(9999)
	await frames(3)
	check("Enemy/IronGuard" in storage.inspect_save().data.defeated_bosses, "Boss defeat is saved immediately without requiring another bonfire")
	game_ui.open_settings()
	game_ui.get_node("%MainMenuButton").pressed.emit()
	await frames(5)
	screen = current_scene
	check(screen.get_node("%Start").text == "继续游戏" and not screen.get_node("%Load").disabled and not paused, "Returning to the title shows Continue and enables Load")
	# 清除内存进度，确保加载靠磁盘文件而不是残留对象。
	storage._level_path = ""
	storage._defeated_bosses.clear()
	await click_button(screen.get_node("%Load"))
	await frames(8)
	world = current_scene
	player = world.get_node("Player")
	check(absf(player.position.x - 4087) < 1 and player.combat.health == 100, "Load restores the saved bonfire with a fresh living player")
	check(not world.has_node("Enemy/IronGuard") and world.get_node("BossDoor").is_open, "Disk loading preserves defeated bosses and opens their bound doors")
	check(world.get_node("NPC/Checkpoint2").active and world.get_node("TriggerDoor").is_open, "Loaded checkpoint is visibly active and entrance gates allow another approach")
	check(world.get_node("Enemy/SmallEnemy").health == 60, "Ordinary enemies restart when a saved level is loaded")
	var respawn: Node = player.get_node("Respawn")
	check(respawn.respawn_position.x == 4087, "Future deaths still use the loaded checkpoint")
	storage.return_to_menu()
	await frames(5)
	screen = current_scene
	screen.get_node("%Start").pressed.emit()
	await frames(8)
	world = current_scene
	player = world.get_node("Player")
	check(absf(player.position.x - 4087) < 1 and not world.has_node("Enemy/IronGuard"), "Continue reads the same persisted slot as Load")
	var original := FileAccess.get_file_as_string(test_save)
	storage.save_path = "res://.godot/missing_save_directory/progress.json"
	check(not storage.save_progress().is_empty() and FileAccess.get_file_as_string(test_save) == original, "A failed write reports the error without damaging the existing save")
	await frames(1)
	check(world.get_node("GameUI").get_node("%SaveNotice").visible, "A failed automatic save is visibly reported in the game")
	storage.save_path = test_save
	storage.auto_save_enabled = false
	FileAccess.open(test_save, FileAccess.WRITE).store_string("{broken save")
	screen = menu()
	await frames(2)
	check(screen.get_node("%Load").disabled and screen.get_node("%Start").disabled and not screen.get_node("%Status").text.is_empty(), "Corrupted saves show an error and cannot be silently overwritten by Start")
	check(FileAccess.get_file_as_string(test_save) == "{broken save", "Inspecting an invalid save leaves the original file untouched")
	var invalid: Dictionary = JSON.parse_string(original)
	invalid.scene = "res://Scenes/Levels/MissingLevel.tscn"
	FileAccess.open(test_save, FileAccess.WRITE).store_string(JSON.stringify(invalid))
	check(not storage.load_game().is_empty() and current_scene == screen, "Missing saved levels keep the user safely on the menu")
	DirAccess.remove_absolute(test_save)
	if FileAccess.file_exists(test_save + ".tmp"):
		DirAccess.remove_absolute(test_save + ".tmp")
	print("Main menu checks complete: ", checks, " checks, ", failures, " failures at ", rate, " Hz")
	# 真正触发退出按钮；如果按钮未接通，外部 --quit-after 会使检查不完整。
	if failures:
		quit(1)
	else:
		screen.get_node("%Quit").pressed.emit()
