extends Node

signal respawned

## 死亡后等待多久自动复活。暂停菜单会暂停这个倒计时。
@export_range(0.1, 5.0, 0.1) var respawn_delay := 1.0
## 复活后的短暂无敌，避免刚回来就连续受击。
@export_range(0.0, 5.0, 0.1) var protection_time := 1.0

var active_checkpoint: Node2D
var respawn_position := Vector2.ZERO
var _respawn_left := -1.0
@onready var actor: CharacterBody2D = get_parent()

func _ready() -> void:
	# 尚未路过篝火时也能复活，退回这一关的初始出生位置。
	respawn_position = actor.global_position
	actor.get_node("Combat").died.connect(_on_died)
	set_physics_process(false)
	_register_for_save.call_deferred()

func _register_for_save() -> void:
	# 练习场会在初始化时替换玩家；挂在自身的延迟调用会随旧玩家一起取消。
	SaveGame.register_player(actor)

func activate_checkpoint(checkpoint: Node2D) -> void:
	if actor.combat.dead:
		return
	respawn_position = checkpoint.get_spawn_position()
	if active_checkpoint == checkpoint:
		return
	if is_instance_valid(active_checkpoint):
		active_checkpoint.set_active(false)
	active_checkpoint = checkpoint
	checkpoint.set_active(true)
	actor.combat.feedback.emit("篝火已激活 · 下次在这里复活")
	SaveGame.checkpoint_activated(actor)

func _on_died() -> void:
	_respawn_left = respawn_delay
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	_respawn_left -= delta
	if _respawn_left <= 0:
		set_physics_process(false)
		# 离开物理遍历后再重置碰撞形状和场景状态。
		respawn.call_deferred()

func respawn() -> void:
	if not actor.combat.dead:
		return
	_respawn_left = -1.0
	set_physics_process(false)
	KeyBindings.release_gameplay_inputs()
	# 同一关内恢复存活敌人和入口；已击败的 Boss 不会复活。
	var level := get_tree().current_scene
	for node in get_tree().get_nodes_in_group("respawn_reset"):
		if is_instance_valid(level) and (node == level or level.is_ancestor_of(node)):
			node.reset_after_player_respawn()
	actor.reset_for_respawn(respawn_position)
	actor.combat.invulnerable_left = protection_time
	for camera in get_tree().get_nodes_in_group("level_camera"):
		if camera.target == actor:
			camera.snap_to_target()
	respawned.emit()
	actor.combat.feedback.emit("重新出发！")
