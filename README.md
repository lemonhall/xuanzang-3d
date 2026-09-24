# 西行·玄奘 3D（xuanzang-3d）

3D 版玄奘西行。核心不是战斗，是**氛围**：一个人在塔克拉玛干里走，
看不见边、看不见路、看不见尽头。引擎 Godot 4.7.2（Forward+）。

## 怎么跑

```powershell
$godot = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
& $godot --path E:\development\xuanzang-3d
```

也可以直接用 Godot 打开本目录按 F5。

### 操作

| 动作 | 键 |
|---|---|
| 行走 | `W` `A` `S` `D` 或方向键 |
| 冲刺（更耗水） | `Shift` |
| 释放/抓回鼠标 | `Esc` |

## 怎么验证

```powershell
& $godot --headless --path E:\development\xuanzang-3d tests/test_scene.tscn
```

输出 `ALL TESTS PASSED (24 项)`、退出码 0。

必须是**场景**跑法。`--script` 模式不注册 autoload，引用 `GameState` 的脚本
连编译都过不了。

想看一眼画面（会短暂弹出窗口）：

```powershell
& $godot --path E:\development\xuanzang-3d --resolution 1600x900 `
    tools/capture.tscn -- --out D:\shot.png --frames 110
```

## 现在有什么

一关竖切：走在塔克拉玛干里，水囊在倒数，沙暴周期性压顶。

| 系统 | 文件 |
|---|---|
| 沙丘高度场 | `scripts/world/dune_field.gd` |
| 地形网格 + 天空 + 雾 + 太阳 | `scripts/world/desert_world.gd` |
| 沙尘天空着色器 | `shaders/dust_sky.gdshader` |
| 沙暴循环 | `scripts/world/sandstorm.gd` |
| 第一人称行走 | `scripts/player/wanderer.gd` |
| 水囊 / 能见度 | `scripts/autoload/game_state.gd` |
| 输入映射 | `scripts/autoload/controls.gd` |
| HUD | `scripts/ui/hud.gd` |

## 氛围设计

塔克拉玛干的可怕不来自怪物，来自四件事。每一件都落成了可断言的机制：

| 感受 | 手段 | 在哪 |
|---|---|---|
| 无参照 | 沙丘脊线单调重复，没有地标 | `dune_field.gd` |
| 无边界 | 距离雾把远处溶进天空色，地平线消失 | `desert_world.gd` 的 fog |
| 无退路 | 水囊 190 秒见底，冲刺与沙暴都会更快 | `game_state.gd` |
| 压迫 | 沙暴周期：平静 → 起风 → 压顶 → 退去 | `sandstorm.gd` |

沙暴同时改四样东西，且四样指向同一个感受——看不清、走不动、心里发慌：
雾浓度、天光、风力推挤（玩家被动位移）、耗水速度。

## 楼兰幻影（海市蜃楼）

沙尘里升起的一座巨城：720 m 高的主塔、1600 m 见方的城墙、四角楼、城门楼、
城内小塔群与房屋——**3484 个部件，合并成单个 mesh**（构建 87 ms）。

尺寸是真实佛塔的二十倍。放大了二十倍，细节就必须配得上这个尺度：一百多个部件
堆出来的轮廓只有六七个转折，一看就是"几个圆柱摞起来"。所以细节全部花在
**剪影**上——两公里外真正能被看见的只有轮廓。

### 它走不近

这是海市蜃楼区别于"远处有个模型"的唯一要点。它是光的像，不是实体：玩家朝它走，
它同步后退，那段距离永远不变（测试里的 `[幻影走不近]` 守着这条）。第一版把幻影
钉在固定世界坐标上，走两百多米就穿模进城，错觉当场就碎。

距离 250 m 是权衡出来的：再远就被深度雾吃掉（雾在 2 km 处透射率只剩 1.2%），
再近就失去"远在天边"的意味。城的实际尺寸靠 0.30 倍缩放补回来。

### 诡异感从哪来

- **分层错位**：每 26 m 一层整体水平错开，且三分之一的层大幅断裂、其余几乎不动。
  均匀错位会读成"千层饼"，偶尔断一次才像光路真的折了一下。
- **冷暖走向**：底部被沙尘染成暖褐、顶部是天空的青蓝。单一颜色无论深浅都像塑料。
- **亮度压在中间调**：ACES 色调映射会把高亮度色彩去饱和推向白色——幻影一旦够亮
  就变成一坨白的，那正是"亚克力"观感的来源。
- **边缘溶解**：轮廓被噪声啃掉，而不是一条干净的边。

## 和 Blender 概念图的关系

`blender/` 里的塔克拉玛干和这里的 3D 世界**共用同一套沙丘公式**：

- Blender：[desert_lib.py](blender/desert_lib.py) 的 `dune_height()`
- Godot：[dune_field.gd](scripts/world/dune_field.gd) 的 `sample()`

参数（`height` / `sharp` / `spacing` / `bend` / `swell` / `vary`）一一对应，
改一处两边能互相印证。Blender 的 5 张氛围图就是这一关的美术方向。

坐标约定：**脊线沿 Z 延伸、沿 X 排列**。相机要朝 ±X 看才能看到一道道叠过来的
沙丘，朝 Z 看只会看到一条条平线。这条在 Blender 端踩过坑，现在有测试守着
（测试里的 `[脊线方向]` 一节）。

## 踩过的坑

完整版在 [blender/README.md](blender/README.md)，这里挑几条跨端的：

1. **Blender 的体积雾是死路。** 世界体积会让画面全黑（阳光在无限光程上被吃光）；
   有限体积盒更怪——纯透明、没挂体积着色器的大盒子也会让地形完全不受光。
   最后改用"渐变沙尘天空 + 材质距离雾"。
2. **Godot 的 sky shader 里没有 `SUN_DIR`**（那是 Blender 的），太阳方向得自己传。
3. **天空噪声别做透视除法**（`dir.xz / dir.y`）：地平线附近 uv 爆掉，
   天空会浮出一块块三角分面。
4. **`var x := some_variant.instantiate()` 会解析失败**；而解析失败后 Godot
   没有主场景可跑，进程会一直挂着——表面看像死锁，实际是脚本根本没加载起来。
5. **`CanvasLayer` 不是 Control**，没有 `size` 也没有 `NOTIFICATION_RESIZED`，
   准星居中要用 CenterContainer 而不是自己算坐标。

## 环境

- Godot：`E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`
- Blender：`E:\apps\blender-5.2.1-windows-x64\blender.exe`（Cycles + OptiX）
