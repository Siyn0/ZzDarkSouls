extends "res://Tests/CombatChecks.gd"

func run_checks() -> void:
	await reset_stage(Vector2(-500, 600))
	var pile: Array[Node2D] = []
	for i in range(12):
		pile.append(bottle(Vector2(0, 540)))
	await seconds(5)
	var positions: Array[float] = []
	for tea in pile:
		positions.append(tea.position.x)
	positions.sort()
	check(positions[-1] - positions[0] > 100, "Twelve bottles landing together visibly spread across the ground")
	check(positions[0] >= -pile[0].landing_spread_radius - 1 and positions[-1] <= pile[0].landing_spread_radius + 1, "The pile stays within the configured small landing radius")
	var unique_positions: Array[int] = []
	for x in positions:
		if not roundi(x) in unique_positions:
			unique_positions.append(roundi(x))
	check(unique_positions.size() >= 10, "Most stocked bottles remain individually visible instead of occupying one pixel position")
	var snapshot: Array[Vector2] = []
	for tea in pile:
		snapshot.append(tea.position)
	await seconds(3)
	var stable := true
	for i in range(pile.size()):
		stable = stable and pile[i].position.distance_to(snapshot[i]) < 0.1
	check(stable, "Settled bottles stop moving instead of endlessly pushing each other")
	player.position = Vector2(pile[0].position.x, 600)
	press("grab")
	await frames(2)
	check(player.combat.carrying(), "A spread-out bottle is still collectible")
	release("grab")
	await frames(1)
	check(not player.combat.carrying(), "A collected bottle still throws normally")

	await reset_stage(Vector2(-500, 600))
	world.get_node("Floor").free()
	solid("Shelf", Vector2(0, 616), Vector2(100, 32))
	for i in range(8):
		bottle(Vector2(30, 560))
	await seconds(5)
	var safe := true
	for tea in get_nodes_in_group("tea_bottles"):
		safe = safe and absf(tea.position.x) < 50 and tea.position.y < 600
	check(safe, "Spreading never pushes a bottle off a narrow shelf")

	await reset_stage(Vector2(-500, 600))
	solid("Wall", Vector2(40, 520), Vector2(20, 160))
	for i in range(8):
		bottle(Vector2(0, 550))
	await seconds(5)
	safe = true
	for tea in get_nodes_in_group("tea_bottles"):
		safe = safe and tea.position.x < 17
	check(safe, "World collision prevents spreading through a wall")

	await reset_stage(Vector2(-500, 600))
	var single := bottle(Vector2(0, 540))
	await seconds(3)
	check(absf(single.position.x) < 0.1, "An isolated supply bottle stays at its original pickup spot")
	var disabled := bottle(Vector2(0, 540))
	disabled.landing_spread_radius = 0
	await seconds(3)
	check(absf(disabled.position.x) < 0.1, "Zero landing radius disables scattering")
	world.free()
	OS.delay_msec(150)
	print("Tea spread checks complete: ", checks, " checks, ", failures, " failures at ", rate, " Hz")
	quit(1 if failures else 0)
