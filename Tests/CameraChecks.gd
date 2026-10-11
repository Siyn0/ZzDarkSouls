extends "res://Tests/MovementChecks.gd"

const CameraScene := preload("res://Scenes/LevelCamera.tscn")

func camera_stage() -> Camera2D:
	await reset_stage()
	player.set_physics_process(false)
	var camera := CameraScene.instantiate()
	world.add_child(camera)
	return camera

func run_checks() -> void:
	var camera := await camera_stage()
	check(camera.target == player and camera.global_position == player.global_position + camera.follow_offset, "Independent camera automatically finds and initially snaps to the player")
	var start: Vector2 = camera.global_position
	player.position.x += 20
	await seconds(0.1)
	check(camera.global_position.is_equal_approx(start), "Small movement inside the dead zone does not shake the camera")
	player.position.x += 180
	await frames(2)
	check(camera.global_position.x > start.x and camera.global_position.x < player.position.x - 32, "Moving outside the dead zone produces a smooth transition")
	await seconds(1)
	check(absf(camera.global_position.x - (player.position.x - 32)) < 2, "Camera catches up to the moving subject's framing")

	camera = await camera_stage()
	var neutral := CameraScene.instantiate()
	neutral.look_ahead_distance = 0
	neutral.enabled = false
	world.add_child(neutral)
	for i in range(rate):
		player.position.x += 240.0 / rate
		await frames(1)
	check(camera.position.x > neutral.position.x + 35, "Running right reveals more space ahead than neutral follow")
	for i in range(rate * 2):
		player.position.x -= 240.0 / rate
		await frames(1)
	check(camera.position.x < neutral.position.x - 35, "Turning left smoothly reverses the look-ahead framing")
	neutral.free()

	camera.set_world_bounds(Rect2(0, 0, 2592, 544))
	player.position = Vector2(-200, -100)
	camera.snap_to_target()
	check(camera.position.is_equal_approx(Vector2(480, 272)), "Bounds clamp the entire viewport at the left and upper edges")
	player.position = Vector2(4000, 2000)
	camera.snap_to_target()
	check(camera.position.is_equal_approx(Vector2(2112, 272)), "Bounds clamp the entire viewport at the right and lower edges")
	camera.zoom = Vector2(2, 2)
	camera.snap_to_target()
	check(camera.position.is_equal_approx(Vector2(2352, 408)), "Bounds adapt to camera zoom")
	camera.set_world_bounds(Rect2(10, 20, 100, 100))
	check(camera.position.is_equal_approx(Vector2(60, 70)), "Rooms smaller than the viewport are centered without oscillation")
	camera.clear_bounds()
	camera.focus_at(Vector2(700, 200), true)
	player.position = Vector2(100, 600)
	await seconds(0.2)
	check(camera.position.is_equal_approx(Vector2(700, 200)), "Fixed view ignores player movement")
	camera.focus_at(Vector2(900, 100))
	await frames(2)
	check(camera.position.x > 700 and camera.position.x < 900, "Scripted focus can transition smoothly")
	camera.resume_follow(true)
	check(camera.position.is_equal_approx(player.position + camera.follow_offset), "Resuming player follow restores framing immediately when requested")
	var other := Node2D.new()
	other.position = Vector2(1500, 700)
	world.add_child(other)
	camera.follow(other, true)
	check(camera.target == other and camera.position.is_equal_approx(other.position + camera.follow_offset), "Camera can follow a non-player target without changing player code")
	other.free()
	await frames(2)
	check(camera.target == player, "Camera safely reacquires the player after a temporary target is removed")
	player.free()
	await frames(2)
	var waiting_at: Vector2 = camera.position
	await frames(2)
	check(camera.position == waiting_at, "Camera holds its position when no target exists")
	player = load("res://Scenes/Player.tscn").instantiate()
	player.position = Vector2(2000, 300)
	world.add_child(player)
	player.set_physics_process(false)
	await frames(2)
	check(camera.target == player and camera.position.is_equal_approx(player.position + camera.follow_offset), "Respawn automatically reacquires and snaps to the new player")

	world.free()
	world = load("res://Scenes/Levels/Tutorial.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	player = world.get_node("Player")
	camera = world.get_node("LevelCamera")
	await frames(3)
	check(camera.world_bounds == Rect2(0, -32, 2592, 576), "Tutorial camera derives bounds from the existing TileMap")
	var ui: CanvasLayer = world.get_node("GameUI")
	var hud_rect: Rect2 = ui.get_node("%Vitals").get_global_rect()
	press("move_right")
	await seconds(3.5)
	release("move_right")
	check(camera.position.x > 800, "Actual gameplay scrolls through the long Tutorial level")
	check(ui.get_node("%Vitals").get_global_rect() == hud_rect, "HUD stays fixed on screen while the level scrolls")
	ui.open_settings()
	var paused_at: Vector2 = camera.position
	await frames(10)
	check(camera.position == paused_at, "Opening settings pauses camera movement")
	ui.close_settings()
	world.free()
	OS.delay_msec(150)
	print("Camera checks complete: ", checks, " checks, ", failures, " failures at ", rate, " Hz")
	quit(1 if failures else 0)
