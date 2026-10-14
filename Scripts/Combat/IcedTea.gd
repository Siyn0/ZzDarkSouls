extends CharacterBody2D

## 冰红茶整体大小，同时缩放外观和碰撞体：1 为原始大小，2 为两倍大小。
@export_range(0.1, 5.0, 0.1, "or_greater") var size_multiplier: float = 2.0
## 落稳后在附近瓶子之间错开，零表示关闭；只影响地面上的堆放。
@export_range(0.0, 320.0, 1.0) var landing_spread_radius := 192.0
@export_range(4.0, 64.0, 1.0) var landing_spacing := 32.0
@export_range(1.0, 120.0, 1.0) var landing_spread_speed := 60.0

@export var damage: int = 30
@export var throw_speed: float = 720.0
@export var gravity: float = 1200.0
## 撞墙后短暂停住再弹回，留出向上冲刺接住的操作窗口。
@export_range(0.0, 0.5, 0.01) var wall_rebound_pause := 0.12
## 撞墙后的水平回弹速度（像素/秒），与投掷速度分开调整。
@export var wall_rebound_speed := 120.0
## 回弹时向上轻弹，并暂缓重力，避免还没接到就落地。
@export var wall_rebound_lift := 150.0
@export_range(0.0, 0.5, 0.01) var wall_rebound_float_time := 0.12
## 从最后出瓶 / 持有位置向下掉出多远后回收；零表示禁用。
@export var fall_cleanup_distance: float = 2000.0
var holder: Node2D
var armed := false
var pickup_lock := 0.0
var armed_left := 0.0
var age := 0.0
var _fall_origin_y := 0.0
var _wall_pause_left := 0.0
var _gravity_delay_left := 0.0
var _settled := false
var _landing_target_x := 0.0

func _ready() -> void:
	_fall_origin_y = global_position.y
	add_to_group("tea_bottles")
	collision_layer = 0
	collision_mask = 1
	z_index = 4
	var shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 7.0 * size_multiplier
	capsule.height = 24.0 * size_multiplier
	shape.shape = capsule
	add_child(shape)
	queue_redraw()

func can_pick_up() -> bool:
	return not is_instance_valid(holder) and pickup_lock <= 0.0

func pick_up(who: Node2D) -> void:
	holder = who
	armed = false
	velocity = Vector2.ZERO
	_wall_pause_left = 0.0
	_gravity_delay_left = 0.0
	_settled = false
	collision_mask = 0
	set_physics_process(false)
	follow_holder()

func follow_holder() -> void:
	if is_instance_valid(holder):
		global_position = holder.global_position + Vector2(holder.get("_facing") * 20, -25)
		_fall_origin_y = global_position.y
		rotation = 0.0

func release_from_hand(direction: float, inherited: Vector2, drop: bool) -> void:
	if not is_instance_valid(holder):
		return
	# 瓶子放大后也要在地面上方出手，避免一投就与脚下地板重叠。
	global_position = holder.global_position + Vector2(0, -maxf(23, 12 * size_multiplier + safe_margin + 1))
	holder = null
	collision_mask = 1 if drop else 5
	move_and_collide(Vector2(direction * 20, 0))
	armed = not drop
	armed_left = 2.0
	pickup_lock = 0.2
	_wall_pause_left = 0.0
	_gravity_delay_left = 0.0
	_settled = false
	velocity = Vector2(direction * 60, 40) if drop else Vector2(direction * throw_speed + inherited.x * 0.4, -210 + minf(0, inherited.y) * 0.3)
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	age += delta
	pickup_lock = maxf(0, pickup_lock - delta)
	armed_left = maxf(0, armed_left - delta)
	if armed_left == 0:
		armed = false
		collision_mask = 1
	if _wall_pause_left > 0:
		var paused_time := minf(delta, _wall_pause_left)
		_wall_pause_left -= paused_time
		delta -= paused_time
		if delta <= 0.000001:
			return
	var float_time := minf(delta, _gravity_delay_left)
	_gravity_delay_left -= float_time
	velocity.y = minf(700, velocity.y + gravity * (delta - float_time))
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
		if absf(hit.get_normal().x) > 0.7 and armed:
			velocity = Vector2(hit.get_normal().x * wall_rebound_speed, minf(velocity.y, -wall_rebound_lift))
			_wall_pause_left = wall_rebound_pause
			_gravity_delay_left = wall_rebound_float_time
			# 已经撞墙反弹，允许立即接回，不再受刚出手的防误抓锁限制。
			pickup_lock = 0.0
		else:
			velocity = velocity.bounce(hit.get_normal()) * 0.32
		if hit.get_normal().y < -0.7:
			armed = false
			collision_mask = 1
			velocity.x = move_toward(velocity.x, 0, 900 * delta)
			if absf(velocity.y) < 45:
				velocity.y = 0
			if velocity.y == 0 and absf(velocity.x) < 1:
				if not _settled:
					_settled = true
					_choose_landing_position()
				_spread_on_floor(delta)
	rotation = move_toward(rotation, 0, delta * 8) if not armed else rotation + delta * velocity.x * 0.006
	if fall_cleanup_distance > 0 and global_position.y > _fall_origin_y + fall_cleanup_distance:
		queue_free()

