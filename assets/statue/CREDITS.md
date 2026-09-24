# 弥勒像白膜：来源、许可、以及怎么从原始文件重做一遍

## 这是什么

场景里那尊 1080 m 高的弥勒，像身不是程序化堆出来的方块，是一份**外部白膜**：
中国民间最常见的那种**大肚弥勒立像**——光头、笑脸、长耳垂、袒胸露腹、
右手把一柄如意举过头顶、脚下踩圆台。

选这个形而不是唐代那种"菩萨装、戴宝冠"的弥勒，是**可读性**优先：
这尊的剪影一眼就是弥勒，而场景里它离玩家 1.3 km、还隔着一层沙尘，
认不出来的话，前面所有的构图都是白搭。

## 出处

| 项 | 值 |
|---|---|
| 名称 | Maitreya（原名 `ruyimile.stl`，如意弥勒） |
| 作者 | stronghero |
| 原始页面 | <https://www.thingiverse.com/thing:2431705> |
| 存档镜像 | <https://archive.org/details/thingiverse-2431705> |
| 下载直链 | `https://archive.org/serve/thingiverse-2431705/Maitreya_2431705.zip` |
| 存档 | `Maitreya_2431705.zip`，81 440 835 字节 |
| 包内文件 | `files/ruyimile.stl`，175 022 784 字节，3 500 454 个三角面 |
| 存档原始 sha1 | `aec6246abfbb3d3685d2715ffe1ea369e7290a28`（archive.org 元数据） |
| 许可 | **Creative Commons Attribution 3.0 Unported（CC BY 3.0）** |

完整许可证原文见同目录的 [LICENSE-CC-BY-3.0.txt](LICENSE-CC-BY-3.0.txt)。
原作者的预览图存档在同目录的 `source-preview.jpg`（就是上面那份 zip 里的图）。

### 署名（CC BY 3.0 要求，删不得）

> Maitreya by stronghero, licensed under Creative Commons Attribution 3.0.
> <https://www.thingiverse.com/thing:2431705>

CC BY 3.0 只要求署名，**不要求**本作品也改用同一许可（那是 SA 才有的条款），
所以这份白膜可以留在这个仓库里、也可以随游戏一起分发，只要署名跟着走。

## 怎么重做

```powershell
$blender = 'E:\apps\blender-5.2.1-windows-x64\blender.exe'
& $blender -b --factory-startup -P blender\build_maitreya.py -- `
    <ruyimile.stl 的路径> assets\statue\maitreya.glb 150000
```

脚本做四件事，每一步的理由都写在它的 docstring 里：**降面到 15 万**、
**转正**（原文件是倒的）、**转朝向**（原文件脸朝 +Y，场景要 -X）、
**归一到"脚底 y=0、轴心在正下方、总高 1080"**。

175 MB 的原始 STL 和 81 MB 的 zip **不入库**——它们是可复现的中间产物，
上面那张表里的直链和哈希足够把它找回来。

## 落进场景时踩到的坑

1. **STL 是打印件，不是渲染件。** 它没有"上"、没有"前"、没有原点约定，
   350 万面是给 0.1 mm 层高准备的。三样都必须重新定义一遍。
2. **变换必须烘进顶点。** 留成 object transform 的话，Godot 里 mesh 自身的
   包围盒还是横躺的；任何"按顶点算"的断言（高度、朝向、肩宽）都会算错，
   而且**画面看起来是对的**——错只在数据里。
3. **`bpy.ops.object.shade_smooth_by_angle`**：平面着色的网格降面之后每个棱
   都看得见。35° 阈值保住衣褶的硬边，只抹平圆弧面。
4. **archive.org 的 `/download/` 和 `/serve/` 不是一回事。** 同一条直链改个
   路径前缀，走本地代理实测 5 KB/s → 9.5 MB/s，差了 1800 倍。
   下次从这里抓素材，直接上 `/serve/`。
