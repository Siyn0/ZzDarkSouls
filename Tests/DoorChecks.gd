extends "res://Tests/CombatChecks.gd"

const TriggerDoor := preload("res://Scenes/Doors/TriggerDoor.tscn")
const BossDoor := preload("res://Scenes/Doors/BossDoor.tscn")
const CloseTrigger := preload("res://Scenes/Doors/DoorCloseTrigger.tscn")

func make_door(at: Vector2) -> Node2D:
	var door := TriggerDoor.instantiate()
	door.position = at
	world.add_child(door)
	return door

func make_trigger(at: Vector2, door: Node2D) -> Area2D:
	var trigger := CloseTrigger.instantiate()
	trigger.position = at
	trigger.region_size = Vector2(60, 120)
	trigger.door = door
	world.add_child(trigger)
	return trigger

func run_checks() -> void:
	# 从两边进入房间，用真正的玩家移动验证通行和封路。
	for direction in [1, -1]:
		await reset_stage(Vector2(-direction * 150, 600))
		var door := make_door(Vector2(0, 600))
		var trigger := make_trigger(Vector2(direction * 100, 540), door)
		await frames(3)
		check(door.is_open, "Entrance starts open, direction %s" % direction)
		var forward := "move_right" if direction == 1 else "move_left"
		var backward := "move_left" if direction == 1 else "move_right"
		press(forward)
		await seconds(1.4)
		release(forward)
		check(player.position.x * direction > 100 and not door.is_open, "Player passes the open door and entering the independent region closes it, direction %s" % direction)
		press(backward)
		await seconds(1.6)
		release(backward)
		check(player.position.x * direction > 20, "Closed door physically prevents returning, direction %s" % direction)
		check(not door.is_open, "Leaving the trigger does not reopen the door")
		# 一次性触发器不会在外部开门后反复触发。
		door.open()
		player.position.x = direction * 200
		player.velocity = Vector2.ZERO
		await frames(4)
		player.position.x = direction * 100
		await frames(4)
		check(door.is_open, "One-shot trigger is consumed after the first entry")
		trigger.free()

	await reset_stage(Vector2(0, 600))
	var door := make_door(Vector2(0, 600))
	make_trigger(Vector2(0, 540), door)
	await frames(6)
	check(door.is_open, "A player spawning inside the trigger and doorway is not trapped")
	press("move_right")
	await seconds(0.5)
	release("move_right")
	check(not door.is_open and player.position.x > 24, "Pending closure happens only after the player's whole body clears the doorway")

	await reset_stage(Vector2(-300, 600))
	door = make_door(Vector2(0, 600))
	make_trigger(Vector2(100, 540), door)
	var enemy := enemy_at(Vector2(100, 600))
	await frames(5)
	check(door.is_open, "An enemy entering the region cannot close the door")
	enemy.free()
	door.door_size = Vector2(48, 200)
	var independent := make_door(Vector2(500, 600))
	check(independent.get_node("Blocker/CollisionShape2D").shape.size == Vector2(24, 160), "Resizing one door leaves other instances unchanged")

	await reset_stage(Vector2(-150, 600))
	var boss := enemy_at(Vector2(400, 600), true)
	var boss_door := BossDoor.instantiate()
	boss_door.position = Vector2(0, 600)
	boss_door.boss = boss
	world.add_child(boss_door)
	press("move_right")
	await seconds(1)
	release("move_right")
	check(not boss_door.is_open and player.position.x < -20, "Boss door starts shut and blocks actual player movement")
	boss.take_tea_hit(1)
	await frames(3)
	check(not boss_door.is_open, "Nonlethal boss damage does not unlock the exit")
	var unrelated := enemy_at(Vector2(700, 600), true)
	unrelated.take_tea_hit(9999)
	await frames(3)
	check(not boss_door.is_open, "Defeating a different boss does not unlock this exit")
	boss.take_tea_hit(9999)
	await frames(4)
	check(boss_door.is_open and not is_instance_valid(boss), "Bound boss death unlocks the door even after the enemy is freed")
	press("move_right")
	await seconds(0.8)
	release("move_right")
	check(player.position.x > 80, "Unlocked exit allows passage to the right")
	press("move_left")
	await seconds(1.4)
	release("move_left")
	check(player.position.x < -80, "Unlocked exit also allows passage to the left")
	boss_door.close()
	await frames(4)
	check(boss_door.is_open, "A defeated boss's door stays open even if a close trigger requests closure")

	await reset_stage(Vector2(-300, 600))
	boss = enemy_at(Vector2(400, 600), true)
	boss_door = BossDoor.instantiate()
	boss_door.boss = boss
	world.add_child(boss_door)
	boss.queue_free()
	await frames(4)
	check(not boss_door.is_open, "Removing a living boss is not mistaken for defeating it")
	var unbound := BossDoor.instantiate()
	world.add_child(unbound)
	await frames(3)
	check(not unbound.is_open, "Unbound boss doors stay shut without runtime errors")

	world.free()
	OS.delay_msec(150)
	print("Door checks complete: ", checks, " checks, ", failures, " failures at ", rate, " Hz")
	quit(1 if failures else 0)
