extends CharacterBody2D

# 参考 Celeste Player 的 Normal / Dash / Climb；空间参数约放大三倍，时间保持原比例。
# 使用 Godot 的胶囊碰撞与连续坐标，并非 Celeste 的逐像素碰撞实现。
@export_group("Movement")
@export var move_speed: float = 270.0
@export var run_acceleration: float = 3000.0
@export var run_reduction: float = 1200.0
@export_range(0.0, 1.0) var air_control: float = 0.65

@export_group("Jump")
@export var jump_speed: float = 315.0
@export var jump_horizontal_boost: float = 120.0
## 离开平台后仍可起跳的时间。
@export var coyote_time: float = 0.1
## 落地前提前按跳跃，保留这次输入的时间。
@export var jump_buffer_time: float = 0.1
## 持续按住跳跃时，维持初始上升速度的时间；松开可小跳。
@export var variable_jump_time: float = 0.2
@export var wall_jump_speed: float = 390.0
@export var wall_jump_force_time: float = 0.16
@export var wall_boost_window: float = 0.2
@export var wall_speed_retention_time: float = 0.06
@export_range(0, 24, 1) var corner_correction: int = 12

@export_group("Gravity")
## 基于项目 Physics > 2D > Default Gravity；默认合计约 2700 像素/秒²。
@export_range(0.1, 5.0, 0.01) var gravity_scale: float = 2.755102
@export_range(1.0, 5.0, 0.1) var fall_gravity_multiplier: float = 1.0
@export var half_gravity_threshold: float = 120.0
## 达到普通落速后，按住向下才会提高落速上限。
@export var max_fall_speed: float = 480.0
@export var fast_max_fall_speed: float = 720.0
@export var fast_fall_acceleration: float = 900.0
@export var wall_slide_start_speed: float = 60.0
@export var wall_slide_time: float = 1.2

@export_group("Dash")
@export_range(1.0, 2000.0) var dash_speed: float = 720.0
@export_range(0.01, 0.5) var dash_duration: float = 0.15
## 起手短暂停顿；只暂停玩家，不暂停菜单和世界。
@export var dash_start_pause: float = 0.05
## 从按下冲刺开始计时。
@export_range(0.0, 2.0) var dash_cooldown: float = 0.2
@export var dash_end_speed: float = 480.0
@export var dash_refill_delay: float = 0.1
@export var dash_attack_time: float = 0.3
@export var dash_buffer_time: float = 0.1
@export var super_jump_speed: float = 780.0
@export var hyper_jump_multiplier: float = 1.25
@export var hyper_jump_height_multiplier: float = 0.5
@export var wall_bounce_speed := Vector2(510.0, -480.0)

@export_group("Climb")
@export var max_stamina: float = 110.0
@export var climb_up_speed: float = 135.0
@export var climb_down_speed: float = 240.0
@export var climb_acceleration: float = 2700.0
@export var climb_up_cost: float = 100.0 / 2.2
@export var climb_hold_cost: float = 10.0
@export var climb_jump_cost: float = 27.5
@export var tired_threshold: float = 20.0

const AFTERIMAGE_INTERVAL: float = 0.025
const AFTERIMAGE_LIFETIME: float = 0.28
const GRAB_DISTANCE: float = 6.0
const WALL_JUMP_DISTANCE: float = 9.0

var stamina: float = 110.0
var is_climbing: bool = false
var is_ducking: bool = false
var _facing: float = 1.0
var _climb_side: float = 1.0
var _climb_wait: float = 0.0
var _regrab_lock: float = 0.0
var _wall_slide_left: float = 0.0
var _coyote_left: float = 0.0
var _jump_buffer_left: float = 0.0
var _variable_jump_left: float = 0.0
var _variable_jump_speed: float = 0.0
var _force_move_left: float = 0.0
var _force_move_direction: float = 0.0
var _wall_boost_left: float = 0.0
var _wall_boost_direction: float = 0.0
var _wall_boost_refund: float = 0.0
var _wall_retention_left: float = 0.0
var _wall_retained_speed: float = 0.0
var _dash_attack_left: float = 0.0
var _dash_buffer_left: float = 0.0
var _dash_started_on_ground: bool = false
var _dash_direction := Vector2.RIGHT
# 独立保存冲刺驱动力：move_and_slide 的碰撞反馈不能提前结束冲刺。
var _dash_velocity := Vector2.ZERO
var _dash_time_left: float = 0.0
var _dash_pause_left: float = 0.0
var _dash_cooldown_left: float = 0.0
var _dash_refill_left: float = 0.0
var _dash_sliding: bool = false
var _afterimage_time_left: float = 0.0
var _air_dash_used: bool = false
var _fall_speed_limit: float = 0.0
var _afterimage_material := CanvasItemMaterial.new()
var _standing_shape: Shape2D
var _duck_shape: CapsuleShape2D

