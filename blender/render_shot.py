"""Render the Taklamakan atmosphere shots with Blender 5.2 / Cycles.

First person: the camera sits at eye height (1.65 m) and looks out across the
dunes, because that is the view the Godot slice has to deliver. No figure is
placed - the player is the figure.

Usage:
    blender -b --factory-startup --python render_shot.py -- \
        --shot dust_wall --width 1600 --height 900 --samples 128
"""

from __future__ import annotations

import argparse
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import desert_lib as lib  # noqa: E402


HERE = os.path.dirname(os.path.abspath(__file__))
RENDER_DIR = os.path.join(HERE, "renders")
BLEND_DIR = os.path.join(HERE, "scenes")

SHOTS = {}

# Multiplied into every atmosphere density; 0 disables dust entirely. Used to
# tell "the sun is not reaching the sand" apart from "the dust is eating it".
FOG_MULT = 1.0


def atmosphere(scene, **kwargs):
    kwargs["density"] = kwargs.get("density", 0.01) * FOG_MULT
    return lib.add_world_atmosphere(scene, **kwargs)


def shot(name):
    def deco(fn):
        SHOTS[name] = fn
        return fn

    return deco


# Crests run along Y, so the camera must look along X to see them stacked.
DUNES = {
    "height": 21.0,
    "sharp": 3.0,
    "spacing": 82.0,
    "bend": 4.5,
    "swell": 7.5,
    "vary": 0.55,
}

TIGHT = {
    "height": 19.0,
    "sharp": 3.2,
    "spacing": 60.0,
    "bend": 5.0,
    "swell": 7.0,
    "vary": 0.60,
}

NOON = {
    "height": 20.0,
    "sharp": 2.6,
    "spacing": 150.0,
    "bend": 3.0,
    "swell": 6.0,
    "vary": 0.45,
}


# ---------------------------------------------------------------------------
# shared plumbing
# ---------------------------------------------------------------------------


def add_camera(location, look_at, lens=50.0, sensor=36.0, fstop=0.0):
    cam = bpy.data.cameras.new("Cam")
    cam.lens = lens
    cam.sensor_width = sensor
    if fstop > 0.0:
        cam.dof.use_dof = True
        cam.dof.focus_distance = (Vector(look_at) - Vector(location)).length
        cam.dof.aperture_fstops = fstop
    obj = bpy.data.objects.new("Camera", cam)
    lib.link(obj)
    obj.location = Vector(location)
    direction = Vector(look_at) - Vector(location)
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = obj
    return obj


def add_eye_camera(
    x,
    y,
    field=None,
    yaw_deg=90.0,
    pitch_deg=-2.0,
    eye=1.66,
    lens=40.0,
    fstop=0.0,
    stand_lift=0.0,
):
    """Camera at standing eye height, looking along `yaw_deg` (0 = +Y, 90 = +X)."""
    field = field or DUNES
    z = lib.dune_height(x, y, **field) + eye + stand_lift
    yaw = math.radians(yaw_deg)
    pitch = math.radians(pitch_deg)
    forward = Vector(
        (
            math.sin(yaw) * math.cos(pitch),
            math.cos(yaw) * math.cos(pitch),
            math.sin(pitch),
        )
    )
    cam = add_camera((x, y, z), Vector((x, y, z)) + forward * 120.0, lens=lens, fstop=fstop)
    print("EYE z=%.2f yaw=%.0f pitch=%.1f" % (z, yaw_deg, pitch_deg))
    return cam


