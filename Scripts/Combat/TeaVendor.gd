@tool
extends Node2D

const Tea := preload("res://Scripts/Combat/IcedTea.gd")

@export_group("Dialogue")
@export var display_name: String = "牢大":
	set(value):
		display_name = value
		_refresh_preview()
@export_multiline var dialogue: String = "man！来点冰红茶吗？无限供应！":
	set(value):
		dialogue = value
		_refresh_preview()
## 蓝色范围框内检测玩家；根节点原点是牢大的脚底。
@export var interaction_size := Vector2(320, 160):
	set(value):
		interaction_size = value.max(Vector2(1, 1))
		_refresh_preview()

@export_group("Supply")
@export var active: bool = true
## 相对脚底的出瓶位置，默认为右手边地面上方。
@export var spawn_offset := Vector2(44, -17):
	set(value):
		spawn_offset = value
		_refresh_preview()
## 出瓶点附近已有未被拿着的冰红茶时，不会再补货。
@export_range(8, 120, 1) var stock_radius: float = 32.0:
	set(value):
		stock_radius = value
		queue_redraw()
@export_range(0.1, 10, 0.1) var refill_delay: float = 0.8

var stock: Node2D
var refill_left := 0.0
# 与试验场供应者接口兼容；飞机仍由独立脚本负责。
var flying := false

func _ready() -> void:
	_refresh_preview()
	$Bubble.hide()
	$BubbleTail.hide()

func _refresh_preview() -> void:
	if not is_node_ready():
		return
	$NameLabel.text = display_name
	$Bubble/Text.text = dialogue
	$TeaSpawn.position = spawn_offset
	var rectangle := RectangleShape2D.new()
	rectangle.size = interaction_size
	$Proximity/CollisionShape2D.set_deferred("shape", rectangle)
	queue_redraw()

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var nearby := false
	if active:
		for body in $Proximity.get_overlapping_bodies():
			if body.is_in_group("player") and not body.combat.dead:
				nearby = true
				break
	$Bubble.visible = nearby
	$BubbleTail.visible = nearby
	if not active:
		return
	stock = _find_stock()
	if is_instance_valid(stock):
		refill_left = refill_delay
		return
	if not nearby:
		return
	refill_left = maxf(0, refill_left - delta)
	if refill_left <= 0:
		var tea := Tea.new()
		var container := get_parent()
		tea.position = container.to_local($TeaSpawn.global_position) if container is Node2D else $TeaSpawn.global_position
		container.add_child(tea)
		stock = tea
		refill_left = refill_delay

func _find_stock() -> Node2D:
	var closest: Node2D
	var distance := stock_radius
	for tea: Node2D in get_tree().get_nodes_in_group("tea_bottles"):
		if tea.is_queued_for_deletion() or is_instance_valid(tea.holder):
			continue
		var next_distance: float = tea.global_position.distance_to($TeaSpawn.global_position)
		if next_distance <= distance:
			closest = tea
			distance = next_distance
	return closest

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or not $Bubble.visible:
		return
	# 气泡随人物处在世界中；靠屏幕边缘时横向挪动，避免文字被裁掉。
	var view: Rect2 = get_global_transform_with_canvas().affine_inverse() * get_viewport_rect()
	var width: float = $Bubble.size.x
	var minimum := view.position.x + 8
	var maximum := view.end.x - width - 8
	$Bubble.position.x = clampf(-width / 2, minimum, maximum) if minimum <= maximum else view.get_center().x - width / 2
	$Bubble.position.y = maxf(-96 - $Bubble.size.y, view.position.y + 8)
	var tail_x := clampf(0, $Bubble.position.x + 12, $Bubble.position.x + width - 12)
	$BubbleTail.position = Vector2(tail_x, $Bubble.position.y + $Bubble.size.y)

func _draw() -> void:
	# 与现有牢大占位形象一致；在编辑器里也能直接看见位置。
	draw_rect(Rect2(-10, -34, 20, 30), Color("815b9b"))
	draw_rect(Rect2(-9, -31, 18, 5), Color("e9c86e"))
	draw_circle(Vector2(0, -43), 10, Color("bb8b68"))
	draw_rect(Rect2(-8, -46, 16, 4), Color("25313a"))
	draw_rect(Rect2(-11, -7, 8, 7), Color("2b3546"))
	draw_rect(Rect2(3, -7, 8, 7), Color("2b3546"))
	draw_rect(Rect2(spawn_offset.x - 16, -4, 34, 4), Color("cc8b4b"))
	if Engine.is_editor_hint():
		var rect := Rect2(Vector2(0, -40) - interaction_size / 2, interaction_size)
		draw_rect(rect, Color(0.4, 0.8, 1, 0.07))
		draw_rect(rect, Color(0.4, 0.8, 1, 0.6), false, 1)
		draw_circle(spawn_offset, stock_radius, Color(1, 0.7, 0.3, 0.13))
		draw_line(spawn_offset - Vector2(5, 0), spawn_offset + Vector2(5, 0), Color("edcda0"), 2)
