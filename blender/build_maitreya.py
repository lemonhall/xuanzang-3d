"""把网上的弥勒白膜 STL 转成 Godot 能直接用的 GLB。

用法：

    blender.exe -b --factory-startup -P blender/build_maitreya.py -- \
        <输入.stl> <输出.glb> [目标三角面数]

来源与许可见 `assets/statue/CREDITS.md`（CC BY 3.0，署名必留）。

## 这个脚本要解决的问题

原始 STL 是**打印用**的，不是渲染用的，三个属性和场景对不上：

  1. **350 万三角面**。打印要的是"表面平滑"，渲染要的是"轮廓正确"。
     这尊像在场景里只有 590 px 高、还隔着一层沙尘，150 万面之后每多一个
     面都是在给一张 3 px 宽的衣纹付钱。降到 15 万，画面看不出来，
     显存和填充率省下来一大截。

  2. **倒着、而且面朝 +Y**。STL 没有"上"的概念，导出的人怎么摆就怎么算。
     这尊的头在 -Z、底板在 +Z，脸朝 -Y。

  3. **原点和场景对不上**。场景约定：脚底 y=0、轴心在像的正下方、
     总高 `STATUE_HEIGHT`（1080 m）、**面朝 -X**（玩家来的方向）。

## 为什么是"绕 X 翻 180° 再绕 Z 转 90°"

blender 的欧拉 XYZ 是 R = Rz·Ry·Rx，所以 `rotation_euler = (pi, 0, pi/2)`
就是"先绕 X 翻 180°、再绕 Z 转 90°"：

    绕 X 翻 180°   z -> -z（转正）   y -> -y（脸从 -Y 转到 +Y）
    绕 Z 转 90°    +Y -> -X          （脸从 +Y 摆到 -X）

翻转和旋转都必须**烘进顶点**（transform_apply）。留成 object transform 的话，
导入 Godot 后 mesh 自身的包围盒还是横躺的，任何按顶点算的断言都会算错。
"""

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

DEFAULT_TARGET_TRIS = 150000
## 场景里的像高（米）。和 Mirage.STATUE_HEIGHT 必须一致。
TARGET_HEIGHT = 1080.0


def _argv() -> list:
    if "--" not in sys.argv:
        raise SystemExit("需要参数：<输入.stl> <输出.glb> [目标三角面数]")
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


def main() -> None:
    argv = _argv()
    src = argv[0]
    dst = argv[1]
    target_tris = int(argv[2]) if len(argv) > 2 else DEFAULT_TARGET_TRIS

    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.ops.wm.stl_import(filepath=src)

    obj = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    obj.data.calc_loop_triangles()
    before = len(obj.data.loop_triangles)
    modifier = obj.modifiers.new(name="decimate", type="DECIMATE")
    modifier.decimate_type = "COLLAPSE"
    modifier.ratio = min(1.0, target_tris / float(before))
    modifier.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier="decimate")
    obj.data.calc_loop_triangles()
    print(
        "TRIS %d -> %d (target %d)" % (before, len(obj.data.loop_triangles), target_tris)
    )

    rot = Matrix.Rotation(math.radians(90.0), 4, "Z") @ Matrix.Rotation(math.pi, 4, "X")
    obj.matrix_world = rot @ obj.matrix_world
    bpy.context.view_layer.update()
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    lo, hi = _bounds(obj)
    _report("UPRIGHT", lo, hi)
    height = hi.z - lo.z

    # 轴心定在**底板**的形心上：绕 Z 转像的时候，转的是像自己的立柱，
    # 而不是一个偏到一边的点。用底面 2% 高度内的顶点，避开衣摆那一圈外沿。
    base_cut = lo.z + height * 0.02
    base = [v.co for v in obj.data.vertices if v.co.z <= base_cut]
    center_x = sum(v.x for v in base) / float(len(base))
    center_y = sum(v.y for v in base) / float(len(base))
    print("BASE_CENTER %.2f %.2f (%d 个顶点)" % (center_x, center_y, len(base)))

    scale = TARGET_HEIGHT / height
    obj.matrix_world = (
        Matrix.Scale(scale, 4) @ Matrix.Translation(Vector((-center_x, -center_y, -lo.z)))
    ) @ obj.matrix_world
    bpy.context.view_layer.update()
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    lo, hi = _bounds(obj)
    _report("FINAL", lo, hi)
    print("SCALE %.6f" % scale)

    # 打印用模型是平面着色的：不平滑的话，150 万面降下来之后每一个棱都看得见。
    # 角度阈值（35°）保住衣褶的硬边，只把圆弧面抹平。
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
