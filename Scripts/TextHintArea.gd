@tool
extends Area2D

## 玩家在区域内时显示的文字，支持换行。关卡中需要一个 GameUI 场景。
@export_multiline var message: String = "前方有敌人，小心应对。"
## 区域以根节点为中心。移动根节点摆放，修改这里调整宽、高。
@export var region_size := Vector2(240, 160):
	set(value):
		region_size = Vector2(maxf(1, value.x), maxf(1, value.y))
		_sync_region()
## 重叠时优先显示数值更高的提示；相同时优先显示最后进入的区域。
@export var hint_priority: int = 0
@export var enabled: bool = true
var entered_frame: int = -1

func _ready() -> void:
	_sync_region()
	if Engine.is_editor_hint():
		return
	add_to_group("text_hint_areas")
	body_entered.connect(_on_body_entered)

func _sync_region() -> void:
	if not is_node_ready():
		return
	var shape: CollisionShape2D = $CollisionShape2D
	var rectangle := RectangleShape2D.new()
	rectangle.size = region_size
	# 新建资源保证复制出来的区域能独立修改大小。
	shape.set_deferred("shape", rectangle)
	queue_redraw()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		entered_frame = Engine.get_physics_frames()

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var rect := Rect2(-region_size / 2, region_size)
	draw_rect(rect, Color(0.4, 0.8, 1, 0.12))
	draw_rect(rect, Color(0.4, 0.8, 1, 0.8), false, 2)
	draw_line(Vector2(-10, 0), Vector2(10, 0), Color(0.7, 0.9, 1), 2)
	draw_line(Vector2(0, -10), Vector2(0, 10), Color(0.7, 0.9, 1), 2)
