# Run: Godot --headless --path . --script res://Tests/MovementChecks.gd --fixed-fps 60 -- 60
extends SceneTree

var failures := 0
var checks := 0
var rate := 60
var world: Node2D
var player: CharacterBody2D

func _initialize() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		rate = int(OS.get_cmdline_user_args()[0])
	Engine.physics_ticks_per_second = rate
	call_deferred("run_checks")

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func seconds(duration: float) -> void:
	await frames(roundi(duration * rate))

func press(action: String) -> void:
	Input.action_press(action)

func release(action: String) -> void:
	Input.action_release(action)

func solid(body_name: String, at: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.name = body_name
	body.position = at
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	shape.shape = rectangle
	body.add_child(shape)
	world.add_child(body)

func reset_stage(at: Vector2 = Vector2(0, 600), wall_side: float = 0.0) -> void:
	for action in ["move_left", "move_right", "aim_up", "aim_down", "jump", "dash", "grab"]:
		release(action)
	if is_instance_valid(world):
		world.free()
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	solid("Floor", Vector2(0, 616), Vector2(4000, 32))
	if wall_side != 0:
		solid("Wall", Vector2(wall_side * 520, -200), Vector2(40, 1600))
	player = load("res://Scenes/Player.tscn").instantiate()
	player.position = at
	world.add_child(player)
	await frames(2)

func jump_height(hold: bool, down: bool = false) -> float:
	await reset_stage()
	var start := player.position.y
	var peak := start
	press("jump")
	if down:
		press("aim_down")
	await frames(1)
	if not hold:
		release("jump")
	for i in range(rate):
		peak = minf(peak, player.position.y)
		await frames(1)
	return start - peak

func grab_wall(side: float = 1.0) -> void:
	await reset_stage(Vector2(side * 489.9, 250), side)
	player.call("_face", side)
	press("grab")
	await seconds(0.15)
	check(player.is_climbing, "Grabs wall on side %s" % side)

func run_checks() -> void:
	print("Movement checks at ", rate, " Hz")
	await reset_stage()
	press("move_right")
	await frames(1)
	check(player.velocity.x > 0 and player.velocity.x < player.move_speed, "Run accelerates instead of instantly reaching maximum")
	await seconds(0.15)
	check(is_equal_approx(player.velocity.x, player.move_speed), "Run reaches its speed cap")
	release("move_right")
	await frames(1)
	check(player.velocity.x > 0 and player.velocity.x < player.move_speed, "Releasing movement brakes gradually")
	await seconds(0.15)
	check(is_zero_approx(player.velocity.x), "Ground braking comes to a full stop")
	var low := await jump_height(false)
	var high := await jump_height(true)
	check(player.is_on_floor(), "Held jump never automatically bounces on landing")
	var low_down := await jump_height(false, true)
	check(high > low * 2, "Holding jump produces a much higher jump than tapping (%s / %s)" % [high, low])
	check(absf(low - low_down) < 0.1, "Down input does not cut a short jump")

	await reset_stage()
	world.get_node("Floor").free()
	await seconds(0.05)
	press("jump")
	await frames(1)
	check(player.velocity.y < 0, "Coyote jump succeeds shortly after leaving an edge")
	await reset_stage()
	world.get_node("Floor").free()
	await seconds(0.15)
	press("jump")
	await frames(1)
	check(player.velocity.y > 0, "Coyote grace expires; no midair double jump")
	await reset_stage(Vector2(0, 565))
	player.velocity.y = 480
	press("jump")
	await seconds(0.1)
	check(player.velocity.y < 0, "Jump pressed shortly before landing is buffered")
	await reset_stage(Vector2(0, 400))
	player.velocity.y = 480
	press("jump")
	await seconds(0.6)
	check(player.is_on_floor(), "Old buffered input expires before a distant landing")

	await reset_stage(Vector2(0, -1000))
	await seconds(0.4)
	check(is_equal_approx(player.velocity.y, player.max_fall_speed), "Normal fall reaches its cap")
	press("aim_down")
	await frames(1)
	check(player.velocity.y > player.max_fall_speed and player.velocity.y < player.fast_max_fall_speed, "Fast fall ramps only after normal cap")
	await seconds(0.3)
	check(is_equal_approx(player.velocity.y, player.fast_max_fall_speed), "Long fast fall reaches its higher cap")
	release("aim_down")
	await seconds(0.3)
	check(is_equal_approx(player.velocity.y, player.max_fall_speed), "Releasing down restores the normal cap")

	await reset_stage(Vector2(0, -300))
	var dash_start := player.position
	press("move_right")
	press("dash")
	await seconds(0.2)
	check(absf(player.position.x - dash_start.x - player.dash_speed * player.dash_duration) < 0.5, "Air dash distance is independent of physics tick rate")
	check(player.velocity.x > player.move_speed and player.get("_dash_time_left") == 0, "Dash exit retains momentum")
	release("dash")
	await frames(2)
	press("dash")
	await frames(1)
	check(player.get("_dash_time_left") == 0, "Cannot dash twice in the air")
	await reset_stage(Vector2(0, -300))
	press("move_right")
	press("aim_up")
	press("dash")
	await seconds(0.1)
	check(absf(player.get("_dash_velocity").length() - player.dash_speed) < 0.1, "Diagonal dash is normalized")
	check(player.velocity.x > 0 and player.velocity.y < 0, "Diagonal dash uses the requested direction")

	await reset_stage(Vector2(489.9, 250), 1)
	press("move_right")
	press("dash")
	await seconds(0.1)
	check(player.position.x < 490.1 and player.get("_dash_time_left") > 0, "Wall blocks displacement without cancelling dash")
	check(player.get("_dash_velocity").x > 0 and get_nodes_in_group("dash_afterimages").size() >= 2, "Wall impact preserves dash drive and afterimages")
	await seconds(0.15)
	check(player.get("_dash_time_left") == 0, "Blocked dash ends by timer")
	await reset_stage()
	press("move_right")
	press("aim_down")
	press("dash")
	await seconds(0.1)
	check(player.get("_dash_sliding") and player.velocity.x > 0, "Down-diagonal dash becomes a ground slide")
	press("jump")
	await frames(1)
	check(player.velocity.x > 900 and player.velocity.y < 0 and player.velocity.y > -player.jump_speed, "Slide jump produces a fast, low hyper jump")
	await reset_stage()
	press("move_right")
	press("dash")
	# 0.05 秒起手停顿不消耗 0.1 秒恢复窗口。
	await seconds(0.17)
	press("jump")
	await frames(1)
	check(player.velocity.x > 700 and player.velocity.y < 0, "Horizontal ground dash can transition into a super jump")
	check(not player.get("_air_dash_used"), "Waiting for the grounded refill window allows a dash after the jump")

	for side: float in [-1.0, 1.0]:
		await grab_wall(side)
		var at := player.position
		var before: float = player.stamina
		await seconds(0.5)
		check(player.position.distance_to(at) < 0.1, "Grab holds position")
		check(absf(before - player.stamina - 5) < 0.2, "Holding drains 10 stamina per second")
		press("aim_up")
		before = player.stamina
		await seconds(0.3)
		check(player.position.y < at.y - 25, "Up input climbs the wall")
		check(absf(before - player.stamina - player.climb_up_cost * 0.3) < 0.3, "Climbing up drains stamina faster")
		release("aim_up")
		press("aim_down")
		before = player.stamina
		await seconds(0.3)
		check(player.velocity.y > 0 and is_equal_approx(before, player.stamina), "Climbing down moves without stamina cost")
		release("aim_down")
		press("move_right" if side < 0 else "move_left")
		before = player.stamina
		press("jump")
		await frames(1)
		check(player.velocity.x * side < -300 and player.velocity.y < 0, "Away+jump kicks off either wall")
		check(is_equal_approx(before, player.stamina), "Away wall jump costs no stamina")

	await grab_wall()
	var before: float = player.stamina
	press("jump")
	await frames(1)
	check(player.velocity.y < 0 and is_zero_approx(player.velocity.x), "Grab+jump climbs straight up")
	check(absf(before - player.stamina - player.climb_jump_cost) < 0.1, "Climb jump costs stamina")
	await grab_wall()
	player.stamina = 0.2
	await seconds(0.3)
	check(not player.is_climbing and player.velocity.y > 0 and player.stamina == 0, "Exhaustion forces falling even while grab remains held")
	release("grab")
	press("grab")
	await frames(2)
	check(not player.is_climbing, "Repressing grab cannot bypass exhausted stamina")
	await seconds(1.0)
	check(is_equal_approx(player.stamina, player.max_stamina), "Landing refills stamina")
	await grab_wall()
	player.set("_air_dash_used", true)
	await seconds(0.2)
	check(not player.dash_available(), "Grabbing a wall does not restore an air dash")
	release("grab")
	await frames(2)
	check(not player.is_climbing and player.velocity.y > 0, "Releasing grab lets go immediately")
	await reset_stage(Vector2(489.9, 100), 1)
	press("move_right")
	await seconds(0.2)
	check(player.velocity.y < 200, "Pressing toward a wall slows the early fall")

	await reset_stage(Vector2(489.9, 580))
	solid("Ledge", Vector2(520, 500), Vector2(40, 200))
	await frames(2)
	press("grab")
	press("aim_up")
	await seconds(2.0)
	check(player.position.y <= 400.1 and player.position.x > 500, "Climbing over a ledge hops onto its top without teleporting")

	await reset_stage(Vector2(0, 200))
	solid("Ceiling", Vector2(0, 145), Vector2(500, 20))
	player.call("_start_jump", player.jump_speed)
	press("jump")
	await seconds(0.15)
	check(player.get("_variable_jump_left") == 0 and player.velocity.y >= 0, "Ceiling impact cancels jump sustain")

	world.free()
	print("Movement checks complete: ", checks, " checks, ", failures, " failures at ", rate, " Hz")
	quit(1 if failures else 0)
