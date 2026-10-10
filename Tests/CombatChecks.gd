# Godot --headless --path . --script res://Tests/CombatChecks.gd --fixed-fps 60 -- 60
extends "res://Tests/MovementChecks.gd"

const Tea := preload("res://Scripts/Combat/IcedTea.gd")
const Enemy := preload("res://Scripts/Combat/TrainingEnemy.gd")

func bottle(at: Vector2) -> CharacterBody2D:
	var tea := Tea.new()
	tea.position = at
	world.add_child(tea)
	return tea

func enemy_at(at: Vector2, boss: bool = false) -> CharacterBody2D:
	var enemy := Enemy.new()
	enemy.position = at
	enemy.boss = boss
	enemy.target = player
	enemy.attacks_enabled = false
	world.add_child(enemy)
	return enemy

func arena_stage(boss: bool = false) -> void:
	for action in ["move_left", "move_right", "aim_up", "aim_down", "jump", "dash", "grab", "defend"]:
		release(action)
	if is_instance_valid(world): world.free()
	world = load("res://Scenes/CombatArena.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	if boss: world.set_mode("boss")
	player = world.player
	for enemy in get_nodes_in_group("enemies"): enemy.attacks_enabled = false
	await frames(3)

func run_checks() -> void:
	await reset_stage()
	var tea := bottle(Vector2(20, 580))
	await frames(1)
	press("grab")
	await frames(1)
	check(player.combat.carrying() and tea.holder == player, "Interaction picks up a nearby bottle")
	press("move_right")
	await seconds(0.2)
	check(player.velocity.x <= 211 and player.velocity.x >= 209, "Carrying uses Theo-like slower running")
	press("jump")
	await frames(1)
	check(player.velocity.y < 0 and player.combat.carrying(), "Can jump while carrying")
	press("dash")
	await frames(1)
	check(player.get("_dash_time_left") == 0, "Carrying blocks dash")
	release("dash")
	release("move_right")
	press("aim_down")
	release("grab")
	await frames(1)
	check(not player.combat.carrying() and not tea.armed, "Down+interaction drops without arming damage")
	check(player.combat.health == 100, "Dropping cannot hurt the player")

	await reset_stage(Vector2(489.9, 300), 1)
	tea = bottle(Vector2(480, 280))
	await frames(1)
	press("grab")
	await frames(1)
	press("grab")
	await seconds(0.1)
	check(not player.is_climbing and player.combat.carrying(), "Cannot climb while carrying")
	press("jump")
	await frames(1)
	check(player.velocity.y >= 0, "Cannot wall-jump while carrying")

	await reset_stage()
	solid("PickupWall", Vector2(20, 550), Vector2(4, 100))
	tea = bottle(Vector2(35, 580))
	await frames(2)
	press("grab")
	await frames(1)
	check(not player.combat.carrying(), "Cannot pick up through a wall")

	await reset_stage()
	var enemy := enemy_at(Vector2(160, 600))
	tea = bottle(Vector2(20, 580))
	await frames(2)
	press("grab")
	await frames(1)
	release("grab")
	await seconds(0.4)
	check(enemy.health == 30 and not is_instance_valid(tea), "Thrown bottle hits through swept collision, deals damage once and breaks")
	await seconds(0.2)
	check(enemy.health == 30, "A consumed bottle cannot damage again")

	await reset_stage()
	enemy = enemy_at(Vector2(160, 600))
	solid("ProjectileWall", Vector2(75, 520), Vector2(8, 160))
	tea = bottle(Vector2(20, 580))
	tea.pick_up(player)
	tea.release_from_hand(1, Vector2.ZERO, false)
	await seconds(0.6)
	check(enemy.health == 60 and tea.position.x < 75, "World geometry blocks thrown bottles")

	await reset_stage()
	enemy = enemy_at(Vector2(60, 600))
	press("defend")
	await frames(1)
	check(player.combat.guarding and player.combat.perfect_left > 0, "One defense key starts the perfect window and holds guard")
	var result: String = player.combat.receive_attack(enemy, 1, 18)
	check(result == "parry" and player.combat.health == 100, "Timed frontal defense prevents health damage")
	check(enemy.phase == "stagger" and enemy.posture == 40, "Perfect defense interrupts and adds enemy posture")
	check(player.combat.get("_audio").stream == load("res://Assets/Audio/parry.wav"), "Perfect defense selects the bright metal sound")
	var guard_before: float = player.combat.guard
	check(player.combat.receive_attack(enemy, 1, 18) == "ignored" and player.combat.guard == guard_before, "One enemy swing resolves only once")
	await seconds(0.22)
	result = player.combat.receive_attack(enemy, 2, 18)
	check(result == "block" and player.combat.health == 100 and player.combat.guard < 100, "Held defense becomes a normal block and consumes posture")
	check(player.combat.get("_audio").stream == load("res://Assets/Audio/block.wav"), "Normal block selects the dull metal sound")
	release("defend")
	await frames(1)
	var recovery_start: float = player.combat.guard
	await seconds(1.0)
	check(player.combat.guard > recovery_start, "Guard posture recovers after releasing defense")

	await reset_stage()
	enemy = enemy_at(Vector2(60, 600))
	press("defend")
	await frames(1)
	player.combat.receive_attack(enemy, 1, 18)
	release("defend")
	await frames(1)
	press("defend")
	await frames(1)
	check(player.combat.receive_attack(enemy, 2, 18) == "block", "Rapid repressing does not repeatedly refresh perfect defense")

	await reset_stage()
	enemy = enemy_at(Vector2(-60, 600))
	press("defend")
	await frames(1)
	check(player.combat.receive_attack(enemy, 1, 18) == "hurt" and player.combat.health == 82, "A frontal guard does not block attacks from behind")
	check(player.combat.receive_attack(enemy, 2, 18) == "evaded" and player.combat.health == 82, "Hurt invulnerability prevents overlapping multi-hits")

	await reset_stage()
	enemy = enemy_at(Vector2(60, 600))
	press("defend")
	await seconds(0.2)
	player.combat.guard = 10
	check(player.combat.receive_attack(enemy, 1, 18) == "hurt" and player.combat.guard == 0, "Empty posture causes guard break and damage")
	check(player.combat.hitstun_left >= 0.6 and not player.combat.guarding, "Guard break leaves a recovery opening")
	await seconds(0.7)
	player.combat.health = 1
	release("defend")
	await frames(1)
	player.combat.receive_attack(enemy, 2, 18)
	check(player.combat.dead and player.combat.health == 0, "Lethal damage enters defeat state")
	press("dash")
	press("jump")
	await frames(2)
	check(player.get("_dash_time_left") == 0 and not player.combat.guarding, "Defeated player cannot attack, jump or guard")

	await reset_stage()
	tea = bottle(Vector2(20, 580))
	player.combat.held_tea = tea
	tea.pick_up(player)
	press("defend")
	await frames(1)
	check(player.combat.guarding and not player.combat.carrying() and not tea.armed, "Defense safely puts down the carried bottle")

	await arena_stage()
	check(get_nodes_in_group("enemies").size() == 1, "Small-enemy room creates a target")
	check(get_nodes_in_group("tea_bottles").size() == 1, "Fixed NPC stocks a bottle")
	for i in range(3):
		var stock: Node2D = world.supplier.stock
		stock.free()
		await seconds(1.1)
		check(is_instance_valid(world.supplier.stock), "NPC replenishes an exhausted stock repeatedly %s" % i)
	for i in range(20):
		world.spawn_tea(Vector2(250 + i, 350))
	check(get_nodes_in_group("tea_bottles").size() <= 10, "Unlimited resupply does not accumulate unlimited physics bodies")
	var old_player := player.get_instance_id()
	player.combat.health = 1
	world.reset_round()
	player = world.player
	await frames(1)
	check(player.get_instance_id() != old_player and player.combat.health == 100, "Retry restores player state without stale references")
	check(get_nodes_in_group("enemies").size() == 1 and get_nodes_in_group("tea_bottles").size() == 1, "Retry clears old enemies and bottles")
	var reference: Node2D = load("res://Scenes/World.tscn").instantiate()
	check(player.jump_speed == reference.get_node("Player").jump_speed and is_equal_approx(player.gravity_scale, reference.get_node("Player").gravity_scale), "Combat scene inherits the user's current movement tuning")
	reference.free()

	await arena_stage(true)
	check(world.supplier.flying, "Boss mode swaps fixed resupply for an airplane")
	await seconds(2)
	check(get_nodes_in_group("tea_bottles").size() >= 2 and world.supplier.dropped, "Airplane actually drops a collectible bottle during boss battle")
	var ui: CanvasLayer = world.get_node("GameUI")
	ui.open_settings()
	var plane_at: Vector2 = world.supplier.position
	var health_before: int = player.combat.health
	var supply_count := get_nodes_in_group("tea_bottles").size()
	await seconds(1)
	check(world.supplier.position == plane_at and get_nodes_in_group("tea_bottles").size() == supply_count and player.combat.health == health_before, "Settings pause freezes combat, projectiles and air supply")
	ui.close_settings()
	for boss_enemy in get_nodes_in_group("enemies"):
		boss_enemy.take_tea_hit(300)
	await frames(2)
	check(world.completed and not world.supplier.active and get_nodes_in_group("enemies").is_empty(), "Boss defeat ends the encounter and stops resupply")
	world.reset_round()
	player = world.player
	await frames(1)
	check(world.mode == "boss" and not world.completed and world.supplier.active, "Boss retry restarts the same encounter")

	# 验证真正的敌人蓄力 -> 命中流程，不只直接调用伤害接口。
	await reset_stage()
	enemy = enemy_at(Vector2(65, 600))
	enemy.attacks_enabled = true
	press("defend")
	await seconds(1.5)
	check(player.combat.last_result == "block" and player.combat.health == 100, "Enemy AI windup and strike produce a real normal block")
	await reset_stage()
	enemy = enemy_at(Vector2(65, 600))
	enemy.attacks_enabled = true
	for i in range(rate * 3):
		await frames(1)
		if enemy.phase == "swing" and enemy.swing_elapsed > 0.10:
			press("defend")
			break
	await seconds(0.15)
	check(player.combat.last_result == "parry" and enemy.phase == "stagger", "Timed input against an actual enemy strike produces a perfect defense")
	await reset_stage()
	enemy = enemy_at(Vector2(65, 600))
	enemy.attacks_enabled = true
	await seconds(1.5)
	check(player.combat.health < 100, "An undefended actual enemy strike deals damage")

	var dull: AudioStreamWAV = load("res://Assets/Audio/block.wav")
	var bright: AudioStreamWAV = load("res://Assets/Audio/parry.wav")
	check(dull.get_length() > 0.2 and bright.get_length() > dull.get_length(), "Both generated WAV assets contain playable audio with distinct decay times")
	check(dull.mix_rate == 44100 and bright.mix_rate == 44100, "Combat sounds use standard 44.1 kHz audio")
	world.free()
	print("Combat checks complete: ", checks, " checks, ", failures, " failures at ", rate, " Hz")
	# --fixed-fps 可瞬间跑完数十秒模拟；给独立音频线程一次真实混音周期以回收已停止的声音。
	OS.delay_msec(150)
	quit(1 if failures else 0)
