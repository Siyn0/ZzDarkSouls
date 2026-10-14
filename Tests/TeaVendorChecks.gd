extends "res://Tests/CombatChecks.gd"

const Vendor := preload("res://Scenes/NPCTriggers/TeaVendor.tscn")

func vendor(at: Vector2) -> Node2D:
	var npc := Vendor.instantiate()
	npc.position = at
	world.add_child(npc)
	return npc

func run_checks() -> void:
	await reset_stage()
	var npc := vendor(Vector2(400, 600))
	await seconds(0.2)
	check(not npc.get_node("Bubble").visible and not is_instance_valid(npc.stock), "Distant player does not trigger dialogue or spawning")
	player.position.x = 400
	await frames(6)
	check(npc.get_node("Bubble").visible and npc.get_node("Bubble/Text").text == "man！来点冰红茶吗？无限供应！", "Approaching the NPC shows the requested overhead dialogue")
	check(is_instance_valid(npc.stock) and get_nodes_in_group("tea_bottles").size() == 1, "Approaching an empty supply point creates exactly one bottle")
	var original: Node2D = npc.stock
	await seconds(2)
	check(npc.stock == original and get_nodes_in_group("tea_bottles").size() == 1, "An untouched bottle prevents repeated spawning")
	player.position.x = 426
	press("grab")
	await frames(2)
	check(player.combat.carrying(), "The supplied bottle supports the normal grab control")
	await seconds(1)
	check(is_instance_valid(npc.stock) and npc.stock != original and original.holder == player, "Picking up the bottle replenishes stock without deleting the held bottle")
	player.position.x = 0
	await frames(6)
	check(not npc.get_node("Bubble").visible, "Leaving the interaction region hides the speech bubble")
	npc.stock.free()
	await seconds(1)
	check(not is_instance_valid(npc.stock), "Refill waits for the player to return")
	player.position.x = 400
	await seconds(1)
	check(is_instance_valid(npc.stock), "Returning starts replenishment again")

	await reset_stage()
	npc = vendor(Vector2(0, 600))
	var existing := bottle(Vector2(44, 583))
	await seconds(1)
	check(npc.stock == existing and get_nodes_in_group("tea_bottles").size() == 1, "A bottle already at the pad counts as stock, regardless of who spawned it")
	existing.position.x = 180
	await frames(3)
	var returned := bottle(Vector2(44, 583))
	await seconds(1)
	check(npc.stock == returned and get_nodes_in_group("tea_bottles").size() == 2, "A returned bottle cancels pending refill instead of creating a duplicate")
	var neighbor := vendor(Vector2(0, 600))
	await seconds(1)
	check(neighbor.stock == returned and npc.stock == returned, "Overlapping suppliers recognize the same existing bottle")
	var distant := vendor(Vector2(800, 600))
	player.position.x = 800
	await seconds(1)
	check(distant.stock != returned and is_instance_valid(distant.stock) and not npc.get_node("Bubble").visible, "Separate NPC instances manage local supply and dialogue independently")
	distant.active = false
	distant.stock.free()
	await seconds(1)
	check(not distant.get_node("Bubble").visible and not is_instance_valid(distant.stock), "Deactivated supplier stops dialogue and refill")

	await reset_stage()
	solid("FarFloor", Vector2(5200, 1416), Vector2(1200, 32))
	player.position = Vector2(5200, 1400)
	var container := Node2D.new()
	container.position = Vector2(5000, 1000)
	world.add_child(container)
	npc = Vendor.instantiate()
	npc.position = Vector2(200, 400)
	container.add_child(npc)
	await seconds(2)
	# 按当前瓶子大小检查底部落在地面；原来的 1388 写死了缩放前的半高。
	var floor_y: float = npc.stock.global_position.y + 12 * npc.stock.size_multiplier if is_instance_valid(npc.stock) else INF
	check(is_instance_valid(npc.stock) and absf(npc.stock.global_position.x - 5244) < 3 and absf(floor_y - 1400) < 3, "Supplier works under translated parents and far beyond the old arena coordinate limits")
	var far_stock: Node2D = npc.stock
	await seconds(2)
	check(npc.stock == far_stock and get_nodes_in_group("tea_bottles").size() == 1, "Stock in a distant level remains stable without endless delete/respawn loops")
	far_stock.fall_cleanup_distance = 100
	far_stock.position.y += 150
	await frames(2)
	check(not is_instance_valid(far_stock), "A bottle falling out of the level still gets cleaned up relative to its origin")
	world.free()
	OS.delay_msec(150)
	print("Tea vendor checks complete: ", checks, " checks, ", failures, " failures at ", rate, " Hz")
	quit(1 if failures else 0)
