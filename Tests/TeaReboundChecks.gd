extends "res://Tests/CombatChecks.gd"

func throw_at_wall() -> CharacterBody2D:
	await reset_stage(Vector2(450, 300), 1)
	var tea := bottle(Vector2(470, 275))
	player.combat.held_tea = tea
	tea.pick_up(player)
	player.combat.throw_tea()
	for i in range(rate):
		await frames(1)
		if tea._wall_pause_left > 0:
			break
	return tea

func run_checks() -> void:
	var tea: CharacterBody2D = await throw_at_wall()
	check(tea._wall_pause_left > 0 and tea.velocity.x < 0, "A real wall collision schedules a rebound toward the player")
	var impact_position := tea.position
	await seconds(0.06)
	check(tea.position.distance_to(impact_position) < 0.1 and tea.can_pick_up(), "Wall impact pauses the bottle and removes its initial pickup lock")
	await seconds(0.12)
	check(tea.position.x < impact_position.x and absf(tea.velocity.x) <= tea.wall_rebound_speed + 1, "Bottle rebounds at its adjustable slower speed after the pause")
	check(tea.position.y < impact_position.y, "Rebound lifts the bottle and briefly delays gravity")

	for mode: String in ["hold", "toggle"]:
		tea = await throw_at_wall()
		root.get_node("KeyBindings").grab_mode = mode
		await seconds(0.04)
		var start_y := player.position.y
		press("aim_up")
		press("dash")
		press("grab")
		await frames(2)
		check(player._dash_time_left > 0 and player.combat.carrying(), "Up + dash + grab together starts a dash and catches the rebounding bottle in " + mode)
		await seconds(0.12)
		check(player.combat.held_tea == tea and tea.holder == player and player.position.y < start_y - 30, "Player and caught bottle move upward together in " + mode)
		await seconds(0.1)
		check(player.velocity.y < 0 and player._air_dash_used and not player.dash_available(), "Catching retains upward momentum without granting another dash in " + mode)
		release("dash")
		if mode == "hold":
			release("grab")
		else:
			release("grab")
			await frames(1)
			press("grab")
		await frames(2)
		check(not player.combat.carrying() and tea.armed, "The caught bottle can be thrown again in " + mode)

	await reset_stage(Vector2(450, 300), 1)
	tea = bottle(Vector2(525, 280))
	press("aim_up")
	press("dash")
	press("grab")
	await frames(3)
	check(not player.combat.carrying(), "Dash grabbing still cannot reach through a wall")
	world.free()
	OS.delay_msec(150)
	print("Tea rebound checks complete: ", checks, " checks, ", failures, " failures at ", rate, " Hz")
	quit(1 if failures else 0)
