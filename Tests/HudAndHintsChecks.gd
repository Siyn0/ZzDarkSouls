extends "res://Tests/CombatChecks.gd"

const HintArea := preload("res://Scenes/Triggers/TextHintArea.tscn")
const HUD_PATH := "res://Scenes/GameUI.tscn"

func hint(at: Vector2, text: String, size: Vector2 = Vector2(120, 100)) -> Area2D:
	var area := HintArea.instantiate()
	area.position = at
	area.message = text
	area.region_size = size
	world.add_child(area)
	return area

func escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)
	await frames(1)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await frames(1)

func run_checks() -> void:
	await reset_stage()
	var ui: CanvasLayer = load(HUD_PATH).instantiate()
	world.add_child(ui)
	await frames(2)
	check(ui.player == player and ui.get_node("%Health").value == 100, "Standalone HUD finds the player and displays 100 initial health")
	check(not ui.has_node("Screen/SettingsButton"), "Gameplay HUD has no settings button")
	check(not ui.get_node("%ArenaButton").visible, "Custom levels hide practice navigation by default")
	var enemy := enemy_at(Vector2(65, 600))
	enemy.attacks_enabled = true
	enemy.phase = "windup"
	enemy.phase_left = 0
	await seconds(0.4)
	check(player.combat.health == 82 and ui.get_node("%Health").value == 82, "Real enemy blade contact immediately reduces the health bar from 100 to 82")
	check(ui.get_node("%HealthLabel").text == "生命  82 / 100", "Health label reports actual combat health")
	enemy.attacks_enabled = false
	await seconds(0.6)
	player._face(1)
	press("defend")
	await seconds(0.25)
	player.combat.receive_attack(enemy, 100, 18)
	await frames(2)
	check(player.combat.last_result == "block" and ui.get_node("%Health").value == 82, "Successful guard does not falsely drain the health bar")
	release("defend")
	await frames(1)
	player.combat.receive_attack(enemy, 101, 999)
	await frames(2)
	check(player.combat.dead and ui.get_node("%Health").value == 0, "Lethal damage clamps the health bar at zero")
	player.free()
	await frames(2)
	check(not ui.get_node("%Vitals").visible, "HUD safely waits while no player exists")
	player = load("res://Scenes/Player.tscn").instantiate()
	player.position = Vector2(0, 600)
	world.add_child(player)
	await frames(2)
	check(ui.player == player and ui.get_node("%Health").value == 100, "Replacement player restores health display without stale references")
	enemy.free()
	await escape()
	check(paused and ui.get_node("%Overlay").visible, "Esc opens settings and pauses gameplay")
	await escape()
	check(not paused and not ui.get_node("%Overlay").visible, "Esc again closes settings and resumes gameplay")

	var first := hint(Vector2(250, 560), "第一条提示\n支持换行")
	var second := hint(Vector2(300, 560), "第二条提示")
	await frames(3)
	check(not ui.get_node("%RegionHint").visible, "No hint is visible while player is outside the areas")
	player.position = Vector2(205, 600)
	player.velocity = Vector2.ZERO
	await frames(5)
	check(ui.get_node("%HintText").text == first.message and ui.get_node("%RegionHint").visible, "Entering the area displays its multiline text")
	player.position.x = 280
	await frames(5)
	check(ui.get_node("%HintText").text == second.message, "Latest entry wins when overlapping hints have equal priority")
	first.hint_priority = 10
	await frames(2)
	check(ui.get_node("%HintText").text == first.message, "Higher-priority hint wins in an overlapping area")
	player.position.x = 345
	await frames(5)
	check(ui.get_node("%HintText").text == second.message, "Leaving the higher-priority area restores the remaining hint")
	second.enabled = false
	await frames(2)
	check(not ui.get_node("%RegionHint").visible, "Disabling an occupied area hides its hint")
	second.enabled = true
	second.message = "修改后的文字"
	await frames(2)
	check(ui.get_node("%HintText").text == "修改后的文字", "Re-enabled occupied area shows updated text")
	second.free()
	await frames(2)
	check(not ui.get_node("%RegionHint").visible, "Deleting an occupied area clears the hint safely")
	first.region_size = Vector2(600, 100)
	var third := hint(Vector2(900, 560), "远处提示")
	await frames(3)
	check(ui.get_node("%HintText").text == first.message, "Resizing an area updates the actual detection range")
	check(third.get_node("CollisionShape2D").shape.size == Vector2(120, 100), "Area instances do not share mutable collision dimensions")
	player.position.x = 700
	await frames(5)
	check(not ui.get_node("%RegionHint").visible, "Leaving every area hides the hint")
	var bystander := enemy_at(Vector2(900, 600))
	await frames(3)
	check(not ui.get_node("%RegionHint").visible, "Enemies entering a trigger do not show player hints")
	bystander.free()

	await reset_stage(Vector2(489.9, 250), 1)
	ui = load(HUD_PATH).instantiate()
	world.add_child(ui)
	press("grab")
	press("aim_up")
	await seconds(0.5)
	player.set_physics_process(false)
	await frames(2)
	check(player.is_climbing and ui.get_node("%Stamina").value < 110 and is_equal_approx(ui.get_node("%Stamina").value, player.stamina), "Climbing drains the actual stamina shown by the green bar")
	player.set_physics_process(true)
	release("grab")
	release("aim_up")
	player.position = Vector2(0, 600)
	player.velocity = Vector2.ZERO
	await frames(3)
	check(ui.get_node("%Stamina").value == player.max_stamina, "Landing restores the green bar")

	world.free()
	world = load("res://Scenes/Levels/Tutorial.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	await frames(3)
	check(world.get_node("GameUI").player == world.get_node("Player"), "User's Tutorial scene includes a working HUD")
	world.free()
	OS.delay_msec(150)
	print("HUD and hints checks complete: ", checks, " checks, ", failures, " failures at ", rate, " Hz")
	quit(1 if failures else 0)