def hold_staff(cam, offset=(0.24, -0.15, -0.72), tilt_deg=26.0, lean_deg=-6.0):
    """Put the khakkhara into the lower right of frame, parented to the camera.

    The staff is long, so it is deliberately swung across the frame rather than
    left vertical: held upright at arm's length it would run from below the
    bottom edge to beyond the top one and read as a pole through the shot.
    """
    staff = lib.build_staff()
    staff.parent = cam
    # Leave matrix_parent_inverse at identity: the child's location is then
    # expressed in camera-local space, which is what we want. Parenting through
    # cam.matrix_world.inverted() would need a depsgraph update first, and in a
    # headless run that matrix is still the identity.
    staff.location = offset
    staff.rotation_euler = (
        math.radians(-90.0),
        math.radians(lean_deg),
        math.radians(tilt_deg),
    )
    bpy.context.view_layer.update()
    from bpy_extras.object_utils import world_to_camera_view

    ndc = world_to_camera_view(
        bpy.context.scene, cam, staff.matrix_world @ Vector((0.0, 0.0, 1.0))
    )
    grip = world_to_camera_view(
        bpy.context.scene, cam, staff.matrix_world @ Vector((0.0, 0.0, 0.0))
    )
    print(
        "STAFF tip ndc=(%.3f, %.3f) grip ndc=(%.3f, %.3f) depth=%.2f"
        % (ndc.x, ndc.y, grip.x, grip.y, ndc.z)
    )
    return staff


def find_viewpoint(
    field=None,
    y=0.0,
    span=900.0,
    step=3.0,
    ahead=38.0,
    eye=1.66,
    target_deg=2.5,
):
    """Pick a spot with a dune rising in front of the lens.

    Three failed strategies before this one, all worth not repeating:

    * standing on a crest - the eye looks down a long empty slope and the
      horizon renders as a single straight line;
    * preferring low ground - the camera lands in a bowl and the frame fills
      with an unbroken wall of orange;
    * scoring an marched skyline by "number of crests" - minute noise jitter
      scored 70 crests on a perfectly smooth slope.

    What actually produces layering in a first-person shot is a crest close in
    front (so the near sand occludes the ground beyond it) with higher ground
    still behind that. Score exactly that, and reject anything whose near rise
    would cover the whole frame.
    """
    field = field or DUNES
    best_x, best_score = 0.0, -1e9
    x = -span
    while x <= span:
        h = lib.dune_height(x, y, **field)
        near = lib.dune_height(x + ahead, y, **field)
        angle = math.degrees(math.atan2(near - (h + eye), ahead))
        far = max(
            lib.dune_height(x + d, y, **field) for d in (100.0, 170.0, 250.0, 340.0)
        )
        # Keep the near crest low so the view stays open, then reward ground
        # that climbs above eye level further out - that is what gives a
        # skyline made of several crests instead of one smooth slope.
        far_lift = far - (h + eye)
        score = -abs(angle - target_deg) * 6.0 + far_lift * 0.8
        if angle > 10.0:
            score -= (angle - 10.0) * 20.0
        if score > best_score:
            best_score, best_x = score, x
        x += step
    h = lib.dune_height(best_x, y, **field)
    near = lib.dune_height(best_x + ahead, y, **field)
    angle = math.degrees(math.atan2(near - (h + eye), ahead))
    print(
        "VIEWPOINT x=%.1f score=%.1f ground=%.1f near_rise=%.1f near_angle=%.1fdeg"
        % (best_x, best_score, h, near - h, angle)
    )
    return best_x


def setup_cycles(scene, width, height, samples, use_gpu=True):
    scene.render.engine = "CYCLES"
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"

    cy = scene.cycles
    cy.samples = samples
    cy.use_denoising = True
    cy.max_bounces = 8
    cy.volume_bounces = 4
    cy.volume_step_rate = 1.0
    cy.caustics_reflective = False
    cy.caustics_refractive = False

    if use_gpu:
        cy.device = "GPU"
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "OPTIX"
        prefs.get_devices()
        for dev in prefs.devices:
            dev.use = dev.type in {"OPTIX", "CUDA"}
    else:
        cy.device = "CPU"

    try:
        scene.view_settings.view_transform = "AgX"
    except Exception as exc:
        print("NOTE: view transform fallback (%s)" % exc)
    for look in ("AgX - Medium High Contrast", "Medium High Contrast"):
        try:
            scene.view_settings.look = look
            break
        except Exception:
            continue
    scene.view_settings.exposure = 0.0


