extends Node2D

signal died
signal feedback(message: String)

@export var max_health: int = 100
@export var max_guard: float = 100.0
@export var perfect_window: float = 0.16
@export var perfect_rearm_delay: float = 0.32
@export var block_cost: float = 24.0
var health := 100
var guard := 100.0
var guarding := false
var dead := false
var held_tea: Node2D
var perfect_left := 0.0
var rearm_left := 0.0
var invulnerable_left := 0.0
var hitstun_left := 0.0
var guard_recovery_left := 0.0
var last_result := ""
var flash_left := 0.0
var _seen_attacks: Dictionary = {}
var _audio: AudioStreamPlayer
var _block_sound: AudioStream
var _parry_sound: AudioStream
var _grab_release_armed := false
var _input_reset_serial := -1
@onready var actor: CharacterBody2D = get_parent()

func _ready() -> void:
	health = max_health
	guard = max_guard
	_audio = AudioStreamPlayer.new()
	_audio.volume_db = -6
	_audio.max_polyphony = 4
	add_child(_audio)
	_block_sound = load("res://Assets/Audio/block.wav")
	_parry_sound = load("res://Assets/Audio/parry.wav")

func carrying() -> bool:
	return is_instance_valid(held_tea)

func _exit_tree() -> void:
	# 重试 / 切换场景时结束尚未播放完的金属余音。
	if is_instance_valid(_audio):
		_audio.stop()
		_audio.stream = null

func movement_factor() -> float:
	return 0.35 if guarding else (70.0 / 90.0 if carrying() else 1.0)

# Called by Player before movement so defensive inputs are deterministic in physics time.
func tick(delta: float) -> bool:
	perfect_left = maxf(0, perfect_left - delta)
	rearm_left = maxf(0, rearm_left - delta)
	invulnerable_left = maxf(0, invulnerable_left - delta)
	hitstun_left = maxf(0, hitstun_left - delta)
	guard_recovery_left = maxf(0, guard_recovery_left - delta)
	flash_left = maxf(0, flash_left - delta)
	if dead or hitstun_left > 0:
		guarding = false
		actor.velocity.x = move_toward(actor.velocity.x, 0, delta * 600)
		actor.velocity.y = minf(480, actor.velocity.y + actor.get_gravity().y * actor.gravity_scale * delta)
		actor.move_and_slide()
		queue_redraw()
		return false
	var can_guard: bool = actor.get("_dash_time_left") <= 0 and not actor.is_climbing
	if Input.is_action_just_pressed("defend") and can_guard:
		if carrying():
			throw_tea(true)
		if rearm_left <= 0:
			perfect_left = perfect_window
			rearm_left = perfect_rearm_delay
	guarding = can_guard and Input.is_action_pressed("defend")
	if not guarding:
		perfect_left = 0
	if guard_recovery_left <= 0:
		guard = minf(max_guard, guard + delta * (12 if guarding else 32))
	_update_grab()
	if carrying():
		held_tea.follow_holder()
	queue_redraw()
	return true

func _process(_delta: float) -> void:
	if carrying():
		held_tea.follow_holder()

func _update_grab() -> void:
	if _input_reset_serial != KeyBindings.input_reset_serial:
		_input_reset_serial = KeyBindings.input_reset_serial
		# 菜单、改键和切换模式清除输入时，不能把手中的瓶子意外扔出去。
		_grab_release_armed = false
		if carrying():
			KeyBindings.resume_carried_grab()
			_grab_release_armed = KeyBindings.grab_mode == "toggle"
	var grabbing := KeyBindings.is_grabbing()
	if carrying():
		if grabbing:
			_grab_release_armed = true
		elif _grab_release_armed:
			throw_tea(Input.is_action_pressed("aim_down"))
	elif grabbing and not guarding and actor.get("_dash_time_left") <= 0:
		# 提前按住抓取再靠近瓶子也能拾取；与抓墙共享同一逻辑状态。
		if try_pick_up(false):
			_grab_release_armed = true

