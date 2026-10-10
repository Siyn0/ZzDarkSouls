extends CharacterBody2D

@export var damage: int = 30
@export var throw_speed: float = 720.0
@export var gravity: float = 1200.0
var holder: Node2D
var armed := false
var pickup_lock := 0.0
var armed_left := 0.0
var age := 0.0

func _ready() -> void:
	add_to_group("tea_bottles")
	collision_layer = 0
	collision_mask = 1
	z_index = 4
	var shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 7
	capsule.height = 24
	shape.shape = capsule
	add_child(shape)
	queue_redraw()

func can_pick_up() -> bool:
	return not is_instance_valid(holder) and pickup_lock <= 0.0

func pick_up(who: Node2D) -> void:
	holder = who
	armed = false
	velocity = Vector2.ZERO
	collision_mask = 0
	set_physics_process(false)
	follow_holder()

func follow_holder() -> void:
	if is_instance_valid(holder):
		global_position = holder.global_position + Vector2(holder.get("_facing") * 20, -25)
		rotation = 0.0

func release_from_hand(direction: float, inherited: Vector2, drop: bool) -> void:
	if not is_instance_valid(holder):
		return
	global_position = holder.global_position + Vector2(0, -23)
	holder = null
	collision_mask = 1 if drop else 5
	move_and_collide(Vector2(direction * 20, 0))
	armed = not drop
	armed_left = 2.0
	pickup_lock = 0.2
	velocity = Vector2(direction * 60, 40) if drop else Vector2(direction * throw_speed + inherited.x * 0.4, -210 + minf(0, inherited.y) * 0.3)
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	age += delta
	pickup_lock = maxf(0, pickup_lock - delta)
	armed_left = maxf(0, armed_left - delta)
	if armed_left == 0:
		armed = false
		collision_mask = 1
	velocity.y = minf(700, velocity.y + gravity * delta)
	var hit := move_and_collide(velocity * delta)
	if hit:
		var body := hit.get_collider()
		if armed and body.has_method("take_tea_hit"):
			armed = false
			body.take_tea_hit(damage)
			var spark := preload("res://Scripts/Combat/HitSpark.gd").new()
			spark.position = global_position
			spark.tint = Color(1, 0.42, 0.15)
			get_parent().add_child(spark)
			queue_free()
			return
		velocity = velocity.bounce(hit.get_normal()) * 0.32
		if hit.get_normal().y < -0.7:
			armed = false
			collision_mask = 1
			velocity.x = move_toward(velocity.x, 0, 900 * delta)
			if absf(velocity.y) < 45:
				velocity.y = 0
	rotation = move_toward(rotation, 0, delta * 8) if not armed else rotation + delta * velocity.x * 0.006
	if global_position.y > 900 or absf(global_position.x) > 2500:
		queue_free()

func _draw() -> void:
	# 小瓶琥珀茶、红标签和瓶盖；与骑士的像素占位画风保持一致。
	draw_rect(Rect2(-7, -9, 14, 21), Color("ad4f16"))
	draw_rect(Rect2(-5, -11, 10, 3), Color("f0bd6b"))
	draw_rect(Rect2(-5, -15, 10, 5), Color("d34239"))
	draw_rect(Rect2(-7, -3, 14, 10), Color("d74b32"))
	draw_rect(Rect2(-4, -1, 8, 2), Color("fff0c1"))
	draw_rect(Rect2(-4, 3, 6, 2), Color("fff0c1"))
	draw_line(Vector2(-4, -8), Vector2(-4, -4), Color("ffcd84"), 2)
