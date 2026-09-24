# 塔克拉玛干场景（Blender 5.2 / Cycles）

程序化生成 + 渲染。没有外部素材：沙丘、天空、沙尘、锡杖全部由代码建出来。

## 目录

| 路径 | 内容 |
|---|---|
| `desert_lib.py` | 场景积木：沙丘高度场、沙材质、渐变沙尘天空、大气、太阳、锡杖 |
| `render_shot.py` | 镜头定义 + 渲染入口（CLI） |
| `scenes/*.blend` | **可编辑源文件**，直接双击用 Blender 打开 |
| `renders/*.png` | 成品图 1600×900 |

## 跑一张图

```powershell
$blender = 'E:\apps\blender-5.2.1-windows-x64\blender.exe'

# 出图（同时保存 scenes/<镜头>.blend）
& $blender -b --factory-startup --python blender\render_shot.py -- `
    --shot dust_wall --width 1600 --height 900 --samples 96

# 只要 .blend，不渲染
& $blender -b --factory-startup --python blender\render_shot.py -- `
    --shot lost --no-render
```

常用参数：`--shot` / `--samples` / `--width` / `--height` / `--out` /
`--no-blend` / `--no-render` / `--cpu` / `--fog-mult`（沙尘浓度倍率，调试用）。

## 五个镜头（全部第一人称，眼高 1.66 m）

| 镜头 | 一句话 |
|---|---|
| `dust_wall` | 沙暴压顶：暖色沙丘脊线，天空退成脏黄 |
| `lost` | 迷失：一层接一层的脊线，没有参照物 |
| `engulfed` | 吞没：能见度不到 20 m，天和地是同一种颜色 |
| `white_noon` | 白炽正午：影子缩到脚下，天地惨白 |
| `bone_night` | 星夜：冷月下的白沙 |

## 场景积木怎么调

`desert_lib.dune_height()` 的参数决定地形性格：

- `height` / `spacing` —— 沙丘高度与脊线间距（决定坡度）
- `bend` —— 脊线蜿蜒程度。**平直脊线会让第一人称画面塌成一条水平线**
- `vary` —— 每座沙丘各自的高度系数。这是"远近脊线能错开"的来源
- `swell` —— 底层大尺度起伏

沙材质 `sand_material()` 带**距离雾**（`haze_near` / `haze_far` / `haze_color`）：
相机射线走得越远，沙色越接近天空色。能见度靠这三个参数控制。

`render_shot.find_viewpoint()` 会自动挑机位：要求前方约 38 m 处有一道
低坡（cut 掉画面下部一小块），同时更远处有高于视线的地形。改地形参数后
机位会自动跟着变。

## 踩过的坑（别重复踩）

1. **世界体积雾（World Volume）会把画面变成全黑。**
   它填满整个空间，阳光从"无限远"射来时光程无限，衰减无上限；密度再小也一样。
2. **有限体积盒（mesh box）同样不可用。**
   在 Blender 5.2 里，一个包住场景的大盒子即使材质是纯 Transparent BSDF、
   连体积着色器都没挂，也会让地形彻底不受光。密度 0.0005 与 0.02 渲染结果
   完全一致，证明它跟密度无关。
3. **Texture Coordinate 的 Object 输出是物体空间（这里是米），不是归一化 0..1。**
   按归一化去写高度衰减，雾层会落在完全错误的高度上。
4. **`world_to_camera_view` 前必须 `bpy.context.view_layer.update()`。**
   否则拿到的是过期矩阵，量出来的屏幕坐标全是假的（曾经把一个站在画面正中的
   人物量成"在画面上方 1.25 屏"）。
5. **Sky Texture 的参数是节点属性，不是 input socket。**
   `sky.aerosol_density = x` 对，`node.inputs["Aerosol Density"]` 不存在。
6. **噪波 bump 给太强会变成"泥浆"。**
   `bump_strength` 0.55 时沙面像融化的泥；0.2 左右才像沙。

最终采用的做法：**渐变沙尘天空 + 沙材质的距离雾**，不碰任何体积散射。
好处是渲染快（5–20 秒/张）、可控、而且不会莫名其妙把光照吃掉。