def build_ground(field=None, size=1600.0, segments=240, material=None, offset=(0.0, 0.0)):
    field = field or DUNES
    terrain = lib.build_dune_field(
        name="Dunes", size=size, segments=segments, offset=offset, **field
    )
    terrain.data.materials.append(material or lib.sand_material())
    return terrain


# ---------------------------------------------------------------------------
# shots
# ---------------------------------------------------------------------------


@shot("dust_wall")
def _dust_wall(scene, args):
    """沙暴压顶：天色变成脏黄，太阳退成一块不刺眼的光斑，
    地平线在你能走到它之前就已经消失了。"""
    sand = lib.sand_material(
        light=(222, 188, 138),
        dark=(186, 152, 104),
        haze_color=(214, 166, 108),
        haze_near=6.0,
        haze_far=95.0,
    )
    vx = find_viewpoint(DUNES)
    build_ground(size=1800.0, segments=280, material=sand, offset=(vx, 0.0))
    lib.build_gradient_sky(
        scene,
        horizon=(216, 168, 110),
        zenith=(74, 52, 40),
        horizon_power=1.15,
        cloud_amount=0.35,
        cloud_scale=1.4,
        glow_elevation_deg=30.0,
        glow_rotation_deg=298.0,
        glow_color=(255, 214, 146),
        glow_strength=1.6,
        glow_focus=34.0,
    )
    lib.add_sun(52.0, 298.0, energy=4.6, color=(255, 226, 180), angle_deg=2.5)
    cam = add_eye_camera(vx, 0.0, yaw_deg=90.0, pitch_deg=6.0, lens=40.0)
    hold_staff(cam)


@shot("white_noon")
def _white_noon(scene, args):
    """白炽正午：影子缩到脚下，天地一片惨白，"上无飞鸟，下无水草"。"""
    bright = lib.sand_material(
        light=(244, 232, 204),
        dark=(212, 184, 142),
        bump_strength=0.18,
        patch_scale=0.09,
        haze_color=(238, 230, 208),
        haze_near=10.0,
        haze_far=190.0,
    )
    nx = find_viewpoint(NOON)
    build_ground(field=NOON, size=2200.0, segments=280, material=bright, offset=(nx, 0.0))
    lib.build_gradient_sky(
        scene,
        horizon=(252, 246, 232),
        zenith=(146, 172, 204),
        horizon_power=1.9,
        glow_elevation_deg=72.0,
        glow_rotation_deg=60.0,
        glow_color=(255, 253, 242),
        glow_strength=1.05,
        glow_focus=90.0,
        cloud_amount=0.18,
        cloud_scale=2.0,
    )
    lib.add_sun(72.0, 60.0, energy=7.5, color=(255, 251, 240), angle_deg=0.5)
    add_eye_camera(nx, 0.0, field=NOON, yaw_deg=90.0, pitch_deg=4.0, lens=35.0)


@shot("bone_night")
def _bone_night(scene, args):
    """星夜：冷月下的白沙，风把沙子吹过看不见的骨头。"""
    cool = lib.sand_material(
        light=(150, 156, 176),
        dark=(96, 102, 126),
        roughness=0.9,
        bump_strength=0.2,
        haze_color=(84, 94, 120),
        haze_near=5.0,
        haze_far=80.0,
    )
    kx = find_viewpoint(DUNES)
    build_ground(size=1800.0, segments=250, material=cool, offset=(kx, 0.0))
    lib.build_gradient_sky(
        scene,
        horizon=(80, 92, 128),
        zenith=(9, 11, 26),
        horizon_power=1.05,
        glow_elevation_deg=36.0,
        glow_rotation_deg=300.0,
        glow_color=(200, 218, 255),
        glow_strength=1.2,
        glow_focus=180.0,
        cloud_amount=0.45,
        cloud_scale=1.3,
    )
    lib.add_sun(46.0, 300.0, energy=3.2, color=(190, 210, 255), angle_deg=3.0)
    cam = add_eye_camera(kx, 0.0, yaw_deg=90.0, pitch_deg=6.0, lens=40.0)
    hold_staff(cam)


