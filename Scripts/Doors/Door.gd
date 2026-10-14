@tool
extends Node2D

signal opened
signal closed

## 门的宽度和高度；根节点位于门底中央，摆放时与地面对齐。
@export var door_size := Vector2(24, 160):
	set(value):
		door_size = Vector2(maxf(8, value.x), maxf(32, value.y))
		_sync_shape()
## 触发器控制的门默认开启；Boss 门场景默认关闭。
@export var starts_open := true:
	set(value):
		starts_open = value
		if Engine.is_editor_hint():
			queue_redraw()

var is_open := true
var _close_requested := false
var _shutter_amount := 0.0
var _animation: Tween

func _ready() -> void:
	_sync_shape()
	if Engine.is_editor_hint():
		return
	add_to_group("respawn_reset")
	is_open = starts_open
	_shutter_amount = 0.0 if is_open else 1.0
	$Blocker/CollisionShape2D.disabled = is_open
	set_physics_process(false)

func reset_after_player_respawn() -> void:
	_close_requested = false
	set_physics_process(false)
	if _animation != null:
		_animation.kill()
	is_open = starts_open
	$Blocker/CollisionShape2D.set_deferred("disabled", is_open)
	_set_shutter_amount(0.0 if is_open else 1.0)

func _sync_shape() -> void:
	if is_node_ready():
		var rectangle := RectangleShape2D.new()
		rectangle.size = door_size
		$Blocker/CollisionShape2D.shape = rectangle
		$Blocker/CollisionShape2D.position = Vector2(0, -door_size.y / 2)
	queue_redraw()

## 开门后取消等待中的关门请求。
func open() -> void:
	_close_requested = false
	set_physics_process(false)
	if is_open:
		return
	is_open = true
	$Blocker/CollisionShape2D.set_deferred("disabled", true)
	_animate_shutter(0.0)
	opened.emit()

## 等玩家完全离开门框后关门，避免触发区域覆盖门口时夹住玩家。
func close() -> void:
	if not is_open:
		return
	_close_requested = true
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or not _close_requested:
		return
	var collision: CollisionShape2D = $Blocker/CollisionShape2D
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision.shape
	query.transform = collision.global_transform
	query.collision_mask = 2
	# 玩家所在的物理层；用门的实际碰撞形状检测，兼容不同玩家体型。
	if not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
		return
	_close_requested = false
	set_physics_process(false)
	is_open = false
	collision.set_deferred("disabled", false)
	_animate_shutter(1.0)
	closed.emit()

func _animate_shutter(amount: float) -> void:
	if _animation != null:
		_animation.kill()
	_animation = create_tween()
	_animation.tween_method(_set_shutter_amount, _shutter_amount, amount, 0.18)

func _set_shutter_amount(amount: float) -> void:
	_shutter_amount = amount
	queue_redraw()

func _draw() -> void:
	var amount := (0.0 if starts_open else 1.0) if Engine.is_editor_hint() else _shutter_amount
	var top_left := Vector2(-door_size.x / 2, -door_size.y)
	var brass := Color("938265")
	# 顶部横梁始终可见；门栅向上收起，开启后留下空的通道。
	draw_rect(Rect2(top_left + Vector2(-4, -6), Vector2(door_size.x + 8, 6)), Color("343532"))
	draw_line(top_left + Vector2(-4, -6), top_left + Vector2(door_size.x + 4, -6), brass, 2)
	if amount > 0.001:
		var shutter := Rect2(top_left, Vector2(door_size.x, door_size.y * amount))
		draw_rect(shutter, Color("292e31"))
		draw_rect(shutter, brass, false, 2)
		for x in range(6, int(door_size.x), 8):
			draw_line(top_left + Vector2(x, 0), top_left + Vector2(x, shutter.size.y), Color("545c60"), 2)
		for y in range(14, int(shutter.size.y), 28):
			draw_line(top_left + Vector2(0, y), top_left + Vector2(door_size.x, y), brass, 3)
	if Engine.is_editor_hint() and starts_open:
		draw_rect(Rect2(top_left, door_size), Color(0.8, 0.7, 0.4, 0.12))
		draw_rect(Rect2(top_left, door_size), Color(0.8, 0.7, 0.4, 0.65), false, 1)
