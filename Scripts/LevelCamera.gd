extends Camera2D

enum Mode { FOLLOW, FIXED }

@export_group("Follow")
## 留空时寻找 player 分组。镜头放在关卡中，不作为玩家的子节点。
@export var target: Node2D
@export var auto_find_player: bool = true
@export var mode: Mode = Mode.FOLLOW
## 玩家原点在脚底，因此默认把视线中心抬高一些。
@export var follow_offset := Vector2(0, -80)
## 玩家在这个宽、高范围内移动时不推动镜头；设为零则始终居中跟随。
@export var dead_zone_size := Vector2(64, 40)
## 数值越大，跟随越紧；零表示立即到位。
@export_range(0, 30, 0.1) var follow_speed: float = 8.0
@export_range(0, 300, 1) var look_ahead_distance: float = 70.0
@export_range(0.1, 30, 0.1) var look_ahead_speed: float = 4.0

@export_group("Bounds")
@export var use_bounds: bool = false
## 可选：启动时读取这个正交 TileMapLayer 的已用范围，换关卡无需改代码。
@export var bounds_source: TileMapLayer
## 世界坐标下的可见区域；小于屏幕的轴会居中显示。
@export var world_bounds := Rect2(0, 0, 960, 544)

@export_group("Fixed View")
## FIXED 模式下的世界坐标焦点，可用于房间固定镜头或剧情。
@export var fixed_position := Vector2(480, 272)

var _look_ahead: float = 0.0
var _last_target_position := Vector2.ZERO

func _ready() -> void:
	# 跟在玩家物理更新之后执行，避免镜头落后一帧。平滑只由本脚本处理一次。
	process_physics_priority = 100
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	position_smoothing_enabled = false
	refresh_bounds()
	_find_player()
	snap_to_target()

func _physics_process(delta: float) -> void:
	if mode == Mode.FOLLOW and not is_instance_valid(target):
		if _find_player():
			snap_to_target()
		else:
			return
	var destination := fixed_position
	if mode == Mode.FOLLOW:
		var speed_x := (target.global_position.x - _last_target_position.x) / maxf(delta, 0.0001)
		_last_target_position = target.global_position
		var ahead := signf(speed_x) * look_ahead_distance if absf(speed_x) > 20 else 0.0
		_look_ahead = lerpf(_look_ahead, ahead, 1.0 - exp(-look_ahead_speed * delta))
		var desired := target.global_position + follow_offset + Vector2(_look_ahead, 0)
		var difference := desired - global_position
		var half_zone := dead_zone_size.max(Vector2.ZERO) / 2
		destination = global_position + Vector2(
			signf(difference.x) * maxf(0, absf(difference.x) - half_zone.x),
			signf(difference.y) * maxf(0, absf(difference.y) - half_zone.y))
	destination = _clamp_to_bounds(destination)
	var weight := 1.0 if follow_speed <= 0 else 1.0 - exp(-follow_speed * delta)
	global_position = _clamp_to_bounds(global_position.lerp(destination, weight))
	force_update_scroll()

## 换成另一个跟随对象（玩家、移动平台或演出角色）。
func follow(who: Node2D, immediate: bool = false) -> void:
	target = who
	mode = Mode.FOLLOW
	_look_ahead = 0
	if is_instance_valid(target):
		_last_target_position = target.global_position
	if immediate:
		snap_to_target()

## 临时看向一个世界坐标，保留原跟随目标；immediate=false 时平滑过渡。
func focus_at(point: Vector2, immediate: bool = false) -> void:
	fixed_position = point
	mode = Mode.FIXED
	if immediate:
		snap_to_target()

func resume_follow(immediate: bool = false) -> void:
	follow(target, immediate)

## 重生 / 传送后调用，避免镜头从旧位置长距离滑行。
func snap_to_target() -> void:
	_look_ahead = 0
	var destination := fixed_position
	if mode == Mode.FOLLOW:
		if not is_instance_valid(target) and not _find_player():
			return
		_last_target_position = target.global_position
		destination = target.global_position + follow_offset
	global_position = _clamp_to_bounds(destination)
	reset_smoothing()
	force_update_scroll()

## 后续镜头区域可以调用这个接口临时限制到某个房间。
func set_world_bounds(rect: Rect2) -> void:
	world_bounds = rect.abs()
	use_bounds = true
	global_position = _clamp_to_bounds(global_position)
	force_update_scroll()

func clear_bounds() -> void:
	use_bounds = false

## 地图运行时扩建或退出临时房间限制后，可重新读取地图边界。
func refresh_bounds() -> void:
	if not is_instance_valid(bounds_source) or bounds_source.tile_set == null:
		return
	var cells := bounds_source.get_used_rect()
	if not cells.has_area():
		return
	var half_tile := Vector2(bounds_source.tile_set.tile_size) / 2
	var start := bounds_source.map_to_local(cells.position) - half_tile
	var end := bounds_source.map_to_local(cells.end - Vector2i.ONE) + half_tile
	var rect := Rect2(bounds_source.to_global(start), Vector2.ZERO)
	for corner in [end, Vector2(start.x, end.y), Vector2(end.x, start.y)]:
		rect = rect.expand(bounds_source.to_global(corner))
	world_bounds = rect

func _find_player() -> bool:
	if is_instance_valid(target):
		return true
	if auto_find_player:
		target = get_tree().get_first_node_in_group("player") as Node2D
	return is_instance_valid(target)

func _clamp_to_bounds(point: Vector2) -> Vector2:
	if not use_bounds or not world_bounds.has_area():
		return point
	# 同时考虑屏幕大小与 Camera2D 的缩放，限制的是整个画面而非只有镜头中心。
	var half_view := get_viewport_rect().size / (zoom.max(Vector2(0.01, 0.01)) * 2)
	var minimum := world_bounds.position + half_view
	var maximum := world_bounds.end - half_view
	return Vector2(
		world_bounds.get_center().x if minimum.x > maximum.x else clampf(point.x, minimum.x, maximum.x),
		world_bounds.get_center().y if minimum.y > maximum.y else clampf(point.y, minimum.y, maximum.y))
