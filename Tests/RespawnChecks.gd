extends "res://Tests/DoorChecks.gd"

const Checkpoint := preload("res://Scenes/NPCTriggers/Checkpoint.tscn")

func checkpoint(at: Vector2, parent: Node = null) -> Area2D:
	var point := Checkpoint.instantiate()
	point.position = at
	(parent if parent != null else world).add_child(point)
	return point

func kill_player(source: Node2D) -> void:
	root.get_node("KeyBindings").release_gameplay_inputs()
	player.combat.invulnerable_left = 0
	player._dash_time_left = 0
	player.combat.guarding = false
	player.combat.receive_attack(source, 999, 9999)

func run_checks() -> void:
	await reset_stage(Vector2(-300, 600))
	var enemy := enemy_at(Vector2(700, 600))
	var original_jump: float = player.jump_speed
	player.position.x = 200
	kill_player(enemy)
	await seconds(0.25)
	check(player.combat.dead, "Death has a short visible delay before automatic respawn")
	await seconds(0.85)
	check(not player.combat.dead and absf(player.position.x + 300) < 1, "Before any checkpoint, death returns to the initial level spawn")
	check(player.combat.health == 100 and player.stamina == player.max_stamina and player.dash_available(), "Respawn restores health, stamina, and dash")
	check(player.jump_speed == original_jump and player.combat.invulnerable_left > 0, "Respawn preserves movement tuning and gives brief protection")

	var first := checkpoint(Vector2(0, 600))
	var second := checkpoint(Vector2(400, 600))
	player.position = Vector2(0, 600)
	await frames(5)
	check(first.active and player.get_node("Respawn").active_checkpoint == first, "Walking into a bonfire activates it without a button")
	player.position.x = 400
	await frames(5)
	check(second.active and not first.active, "The latest visited bonfire replaces the previous one")
	# 在离第一个篝火更近的位置死亡，仍然必须回到最后激活的第二个。
	player.position.x = 80
	player.stamina = 0
	player._air_dash_used = true
	player._wall_boost_left = 1
	player._dash_attack_left = 1
	player._set_ducking(true)
	kill_player(enemy)
	paused = true
	await seconds(1.2)
	check(player.combat.dead, "Pause settings suspend the respawn countdown")
	paused = false
	await seconds(1.1)
	check(absf(player.position.x - 400) < 1 and not player.combat.dead, "Respawn chooses the last visited bonfire rather than the closest one to death")
	check(not player.is_ducking and not player.is_climbing and player._wall_boost_left == 0 and player._dash_attack_left == 0, "Respawn clears crouching, climbing, and advanced movement windows")
	player.position.x = 0
	await frames(5)
	check(first.active and not second.active, "Revisiting an older checkpoint makes it the current spawn again")
	player.position.x = 200
	await frames(5)
	first.free()
	kill_player(enemy)
	await seconds(1.1)
	check(absf(player.position.x) < 1 and not player.combat.dead, "A removed checkpoint leaves its last recorded spawn position usable")

	await reset_stage(Vector2(-300, 600))
	var container := Node2D.new()
	container.position = Vector2(1000, 100)
	world.add_child(container)
	var translated := checkpoint(Vector2(0, 500), container)
	translated.spawn_offset = Vector2(20, -2)
	player.position = Vector2(1000, 600)
	await frames(5)
	check(player.get_node("Respawn").respawn_position.is_equal_approx(Vector2(1020, 598)), "Checkpoint spawn offsets use global coordinates under translated parents")
	enemy = enemy_at(Vector2(-500, 600))
	var camera: Camera2D = load("res://Scenes/LevelCamera.tscn").instantiate()
	world.add_child(camera)
	player.position.x = -300
	kill_player(enemy)
	await seconds(1.1)
	check(absf(player.position.x - 1020) < 1 and absf(camera.global_position.x - player.position.x) < 2, "Respawn teleports both player and following camera to the checkpoint")

	await reset_stage(Vector2(-300, 600))
	var entrance := make_door(Vector2(0, 600))
	make_trigger(Vector2(100, 540), entrance)
	var boss := enemy_at(Vector2(500, 600), true)
	var exit := BossDoor.instantiate()
	exit.position = Vector2(800, 600)
	exit.boss = boss
	world.add_child(exit)
	player.position.x = 100
	await frames(5)
	check(not entrance.is_open, "Entering the arena closes its entrance")
	boss.take_tea_hit(30)
	boss.position.x = 400
	kill_player(boss)
	await seconds(1.1)
	check(entrance.is_open and not exit.is_open, "Death resets the entrance while the undefeated boss exit stays shut")
	check(boss.health == boss.max_health and absf(boss.position.x - 500) < 1, "A surviving boss returns home with full health for the next attempt")
	player.position.x = 100
	await frames(5)
	check(not entrance.is_open, "The entrance trigger rearms and closes on the next attempt")
	boss.take_tea_hit(9999)
	await frames(3)
	enemy = enemy_at(Vector2(600, 600))
	kill_player(enemy)
	await seconds(1.1)
	check(exit.is_open and not is_instance_valid(boss), "Defeated bosses remain defeated and their exit doors stay open after player death")

	await arena_stage(true)
	var arena_boss: Node2D = get_nodes_in_group("enemies")[0]
	kill_player(arena_boss)
	await seconds(1.1)
	check(not player.combat.dead and world.mode == "boss" and world.supplier.active, "Practice boss mode and airplane supplies resume after automatic respawn")
	world.free()
	OS.delay_msec(150)
	print("Respawn checks complete: ", checks, " checks, ", failures, " failures at ", rate, " Hz")
	quit(1 if failures else 0)
