@tool
extends "res://Scripts/Doors/Door.gd"

const Enemy = preload("res://Scripts/Combat/TrainingEnemy.gd")

## 把场景中的 Boss 节点拖到这里；监听 defeated 信号，击败它后永久开门。
@export var boss: Enemy:
	set(value):
		boss = value
		update_configuration_warnings()

var _unlocked := false

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	if is_instance_valid(boss):
		boss.defeated.connect(_on_boss_defeated)
		# 兼容门比 Boss 晚加入场景的情况。
		if not boss.alive:
			_on_boss_defeated(boss)

func _on_boss_defeated(_enemy: Node) -> void:
	_unlocked = true
	open()

func close() -> void:
	if not _unlocked:
		super.close()

func reset_after_player_respawn() -> void:
	if not _unlocked:
		super.reset_after_player_respawn()

func _get_configuration_warnings() -> PackedStringArray:
	if not is_instance_valid(boss):
		return ["请把场景中的 Boss 节点拖到 Boss 属性中；未绑定时门不会自动打开。"]
	return []