func _choose_landing_position() -> void:
	_landing_target_x = global_position.x
	if landing_spread_radius <= 0:
		return
	var neighbors: Array[Node2D] = []
	for tea: Node2D in get_tree().get_nodes_in_group("tea_bottles"):
		if tea != self and tea._settled and not is_instance_valid(tea.holder):
			var floor_difference: float = global_position.y + 12 * size_multiplier - tea.global_position.y - 12 * tea.size_multiplier
			if absf(floor_difference) < 5 and absf(tea.global_position.x - global_position.x) < landing_spread_radius * 2 + landing_spacing:
				neighbors.append(tea)
	if neighbors.is_empty():
		return
	var best_score := INF
	var step := maxf(2, landing_spacing / 2)
	for i in range(-floori(landing_spread_radius / step), floori(landing_spread_radius / step) + 1):
		var offset := i * step
		if not _has_floor_at(offset) or (offset != 0 and test_move(global_transform, Vector2(offset, 0))):
			continue
		var candidate := global_position.x + offset
		var score := absf(offset) * 0.001
		for tea in neighbors:
			# 预留彼此的终点，连续落下的多瓶不会一起挪到同一个空位。
			score += pow(maxf(0, landing_spacing - absf(candidate - tea._landing_target_x)), 2)
		if score < best_score:
			best_score = score
			_landing_target_x = candidate

func _has_floor_at(offset: float) -> bool:
	var start := global_position + Vector2(offset, 0)
	var query := PhysicsRayQueryParameters2D.create(start, start + Vector2(0, 12 * size_multiplier + 5), 1)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.normal.y < -0.7

func _spread_on_floor(delta: float) -> void:
	var motion := clampf(_landing_target_x - global_position.x, -landing_spread_speed * delta, landing_spread_speed * delta)
	if absf(motion) < 0.01:
		return
	if not _has_floor_at(motion):
		_landing_target_x = global_position.x
		return
	if move_and_collide(Vector2(motion, 0)) != null:
		_landing_target_x = global_position.x

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * size_multiplier)
	# 小瓶琥珀茶、红标签和瓶盖；与骑士的像素占位画风保持一致。
	draw_rect(Rect2(-7, -9, 14, 21), Color("ad4f16"))
	draw_rect(Rect2(-5, -11, 10, 3), Color("f0bd6b"))
	draw_rect(Rect2(-5, -15, 10, 5), Color("d34239"))
	draw_rect(Rect2(-7, -3, 14, 10), Color("d74b32"))
	draw_rect(Rect2(-4, -1, 8, 2), Color("fff0c1"))
	draw_rect(Rect2(-4, 3, 6, 2), Color("fff0c1"))
	draw_line(Vector2(-4, -8), Vector2(-4, -4), Color("ffcd84"), 2)
