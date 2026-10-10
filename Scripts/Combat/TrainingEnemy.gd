extends CharacterBody2D

signal defeated(enemy: Node)
@export var boss := false
## 蓄力结束后的实际挥刀时间；命中取决于刀刃触碰玩家，而非这个阶段开始。
@export var swing_duration: float = 0.28
@export var boss_swing_duration: float = 0.34
var target: CharacterBody2D
var health := 60
var max_health := 60
var posture := 0.0
var phase := "approach"
var phase_left := 0.6
var facing := -1.0
var attack_id := 0
var hit_flash := 0.0
var alive := true
var attacks_enabled := true
var swing_elapsed := 0.0
var _swing_hit := false

func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 4
	collision_mask = 1
	z_index = 2
	max_health = 300 if boss else 60
	health = max_health
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(40, 72) if boss else Vector2(26, 42)
	shape.shape = rectangle
	shape.position.y = -rectangle.size.y / 2
	add_child(shape)

func _physics_process(delta: float) -> void:
	if not alive:
		return
	hit_flash = maxf(0, hit_flash - delta)
	phase_left -= delta
	velocity.y = minf(480, velocity.y + 1800 * delta)
	if not is_instance_valid(target) or target.combat.dead or not attacks_enabled:
		velocity.x = 0
		move_and_slide()
		queue_redraw()
		return
	var distance: float = target.global_position.x - global_position.x
	match phase:
		"approach":
			posture = maxf(0, posture - delta * 5)
			facing = signf(distance) if absf(distance) > 1 else facing
			var reach := 105.0 if boss else 70.0
			velocity.x = facing * (78 if boss else 58) if absf(distance) > reach else 0.0
			if absf(distance) <= reach + 4 and absf(target.global_position.y - global_position.y) < 80 and phase_left <= 0:
				phase = "windup"
				phase_left = 0.8 if boss else 0.65
				velocity.x = 0
		"windup":
			velocity.x = 0
			if phase_left <= 0:
				phase = "swing"
				phase_left = _swing_duration()
				swing_elapsed = 0.0
				_swing_hit = false
				attack_id += 1
		"swing":
			velocity.x = 0
			var previous := swing_elapsed
			swing_elapsed = minf(_swing_duration(), swing_elapsed + delta)
			_sweep_blade(previous, swing_elapsed)
			if phase == "swing" and swing_elapsed >= _swing_duration():
				phase = "recover"
				phase_left = 0.85 if boss else 1.0
		"recover", "stagger":
			velocity.x = move_toward(velocity.x, 0, delta * 700)
			if phase_left <= 0:
				phase = "approach"
	move_and_slide()
	queue_redraw()

func _swing_duration() -> float:
	return maxf(0.05, boss_swing_duration if boss else swing_duration)

func _sword_origin() -> Vector2:
	return Vector2(facing * (25 if boss else 18), -(72 if boss else 42) * 0.55)

func _sword_vector(progress: float) -> Vector2:
	var angle := lerpf(deg_to_rad(-110), deg_to_rad(25), clampf(progress, 0, 1))
	return Vector2(cos(angle) * facing, sin(angle)) * (110 if boss else 72)

func _sweep_blade(previous: float, current: float) -> void:
	if _swing_hit:
		return
	# 画面和物理使用相同刀刃姿态；角度分段避免低物理帧率跳过玩家。
	var steps := maxi(1, ceili((current - previous) / _swing_duration() * 135.0 / 3.0))
	var blade := CapsuleShape2D.new()
	blade.radius = 2.5 if boss else 1.5
	blade.height = (110 if boss else 72) + blade.radius * 2
	for i in range(steps + 1):
		var progress := lerpf(previous, current, float(i) / steps) / _swing_duration()
		var sword := _sword_vector(progress)
		var origin := global_position + _sword_origin()
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = blade
		query.transform = Transform2D(sword.angle() - PI / 2, origin + sword / 2)
		query.collision_mask = 2
		for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(query):
			if hit.collider != target:
				continue
			var ray := PhysicsRayQueryParameters2D.create(origin, target.global_position + Vector2(0, -20), 1)
			if not get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
				continue
			_swing_hit = true
			target.combat.receive_attack(self, attack_id, 25 if boss else 18)
			return

func parried() -> void:
	posture += 40
	phase = "stagger"
	phase_left = 1.1
	velocity.x = -facing * 110
	if posture >= (100 if boss else 60):
		posture = 0
		phase_left = 2.5
		# 架势打崩后留出投掷窗口，而不是靠精准防御直接扣血。
		if is_instance_valid(target):
			target.combat.feedback.emit("敌人架势崩溃！趁现在投掷")

func take_tea_hit(amount: int) -> void:
	if not alive:
		return
	health = maxi(0, health - amount)
	hit_flash = 0.18
	if not boss:
		phase = "stagger"
		phase_left = 0.55
	if is_instance_valid(target):
		target.combat.feedback.emit("冰红茶命中  -%d" % amount)
	if health == 0:
		alive = false
		defeated.emit(self)
		queue_free()

func _draw() -> void:
	var height := 72.0 if boss else 42.0
	var width := 40.0 if boss else 26.0
	var color := Color("914b54") if boss else Color("637985")
	if hit_flash > 0:
		color = Color("fff0b5")
	draw_rect(Rect2(-width / 2, -height, width, height), color)
	draw_rect(Rect2(-width / 2 - 5, -height + 12, width + 10, 9), color.lightened(0.2))
	draw_rect(Rect2(facing * 6 - 5, -height + 8, 10, 4), Color("ffc369"))
	draw_rect(Rect2(-width / 2, -8, width, 8), Color("27363f"))
	var sword_from := _sword_origin()
	var sword_to := sword_from + Vector2(facing * 7, -32)
	if phase == "windup":
		var progress := 1.0 - phase_left / (0.8 if boss else 0.65)
		sword_to = sword_from + _sword_vector(0)
		draw_arc(Vector2(0, -height - 22), 8, -PI / 2, -PI / 2 + TAU * clampf(progress, 0, 1), 24, Color("ffb45a"), 3)
	elif phase == "swing":
		sword_to = sword_from + _sword_vector(swing_elapsed / _swing_duration())
		var previous_tip := sword_from + _sword_vector(maxf(0, swing_elapsed / _swing_duration() - 0.12))
		draw_line(previous_tip, sword_to, Color(1, 0.8, 0.45, 0.55), 4)
	elif phase == "recover" and phase_left > 0.65:
		sword_to = sword_from + _sword_vector(1)
	elif phase == "stagger":
		draw_circle(Vector2(-10, -height - 15), 2, Color("ffe28b"))
		draw_circle(Vector2(10, -height - 15), 2, Color("ffe28b"))
	draw_line(sword_from, sword_to, Color("c4cdd0"), 5 if boss else 3)
	draw_rect(Rect2(-30, -height - 10, 60, 4), Color("202a36"))
	draw_rect(Rect2(-30, -height - 10, 60.0 * health / max_health, 4), Color("d47664"))
	if posture > 0:
		draw_rect(Rect2(-30, -height - 5, 60 * posture / (100 if boss else 60), 2), Color("ffd572"))