@onready var sprite: Sprite2D = $Sprite2D
@onready var _normal_modulate: Color = sprite.modulate
@onready var _body_shape: CollisionShape2D = $CollisionShape2D
@onready var _standing_offset: Vector2 = _body_shape.position
@onready var _sprite_offset: Vector2 = sprite.position


func _ready() -> void:
	_standing_shape = _body_shape.shape
	_duck_shape = CapsuleShape2D.new()
	_duck_shape.radius = 10.0
	_duck_shape.height = 24.0
	stamina = max_stamina
	_fall_speed_limit = max_fall_speed
	_wall_slide_left = wall_slide_time
	_afterimage_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_afterimage_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED


func dash_available() -> bool:
	return not _air_dash_used and _dash_cooldown_left <= 0.0


func _physics_process(delta: float) -> void:
	# 起手停顿不推进玩家的动作窗口；停顿中按下的跳跃/冲刺仍会缓存。
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_left = jump_buffer_time
	if Input.is_action_just_pressed("dash"):
		_dash_buffer_left = dash_buffer_time
	if _dash_pause_left > 0.0:
		var frozen := minf(delta, _dash_pause_left)
		_dash_pause_left -= frozen
		delta -= frozen
		if delta <= 0.000001:
			return
	_dash_cooldown_left = maxf(0.0, _dash_cooldown_left - delta)
	_dash_refill_left = maxf(0.0, _dash_refill_left - delta)
	_regrab_lock = maxf(0.0, _regrab_lock - delta)
	_force_move_left = maxf(0.0, _force_move_left - delta)
	_coyote_left = maxf(0.0, _coyote_left - delta)
	_jump_buffer_left = maxf(0.0, _jump_buffer_left - delta)
	_dash_buffer_left = maxf(0.0, _dash_buffer_left - delta)
	_dash_attack_left = maxf(0.0, _dash_attack_left - delta)
	_variable_jump_left = maxf(0.0, _variable_jump_left - delta)
	var grounded := _on_ground()
	if grounded:
		stamina = max_stamina
		_wall_slide_left = wall_slide_time
		_coyote_left = coyote_time
		_fall_speed_limit = max_fall_speed
		if _dash_refill_left <= 0.0:
			_air_dash_used = false
	var horizontal := Input.get_axis("move_left", "move_right")
	if horizontal != 0.0 and not is_climbing:
		_face(horizontal)
	_update_wall_windows(delta, horizontal)
	if _dash_buffer_left > 0.0 and dash_available() and _dash_time_left <= 0.0:
		_begin_dash()
	if _dash_time_left > 0.0:
		_update_dash(delta, grounded)
		return
	if is_climbing:
		_update_climb(delta, horizontal, grounded)
		return
	if Input.is_action_pressed("grab") and not is_ducking and stamina >= tired_threshold and _regrab_lock <= 0.0 and velocity.y >= 0.0 and signf(velocity.x) != -_facing and _wall_at(_facing, GRAB_DISTANCE):
		_begin_climb()
		_update_climb(delta, horizontal, grounded)
		return
	_update_normal(delta, horizontal, grounded)


func _on_ground() -> bool:
	if velocity.y < 0.0:
		return false
	var hit := KinematicCollision2D.new()
	return test_move(global_transform, Vector2(0.0, 0.2), hit) and hit.get_normal().y < -0.7