func try_pick_up(show_hint: bool = true) -> bool:
	if carrying() or dead:
		return false
	var closest: Node2D
	var distance := 48.0
	var center := actor.global_position + Vector2(0, -20)
	for tea: Node2D in get_tree().get_nodes_in_group("tea_bottles"):
		if not tea.can_pick_up():
			continue
		var next_distance := center.distance_to(tea.global_position)
		if next_distance < distance:
			var ray := PhysicsRayQueryParameters2D.create(center, tea.global_position, 1)
			if actor.get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
				closest = tea
				distance = next_distance
	if closest == null:
		if show_hint:
			feedback.emit("靠近冰红茶再抓取")
		return false
	held_tea = closest
	held_tea.pick_up(actor)
	actor.is_climbing = false
	actor._dash_buffer_left = 0
	feedback.emit("拿好了：再按抓取键投掷，配合向下则放下" if KeyBindings.grab_mode == "toggle" else "拿好了：松开抓取键投掷，按住向下再松开则放下")
	return true

func throw_tea(drop: bool = false) -> void:
	if not carrying():
		return
	var horizontal := Input.get_axis("move_left", "move_right")
	if horizontal != 0:
		actor._face(horizontal)
	held_tea.release_from_hand(actor.get("_facing"), actor.velocity, drop)
	held_tea = null
	_grab_release_armed = false

func receive_attack(source: Node2D, attack_id: int, damage: int) -> String:
	if dead or not is_instance_valid(source):
		return "ignored"
	var key := "%s:%s" % [source.get_instance_id(), attack_id]
	if _seen_attacks.has(key):
		return "ignored"
	_seen_attacks[key] = true
	if _seen_attacks.size() > 64:
		_seen_attacks.erase(_seen_attacks.keys()[0])
	if invulnerable_left > 0 or actor.get("_dash_time_left") > 0:
		return "evaded"
	var front: bool = (source.global_position.x - actor.global_position.x) * actor.get("_facing") >= 0
	var valid_guard: bool = guarding and Input.is_action_pressed("defend") and not actor.is_climbing
	if valid_guard and front:
		guard_recovery_left = 0.6
		if perfect_left > 0:
			perfect_left = 0
			guard = minf(max_guard, guard + 18)
			if source.has_method("parried"):
				source.parried()
			_resolve("parry", "精准防御！", Color("ffe28b"))
			return "parry"
		guard = maxf(0, guard - block_cost)
		if guard > 0:
			_resolve("block", "格挡", Color("7dbacb"))
			return "block"
		guarding = false
		hitstun_left = 0.65
		feedback.emit("架势崩溃！松开防御恢复架势")
	# 背后命中和破防都正常扣血；短暂无敌避免同一轮受击重复扣血。
	health = maxi(0, health - damage)
	invulnerable_left = 0.55
	hitstun_left = maxf(hitstun_left, 0.18)
	perfect_left = 0
	throw_tea(true)
	_cancel_movement()
	var away := signf(actor.global_position.x - source.global_position.x)
	actor.velocity = Vector2(away * 200, -120)
	_resolve("hurt", "受伤  -%d" % damage if guard > 0 else "破防受伤  -%d" % damage, Color("ed7469"))
	if health <= 0:
		dead = true
		guarding = false
		feedback.emit("倒下了。点击「重试」再来一次")
		died.emit()
	return "hurt"

func _cancel_movement() -> void:
	actor._dash_time_left = 0
	actor._dash_pause_left = 0
	actor._dash_buffer_left = 0
	actor._variable_jump_left = 0
	actor._force_move_left = 0
	actor._wall_retention_left = 0
	actor._jump_buffer_left = 0
	actor.is_climbing = false

func _resolve(result: String, message: String, tint: Color) -> void:
	last_result = result
	flash_left = 0.3
	feedback.emit(message)
	if result == "parry" or result == "block":
		_audio.stream = _parry_sound if result == "parry" else _block_sound
		_audio.play()
	var spark := preload("res://Scripts/Combat/HitSpark.gd").new()
	spark.position = actor.global_position + Vector2(actor.get("_facing") * 17, -22)
	spark.tint = tint
	spark.strong = result == "parry"
	actor.get_parent().add_child(spark)

func _draw() -> void:
	if guarding:
		var color := Color("ffe28b") if perfect_left > 0 else Color("77adbd")
		var direction: float = actor.get("_facing")
		draw_arc(Vector2(0, -22), 27, -1.15 if direction > 0 else PI - 1.15, 1.15 if direction > 0 else PI + 1.15, 16, color, 4)
	if flash_left > 0:
		draw_circle(Vector2(0, -22), 22, Color(1, 0.85, 0.5, flash_left * 0.4))
