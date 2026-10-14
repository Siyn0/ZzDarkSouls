@tool
extends Area2D

## 自动激活范围，根节点位于篝火底部中央。
@export var activation_size := Vector2(88, 80):
	set(value):
		activation_size = Vector2(maxf(1, value.x), maxf(1, value.y))
		_refresh_preview()
## 相对篝火底部的玩家脚底位置，编辑器的十字标记显示复活位置。
@export var spawn_offset := Vector2(0, -2):
	set(value):
		spawn_offset = value
		_refresh_preview()
## 仅缩放美术，激活范围独立调整。
@export_range(0.1, 4.0, 0.05) var artwork_scale := 0.65:
	set(value):
		artwork_scale = value
		_refresh_preview()

var active := false
var _notice_left := 0.0

func _ready() -> void:
	_refresh_preview()
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)

func get_spawn_position() -> Vector2:
	return to_global(spawn_offset)

func set_active(value: bool) -> void:
	active = value
	_notice_left = 2.0 if value else 0.0
	_refresh_artwork()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		if body.has_node("Combat"):
			var combat = body.get_node("Combat")
			if not combat.dead:
				combat.health = combat.max_health
		if body.has_node("Respawn"):
			body.get_node("Respawn").activate_checkpoint(self)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_notice_left = maxf(0, _notice_left - delta)
	$Notice.visible = _notice_left > 0

func _refresh_preview() -> void:
	if is_node_ready():
		var rectangle := RectangleShape2D.new()
		rectangle.size = activation_size
		$CollisionShape2D.set_deferred("shape", rectangle)
		$CollisionShape2D.position.y = -activation_size.y / 2
		$Sprite2D.scale = Vector2.ONE * artwork_scale
		$Notice.position = Vector2(-100, -110 * artwork_scale - 28)
		_refresh_artwork()
	queue_redraw()

func _refresh_artwork() -> void:
	$Sprite2D.modulate = Color.WHITE if active or Engine.is_editor_hint() else Color(0.65, 0.65, 0.65)
	$ActiveGlow.visible = active
	$Notice.visible = _notice_left > 0

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var rect := Rect2(Vector2(-activation_size.x / 2, -activation_size.y), activation_size)
	draw_rect(rect, Color(1, 0.6, 0.2, 0.08))
	draw_rect(rect, Color(1, 0.6, 0.2, 0.6), false, 1)
	draw_line(spawn_offset - Vector2(7, 0), spawn_offset + Vector2(7, 0), Color.GREEN, 2)
	draw_line(spawn_offset - Vector2(0, 7), spawn_offset + Vector2(0, 7), Color.GREEN, 2)
