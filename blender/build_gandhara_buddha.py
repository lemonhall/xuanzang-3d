"""把网上的犍陀罗立佛 GLB 转成 Godot 能直接用的白膜 GLB。

用法：

    blender.exe -b --factory-startup -P blender/build_gandhara_buddha.py -- \
        <输入.glb> <输出.glb> [目标三角面数，0 = 不降面]

来源与许可见 `assets/statue/CREDITS.md`（**CC0**，无署名义务，我们照署）。
选型过程与完整候选对比见 `docs/design/asset-sourcing.md`。

## 这个脚本要解决的问题

原始 GLB 是**扫描件**，不是为这个场景做的，三件事和场景对不上：

  1. **朝向**。源文件是 Z 轴向上、**面朝 -Y**；场景约定 **面朝 -X**
     （玩家从 +X 方向走过来）。绕 Z 转 -90° 正好把 -Y 送到 -X。
     不需要像上一版（STL 打印件）那样先绕 X 翻 180°——GLB 本身
     已经带正确的 Y-up→Z-up 约定，再翻一次就变成躺着的了。

  2. **原点和尺度**。场景约定：脚底 z=0、轴心在像的正下方、
     总高 `TARGET_HEIGHT`（1080 m，和 Mirage.STATUE_HEIGHT 必须一致）。

  3. **贴图和材质是死重量**。场景里像身挂的是自己的 `mirage.gdshader`
     （`material_override`），GLB 自带的 PBR 材质和 3 MB 的漫反射
     贴图一个像素都不会被用到。而且——**这是一份"白膜"**，带一张
     石头的照片贴图在语义上就不对了。所以这里把材质和贴图全部丢掉。

## 翻转和旋转必须烘进顶点

留成 object transform 的话，导入 Godot 后 mesh 自身的包围盒还是横躺的，
任何"按顶点算"的断言（高度、朝向、肩宽）都会算错，而且**画面看起来是对的**
——错只在数据里。上一版在 STL 上踩过，这里用同样的 `transform_apply`。

## 顺带打印一份高度剖面

`STATUE_HEAD_RATIO`（头顶在像高里的位置）和 `STATUE_SHOULDER_RATIO`
（环心高度那一层的半宽）是构图和测试都要用的数字，必须**从这个文件量出来**，
不能凭上一版的白膜抄。所以每跑一次都会把剖面打出来。
"""

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

## 场景里的像高（米）。和 Mirage.STATUE_HEIGHT 必须一致。
TARGET_HEIGHT = 1080.0
## 0 表示"不降面"。源文件只有 7 万面，比上一版的 15 万还低，够用。
DEFAULT_TARGET_TRIS = 0
## 量肩宽用的高度分位（像高比例）。和 Mirage.HALO_CENTER_RATIO 对齐。
SHOULDER_AT = 0.745


def _argv() -> list:
    if "--" not in sys.argv:
        raise SystemExit("需要参数：<输入.glb> <输出.glb> [目标三角面数]")
    return sys.argv[sys.argv.index("--") + 1 :]


def _bounds(obj) -> tuple:
    lo = Vector((1e18, 1e18, 1e18))
    hi = Vector((-1e18, -1e18, -1e18))
    for vertex in obj.data.vertices:
        world = obj.matrix_world @ vertex.co
        for axis in range(3):
            lo[axis] = min(lo[axis], world[axis])
            hi[axis] = max(hi[axis], world[axis])
    return lo, hi


def _report(tag: str, lo: Vector, hi: Vector) -> None:
    print(
        "%s MIN %s MAX %s SIZE %s"
        % (
            tag,
            tuple(round(v, 2) for v in lo),
            tuple(round(v, 2) for v in hi),
            tuple(round(hi[i] - lo[i], 2) for i in range(3)),
        )
    )