@shot("lost")
def _lost(scene, args):
    """迷失：贴着沙面望出去，一层接一层的脊线，没有尽头，
    也没有任何东西可以拿来定位。"""
    sand = lib.sand_material(
        light=(206, 172, 126),
        dark=(172, 138, 96),
        haze_color=(196, 148, 98),
        haze_near=2.0,
        haze_far=46.0,
    )
    vx = find_viewpoint(TIGHT)
    build_ground(field=TIGHT, size=2400.0, segments=320, material=sand, offset=(vx, 0.0))
    lib.build_gradient_sky(
        scene,
        horizon=(196, 148, 98),
        zenith=(86, 62, 48),
        horizon_power=1.0,
        cloud_amount=0.40,
        cloud_scale=1.1,
        glow_elevation_deg=18.0,
        glow_rotation_deg=292.0,
        glow_color=(230, 174, 106),
        glow_strength=0.95,
        glow_focus=26.0,
    )
    lib.add_sun(44.0, 292.0, energy=3.8, color=(255, 214, 160), angle_deg=3.5)
    cam = add_eye_camera(vx, 0.0, field=TIGHT, yaw_deg=90.0, pitch_deg=6.0, lens=45.0)
    hold_staff(cam)


# ---------------------------------------------------------------------------
# entry point
# ---------------------------------------------------------------------------


@shot("engulfed")
def _engulfed(scene, args):
    """吞没：能见度不到二十米，天和地是同一种颜色，
    只剩下风和脚下的沙，没有任何可以拿来定位的东西。"""
    sand = lib.sand_material(
        light=(198, 160, 114),
        dark=(172, 134, 92),
        haze_color=(186, 138, 88),
        haze_near=0.0,
        haze_far=24.0,
    )
    vx = find_viewpoint(DUNES)
    build_ground(size=1600.0, segments=260, material=sand, offset=(vx, 0.0))
    lib.build_gradient_sky(
        scene,
        horizon=(188, 140, 90),
        zenith=(106, 76, 58),
        horizon_power=0.85,
        cloud_amount=0.55,
        cloud_scale=0.9,
        glow_elevation_deg=34.0,
        glow_rotation_deg=296.0,
        glow_color=(232, 186, 128),
        glow_strength=0.9,
        glow_focus=20.0,
    )
    lib.add_sun(40.0, 296.0, energy=3.0, color=(255, 224, 176), angle_deg=4.0)
    cam = add_eye_camera(vx, 0.0, yaw_deg=90.0, pitch_deg=2.0, lens=45.0)
    hold_staff(cam)


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--shot", default="dust_wall", choices=sorted(SHOTS))
    parser.add_argument("--samples", type=int, default=128)
    parser.add_argument("--width", type=int, default=1600)
    parser.add_argument("--height", type=int, default=900)
    parser.add_argument("--out", default="")
    parser.add_argument("--cpu", action="store_true")
    parser.add_argument(
        "--fog-mult", type=float, default=1.0, help="scale every haze density"
    )
    parser.add_argument("--blend", default="", help="path for the saved .blend")
    parser.add_argument("--no-blend", action="store_true", help="render only")
    parser.add_argument(
        "--no-render", action="store_true", help="build and save the .blend only"
    )
    return parser.parse_args(argv)


def main():
    global FOG_MULT
    args = parse_args()
    FOG_MULT = args.fog_mult
    scene = lib.reset_scene()
    SHOTS[args.shot](scene, args)
    setup_cycles(scene, args.width, args.height, args.samples, use_gpu=not args.cpu)

    os.makedirs(RENDER_DIR, exist_ok=True)
    if not args.no_blend:
        os.makedirs(BLEND_DIR, exist_ok=True)
        blend_path = args.blend or os.path.join(BLEND_DIR, args.shot + ".blend")
        bpy.ops.wm.save_as_mainfile(filepath=blend_path)
        print("SAVED_BLEND: %s" % blend_path)

    if args.no_render:
        print("SKIPPED_RENDER (--no-render)")
        return

    out = args.out or os.path.join(RENDER_DIR, args.shot + ".png")
    scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    print("RENDERED: %s" % out)


main()
