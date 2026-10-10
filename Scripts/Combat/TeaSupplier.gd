extends Node2D

var flying := false
var active := true
var stock: Node2D
var refill_left := 0.0
var flight_left := 0.0
var dropped := false
var arena: Node2D
var propeller := 0.0

func _physics_process(delta: float) -> void:
	if not active:
		return
	if flying:
		propeller += delta * 45
		if flight_left > 0:
			flight_left -= delta
			if flight_left <= 0:
				position = Vector2(-90, 274)
				dropped = false
				show()
		else:
			position.x += delta * 245
			if not dropped and position.x >= clampf(arena.player.position.x, 160, 790):
				arena.spawn_tea(position + Vector2(0, 20))
				dropped = true
				arena.announce("牢大空投：冰红茶已送达！")
			if position.x > 1050:
				hide()
				flight_left = 2.0
	else:
		if is_instance_valid(stock) and (stock.holder != null or stock.global_position.distance_to(global_position + Vector2(44, -17)) > 55):
			stock = null
			refill_left = 1.0
		if not is_instance_valid(stock):
			refill_left = maxf(0, refill_left - delta)
			if refill_left <= 0:
				stock = arena.spawn_tea(global_position + Vector2(44, -17))
				refill_left = 1.0
	queue_redraw()

func _draw() -> void:
	if flying:
		draw_colored_polygon(PackedVector2Array([Vector2(-55, 0), Vector2(40, -3), Vector2(60, 7), Vector2(-45, 12)]), Color("d6b573"))
		draw_colored_polygon(PackedVector2Array([Vector2(-28, 4), Vector2(-5, -18), Vector2(12, -18), Vector2(5, 4)]), Color("768b98"))
		draw_colored_polygon(PackedVector2Array([Vector2(-47, 0), Vector2(-59, -21), Vector2(-42, -21), Vector2(-31, 0)]), Color("8f708d"))
		draw_line(Vector2(59, 5 - sin(propeller) * 19), Vector2(59, 5 + sin(propeller) * 19), Color("d8e5e8"), 3)
		draw_circle(Vector2(16, -12), 8, Color("bb8b68"))
		draw_rect(Rect2(10, -15, 14, 4), Color("263541"))
	else:
		draw_rect(Rect2(-10, -34, 20, 30), Color("815b9b"))
		draw_rect(Rect2(-9, -31, 18, 5), Color("e9c86e"))
		draw_circle(Vector2(0, -43), 10, Color("bb8b68"))
		draw_rect(Rect2(-8, -46, 16, 4), Color("25313a"))
		draw_rect(Rect2(-11, -7, 8, 7), Color("2b3546"))
		draw_rect(Rect2(3, -7, 8, 7), Color("2b3546"))
		draw_rect(Rect2(28, -4, 34, 4), Color("cc8b4b"))
		draw_rect(Rect2(33, 0, 5, 12), Color("624935"))
		draw_rect(Rect2(54, 0, 5, 12), Color("624935"))