func _wall_at(side: float, distance: float) -> bool:
	var hit := KinematicCollision2D.new()
	return test_move(global_transform, Vector2(side * distance, 0.0), hit) and hit.get_normal().x * side < -0.8


func _jump_wall_side() -> float:
	if _wall_at(_facing, WALL_JUMP_DISTANCE):
		return _facing
	if _wall_at(-_facing, WALL_JUMP_DISTANCE):
		return -_facing
	return 0.0


func _face(direction: float) -> void:
	_facing = signf(direction)
	sprite.flip_h = _facing < 0.0


func _update_normal(delta: float, horizontal: float, grounded: bool) -> void:
	if grounded and Input.is_action_pressed("aim_down"):
		_set_ducking(true)
	elif is_ducking and _can_stand():
		_set_ducking(false)
	if _force_move_left > 0.0:
		horizontal = _force_move_direction
	var acceleration := run_acceleration
	if absf(velocity.x) > move_speed and signf(velocity.x) == horizontal:
		acceleration = run_reduction
	if is_ducking and grounded:
		velocity.x = move_toward(velocity.x, 0.0, 1500.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, horizontal * move_speed, acceleration * (1.0 if grounded else air_control) * delta)
	if not grounded:
		_update_fall(delta, horizontal)
		if _variable_jump_left > 0.0:
			if Input.is_action_pressed("jump"):
				velocity.y = minf(velocity.y, _variable_jump_speed)
			else:
				_variable_jump_left = 0.0
	else:
		# 保持与地面的物理接触，让 is_on_floor 和菜单提示一致。
		velocity.y = 1.0
	# 源码在重力/变高跳计算之后处理新的起跳，首帧不扣一次重力。
	if _jump_buffer_left > 0.0 and _can_stand():
		if _coyote_left > 0.0:
			velocity.x += horizontal * jump_horizontal_boost
			_start_jump(jump_speed)
		else:
			var side := _jump_wall_side()
			if side != 0.0:
				if side == _facing and Input.is_action_pressed("grab") and stamina > 0.0:
					_climb_jump(horizontal, grounded)
				else:
					_wall_jump(-side, _dash_attack_left > 0.0 and _dash_direction == Vector2.UP)
	_move_player(delta)
	if is_on_ceiling():
		if _variable_jump_left < variable_jump_time - 0.05:
			_variable_jump_left = 0.0


func _update_fall(delta: float, horizontal: float) -> void:
	var target_limit := max_fall_speed
	if Input.get_axis("aim_up", "aim_down") > 0.0 and velocity.y >= max_fall_speed:
		target_limit = maxf(max_fall_speed, fast_max_fall_speed)
	_fall_speed_limit = move_toward(_fall_speed_limit, target_limit, fast_fall_acceleration * delta)
	var limit := _fall_speed_limit
	# 不抓墙也可朝墙缓滑；缓滑效果逐渐减弱，不能无限挂墙。
	var toward_wall := horizontal == _facing or (horizontal == 0.0 and Input.is_action_pressed("grab"))
	if toward_wall and not Input.is_action_pressed("aim_down") and velocity.y >= 0.0 and stamina > 0.0 and _wall_slide_left > 0.0 and _wall_at(_facing, GRAB_DISTANCE):
		limit = minf(limit, lerpf(max_fall_speed, wall_slide_start_speed, _wall_slide_left / maxf(0.001, wall_slide_time)))
		_wall_slide_left = maxf(0.0, _wall_slide_left - delta)
	var acceleration := get_gravity().y * gravity_scale
	if velocity.y >= 0.0:
		acceleration *= fall_gravity_multiplier
	if absf(velocity.y) < half_gravity_threshold and Input.is_action_pressed("jump"):
		acceleration *= 0.5
	velocity.y = move_toward(velocity.y, limit, acceleration * delta)


func _start_jump(speed: float, hold_time: float = -1.0) -> void:
	_set_ducking(false)
	_dash_attack_left = 0.0
	_wall_boost_left = 0.0
	_wall_slide_left = wall_slide_time
	is_climbing = false
	_jump_buffer_left = 0.0
	_coyote_left = 0.0
	_variable_jump_left = variable_jump_time if hold_time < 0.0 else hold_time
	_variable_jump_speed = -speed
	velocity.y = -speed
	_regrab_lock = 0.1


