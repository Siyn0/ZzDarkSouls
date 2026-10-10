# Shared hold/toggle grab and actual animated blade contacts, at 60 / 120 Hz.
extends "res://Tests/CombatChecks.gd"

func begin_swing(boss: bool = false) -> CharacterBody2D:
	await reset_stage()
	var enemy := enemy_at(Vector2(105 if boss else 65, 600), boss)
	enemy.attacks_enabled = true
	enemy.phase = "windup"
	enemy.phase_left = 0
	await frames(1)
	return enemy

func run_checks() -> void:
	var settings: Node = root.get_node("KeyBindings")
	settings.set("_config_path", "res://.godot/grab_test_%s.cfg" % rate)
	await reset_stage()
	press("grab")
	await frames(2)
	var tea := bottle(Vector2(20, 580))
	await frames(2)
	check(player.combat.carrying(), "Pre-held grab automatically catches a bottle entering reach")
	release("grab")
	press("move_left")
	await frames(1)
	check(not player.combat.carrying() and tea.armed and tea.velocity.x < 0, "Release throws in the direction pressed on that frame")

	await reset_stage(Vector2(489.9, 250), 1)
	press("grab")
	await seconds(0.1)
	check(player.is_climbing, "Shared hold key grabs the wall")
	tea = bottle(player.position + Vector2(-15, -20))
	await frames(2)
	check(player.combat.carrying() and not player.is_climbing, "A reachable bottle takes priority over climbing")

	await reset_stage(Vector2(489.9, 250), 1)
	settings.set_grab_mode("toggle")
	press("grab")
	await frames(1)
	release("grab")
	await seconds(0.1)
	check(player.is_climbing, "Toggle keeps wall grip after key release")
	press("grab")
	await frames(1)
	check(not player.is_climbing, "Second toggle lets go of the wall")

	await reset_stage()
	settings.set_grab_mode("toggle")
	tea = bottle(Vector2(20, 580))
	await frames(1)
	press("grab")
	await frames(1)
	release("grab")
	await frames(2)
	check(player.combat.carrying(), "Toggle keeps tea in hand after key release")
	press("aim_down")
	press("grab")
	await frames(1)
	check(not player.combat.carrying() and not tea.armed, "Down and second toggle gently put tea down")

	for mode: String in ["hold", "toggle"]:
		await arena_stage()
		settings.set_grab_mode(mode)
		player.position = Vector2(146, 416)
		player.velocity = Vector2.ZERO
		await frames(2)
		press("grab")
		await frames(1)
		check(player.combat.carrying(), "Arena pickup in " + mode)
		var ui: CanvasLayer = world.get_node("GameUI")
		ui.open_settings()
		release("grab")
		await frames(2)
		ui.close_settings()
		await frames(2)
		check(player.combat.carrying(), "Closing the menu does not throw tea in " + mode)
		press("grab")
		await frames(1)
		if mode == "hold":
			check(player.combat.carrying(), "Holding again after menu resumes ordinary hold control")
			release("grab")
			await frames(1)
		check(not player.combat.carrying(), "Grab release / second press works after menu in " + mode)

	await reset_stage()
	tea = bottle(Vector2(20, 580))
	await frames(1)
	press("grab")
	await frames(1)
	settings.set_grab_mode("toggle")
	press("grab")
	await frames(1)
	check(not player.combat.carrying() and tea.armed, "First toggle on the exact resume frame releases carried tea")

	settings.set_grab_mode("toggle")
	settings.rebind("grab", 0, KEY_O)
	settings.load_bindings()
	check(settings.grab_mode == "toggle" and settings.get_key("grab", 0) == KEY_O, "Mode and shared key survive save, rebind and reload")
	settings.restore_defaults()
	check(settings.grab_mode == "toggle", "Restoring key defaults preserves grab behavior")
	var saved_path: String = settings.get("_config_path")
	settings.set("_config_path", "res://.godot/missing_grab_test_dir/settings.cfg")
	check(not settings.set_grab_mode("hold").is_empty() and settings.grab_mode == "toggle", "Failed save keeps the previous grab mode")
	settings.set("_config_path", saved_path)
	var legacy := ConfigFile.new()
	for action: String in settings.get("_defaults"):
		legacy.set_value("keys", action, settings.get("_defaults")[action])
	legacy.set_value("keys", "grab", [KEY_O, 0])
	legacy.set_value("keys", "interact", [KEY_P, 0])
	legacy.save(saved_path)
	settings.load_bindings()
	check(settings.grab_mode == "hold" and settings.get_key("grab", 0) == KEY_O, "Old separate pickup config migrates to hold while preserving wall-grab key")
	settings.restore_defaults()

	for boss: bool in [false, true]:
		var label := "Boss" if boss else "Small enemy"
		var enemy := await begin_swing(boss)
		check(enemy.phase == "swing" and player.combat.health == 100, label + " does not hit at windup completion")
		var impact_frame := 0
		for i in range(rate):
			await frames(1)
			if player.combat.health < 100:
				impact_frame = i + 1
				break
		check(impact_frame > roundi(rate * 0.16), label + " blade travels before actually contacting the player")
		check(player.combat.health == (75 if boss else 82), label + " real blade contact deals expected damage")
		await seconds(0.4)
		check(player.combat.health == (75 if boss else 82), label + " cannot hit twice in the same swing")

		enemy = await begin_swing(boss)
		press("defend")
		await frames(impact_frame + 2)
		check(player.combat.last_result == "block", label + " defense at swing start expires to ordinary block")

		enemy = await begin_swing(boss)
		await frames(maxi(0, impact_frame - 1))
		press("defend")
		await frames(2)
		check(player.combat.last_result == "parry" and enemy.phase == "stagger", label + " defense at contact parries and interrupts the swing")

		enemy = await begin_swing(boss)
		player.position.x = -200
		await seconds(0.4)
		check(player.combat.health == 100, label + " cannot hit a player who moved out of blade reach")

		enemy = await begin_swing(boss)
		solid("SwordWall", Vector2(30, 500), Vector2(6, 200))
		await seconds(0.4)
		check(player.combat.health == 100, label + " cannot strike through a wall")

	world.free()
	OS.delay_msec(150)
	print("Grab and timing checks complete: ", checks, " checks, ", failures, " failures at ", rate, " Hz")
	quit(1 if failures else 0)
