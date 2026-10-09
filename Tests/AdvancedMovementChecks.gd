# Uses the same input-driven fixture as the basic movement checks.
# Godot --headless --path . --script res://Tests/AdvancedMovementChecks.gd --fixed-fps 60 -- 60
extends "res://Tests/MovementChecks.gd"

func neutral_cycle(side: float) -> float:
	var toward := "move_right" if side > 0 else "move_left"
	release(toward)
	release("jump")
	await frames(1)
	var start_y := player.position.y
	press("aim_up")
	press("jump")
	await frames(1)
	check(player.get("_force_move_left") == 0, "Neutral wall jump does not lock horizontal input")
	press(toward)
	for i in range(rate):
		await frames(1)
		if player.position.x * side >= 489.0 and player.velocity.x * side >= 0:
			break
	return start_y - player.position.y

func run_checks() -> void:
	print("Advanced movement checks at ", rate, " Hz")
	for side: float in [-1.0, 1.0]:
		await reset_stage(Vector2(side * 489.9, 300), side)
		player.call("_face", side)
		player.stamina = 0
		for cycle in range(3):
			var height := await neutral_cycle(side)
			check(height > 20, "Repeated neutral jump returns higher on side %s cycle %s (%s px)" % [side, cycle, height])
			check(player.stamina == 0 and not player.is_climbing, "Neutral climbing remains possible with zero stamina and without grab")
		await reset_stage(Vector2(side * 489.9, 300), side)
		player.call("_face", side)
		press("jump")
		await seconds(0.15)
		var neutral_distance := absf(player.position.x - side * 489.9)
		await reset_stage(Vector2(side * 489.9, 300), side)
		press("move_left" if side > 0 else "move_right")
		press("jump")
		await seconds(0.15)
		check(absf(player.position.x - side * 489.9) > neutral_distance + 8, "Directional wall jump travels farther than neutral")

	await grab_wall()
	var before: float = player.stamina
	press("jump")
	await frames(1)
	check(is_zero_approx(player.velocity.x) and player.velocity.y < 0, "Climb jump with no horizontal input goes straight up")
	await seconds(0.08)
	press("move_left")
	await frames(1)
	check(player.velocity.x < -300 and absf(player.stamina - before) < 0.01, "Turning away within 0.2 seconds refunds the climb jump")
	await seconds(0.08)
	check(player.stamina <= before, "Refund occurs only once")
	await grab_wall()
	before = player.stamina
	press("jump")
	await seconds(0.22)
	press("move_left")
	await frames(1)
	check(absf(before - player.stamina - player.climb_jump_cost) < 0.01, "Late turn does not refund climb stamina")
	await grab_wall()
	player.stamina = 5
	press("jump")
	await frames(1)
	press("move_left")
	await frames(1)
	check(absf(player.stamina - 5) < 0.01, "Low-stamina refund cannot create extra stamina")

	await reset_stage(Vector2(489.9, 300), 1)
	player.velocity.y = -120
	player.stamina = 60
	press("grab")
	press("jump")
	await frames(1)
	check(player.velocity.y <= -player.jump_speed and is_zero_approx(player.velocity.x), "Grab+jump works at a wall while rising, outside climb state")
	check(absf(player.stamina - (60 - player.climb_jump_cost)) < 0.01, "Rising climb jump still costs stamina")

	for low_jump in [false, true]:
		await reset_stage()
		press("move_right")
		if low_jump: press("aim_down")
		press("dash")
		await seconds(0.08)
		press("jump")
		await frames(1)
		check(player.get("_air_dash_used"), "Early super/hyper consumes the air dash")
		check(player.velocity.x > (900 if low_jump else 700), "Early super/hyper receives launch speed")
		await reset_stage()
		press("move_right")
		if low_jump: press("aim_down")
		press("dash")
		await seconds(0.17)
		press("jump")
		await frames(1)
		check(not player.get("_air_dash_used"), "Extended super/hyper retains a dash after the recovery window")
		var launch_y := player.position.y
		var launch_x := player.position.x
		release("dash")
		await seconds(0.1)
		check(player.position.x - launch_x > 60 and player.position.y < launch_y, "Dash jump travels quickly through the air without resetting to run speed")
		press("dash")
		await frames(1)
		check(player.get("_dash_time_left") > 0, "Extended jump can actually dash again in midair")
		await reset_stage()
		press("move_right")
		if low_jump: press("aim_down")
		press("dash")
		await seconds(0.12)
		release("move_right")
		press("move_left")
		press("jump")
		await frames(1)
		check(player.velocity.x < (-900 if low_jump else -700), "Reverse super/hyper follows jump-time facing")

	await reset_stage()
	press("move_right")
	press("dash")
	await seconds(0.09)
	world.get_node("Floor").free()
	await seconds(0.04)
	press("jump")
	await frames(1)
	check(player.velocity.x > 700 and player.velocity.y < 0, "Super jump accepts coyote time just past a ledge")

	# Airborne diagonal dash lands late enough to refill, then jumps while still dashing.
	await reset_stage(Vector2(0, 541))
	press("move_right")
	press("aim_down")
	press("dash")
	for i in range(rate):
		await frames(1)
		if player.is_on_floor(): break
	check(player.get("_dash_time_left") > 0 and player.is_ducking, "Wavedash landing converts diagonal dash into a crouched slide")
	press("jump")
	await frames(1)
	check(player.velocity.x > 900 and player.velocity.y < 0 and not player.get("_air_dash_used"), "Wavedash jumps fast and low with the air dash restored")

	# Greater pre-dash speed survives down-diagonal dash, and landing adds 20% even after dash ends.
	await reset_stage(Vector2(0, 400))
	player.velocity.x = 1200
	press("move_right")
	press("aim_down")
	press("dash")
	await seconds(0.21)
	check(player.velocity.x > 1100 and player.get("_dash_time_left") == 0, "Downward dash preserves pre-existing horizontal momentum after ending")
	var landing_speed := 0.0
	var before_landing := 0.0
	for i in range(rate):
		before_landing = player.velocity.x
		await frames(1)
		if player.is_on_floor():
			landing_speed = player.velocity.x
			break
	check(landing_speed > before_landing * 1.15 and landing_speed <= before_landing * 1.2 and player.is_ducking, "Ultra landing adds 20% after this frame's normal air friction")
	release("aim_down")
	press("jump")
	await frames(1)
	check(player.velocity.x > 1250 and player.velocity.y < 0, "Immediate bunny hop carries ultra momentum")

	for delay in [0.12, 0.23, 0.4]:
		await reset_stage(Vector2(489.9, 300), 1)
		press("aim_up")
		press("dash")
		await seconds(delay)
		press("jump")
		await frames(1)
		if delay < 0.3:
			check(player.velocity.x < -480 and player.velocity.y <= -470, "Wallbounce works during / shortly after upward dash (%s)" % delay)
		else:
			check(absf(player.velocity.x) < 450, "Wallbounce opportunity expires")

	await reset_stage()
	press("aim_down")
	await frames(1)
	check(player.is_ducking and player.get_node("CollisionShape2D").shape.height == 24, "Crouching changes the physical hitbox")
	solid("LowRoof", Vector2(0, 560), Vector2(200, 30))
	await frames(2)
	release("aim_down")
	press("jump")
	await seconds(0.15)
	check(player.is_ducking and player.position.y > 590, "Cannot stand up or jump through a low ceiling")
	world.get_node("LowRoof").free()
	await frames(2)
	check(not player.is_ducking, "Automatically stands once there is room")

	# Capsule tip touches the underside near an outside corner; correction must preserve rise.
	await reset_stage(Vector2(98, 200))
	solid("Corner", Vector2(140, 140), Vector2(80, 20))
	player.velocity = Vector2(0, -315)
	press("jump")
	var crossed := false
	for i in range(20):
		await frames(1)
		if player.position.y < 185:
			crossed = true
	check(crossed and player.position.x < 98, "Upward corner correction nudges clear instead of cancelling the jump")

	# Corner boost: hit a short wall, then jump above its top within the retention window.
	await reset_stage(Vector2(488, 300))
	solid("CornerWall", Vector2(520, 390), Vector2(40, 200))
	player.velocity = Vector2(800, -315)
	press("move_right")
	press("grab")
	press("jump")
	await frames(1)
	check(player.get("_wall_retention_left") > 0, "A wall collision saves horizontal momentum briefly")
	var restored := false
	for i in range(10):
		await frames(1)
		if player.velocity.x > 600: restored = true
	check(restored, "Clearing a wall corner restores retained speed")

	await reset_stage()
	press("move_right")
	press("dash")
	await frames(1)
	press("jump")
	await seconds(0.08)
	check(player.velocity.x > 700 and player.velocity.y < 0, "Jump pressed during dash startup freeze is buffered")
	await reset_stage()
	press("move_right")
	press("aim_up")
	press("dash")
	await seconds(0.08)
	press("jump")
	await frames(1)
	check(player.get("_dash_time_left") > 0 and player.velocity.x < 600, "Up-diagonal dash cannot incorrectly trigger a grounded super")
	await reset_stage()
	press("move_right")
	press("dash")
	await seconds(0.3)
	check(player.get("_dash_time_left") == 0, "Holding dash never repeats it automatically")
	await reset_stage()
	press("move_right")
	press("dash")
	await frames(1)
	release("dash")
	await seconds(0.2)
	press("dash")
	await frames(1)
	release("dash")
	await seconds(0.06)
	check(player.get("_dash_time_left") > 0, "Dash pressed just before cooldown ends is buffered")
	await reset_stage(Vector2(0, 600))
	solid("TunnelRoof", Vector2(90, 560), Vector2(80, 30))
	press("move_right")
	press("dash")
	await seconds(0.15)
	check(player.is_ducking and player.position.x > 50, "Horizontal ground dash automatically ducks into a low tunnel")

	world.free()
	print("Advanced movement checks complete: ", checks, " checks, ", failures, " failures at ", rate, " Hz")
	quit(1 if failures else 0)