def _profile(obj, lo: Vector, height: float, bands: int = 20) -> None:
    """按高度切片，打印每一层的横向/前后跨度。

    头顶在哪、肩在哪、台座在哪，都从这张表上读——**不要猜**。
    """
    print("PROFILE 像高 %.1f m，分 %d 层：" % (height, bands))
    print("  层     y下限      y上限     宽(Z)      厚(X)      X最小      X最大")
    for i in range(bands):
        y0 = lo.z + height * float(i) / bands
        y1 = lo.z + height * float(i + 1) / bands
        xs = []
        zs = []
        for vertex in obj.data.vertices:
            y = vertex.co.z
            if y0 <= y <= y1:
                xs.append(vertex.co.x)
                zs.append(vertex.co.y)
        if not xs:
            print("  %2d  %8.0f  %8.0f      —— 空层" % (i, y0, y1))
            continue
        print(
            "  %2d  %8.0f  %8.0f  %8.0f  %8.0f  %8.0f  %8.0f"
            % (
                i,
                y0,
                y1,
                max(zs) - min(zs),
                max(xs) - min(xs),
                min(xs),
                max(xs),
            )
        )


def main() -> None:
    argv = _argv()
    src = argv[0]
    dst = argv[1]
    target_tris = int(argv[2]) if len(argv) > 2 else DEFAULT_TARGET_TRIS

    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.ops.import_scene.gltf(filepath=src)

    obj = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    obj.data.calc_loop_triangles()
    before = len(obj.data.loop_triangles)
    if target_tris > 0 and before > target_tris:
        modifier = obj.modifiers.new(name="decimate", type="DECIMATE")
        modifier.decimate_type = "COLLAPSE"
        modifier.ratio = target_tris / float(before)
        modifier.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier="decimate")
        obj.data.calc_loop_triangles()
    print(
        "TRIS %d -> %d (target %s)"
        % (before, len(obj.data.loop_triangles), target_tris or "keep")
    )

    # 源文件：Z 向上、面朝 -Y。场景要面朝 -X，绕 Z 转 -90° 即可。
    # Rz(-90°) 把 (0,-1,0) 送到 (-1,0,0)，也就是把"脸"从 -Y 转到 -X。
    obj.matrix_world = Matrix.Rotation(math.radians(-90.0), 4, "Z") @ obj.matrix_world
    bpy.context.view_layer.update()
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    lo, hi = _bounds(obj)
    _report("FACING_X", lo, hi)
    height = hi.z - lo.z

    # 轴心定在**底面**的形心上：绕 Z 转像的时候转的是像自己的立柱，
    # 而不是一个偏到一边的点。取底面 2% 高度内的顶点，避开台座外沿。
    base_cut = lo.z + height * 0.02
    base = [v.co for v in obj.data.vertices if v.co.z <= base_cut]
    center_x = sum(v.x for v in base) / float(len(base))
    center_y = sum(v.y for v in base) / float(len(base))
    print("BASE_CENTER %.2f %.2f (%d 个顶点)" % (center_x, center_y, len(base)))

    scale = TARGET_HEIGHT / height
    obj.matrix_world = (
        Matrix.Scale(scale, 4)
        @ Matrix.Translation(Vector((-center_x, -center_y, -lo.z)))
    ) @ obj.matrix_world
    bpy.context.view_layer.update()
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    lo, hi = _bounds(obj)
    _report("FINAL", lo, hi)
    print("SCALE %.6f" % scale)
    _profile(obj, lo, hi.z - lo.z)

    # 白膜：材质和贴图全部丢掉。场景里像身挂的是 material_override，
    # 自带的 PBR 用不上；而且"白膜"本来就该是没有颜色的。
    images = [img for img in bpy.data.images if img.users]
    print("STRIP images=%d materials=%d" % (len(images), len(obj.data.materials)))
    obj.data.materials.clear()
    for img in images:
        bpy.data.images.remove(img)

    # 扫描件是平面着色的：不平滑的话台座和衣褶的每一道棱都看得见。
    # 35° 阈值保住衣褶的硬边，只把圆弧面抹平。
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35.0))

    os.makedirs(os.path.dirname(dst), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=dst,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
    )
    print("GLB %s %d bytes" % (dst, os.path.getsize(dst)))


main()