func _wall_jump(direction: float, super_jump: bool = false) -> void:
	_start_jump(-wall_bounce_speed.y if super_jump else jump_speed, 0.25 if super_jump else variable_jump_time)
	velocity.x = direction * (wall_bounce_speed.x if super_jump else wall_jump_speed)
	_force_move_left = 0.0
	# Neutral jump 的核心：无左右输入就不强推，允许立即向墙面空中转向。
	if not super_jump and Input.get_axis("move_left", "move_right") != 0.0:
		_force_move_direction = direction
		_force_move_left = wall_jump_force_time


func _climb_jump(horizontal: float, grounded: bool) -> void:
	var refund := climb_jump_cost if not grounded else 0.0
	# 允许暂时为负，窗口内返还实际扣款；窗口过后再归零，避免凭空多回体力。
	stamina -= refund
	velocity.x += horizontal * jump_horizontal_boost
	_start_jump(jump_speed)
	if horizontal == 0.0 and refund > 0.0:
		_wall_boost_left = wall_boost_window
		_wall_boost_direction = -_facing
		_wall_boost_refund = refund


func _update_wall_windows(delta: float, horizontal: float) -> void:
	if _wall_boost_left > 0.0:
		_wall_boost_left = maxf(0.0, _wall_boost_left - delta)
		if _wall_boost_left > 0.000001 and horizontal == _wall_boost_direction:
			velocity.x = wall_jump_speed * horizontal
			stamina = minf(max_stamina, stamina + _wall_boost_refund)
			_wall_boost_left = 0.0
	if _wall_boost_left <= 0.0:
		stamina = maxf(0.0, stamina)
	if _wall_retention_left > 0.0:
		if signf(velocity.x) == -signf(_wall_retained_speed):
			_wall_retention_left = 0.0
		elif not _wall_at(signf(_wall_retained_speed), 0.5):
			velocity.x = _wall_retained_speed
			_wall_retention_left = 0.0
		else:
			_wall_retention_left = maxf(0.0, _wall_retention_left - delta)


func _begin_climb() -> void:
	_wall_boost_left = 0.0
	_wall_retention_left = 0.0
	is_climbing = true
	_climb_side = _facing
	_climb_wait = 0.1
	_wall_slide_left = wall_slide_time
	velocity = Vector2(0.0, velocity.y * 0.2)
	# 把抓墙容错距离内的间隙收拢；碰撞仍由物理引擎处理。
	move_and_collide(Vector2(_climb_side * GRAB_DISTANCE, 0.0))


func _update_climb(delta: float, horizontal: float, grounded: bool) -> void:
	if not Input.is_action_pressed("grab") or stamina <= 0.0:
		is_climbing = false
		_regrab_lock = 0.1
		_update_normal(delta, horizontal, grounded)
		return
	if _jump_buffer_left > 0.0 and _can_stand():
		if horizontal == -_climb_side:
			_wall_jump(-_climb_side)
		else:
			_climb_jump(horizontal, grounded)
		_move_player(delta)
		return
	if not _wall_at(_climb_side, GRAB_DISTANCE):
		is_climbing = false
		if velocity.y < 0.0:
			# 越过墙沿时轻轻向前翻上平台，路径仍正常检测碰撞。
			velocity = Vector2(_climb_side * 300.0, -360.0)
			# 源码这里强制零水平输入，让起跳惯性自然减速，防止越过窄平台。
			_force_move_direction = 0.0
			_force_move_left = 0.2
			_regrab_lock = 0.2
		_update_normal(delta, horizontal, grounded)
		return
	_climb_wait = maxf(0.0, _climb_wait - delta)
	var vertical := Input.get_axis("aim_up", "aim_down") if _climb_wait <= 0.0 else 0.0
	var target := -climb_up_speed if vertical < 0.0 else climb_down_speed * vertical
	if grounded and target > 0.0:
		target = 0.0
	velocity.x = 0.0
	velocity.y = move_toward(velocity.y, target, climb_acceleration * delta)
	move_and_slide()
	if not grounded and _climb_wait <= 0.0:
		var cost := climb_up_cost if vertical < 0.0 else (climb_hold_cost if vertical == 0.0 else 0.0)
		stamina = maxf(0.0, stamina - cost * delta)
		if stamina <= 0.0:
			is_climbing = false
			_regrab_lock = 0.1


