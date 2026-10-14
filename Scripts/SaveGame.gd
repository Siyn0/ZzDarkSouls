extends Node

signal save_failed(message: String)

const FIRST_LEVEL := "res://Scenes/Levels/Tutorial.tscn"
const MAIN_MENU := "res://Scenes/MainMenu.tscn"
const SAVE_VERSION := 1

## 单存档位置。测试使用独立路径，正式游戏保存在 Godot 的用户数据目录。
var save_path := "user://savegame.json"
var auto_save_enabled := true
var _player: CharacterBody2D
var _level_path := ""
var _defeated_bosses: Array[String] = []
var _pending: Dictionary = {}
var _restoring := false

func inspect_save() -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return {"exists": false, "data": {}, "error": ""}
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return {"exists": true, "data": {}, "error": "无法读取存档，请检查文件权限。"}
	if file.get_length() > 1048576:
		return {"exists": true, "data": {}, "error": "存档文件异常，暂时无法加载。"}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {"exists": true, "data": {}, "error": "存档已损坏，暂时无法加载。"}
	var data: Dictionary = parser.data
	var error := _validate(data)
	return {"exists": true, "data": data if error.is_empty() else {}, "error": error}

func _validate(data: Dictionary) -> String:
	if data.get("version") != SAVE_VERSION:
		return "存档版本不兼容。"
	var scene = data.get("scene")
	if not scene is String or not scene.begins_with("res://Scenes/Levels/") or not ResourceLoader.exists(scene, "PackedScene"):
		return "存档中的关卡不存在。"
	var point = data.get("spawn")
	if not point is Array or point.size() != 2:
		return "存档中的复活位置无效。"
	for coordinate in point:
		if not (coordinate is float or coordinate is int) or not is_finite(float(coordinate)) or absf(float(coordinate)) > 10000000:
			return "存档中的复活位置无效。"
	if not data.get("checkpoint", "") is String or not data.get("defeated_bosses") is Array:
		return "存档进度格式无效。"
	var checkpoint: String = data.get("checkpoint", "")
	if checkpoint.begins_with("/") or ".." in checkpoint.split("/"):
		return "存档中的篝火记录无效。"
	for path in data.defeated_bosses:
		if not path is String or path.is_empty() or path.begins_with("/") or ".." in path.split("/"):
			return "存档中的 Boss 记录无效。"
	return ""

func start_new_game() -> String:
	_pending = {}
	_level_path = ""
	_defeated_bosses.clear()
	return _change_level(FIRST_LEVEL)

func load_game() -> String:
	var result := inspect_save()
	if not result.error.is_empty():
		return result.error
	if result.data.is_empty():
		return "还没有存档，请先开始游戏。"
	_pending = result.data.duplicate(true)
	return _change_level(_pending.scene)

func _change_level(path: String) -> String:
	get_tree().paused = false
	KeyBindings.release_gameplay_inputs()
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		_pending.clear()
		return "关卡加载失败，请重试。"
	return ""

func return_to_menu() -> String:
	var error := save_progress()
	if not error.is_empty():
		return error
	return _change_level(MAIN_MENU)

## 玩家就绪后注册，直接从编辑器运行正式关卡也支持自动存档。
func register_player(actor: CharacterBody2D) -> void:
	if not auto_save_enabled or not is_instance_valid(actor) or actor.is_queued_for_deletion():
		return
	var level := get_tree().current_scene
	if level == null or not level.is_ancestor_of(actor) or not level.scene_file_path.begins_with("res://Scenes/Levels/"):
		return
	_player = actor
	if _level_path != level.scene_file_path:
		_defeated_bosses.clear()
	_level_path = level.scene_file_path
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if level.is_ancestor_of(enemy) and enemy.boss and not enemy.defeated.is_connected(_on_boss_defeated):
			enemy.defeated.connect(_on_boss_defeated)
	if not _pending.is_empty() and _pending.scene == _level_path:
		_restore_progress(level)
	_pending.clear()
	save_progress()

func _restore_progress(level: Node) -> void:
	_restoring = true
	_defeated_bosses.assign(_pending.defeated_bosses)
	var respawn: Node = _player.get_node("Respawn")
	respawn.respawn_position = Vector2(_pending.spawn[0], _pending.spawn[1])
	if not String(_pending.get("checkpoint", "")).is_empty():
		var checkpoint := level.get_node_or_null(NodePath(_pending.checkpoint))
		if checkpoint != null and checkpoint.has_method("get_spawn_position"):
			respawn.activate_checkpoint(checkpoint)
	_player.reset_for_respawn(respawn.respawn_position)
	_player.combat.invulnerable_left = respawn.protection_time
	# 发出既有死亡信号，让绑定该 Boss 的门正常解锁，再移除已击败的 Boss。
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if level.is_ancestor_of(enemy) and str(level.get_path_to(enemy)) in _defeated_bosses:
			enemy.alive = false
			enemy.defeated.emit(enemy)
			enemy.queue_free()
	for camera in get_tree().get_nodes_in_group("level_camera"):
		if camera.target == _player:
			camera.snap_to_target()
	_restoring = false

func checkpoint_activated(actor: CharacterBody2D) -> void:
	if actor == _player and not _restoring:
		save_progress()

func _on_boss_defeated(enemy: Node) -> void:
	if _restoring or not is_instance_valid(_player):
		return
	var level := get_tree().current_scene
	if level == null or not level.is_ancestor_of(enemy):
		return
	var path := str(level.get_path_to(enemy))
	if not path in _defeated_bosses:
		_defeated_bosses.append(path)
	save_progress()

func save_progress() -> String:
	if not auto_save_enabled or _restoring or not is_instance_valid(_player):
		return ""
	var level := get_tree().current_scene
	if level == null or not level.is_ancestor_of(_player) or level.scene_file_path != _level_path:
		return ""
	var respawn: Node = _player.get_node("Respawn")
	var checkpoint_path := ""
	if is_instance_valid(respawn.active_checkpoint) and level.is_ancestor_of(respawn.active_checkpoint):
		checkpoint_path = str(level.get_path_to(respawn.active_checkpoint))
	var data := {"version": SAVE_VERSION, "scene": _level_path,
		"checkpoint": checkpoint_path, "spawn": [respawn.respawn_position.x, respawn.respawn_position.y],
		"defeated_bosses": _defeated_bosses.duplicate()}
	# 先完整写入临时文件，成功后替换旧档，写入失败不会截断原有进度。
	var temporary := save_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _save_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(temporary, save_path) != OK:
		return _save_error()
	return ""

func _save_error() -> String:
	var message := "进度保存失败，请检查存储空间和文件权限。"
	save_failed.emit(message)
	return message
