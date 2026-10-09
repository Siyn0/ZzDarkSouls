# ZzDarkSouls

用 Godot 一点点制作的横版 2D 类魂练习项目。当前是第一步：TileMap 地面和玩家左右移动。

## 运行

使用 Godot 4.7.2 打开 `project.godot`，按 **F5** 运行项目主场景 `Scenes/World.tscn`。

- **A / D** 或 **← / →**：左右移动，松开立即停止，同时按住两个方向则站住。
- 玩家会受重力落到地面，两端石墙会挡住玩家。
- 当前没有跳跃、翻滚和战斗；小骑士与石砖都是可替换的占位素材。

## 从哪里开始看

- `Scenes/World.tscn`：练习场，包含背景、`Ground` 地图层、玩家实例和按键提示。
- `Scenes/Player.tscn`：玩家，由 `CharacterBody2D`、`Sprite2D` 和 `CollisionShape2D` 组成。玩家节点的位置在脚底。
- `Scripts/Player.gd`：读取输入、应用重力、调用 `move_and_slide()` 处理移动和碰撞。
- `Assets/Tiles/StoneTiles.tres`：32×32 的 TileSet，三块石砖都已配置完整的方形碰撞。

## 自己改一改

1. **画地图**：打开 `World.tscn`，在场景树选中 `Ground`，使用底部的 TileMap 面板选取石砖，在 2D 视图中左键绘制、右键擦除。图集从左到右是草苔地表、普通石砖、裂纹石砖。地图已保存在场景中，可以直接编辑。
2. **改速度**：选中 `World` 中的 `Player`，在右侧检查器调整 `Move Speed`（默认 220 像素/秒）。
3. **改按键**：项目 → 项目设置 → 输入映射，修改 `move_left`、`move_right`。
4. **看碰撞**：编辑器顶部“调试”菜单中打开“可见碰撞形状”，再运行项目。

场地目前固定为 960×544，没有滚动相机。画图时先保留底部地面与两端围墙，玩家出生点也要放在地面上方。

Godot 4.7 使用 `TileMapLayer` 绘制单层地图（旧 `TileMap` 节点已弃用）：[官方文档](https://docs.godotengine.org/en/4.7/classes/class_tilemaplayer.html)。