func _begin_dash() -> void:
	_dash_buffer_left = 0.0
	_wall_boost_left = 0.0
	_wall_retention_left = 0.0
	_wall_slide_left = wall_slide_time
	_dash_attack_left = dash_attack_time
	_dash_started_on_ground = _on_ground()
	if not _dash_started_on_ground and _can_stand():
		_set_ducking(false)
	elif _dash_started_on_ground and Input.is_action_pressed("aim_down"):
		_set_ducking(true)
	is_climbing = false
	_variable_jump_left = 0.0
	_force_move_left = 0.0
	_dash_direction = Input.get_vector("move_left", "move_right", "aim_up", "aim_down")
	if _dash_direction == Vector2.ZERO:
		_dash_direction = Vector2(_facing, 0.0)
	_dash_velocity = _dash_direction * dash_speed
	if signf(velocity.x) == signf(_dash_velocity.x) and absf(velocity.x) > absf(_dash_velocity.x):
		_dash_velocity.x = velocity.x
	_dash_time_left = dash_duration
	_dash_pause_left = dash_start_pause
	_dash_cooldown_left = dash_cooldown
	_dash_refill_left = dash_refill_delay
	_dash_sliding = false
	_air_dash_used = true
	_afterimage_time_left = AFTERIMAGE_INTERVAL
	velocity = Vector2.ZERO
	sprite.modulate = Color(0.65, 1.0, 1.0)
	_spawn_afterimage()


func _update_dash(delta: float, grounded: bool) -> void:
	var step := delta
	if _dash_pause_left > 0.0:
		var pause_step := minf(step, _dash_pause_left)
		_dash_pause_left = maxf(0.0, _dash_pause_left - pause_step)
		step -= pause_step
		if step <= 0.000001:
			return
	if grounded and _dash_direction.y > 0.0 and _dash_direction.x != 0.0:
		_dash_slide()
	if _jump_buffer_left > 0.0 and _can_stand():
		if _coyote_left > 0.0 and _dash_direction.y == 0.0:
			_super_jump()
			_move_player(delta)
			return
		var side := _jump_wall_side()
		if side != 0.0:
			var upward := _dash_direction.y < 0.0 and _dash_direction.x == 0.0
			_end_dash()
			_wall_jump(-side, upward)
			_move_player(delta)
			return
	step = minf(step, _dash_time_left)
	velocity = _dash_velocity
	_move_player(step, true)
	_dash_time_left = maxf(0.0, _dash_time_left - step)
	_afterimage_time_left -= step
	if _afterimage_time_left <= 0.0:
		_spawn_afterimage()
		_afterimage_time_left += AFTERIMAGE_INTERVAL
	# 墙壁只阻挡位移；冲刺驱动力、计时和残影保持到动作结束。
	if _dash_time_left <= 0.000001:
		_end_dash()


func _super_jump() -> void:
	var low_jump := is_ducking
	# 使用起跳时朝向，支持 reverse super / hyper；不受原冲刺方向锁死。
	var direction := _facing
	_end_dash()
	_start_jump(jump_speed * (hyper_jump_height_multiplier if low_jump else 1.0))
	velocity.x = direction * super_jump_speed * (hyper_jump_multiplier if low_jump else 1.0)


func _dash_slide() -> void:
	_dash_direction = Vector2(signf(_dash_direction.x), 0.0)
	if _dash_time_left > 0.0:
		_dash_velocity = Vector2(_dash_velocity.x * 1.2, 0.0)
		velocity = _dash_velocity
	else:
		# 斜下冲刺结束后才落地，也保留水平速度并乘 1.2：ultra 的基础。
		velocity.x *= 1.2
		velocity.y = 0.0
	_dash_sliding = true
	_set_ducking(true)


