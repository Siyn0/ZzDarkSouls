extends Node2D

const Tea := preload("res://Scripts/Combat/IcedTea.gd")
const SmallEnemy := preload("res://Scenes/Enemies/SmallEnemy.tscn")
const BossEnemy := preload("res://Scenes/Enemies/IronGuard.tscn")
const Supplier := preload("res://Scripts/Combat/TeaSupplier.gd")
const Vendor := preload("res://Scenes/NPCTriggers/TeaVendor.tscn")
var mode := "mobs"
var player: CharacterBody2D
var supplier: Node2D
var completed := false
var _respawn_left := 0.0
var _message_left := 0.0
var _template := PackedScene.new()
var _banner: Label
var _stats: Label
var _boss_bar: ProgressBar
var _boss_name: Label
var _arena_buttons: Array[Button] = []

func is_combat_arena() -> bool:
	return true

func _ready() -> void:
	player = $Player
	_template.pack(player)
	# 继承原场景的玩家参数与美术，在此场景清出投掷和战斗空间。
	var tiles: TileMapLayer = $Ground
	tiles.clear()
	for x in range(30):
		for y in range(13, 17):
			tiles.set_cell(Vector2i(x, y), 0, Vector2i(0 if y == 13 else 1, 0))
	for y in range(-1, 13):
		for x in [0, 29]:
			tiles.set_cell(Vector2i(x, y), 0, Vector2i(1, 0))
	_create_hud()
	reset_round()

func _create_hud() -> void:
	var screen: Control = $GameUI/Screen
	_banner = Label.new()
	_banner.position = Vector2(320, 64)
	_banner.size = Vector2(610, 56)
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.add_theme_font_size_override("font_size", 15)
	_banner.modulate = Color("edcda0")
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(_banner)
	_stats = Label.new()
	_stats.position = Vector2(24, 454)
	_stats.size = Vector2(195, 44)
	_stats.add_theme_font_size_override("font_size", 13)
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(_stats)
	_boss_bar = ProgressBar.new()
	_boss_bar.position = Vector2(230, 476)
	_boss_bar.size = Vector2(676, 16)
	_boss_bar.show_percentage = false
	var health_bar: ProgressBar = $GameUI.get_node("%Health")
	_boss_bar.add_theme_stylebox_override("background", health_bar.get_theme_stylebox("background"))
	_boss_bar.add_theme_stylebox_override("fill", health_bar.get_theme_stylebox("fill"))
	screen.add_child(_boss_bar)
	_boss_bar.set_deferred("size", Vector2(676, 16))
	_boss_name = Label.new()
	_boss_name.position = Vector2(232, 450)
	_boss_name.size = Vector2(674, 22)
	_boss_name.add_theme_font_size_override("font_size", 18)
	_boss_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(_boss_name)
	var titles := ["小怪练习", "Boss 空投战", "重试"]
	for i in range(3):
		var button := Button.new()
		button.position = Vector2(570 + i * 118, 505)
		button.size = Vector2(112, 32)
		button.text = titles[i]
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 13)
		if i == 2:
			button.pressed.connect(reset_round)
		else:
			button.pressed.connect(set_mode.bind("mobs" if i == 0 else "boss"))
		screen.add_child(button)
		_arena_buttons.append(button)
	# 战斗 HUD 位于设置遮罩下面，暂停菜单始终遮挡并接收鼠标。
	screen.move_child($GameUI.get_node("%Overlay"), -1)

func set_mode(next_mode: String) -> void:
	mode = next_mode
	reset_round()

func reset_round() -> void:
	KeyBindings.release_gameplay_inputs()
	for group in ["enemies", "tea_bottles", "dash_afterimages", "combat_effects"]:
		for node in get_tree().get_nodes_in_group(group):
			if is_ancestor_of(node):
				node.free()
	if is_instance_valid(supplier):
		supplier.free()
	if is_instance_valid(player):
		player.free()
	player = _template.instantiate()
	player.name = "Player"
	player.position = Vector2(225, 414)
	add_child(player)
	$GameUI.player = player
	player.combat.feedback.connect(announce)
	player.combat.died.connect(_on_player_died)
	completed = false
	_respawn_left = 0
	supplier = Supplier.new() if mode == "boss" else Vendor.instantiate()
	if mode == "boss":
		supplier.arena = self
		supplier.flying = true
	supplier.position = Vector2(-90, 274) if supplier.flying else Vector2(90, 416)
	add_child(supplier)
	_boss_bar.visible = mode == "boss"
	_boss_name.visible = mode == "boss"
	if mode == "boss":
		spawn_tea(Vector2(200, 398))
	_spawn_enemy()
	announce("牢大：冰红茶管够，等刀落下来再弹！" if mode == "mobs" else "补给航线已开启 · " + _boss_name.text)

func spawn_tea(at: Vector2) -> Node2D:
	var bottles: Array[Node] = get_tree().get_nodes_in_group("tea_bottles")
	# 补给次数无限；旧的闲置瓶子回收，避免长时间游玩无限堆积。
	if bottles.size() >= 10:
		for bottle in bottles:
			if is_ancestor_of(bottle) and not is_instance_valid(bottle.holder) and not bottle.armed:
				bottle.free()
				break
		if get_tree().get_nodes_in_group("tea_bottles").size() >= 10:
			return null
	var tea := Tea.new()
	tea.position = at
	add_child(tea)
	return tea

func _spawn_enemy() -> void:
	var enemy := (BossEnemy if mode == "boss" else SmallEnemy).instantiate()
	enemy.position = Vector2(700 if enemy.boss else 580, 414)
	enemy.target = player
	enemy.defeated.connect(_on_enemy_defeated)
	add_child(enemy)
	if enemy.boss:
		_boss_name.text = enemy.display_name + " · BOSS"

func _on_enemy_defeated(enemy: Node) -> void:
	if mode == "boss":
		completed = true
		supplier.active = false
		supplier.hide()
		announce("%s击败！牢大：下一瓶算我的。" % enemy.display_name, 1000)
	else:
		_respawn_left = 3.0
		announce("%s击败！3 秒后再来一只；牢大继续补货。" % enemy.display_name, 3.0)

func _on_player_died() -> void:
	_respawn_left = 0
	if is_instance_valid(supplier):
		supplier.active = false

func announce(message: String, duration: float = 2.5) -> void:
	_banner.text = message
	_message_left = duration

func _physics_process(delta: float) -> void:
	_message_left = maxf(0, _message_left - delta)
	if _message_left == 0 and not player.combat.dead and not completed:
		_banner.text = "观察挥刀 → 命中前防御 / 精准防御 → 冰红茶反击"
	if _respawn_left > 0 and not player.combat.dead:
		_respawn_left -= delta
		if _respawn_left <= 0:
			_spawn_enemy()
	_stats.text = "架势  %d / %d\n%s" % [ceili(player.combat.guard), ceili(player.combat.max_guard), "持有冰红茶" if player.combat.carrying() else ""]
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.boss:
			_boss_bar.max_value = enemy.max_health
			_boss_bar.value = enemy.health
	if completed:
		_boss_bar.value = 0
