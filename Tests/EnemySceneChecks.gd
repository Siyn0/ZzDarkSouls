# Checks the same PackedScenes a level designer drags into a custom level.
extends "res://Tests/CombatChecks.gd"

func place_enemy(at: Vector2) -> CharacterBody2D:
	var enemy := Enemy.instantiate()
	enemy.position = at
	world.add_child(enemy)
	return enemy

func run_checks() -> void:
	await reset_stage()
	var first := Enemy.instantiate()
	first.display_name = "门口保安"
	first.max_health = 90
	first.attack_damage = 7
	first.move_speed = 120
	first.body_size = Vector2(34, 50)
	first.position = Vector2(65, 600)
	world.add_child(first)
	var second := place_enemy(Vector2(800, 600))
	check(first.target == player and second.target == player, "Placed scenes automatically find the player without arena code")
	check(first.health == 90 and second.health == 60, "Per-instance health overrides initialize independently")
	check(first.get_node("NameLabel").text == "门口保安", "Inspector name appears on the enemy")
	check(first.get_node("CollisionShape2D").shape.size == Vector2(34, 50) and second.get_node("CollisionShape2D").shape.size == Vector2(26, 42), "Body overrides create independent matching collision shapes")
	await seconds(1.5)
	check(player.combat.health == 93, "Autonomous enemy uses its configured damage on actual blade contact")
	check(is_equal_approx(second.position.x, 800), "An enemy outside awareness stays at its placed location")
	second.position.x = 200
	await frames(2)
	check(second.velocity.x < 0, "Entering awareness starts pursuit")
	second.display_name = "巡逻保安"
	check(second.get_node("NameLabel").text == "巡逻保安", "Name preview updates when the property changes")
	first.take_tea_hit(30)
	check(first.health == 60 and second.health == 60, "Tea damage only affects its own enemy instance")
	first.take_tea_hit(100)
	await frames(2)
	check(not is_instance_valid(first) and is_instance_valid(second), "Enemy death frees only that enemy")
	player.free()
	await seconds(0.6)
	check(not is_instance_valid(second.target) and second.velocity.x == 0, "Missing player safely stops enemy AI")
	player = load("res://Scenes/Player.tscn").instantiate()
	player.position = Vector2(0, 600)
	world.add_child(player)
	await seconds(0.6)
	check(second.target == player, "An existing enemy finds a newly spawned replacement player")

	await reset_stage()
	var boss := Boss.instantiate()
	boss.position = Vector2(200, 600)
	world.add_child(boss)
	check(boss.boss and boss.health == 300 and boss.attack_damage == 25, "Inherited boss scene retains its own combat tuning")
	check(boss.get_node("CollisionShape2D").shape.size == Vector2(40, 72) and boss.get_node("NameLabel").text == "铁罐守卫", "Inherited boss has correct preview name and collision size")

	await reset_stage()
	player.combat.max_health = 100000
	player.combat.health = 100000
	var crowd: Array[CharacterBody2D] = []
	for i in range(99):
		crowd.append(place_enemy(Vector2(-1470 + i * 30, 600)))
	await seconds(2)
	check(get_nodes_in_group("enemies").size() == 99, "A custom level runs 99 placed enemy scene instances")
	var all_target := true
	var shapes := {}
	for enemy in crowd:
		all_target = all_target and enemy.target == player
		shapes[enemy.get_node("CollisionShape2D").shape.get_instance_id()] = true
	check(all_target and shapes.size() == 99, "All 99 enemies find the player and own separate collision shapes")
	check(player.combat.health < 100000, "Nearby enemies in the crowd actually attack")
	for i in range(0, 99, 2):
		crowd[i].take_tea_hit(100)
	await frames(2)
	check(get_nodes_in_group("enemies").size() == 49, "Multiple simultaneous deaths preserve surviving crowd instances")
	world.free()
	OS.delay_msec(150)
	print("Enemy scene checks complete: ", checks, " checks, ", failures, " failures at ", rate, " Hz")
	quit(1 if failures else 0)
