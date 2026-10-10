@tool
extends CharacterBody2D

signal defeated(enemy: Node)
@export_group("Identity")
## 头顶名称与战斗提示使用这个名字，与场景树节点名称无关。
@export var display_name: String = "持刀小怪":
	set(value):
		display_name = value
		_refresh_preview()
## Boss 不会被普通冰红茶命中打断；其余数值由场景单独配置。
@export var boss := false
@export var body_color := Color("637985"):
	set(value):
		body_color = value
		queue_redraw()
@export var body_size := Vector2(26, 42):
	set(value):
		body_size = Vector2(maxf(8, value.x), maxf(8, value.y))
		_refresh_preview()

@export_group("Stats")
@export_range(1, 10000, 1) var max_health: int = 60
@export_range(1, 1000, 1) var attack_damage: int = 18
@export_range(1, 1000, 1) var max_posture: float = 60.0
@export_range(0, 600, 1) var move_speed: float = 58.0
@export var attacks_enabled := true

@export_group("Awareness")
## 距离脚底的水平 / 垂直警戒范围；范围外保持原地，不会全图追击。
@export_range(0, 5000, 10) var detection_range: float = 420.0
@export_range(0, 2000, 10) var detection_height: float = 160.0
## 留空会自动寻找 player 分组中的玩家。
@export var target: CharacterBody2D

@export_group("Attack")
## 进入这个水平距离后开始蓄力；实际命中范围由刀刃长度和轨迹决定。
@export_range(1, 500, 1) var attack_range: float = 70.0
@export_range(0.05, 5, 0.01) var windup_duration: float = 0.65
## 蓄力结束后的实际挥刀时间；命中取决于刀刃触碰玩家，而非这个阶段开始。
@export_range(0.05, 2, 0.01) var swing_duration: float = 0.28
@export_range(0.05, 5, 0.01) var recovery_duration: float = 1.0
@export_range(0, 5, 0.05) var initial_attack_delay: float = 0.6
@export_range(1, 500, 1) var sword_length: float = 72.0:
	set(value):
		sword_length = value
		queue_redraw()
@export_range(1, 20, 0.5) var sword_width: float = 3.0:
	set(value):
		sword_width = value
		queue_redraw()

var health := 60
var posture := 0.0
var phase := "approach"
var phase_left := 0.6
var facing := -1.0
var attack_id := 0
var hit_flash := 0.0
var alive := true
var swing_elapsed := 0.0
var _swing_hit := false
var _target_search_left := 0.0

func _ready() -> void:
	_refresh_preview()
	if Engine.is_editor_hint():
		return
	add_to_group("enemies")
	health = max_health
	phase_left = initial_attack_delay
	_find_target()

func _refresh_preview() -> void:
	if not is_node_ready():
		return
	var shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape == null:
		return
	# 每个实例拥有独立碰撞资源，编辑一只的体型不会改变其他小怪。
	var rectangle := RectangleShape2D.new()
	rectangle.size = body_size
	shape.shape = rectangle
	shape.position.y = -body_size.y / 2
	var label := get_node_or_null("NameLabel") as Label
	if label != null:
		label.text = display_name
		label.position = Vector2(-90, -body_size.y - 54)
	queue_redraw()

func _find_target() -> void:
	if is_instance_valid(target):
		return
	var candidate := get_tree().get_first_node_in_group("player")
	if candidate is CharacterBody2D and candidate.has_node("Combat"):
		target = candidate

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not alive:
		return
	if not is_instance_valid(target):
		_target_search_left -= delta
		if _target_search_left <= 0:
			_find_target()
			_target_search_left = 0.5
	hit_flash = maxf(0, hit_flash - delta)
	phase_left -= delta
	velocity.y = minf(480, velocity.y + 1800 * delta)
	if not is_instance_valid(target) or not target.has_node("Combat") or target.combat.dead or not attacks_enabled:
		velocity.x = 0
		move_and_slide()
		queue_redraw()
		return
	var distance: float = target.global_position.x - global_position.x
	match phase:
		"approach":
			posture = maxf(0, posture - delta * 5)
			if absf(distance) > detection_range or absf(target.global_position.y - global_position.y) > detection_height:
				velocity.x = 0
				move_and_slide()
				queue_redraw()
				return
			facing = signf(distance) if absf(distance) > 1 else facing
			velocity.x = facing * move_speed if absf(distance) > attack_range else 0.0
			if absf(distance) <= attack_range + 4 and absf(target.global_position.y - global_position.y) < 80 and phase_left <= 0:
				phase = "windup"
				phase_left = windup_duration
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
				phase_left = recovery_duration
		"recover", "stagger":
			velocity.x = move_toward(velocity.x, 0, delta * 700)
			if phase_left <= 0:
				phase = "approach"
	move_and_slide()
	queue_redraw()

func _swing_duration() -> float:
	return maxf(0.05, swing_duration)

func _sword_origin() -> Vector2:
	return Vector2(facing * (body_size.x / 2 + 5), -body_size.y * 0.55)

func _sword_vector(progress: float) -> Vector2:
	var angle := lerpf(deg_to_rad(-110), deg_to_rad(25), clampf(progress, 0, 1))
	return Vector2(cos(angle) * facing, sin(angle)) * sword_length

func _sweep_blade(previous: float, current: float) -> void:
	if _swing_hit:
		return
	# 画面和物理使用相同刀刃姿态；角度分段避免低物理帧率跳过玩家。
	var steps := maxi(1, ceili((current - previous) / _swing_duration() * 135.0 / 3.0))
	var blade := CapsuleShape2D.new()
	blade.radius = sword_width / 2
	blade.height = sword_length + blade.radius * 2
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
			target.combat.receive_attack(self, attack_id, attack_damage)
			return

func parried() -> void:
	posture += 40
	phase = "stagger"
	phase_left = 1.1
	velocity.x = -facing * 110
	if posture >= max_posture:
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
	var height := body_size.y
	var width := body_size.x
	var color := body_color
	if hit_flash > 0:
		color = Color("fff0b5")
	draw_rect(Rect2(-width / 2, -height, width, height), color)
	draw_rect(Rect2(-width / 2 - 5, -height + 12, width + 10, 9), color.lightened(0.2))
	draw_rect(Rect2(facing * 6 - 5, -height + 8, 10, 4), Color("ffc369"))
	draw_rect(Rect2(-width / 2, -8, width, 8), Color("27363f"))
	var sword_from := _sword_origin()
	var sword_to := sword_from + Vector2(facing * 7, -32)
	if phase == "windup":
		var progress := 1.0 - phase_left / maxf(0.05, windup_duration)
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
	draw_line(sword_from, sword_to, Color("c4cdd0"), sword_width)
	draw_rect(Rect2(-30, -height - 10, 60, 4), Color("202a36"))
	draw_rect(Rect2(-30, -height - 10, 60.0 * (1.0 if Engine.is_editor_hint() else float(health) / maxi(1, max_health)), 4), Color("d47664"))
	if posture > 0:
		draw_rect(Rect2(-30, -height - 5, 60 * posture / maxf(1, max_posture), 2), Color("ffd572"))
