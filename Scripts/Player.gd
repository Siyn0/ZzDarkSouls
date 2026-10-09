extends CharacterBody2D

# 在检查器里调整移动速度，单位是像素/秒。
@export var move_speed: float = 220.0

@onready var sprite: Sprite2D = $Sprite2D


func _physics_process(delta: float) -> void:
	# 重力让角色落到 TileMap 的碰撞地面上。
	if not is_on_floor():
		velocity += get_gravity() * delta

	# 左为 -1，右为 1；松开按键或同时按住两边时为 0。
	var direction := Input.get_axis("move_left", "move_right")
	velocity.x = direction * move_speed
	if direction != 0.0:
		sprite.flip_h = direction < 0.0

	# velocity 已经是每秒速度，这里不需要再乘 delta。
	move_and_slide()
