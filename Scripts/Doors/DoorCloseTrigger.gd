@tool
extends Area2D

const Door = preload("res://Scripts/Doors/Door.gd")

## 把要关闭的门节点拖到这里。触发器可摆在房间任意位置，与门的方向无关。
@export var door: Door:
	set(value):
		door = value
		update_configuration_warnings()
## 以此节点为中心的触发范围，编辑器中的橙色矩形仅用于摆放预览。
@export var region_size := Vector2(120, 160):
	set(value):
		region_size = Vector2(maxf(1, value.x), maxf(1, value.y))
		_sync_region()
## 默认只触发一次，离开区域不会重新开门。
@export var one_shot := true
@export var enabled := true

var _triggered := false

func _ready() -> void:
	_sync_region()
	if not Engine.is_editor_hint():
		add_to_group("respawn_reset")
		body_entered.connect(_on_body_entered)

func reset_after_player_respawn() -> void:
	_triggered = false

func _sync_region() -> void:
	if is_node_ready():
		var rectangle := RectangleShape2D.new()
		rectangle.size = region_size
		$CollisionShape2D.set_deferred("shape", rectangle)
	queue_redraw()

func _on_body_entered(body: Node2D) -> void:
	if not enabled or (one_shot and _triggered) or not body.is_in_group("player"):
		return
	if is_instance_valid(door):
		_triggered = true
		door.close()

func _get_configuration_warnings() -> PackedStringArray:
	if not is_instance_valid(door):
		return ["请把要关闭的门节点拖到 Door 属性中。"]
	return []

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var rect := Rect2(-region_size / 2, region_size)
	draw_rect(rect, Color(0.95, 0.55, 0.2, 0.12))
	draw_rect(rect, Color(0.95, 0.55, 0.2, 0.8), false, 2)
	draw_line(Vector2(-8, -8), Vector2(8, 8), Color("e5a359"), 2)
	draw_line(Vector2(-8, 8), Vector2(8, -8), Color("e5a359"), 2)