func _can_stand() -> bool:
	if not is_ducking:
		return true
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _standing_shape
	query.transform = global_transform * Transform2D(0.0, _standing_offset)
	# 接触地面不等于站立空间被占用；避开查询把零间隙接触视为重叠。
	query.transform.origin.y -= safe_margin + 0.01
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _set_ducking(duck: bool) -> void:
	if is_ducking == duck:
		return
	is_ducking = duck
	_body_shape.shape = _duck_shape if duck else _standing_shape
	_body_shape.position = Vector2(0.0, -12.0) if duck else _standing_offset
	sprite.scale = Vector2(1.2, 0.6) if duck else Vector2.ONE
	sprite.position = _sprite_offset * Vector2(1.0, 0.6) if duck else _sprite_offset


func _move_player(step: float, dashing: bool = false) -> void:
	var motion := velocity * step
	_corner_adjust(motion, dashing)
	var before := velocity
	var frame_delta := get_physics_process_delta_time()
	# move_and_slide 使用完整物理帧时长；只走剩余冲刺时间，随后恢复速度单位。
	velocity *= step / frame_delta
	move_and_slide()
	velocity *= frame_delta / step
	if is_on_wall() and absf(before.x) > 0.0 and not dashing:
		if _wall_retention_left <= 0.0:
			_wall_retained_speed = before.x
			_wall_retention_left = wall_speed_retention_time
		_dash_attack_left = 0.0
	if is_on_floor() and before.y > 0.0:
		if _dash_direction.y > 0.0 and _dash_direction.x != 0.0:
			velocity.x = before.x
			_dash_slide()
		_dash_attack_left = 0.0
	elif is_on_ceiling():
		_dash_attack_left = 0.0


func _corner_adjust(motion: Vector2, dashing: bool) -> void:
	if corner_correction <= 0:
		return
	var hit := KinematicCollision2D.new()
	if not test_move(global_transform, motion, hit):
		return
	var normal := hit.get_normal()
	# 地面水平冲刺遇到可钻过的低矮通道时自动压低碰撞体。
	if dashing and _on_ground() and absf(normal.x) > 0.7 and not is_ducking:
		_set_ducking(true)
		if not test_move(global_transform, motion):
			return
		_set_ducking(false)
	var vertical_hit := motion.y < 0.0 and normal.y > 0.7
	var down_dash_hit := dashing and not _dash_started_on_ground and motion.y > 0.0 and normal.y < -0.7
	var horizontal_dash_hit := dashing and is_zero_approx(motion.y) and absf(normal.x) > 0.7
	if not (vertical_hit or down_dash_hit or horizontal_dash_hit):
		return
	for distance in range(1, corner_correction + 1):
		for side: float in [-1.0, 1.0]:
			if not horizontal_dash_hit and motion.x * side < 0.0:
				continue
			var offset := Vector2(0.0, side * distance) if horizontal_dash_hit else Vector2(side * distance, 0.0)
			var shifted := global_transform
			shifted.origin += offset
			# 校正的横/纵路径与后续移动都必须畅通，不能穿过薄墙或天花板。
			if not test_move(global_transform, offset) and not test_move(shifted, motion):
				move_and_collide(offset)
				return


func _end_dash() -> void:
	_dash_time_left = 0.0
	_dash_pause_left = 0.0
	velocity = _dash_direction * dash_end_speed if _dash_direction.y <= 0.0 else _dash_velocity
	if velocity.y < 0.0:
		velocity.y *= 0.75
	if (is_on_floor() and velocity.y > 0.0) or (is_on_ceiling() and velocity.y < 0.0):
		velocity.y = 0.0
	_fall_speed_limit = max_fall_speed
	sprite.modulate = _normal_modulate


func _spawn_afterimage() -> void:
	var afterimage := sprite.duplicate() as Sprite2D
	get_parent().add_child(afterimage)
	afterimage.global_transform = sprite.global_transform
	afterimage.z_index = z_index - 1
	afterimage.modulate = Color(0.3, 0.85, 1.0, 0.7)
	afterimage.material = _afterimage_material
	afterimage.add_to_group("dash_afterimages")
	var fade := afterimage.create_tween()
	fade.tween_property(afterimage, "modulate:a", 0.0, AFTERIMAGE_LIFETIME)
	fade.tween_callback(afterimage.queue_free)
