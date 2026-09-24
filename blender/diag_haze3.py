"""Haze experiment, round 3.

Round 2: density 0.0005 and 0.02 render identically black, so whatever is
darkening the terrain is not scaling with density at all. Two candidates left:
the box mesh blocking light, or the Density socket never actually being set.
This round prints the socket value and tests a box with no volume at all.
"""

from __future__ import annotations

import os
import sys

import bpy
from mathutils import Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import desert_lib as lib  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "renders")
FIELD = {"height": 26.0, "sharp": 2.2, "spacing": 118.0, "bend": 2.6, "swell": 5.0}


def setup(scene, name, samples=24, w=440, h=248):
    scene.render.engine = "CYCLES"
    scene.render.resolution_x = w
    scene.render.resolution_y = h
    scene.render.image_settings.file_format = "PNG"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.cycles.device = "CPU"
    scene.cycles.volume_bounces = 4
    scene.render.filepath = os.path.join(OUT, "hz3-%s.png" % name)
    try:
        scene.view_settings.view_transform = "AgX"
    except Exception:
        pass


def flat_light(scene, strength=1.0):
    world = bpy.data.worlds.new("Flat")
    scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Strength"].default_value = strength
    bg.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])


def camera(scene, lens=62.0):
    cx, cy = 6.0, -32.0
    cam_z = lib.dune_height(cx, cy, **FIELD) + 4.2
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = lens
    cam = bpy.data.objects.new("Camera", cam_data)
    lib.link(cam)
    cam.location = (cx, cy, cam_z)
    direction = Vector((0.0, 70.0, cam_z + 6.0)) - Vector(cam.location)
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam


def terrain():
    obj = lib.build_dune_field(
        name="Dunes", size=1600.0, segments=150, offset=(0.0, 160.0), **FIELD
    )
    obj.data.materials.append(lib.sand_material())


def box(scene, density=None, name="Box"):
    obj = lib._box_mesh(name, (2800.0, 2800.0, 260.0))
    obj.location = (0.0, 160.0, 110.0)
    lib.link(obj)
    _mat, nt, out = lib.new_material(name + "Mat")
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    tr.location = (300, 200)
    nt.links.new(tr.outputs["BSDF"], out.inputs["Surface"])
    if density is not None:
        vol = nt.nodes.new("ShaderNodeVolumeScatter")
        vol.location = (300, -200)
        lib.set_input(vol, "Color", lib.to_linear((226, 182, 122)))
        lib.set_input(vol, "Anisotropy", 0.35)
        lib.set_input(vol, "Density", 1.0)
        print("BOX_DENSITY_BEFORE %.6f" % vol.inputs["Density"].default_value)
        vol.inputs["Density"].default_value = density
        print("BOX_DENSITY_AFTER  %.6f" % vol.inputs["Density"].default_value)
        print("BOX_HAS_SOCKET %s" % ("Density" in vol.inputs))
        print("BOX_IS_LINKED %s" % vol.inputs["Density"].is_linked)
        nt.links.new(vol.outputs["Volume"], out.inputs["Volume"])
    return obj


def run(name, haze_fn):
    scene = lib.reset_scene()
    flat_light(scene, 1.0)
    lib.add_sun(16.0, 200.0, energy=5.5, color=(255, 214, 158), angle_deg=4.0)
    terrain()
    if haze_fn is not None:
        haze_fn(scene)
    camera(scene)
    setup(scene, name)
    print("SCENE_OBJECTS %s" % [o.name for o in scene.objects])
    bpy.ops.render.render(write_still=True)
    print("HZ3_DONE %s" % name)


def main():
    os.makedirs(OUT, exist_ok=True)
    run("G1_transparent_box_no_volume", lambda s: box(s, density=None))
    run("G2_box_volume_0p0005", lambda s: box(s, density=0.0005))
    run("G3_no_box", lambda s: None)


main()
