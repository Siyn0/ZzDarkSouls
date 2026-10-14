extends Control

## 主菜单标题，之后可以直接在检查器里改游戏名。
@export var game_title := "ZZ DARK SOULS"
var _busy := false

func _ready() -> void:
	get_tree().paused = false
	KeyBindings.release_gameplay_inputs()
	%Title.text = game_title
	_style_buttons()
	%Start.pressed.connect(_start)
	%Load.pressed.connect(_load)
	%Settings.pressed.connect($SettingsUI.open_settings)
	%Quit.pressed.connect(func(): get_tree().quit())
	$SettingsUI.settings_closed.connect(func(): %Settings.grab_focus())
	refresh_save_state()
	%Start.grab_focus()
	resized.connect(queue_redraw)

func refresh_save_state() -> void:
	var saved := SaveGame.inspect_save()
	var valid: bool = not saved.data.is_empty()
	%Start.text = "继续游戏" if valid else "开始游戏"
	%Load.disabled = not valid
	%Load.tooltip_text = "读取最近激活的篝火进度" if valid else "暂无可读取的存档"
	%Status.text = saved.error
	# 无法读取的档案保留原样，避免把一次失败当成没有存档并自动覆盖。
	%Start.disabled = saved.exists and not valid

func _start() -> void:
	if _busy:
		return
	var saved := SaveGame.inspect_save()
	if not saved.error.is_empty():
		%Status.text = saved.error
		return
	_switch(SaveGame.load_game() if not saved.data.is_empty() else SaveGame.start_new_game())

func _load() -> void:
	if not _busy:
		_switch(SaveGame.load_game())

func _switch(error: String) -> void:
	if not error.is_empty():
		%Status.text = error
		return
	_busy = true
	for button: Button in %Buttons.get_children():
		button.disabled = true

func _style_buttons() -> void:
	var empty := StyleBoxEmpty.new()
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0, 0.45, 1])
	gradient.colors = PackedColorArray([Color(0.38, 0.25, 0.025, 0.65), Color(0.23, 0.15, 0.015, 0.4), Color(0.1, 0.07, 0, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 384
	texture.height = 48
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1, 0.5)
	var glow := StyleBoxTexture.new()
	glow.texture = texture
	for button: Button in %Buttons.get_children():
		for state in ["normal", "disabled"]:
			button.add_theme_stylebox_override(state, empty)
		for state in ["hover", "pressed", "focus", "hover_pressed"]:
			button.add_theme_stylebox_override(state, glow)
		button.add_theme_color_override("font_color", Color("a9a69e"))
		button.add_theme_color_override("font_focus_color", Color("ece0b7"))
		button.add_theme_color_override("font_hover_color", Color("ece0b7"))
		button.add_theme_color_override("font_pressed_color", Color("fff0c5"))
		button.add_theme_color_override("font_disabled_color", Color("494843"))
		button.mouse_entered.connect(func():
			if not button.disabled and not $SettingsUI.overlay.visible:
				button.grab_focus())

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	# 一道断续的旧银色刻痕，呼应标题；用绘制实现，不依赖截图或外部字体素材。
	var y := size.y * 0.295
	for i in range(55):
		var x := size.x * (0.035 + float(i) / 55 * 0.93)
		var length := size.x * (0.008 if i % 4 == 0 else 0.013)
		draw_line(Vector2(x, y + (i % 3 - 1)), Vector2(x + length, y), Color(0.7, 0.68, 0.62, 0.18), 1)
