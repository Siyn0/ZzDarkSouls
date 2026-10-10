extends Node2D

var lifetime := 0.0
var tint := Color(1, 0.8, 0.3)
var strong := false

func _ready() -> void:
	add_to_group("combat_effects")
	z_index = 6

func _process(delta: float) -> void:
	lifetime += delta
	queue_redraw()
	if lifetime >= 0.32:
		queue_free()

func _draw() -> void:
	var progress := lifetime / 0.32
	var color := Color(tint, 1.0 - progress)
	var radius := lerpf(4.0, 40.0 if strong else 23.0, progress)
	draw_arc(Vector2.ZERO, radius, 0, TAU, 28, color, 2.0)
	for i in range(8):
		var direction := Vector2.from_angle(i * TAU / 8.0 + 0.2)
		draw_line(direction * radius * 0.55, direction * radius, color, 3.0 if strong else 2.0)
