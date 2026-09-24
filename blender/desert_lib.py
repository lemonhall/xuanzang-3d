"""Procedural Taklamakan desert builders for Blender 5.2 / Cycles.

Everything here is generated from code: dunes, sand shader, sky, dust volumes
and the pilgrim silhouette. No external assets are required.

Colors are given as sRGB 0-255 and converted to linear, because Blender's
shader inputs are linear and feeding raw sRGB values silently over-brightens.
"""

from __future__ import annotations

import math

import bpy
from mathutils import Vector, noise


# ---------------------------------------------------------------------------
# small helpers
# ---------------------------------------------------------------------------


def to_linear(rgb):
    """sRGB 0-255 tuple -> linear RGBA tuple."""

    def conv(c):
        c = c / 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return (conv(rgb[0]), conv(rgb[1]), conv(rgb[2]), 1.0)


def set_input(node, name, value):
    """Set a node input only if it exists (guards against Blender API drift)."""
    if name in node.inputs:
        node.inputs[name].default_value = value
        return True
    print("WARN: missing input %r on %s" % (name, node.bl_idname))
    return False


def set_attr(obj, name, value):
    """Set a node property (Sky Texture exposes its knobs as properties)."""
    if hasattr(obj, name):
        setattr(obj, name, value)
        return True
    print("WARN: missing property %r on %s" % (name, obj.bl_idname))
    return False


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    return bpy.context.scene


def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def new_material(name):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (800, 0)
    return mat, nt, out


def shade_smooth(obj):
    mesh = obj.data
    mesh.polygons.foreach_set("use_smooth", [True] * len(mesh.polygons))
    mesh.update()


def _fbm(p, octaves, lacunarity=2.0, gain=0.5):
    """Fractal Brownian motion, roughly -1..1."""
    total = 0.0
    norm = 0.0
    amp = 1.0
    freq = 1.0
    for _ in range(octaves):
        total += amp * noise.noise(p * freq)
        norm += amp
        amp *= gain
        freq *= lacunarity
    return total / norm


# ---------------------------------------------------------------------------
# terrain
# ---------------------------------------------------------------------------


def dune_height(
    x,
    y,
    height=21.0,
    sharp=2.2,
    spacing=82.0,
    bend=4.5,
    swell=7.5,
    vary=0.55,
    seed=0.0,
):
    """Height of the sand at world (x, y): wind-aligned crescent dunes.

    Crests stand perpendicular to the wind (which blows along +X) and are
    spaced `spacing` metres apart.

    `bend` wanders the crest lines so they are not ruler-straight - and that
    matters more than it looks. With straight crests, a camera looking along X
    sees every crest as one horizontal line and the whole desert collapses into
    a flat horizon. `vary` scales each dune's own height, which is what makes
    one crest stand proud of the next and produces the stacked look. `swell`
    adds the long, lazy undulation of the open erg underneath everything.

    Deliberately no high-frequency ripple here - the mesh cannot resolve it
    and it only aliases into gravel-looking speckle. Wind ripple lives in the
    shader bump instead.
    """
    lane = x / max(spacing, 1e-3)
    wander = _fbm(Vector((x * 0.0012, y * 0.0017, seed)), 3) * bend
    phase = (lane + wander) * math.pi
    s = (math.cos(phase) + 1.0) * 0.5
    # per-dune height multiplier in [1 - vary, 1]
    scale = 1.0 - vary * (0.5 + 0.5 * _fbm(Vector((x * 0.0048, y * 0.0048, seed + 3.0)), 2))
    h = (s ** sharp) * height * scale
    h += _fbm(Vector((x * 0.00085, y * 0.0011, seed + 5.0)), 3) * swell
    h += _fbm(Vector((x * 0.0042, y * 0.0060, seed + 9.0)), 2) * 0.55
    return h


def build_dune_field(
    name="Dunes",
    size=900.0,
    segments=200,
    height=21.0,
    sharp=2.2,
    spacing=82.0,
    bend=4.5,
    swell=7.5,
    vary=0.55,
    seed=0.0,
    offset=(0.0, 0.0),
):
    """A square heightfield mesh centred on `offset`."""
    step = size / float(segments)
    half = size * 0.5
    verts = []
    for j in range(segments + 1):
        wy = -half + j * step + offset[1]
        for i in range(segments + 1):
            wx = -half + i * step + offset[0]
            verts.append(
                (
                    wx,
                    wy,
                    dune_height(
                        wx, wy, height, sharp, spacing, bend, swell, vary, seed
                    ),
                )
            )

    faces = []
    row = segments + 1
    for j in range(segments):
        base = j * row
        for i in range(segments):
            a = base + i
            faces.append((a, a + 1, a + row + 1, a + row))

    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.validate(verbose=False)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    link(obj)
    shade_smooth(obj)
    return obj


def sand_material(
    name="Sand",
    light=(226, 196, 142),
    dark=(161, 121, 74),
    roughness=0.85,
    bump_strength=0.45,
    ripple_scale=7.0,
    patch_scale=0.13,
    haze_color=(216, 168, 110),
    haze_near=18.0,
    haze_far=230.0,
):
    """Warm sand: broad tonal patches, a wind-ripple micro-bump, and distance haze.

    The haze is mixed into the base colour by camera ray length rather than
    done with a scattering volume. A volume here was a trap: at any usable
    density it darkened the sand itself (the sun was being attenuated, not the
    distance), and the whole frame went muddy. Fading the colour toward the sky
    instead gives controllable visibility - far dunes dissolve into the sky -
    while leaving the lighting on the sand alone.
    """
    mat, nt, out = new_material(name)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (420, 0)
    set_input(bsdf, "Roughness", roughness)
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    tex = nt.nodes.new("ShaderNodeTexCoord")
    tex.location = (-1100, 0)

    # tonal patches several metres to tens of metres across
    patch = nt.nodes.new("ShaderNodeTexNoise")
    patch.location = (-880, 220)
    set_input(patch, "Scale", patch_scale)
    set_input(patch, "Detail", 6.0)
    set_input(patch, "Roughness", 0.55)
    nt.links.new(tex.outputs["Object"], patch.inputs["Vector"])

    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.location = (-640, 220)
    ramp.color_ramp.elements[0].position = 0.34
    ramp.color_ramp.elements[0].color = to_linear(dark)
    ramp.color_ramp.elements[1].position = 0.68
    ramp.color_ramp.elements[1].color = to_linear(light)
    nt.links.new(patch.outputs["Fac"], ramp.inputs["Fac"])

    # distance haze driven by how far the camera ray has travelled
    haze = nt.nodes.new("ShaderNodeRGB")
    haze.location = (-880, 460)
    haze.outputs[0].default_value = to_linear(haze_color)

    path = nt.nodes.new("ShaderNodeLightPath")
    path.location = (-1100, 620)
    hrange = nt.nodes.new("ShaderNodeMapRange")
    hrange.location = (-880, 620)
    set_input(hrange, "From Min", haze_near)
    set_input(hrange, "From Max", haze_far)
    set_input(hrange, "To Min", 0.0)
    set_input(hrange, "To Max", 1.0)
    hrange.clamp = True
    nt.links.new(path.outputs["Ray Length"], hrange.inputs["Value"])

    mix = None
    try:
        mix = nt.nodes.new("ShaderNodeMixRGB")
        mix.blend_type = "MIX"
        fac_in, a_in, b_in = mix.inputs["Fac"], mix.inputs["Color1"], mix.inputs["Color2"]
        color_out = mix.outputs["Color"]
    except Exception:
        # Blender 4.x folded MixRGB into the generic Mix node.
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MIX"
        fac_in, a_in, b_in = mix.inputs[0], mix.inputs[6], mix.inputs[7]
        color_out = mix.outputs[2]
    mix.location = (-420, 300)
    nt.links.new(ramp.outputs["Color"], a_in)
    nt.links.new(haze.outputs[0], b_in)
    nt.links.new(hrange.outputs["Result"], fac_in)
    nt.links.new(color_out, bsdf.inputs["Base Color"])

    # wind ripple: stretched along X so it reads as drifting sand, not gravel
    ripple_map = nt.nodes.new("ShaderNodeMapping")
    ripple_map.location = (-980, -240)
    set_input(ripple_map, "Scale", (0.32, 1.0, 1.0))
    nt.links.new(tex.outputs["Object"], ripple_map.inputs["Vector"])

    grain = nt.nodes.new("ShaderNodeTexNoise")
    grain.location = (-880, -220)
    set_input(grain, "Scale", ripple_scale)
    set_input(grain, "Detail", 4.0)
    set_input(grain, "Roughness", 0.45)
    nt.links.new(ripple_map.outputs["Vector"], grain.inputs["Vector"])

    bump = nt.nodes.new("ShaderNodeBump")
    bump.location = (-300, -220)
    set_input(bump, "Strength", bump_strength)
    set_input(bump, "Distance", 0.18)
    nt.links.new(grain.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


# ---------------------------------------------------------------------------
# sky, sun, dust
# ---------------------------------------------------------------------------


def build_sky(
    scene,
    elevation_deg=14.0,
    rotation_deg=196.0,
    aerosol=3.4,
    air=1.0,
    ozone=1.0,
    altitude=260.0,
    strength=1.0,
    background_color=(236, 198, 140),
):
    """Sky dome for the world.

    `aerosol` is the dust knob: high values give the flat, chalky, sun-eaten
    sky of a sandstorm. If the physical sky node is unavailable we fall back to
    a flat background so a render still comes out.
    """
    world = bpy.data.worlds.new("Taklamakan")
    scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    out.location = (600, 0)
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.location = (300, 0)
    set_input(bg, "Strength", strength)

    sky = None
    try:
        sky = nt.nodes.new("ShaderNodeTexSky")
        sky.sky_type = "MULTIPLE_SCATTERING"
    except Exception as exc:  # pragma: no cover - depends on the build
        print("WARN: sky node unavailable (%s), flat background instead" % exc)
        sky = None

    if sky is not None:
        sky.location = (0, 0)
        set_attr(sky, "sun_disc", True)
        set_attr(sky, "sun_elevation", math.radians(elevation_deg))
        set_attr(sky, "sun_rotation", math.radians(rotation_deg))
        set_attr(sky, "sun_intensity", 1.0)
        set_attr(sky, "sun_size", 0.35)
        set_attr(sky, "aerosol_density", aerosol)
        set_attr(sky, "air_density", air)
        set_attr(sky, "ozone_density", ozone)
        set_attr(sky, "altitude", altitude)
        set_attr(sky, "ground_albedo", 0.45)
        nt.links.new(sky.outputs["Color"], bg.inputs["Color"])
    else:
        set_input(bg, "Color", to_linear(background_color))

    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])
    return world


def add_world_haze(world, color=(210, 176, 130), density=0.0022, anisotropy=0.45):
    """Global suspended dust.

    WARNING: a world volume fills all of space, so sunlight travelling from
    infinity to the ground is attenuated without limit and the render goes
    black even at tiny densities. Kept only for reference; prefer
    `add_haze_volume`, which is bounded and height-faded.
    """
    nt = world.node_tree
    out = next(n for n in nt.nodes if n.bl_idname == "ShaderNodeOutputWorld")
    vol = nt.nodes.new("ShaderNodeVolumeScatter")
    vol.location = (300, -320)
    set_input(vol, "Color", to_linear(color))
    set_input(vol, "Density", density)
    set_input(vol, "Anisotropy", anisotropy)
    nt.links.new(vol.outputs["Volume"], out.inputs["Volume"])
    return vol


def sun_direction(elevation_deg, rotation_deg):
    """Unit vector pointing from the scene toward the sun."""
    e = math.radians(elevation_deg)
    r = math.radians(rotation_deg)
    return (math.cos(e) * math.sin(r), -math.cos(e) * math.cos(r), math.sin(e))


def build_gradient_sky(
    scene,
    horizon=(228, 176, 104),
    zenith=(128, 96, 70),
    horizon_power=1.5,
    strength=1.0,
    glow_elevation_deg=None,
    glow_rotation_deg=None,
    glow_color=(255, 226, 170),
    glow_strength=1.6,
    glow_focus=180.0,
    cloud_amount=0.0,
    cloud_scale=1.6,
):
    """Two-stop dust sky with an optional smeared sun glow.

    A physically based sky fights back once the air is mostly dust; a gradient
    that runs bright at the horizon and dark at the zenith reads far closer to
    a real haboob, and it stays under direct control.
    """
    world = bpy.data.worlds.new("DustSky")
    scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()

    out = nt.nodes.new("ShaderNodeOutputWorld")
    out.location = (900, 0)
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.location = (660, 0)
    set_input(bg, "Strength", strength)
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])

    tex = nt.nodes.new("ShaderNodeTexCoord")
    tex.location = (-1200, 0)
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    sep.location = (-1020, 0)
    nt.links.new(tex.outputs["Generated"], sep.inputs["Vector"])

    rng = nt.nodes.new("ShaderNodeMapRange")
    rng.location = (-820, 0)
    set_input(rng, "From Min", -0.12)
    set_input(rng, "From Max", 0.62)
    set_input(rng, "To Min", 0.0)
    set_input(rng, "To Max", 1.0)
    rng.clamp = True
    nt.links.new(sep.outputs["Z"], rng.inputs["Value"])

    power = nt.nodes.new("ShaderNodeMath")
    power.location = (-620, 0)
    power.operation = "POWER"
    power.inputs[1].default_value = horizon_power
    nt.links.new(rng.outputs["Result"], power.inputs[0])

    height_src = power.outputs["Value"]
    if cloud_amount > 0.0:
        # Break up the clean vertical gradient: a dust storm is not a tidy
        # two-stop ramp, it is a churning ceiling of suspended sand.
        cloud = nt.nodes.new("ShaderNodeTexNoise")
        cloud.location = (-1020, -140)
        set_input(cloud, "Scale", cloud_scale)
        set_input(cloud, "Detail", 6.0)
        set_input(cloud, "Roughness", 0.6)
        nt.links.new(tex.outputs["Generated"], cloud.inputs["Vector"])

        centred = nt.nodes.new("ShaderNodeMath")
        centred.location = (-820, -140)
        centred.operation = "SUBTRACT"
        centred.inputs[1].default_value = 0.5
        nt.links.new(cloud.outputs["Fac"], centred.inputs[0])

        scaled = nt.nodes.new("ShaderNodeMath")
        scaled.location = (-620, -140)
        scaled.operation = "MULTIPLY"
        scaled.inputs[1].default_value = cloud_amount
        nt.links.new(centred.outputs["Value"], scaled.inputs[0])

        bumped = nt.nodes.new("ShaderNodeMath")
        bumped.location = (-420, -60)
        bumped.operation = "ADD"
        nt.links.new(power.outputs["Value"], bumped.inputs[0])
        nt.links.new(scaled.outputs["Value"], bumped.inputs[1])

        clamper = nt.nodes.new("ShaderNodeClamp")
        clamper.location = (-220, -60)
        nt.links.new(bumped.outputs["Value"], clamper.inputs["Value"])
        height_src = clamper.outputs["Result"]

    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.location = (-400, 0)
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = to_linear(horizon)
    ramp.color_ramp.elements[1].position = 1.0
    ramp.color_ramp.elements[1].color = to_linear(zenith)
    nt.links.new(height_src, ramp.inputs["Fac"])

    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    shader_out = bg.outputs["Background"]

    if glow_elevation_deg is not None:
        # The sun in a dust storm is a smeared bright patch, not a disc: add a
        # second background whose strength falls off with the angle to the sun.
        sdir = sun_direction(glow_elevation_deg, glow_rotation_deg or 0.0)
        view_norm = nt.nodes.new("ShaderNodeVectorMath")
        view_norm.location = (-1200, -340)
        view_norm.operation = "NORMALIZE"
        nt.links.new(tex.outputs["Generated"], view_norm.inputs[0])

        sun_norm = nt.nodes.new("ShaderNodeVectorMath")
        sun_norm.location = (-1200, -560)
        sun_norm.operation = "NORMALIZE"
        sun_norm.inputs[0].default_value = sdir

        dot = nt.nodes.new("ShaderNodeVectorMath")
        dot.location = (-980, -420)
        dot.operation = "DOT_PRODUCT"
        nt.links.new(view_norm.outputs["Vector"], dot.inputs[0])
        nt.links.new(sun_norm.outputs["Vector"], dot.inputs[1])

        clamped = nt.nodes.new("ShaderNodeMath")
        clamped.location = (-780, -420)
        clamped.operation = "MAXIMUM"
        clamped.inputs[1].default_value = 0.0
        nt.links.new(dot.outputs["Value"], clamped.inputs[0])

        focus = nt.nodes.new("ShaderNodeMath")
        focus.location = (-580, -420)
        focus.operation = "POWER"
        focus.inputs[1].default_value = glow_focus
        nt.links.new(clamped.outputs["Value"], focus.inputs[0])

        gain = nt.nodes.new("ShaderNodeMath")
        gain.location = (-380, -420)
        gain.operation = "MULTIPLY"
        gain.inputs[1].default_value = glow_strength
        nt.links.new(focus.outputs["Value"], gain.inputs[0])

        glow_bg = nt.nodes.new("ShaderNodeBackground")
        glow_bg.location = (-140, -420)
        set_input(glow_bg, "Color", to_linear(glow_color))
        nt.links.new(gain.outputs["Value"], glow_bg.inputs["Strength"])

        add = nt.nodes.new("ShaderNodeAddShader")
        add.location = (300, -120)
        nt.links.new(bg.outputs["Background"], add.inputs[0])
        nt.links.new(glow_bg.outputs["Background"], add.inputs[1])
        shader_out = add.outputs["Shader"]

    nt.links.new(shader_out, out.inputs["Surface"])
    return world


def add_haze_volume(
    scene,
    name="Haze",
    center=(0.0, 40.0, 110.0),
    size=(2600.0, 2600.0, 260.0),
    color=(222, 186, 132),
    density=0.0055,
    scale_height=48.0,
    base_z=0.0,
    anisotropy=0.35,
    turb_scale=1.1,
    turb_amount=0.55,
):
    """Bounded dust layer with exponential height falloff.

    Bounded and height-faded on purpose: the layer is thick at ankle height
    (so the horizon dissolves) and thin high up (so sunlight still reaches the
    ground instead of being extinguished over an infinite path).

    Height is measured in WORLD space from `base_z` via the Geometry node.
    Deriving it from the Texture Coordinate node was a trap: that output is
    object-space (metres here, not the normalised 0..1 I first assumed), so the
    layer silently ended up at the wrong altitude.
    """
    obj = _box_mesh(name, size)
    obj.location = center
    link(obj)

    _mat, nt, out = new_material(name + "Mat")
    vol = nt.nodes.new("ShaderNodeVolumeScatter")
    vol.location = (760, 0)
    set_input(vol, "Color", to_linear(color))
    set_input(vol, "Anisotropy", anisotropy)
    nt.links.new(vol.outputs["Volume"], out.inputs["Volume"])

    tex = nt.nodes.new("ShaderNodeTexCoord")
    tex.location = (-1500, 0)

    def math_node(op, loc, c0=None, c1=None):
        node = nt.nodes.new("ShaderNodeMath")
        node.operation = op
        node.location = loc
        if c0 is not None:
            node.inputs[0].default_value = c0
        if c1 is not None:
            node.inputs[1].default_value = c1
        return node

    geo = nt.nodes.new("ShaderNodeNewGeometry")
    geo.location = (-1500, -320)
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    sep.location = (-1320, -320)
    nt.links.new(geo.outputs["Position"], sep.inputs["Vector"])

    # height above the desert floor, never negative
    lifted = math_node("SUBTRACT", (-1120, -320), c1=-base_z)
    nt.links.new(sep.outputs["Z"], lifted.inputs[0])
    clamped = math_node("MAXIMUM", (-940, -320), c1=0.0)
    nt.links.new(lifted.outputs["Value"], clamped.inputs[0])
    normed = math_node("DIVIDE", (-760, -320), c1=max(scale_height, 1e-3))
    nt.links.new(clamped.outputs["Value"], normed.inputs[0])
    negated = math_node("MULTIPLY", (-580, -320), c1=-1.0)
    nt.links.new(normed.outputs["Value"], negated.inputs[0])
    falloff = math_node("EXPONENT", (-400, -320))
    nt.links.new(negated.outputs["Value"], falloff.inputs[0])

    # drifting turbulence so the layer billows rather than sits
    turb = nt.nodes.new("ShaderNodeTexNoise")
    turb.location = (-1120, 220)
    set_input(turb, "Scale", turb_scale)
    set_input(turb, "Detail", 6.0)
    set_input(turb, "Roughness", 0.6)
    nt.links.new(tex.outputs["Object"], turb.inputs["Vector"])

    trange = nt.nodes.new("ShaderNodeMapRange")
    trange.location = (-900, 220)
    set_input(trange, "From Min", 0.0)
    set_input(trange, "From Max", 1.0)
    set_input(trange, "To Min", 1.0 - turb_amount)
    set_input(trange, "To Max", 1.0 + turb_amount)
    nt.links.new(turb.outputs["Fac"], trange.inputs["Value"])

    combined = math_node("MULTIPLY", (-180, -60))
    nt.links.new(falloff.outputs["Value"], combined.inputs[0])
    nt.links.new(trange.outputs["Result"], combined.inputs[1])

    final = math_node("MULTIPLY", (60, -60), c1=density)
    nt.links.new(combined.outputs["Value"], final.inputs[0])
    nt.links.new(final.outputs["Value"], vol.inputs["Density"])
    return obj


def add_world_atmosphere(
    scene,
    color=(222, 186, 132),
    density=0.014,
    scale_height=42.0,
    near_distance=22.0,
    far_distance=130.0,
    shadow_fraction=0.06,
    anisotropy=0.35,
    turb_scale=0.85,
    turb_amount=0.5,
):
    """Dust that only the camera ray can see.

    Two dead ends led here, both worth remembering:

    * A world volume fills all of space, so sunlight travelling from infinity
      is attenuated without bound - the render goes black at any density.
    * A bounded mesh box is worse: in Blender 5.2 a large transparent box
      around the scene kills the terrain lighting outright, even with no
      volume shader attached and even at 0.0005 density.

    So the dust is a world volume split by the Light Path node: camera rays get
    the full density (that is the look), every other ray - shadow rays in
    particular - gets a small fraction, which keeps the sun alive. On top of
    that the density falls off with height (thick at ankle level, thin up high)
    and ramps in with ray length (clear nearby, opaque far away), which is what
    actually reads as *visibility*.
    """
    world = scene.world
    nt = world.node_tree
    out = next(n for n in nt.nodes if n.bl_idname == "ShaderNodeOutputWorld")

    def math_node(op, loc, c1=None):
        node = nt.nodes.new("ShaderNodeMath")
        node.operation = op
        node.location = loc
        if c1 is not None:
            node.inputs[1].default_value = c1
        return node

    geo = nt.nodes.new("ShaderNodeNewGeometry")
    geo.location = (-1600, -400)
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    sep.location = (-1420, -400)
    nt.links.new(geo.outputs["Position"], sep.inputs["Vector"])

    above = math_node("MAXIMUM", (-1220, -400), c1=0.0)
    nt.links.new(sep.outputs["Z"], above.inputs[0])
    hnorm = math_node("DIVIDE", (-1040, -400), c1=max(scale_height, 1e-3))
    nt.links.new(above.outputs["Value"], hnorm.inputs[0])
    hneg = math_node("MULTIPLY", (-860, -400), c1=-1.0)
    nt.links.new(hnorm.outputs["Value"], hneg.inputs[0])
    hfall = math_node("EXPONENT", (-680, -400))
    nt.links.new(hneg.outputs["Value"], hfall.inputs[0])

    path = nt.nodes.new("ShaderNodeLightPath")
    path.location = (-1600, 120)

    # ramp the layer in with distance so the ground underfoot stays readable
    dnorm = math_node("DIVIDE", (-1220, 120), c1=max(far_distance - near_distance, 1e-3))
    nt.links.new(path.outputs["Ray Length"], dnorm.inputs[0])
    dclamp = nt.nodes.new("ShaderNodeClamp")
    dclamp.location = (-1040, 120)
    nt.links.new(dnorm.outputs["Value"], dclamp.inputs["Value"])

    turb = nt.nodes.new("ShaderNodeTexNoise")
    turb.location = (-1220, -120)
    set_input(turb, "Scale", turb_scale)
    set_input(turb, "Detail", 5.0)
    set_input(turb, "Roughness", 0.55)
    nt.links.new(geo.outputs["Position"], turb.inputs["Vector"])
    trange = nt.nodes.new("ShaderNodeMapRange")
    trange.location = (-1040, -120)
    set_input(trange, "From Min", 0.0)
    set_input(trange, "From Max", 1.0)
    set_input(trange, "To Min", 1.0 - turb_amount)
    set_input(trange, "To Max", 1.0 + turb_amount)
    nt.links.new(turb.outputs["Fac"], trange.inputs["Value"])

    hd = math_node("MULTIPLY", (-400, 0))
    nt.links.new(hfall.outputs["Value"], hd.inputs[0])
    nt.links.new(dclamp.outputs["Result"], hd.inputs[1])
    hdt = math_node("MULTIPLY", (-220, 0))
    nt.links.new(hd.outputs["Value"], hdt.inputs[0])
    nt.links.new(trange.outputs["Result"], hdt.inputs[1])
    cam_density = math_node("MULTIPLY", (-40, 0), c1=density)
    nt.links.new(hdt.outputs["Value"], cam_density.inputs[0])

    vol_cam = nt.nodes.new("ShaderNodeVolumeScatter")
    vol_cam.location = (200, -160)
    set_input(vol_cam, "Color", to_linear(color))
    set_input(vol_cam, "Anisotropy", anisotropy)
    nt.links.new(cam_density.outputs["Value"], vol_cam.inputs["Density"])

    vol_rest = nt.nodes.new("ShaderNodeVolumeScatter")
    vol_rest.location = (200, 200)
    set_input(vol_rest, "Color", to_linear(color))
    set_input(vol_rest, "Anisotropy", anisotropy)
    set_input(vol_rest, "Density", density * shadow_fraction)

    mix = nt.nodes.new("ShaderNodeMixShader")
    mix.location = (460, 0)
    nt.links.new(path.outputs["Is Camera Ray"], mix.inputs["Fac"])
    nt.links.new(vol_rest.outputs["Volume"], mix.inputs[1])
    nt.links.new(vol_cam.outputs["Volume"], mix.inputs[2])
    nt.links.new(mix.outputs["Shader"], out.inputs["Volume"])
    return world


def add_sun(elevation_deg, rotation_deg, energy=4.0, color=(255, 240, 210), angle_deg=1.2):
    light = bpy.data.lights.new("Sun", type="SUN")
    light.energy = energy
    light.color = to_linear(color)[:3]
    light.angle = math.radians(angle_deg)
    obj = bpy.data.objects.new("Sun", light)
    link(obj)
    obj.rotation_euler = (
        math.radians(90.0 - elevation_deg),
        0.0,
        math.radians(rotation_deg),
    )
    return obj


def _box_mesh(name, size):
    sx, sy, sz = (s * 0.5 for s in size)
    corners = [
        (-sx, -sy, -sz), (sx, -sy, -sz), (sx, sy, -sz), (-sx, sy, -sz),
        (-sx, -sy, sz), (sx, -sy, sz), (sx, sy, sz), (-sx, sy, sz),
    ]
    quads = [
        (0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
        (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7),
    ]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(corners, [], quads)
    mesh.validate(verbose=False)
    mesh.update()
    return bpy.data.objects.new(name, mesh)


def build_dust_wall(
    name="DustWall",
    location=(0.0, 300.0, 55.0),
    size=(760.0, 300.0, 220.0),
    color=(198, 158, 108),
    density=0.02,
    noise_scale=2.6,
    height_falloff=True,
):
    """A big noisy volume box - the advancing wall of a sandstorm."""
    obj = _box_mesh(name, size)
    obj.location = location
    link(obj)

    _mat, nt, out = new_material(name + "Mat")
    vol = nt.nodes.new("ShaderNodeVolumeScatter")
    vol.location = (620, 0)
    set_input(vol, "Color", to_linear(color))
    set_input(vol, "Anisotropy", 0.6)
    nt.links.new(vol.outputs["Volume"], out.inputs["Volume"])

    tex = nt.nodes.new("ShaderNodeTexCoord")
    tex.location = (-1020, 0)
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.location = (-840, 0)
    set_input(mapping, "Scale", (1.0, 1.0, 2.4))
    nt.links.new(tex.outputs["Object"], mapping.inputs["Vector"])

    turb = nt.nodes.new("ShaderNodeTexNoise")
    turb.location = (-640, 0)
    set_input(turb, "Scale", noise_scale)
    set_input(turb, "Detail", 10.0)
    set_input(turb, "Roughness", 0.65)
    nt.links.new(mapping.outputs["Vector"], turb.inputs["Vector"])

    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.location = (-400, 0)
    ramp.color_ramp.elements[0].position = 0.34
    ramp.color_ramp.elements[0].color = (0.0, 0.0, 0.0, 1.0)
    ramp.color_ramp.elements[1].position = 0.78
    ramp.color_ramp.elements[1].color = (1.0, 1.0, 1.0, 1.0)
    nt.links.new(turb.outputs["Fac"], ramp.inputs["Fac"])

    density_src = ramp.outputs["Color"]
    if height_falloff:
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        sep.location = (-1020, -340)
        nt.links.new(tex.outputs["Object"], sep.inputs["Vector"])
        rng = nt.nodes.new("ShaderNodeMapRange")
        rng.location = (-640, -340)
        set_input(rng, "From Min", -0.5)
        set_input(rng, "From Max", 0.5)
        set_input(rng, "To Min", 1.4)
        set_input(rng, "To Max", 0.12)
        rng.clamp = True
        nt.links.new(sep.outputs["Z"], rng.inputs["Value"])

        mul_h = nt.nodes.new("ShaderNodeMath")
        mul_h.location = (-180, -160)
        mul_h.operation = "MULTIPLY"
        nt.links.new(ramp.outputs["Color"], mul_h.inputs[0])
        nt.links.new(rng.outputs["Result"], mul_h.inputs[1])
        density_src = mul_h.outputs["Value"]

    mul_d = nt.nodes.new("ShaderNodeMath")
    mul_d.location = (180, 0)
    mul_d.operation = "MULTIPLY"
    mul_d.inputs[1].default_value = density
    nt.links.new(density_src, mul_d.inputs[0])
    nt.links.new(mul_d.outputs["Value"], vol.inputs["Density"])
    return obj


# ---------------------------------------------------------------------------
# the pilgrim - a silhouette, deliberately low detail
# ---------------------------------------------------------------------------


def _cylinder(name, radius_top, radius_bottom, depth, segments=16):
    verts = []
    faces = []
    for i in range(segments):
        a = 2.0 * math.pi * i / segments
        ca, sa = math.cos(a), math.sin(a)
        verts.append((radius_bottom * ca, radius_bottom * sa, -depth * 0.5))
        verts.append((radius_top * ca, radius_top * sa, depth * 0.5))
    for i in range(segments):
        j = (i + 1) % segments
        faces.append((i * 2, j * 2, j * 2 + 1, i * 2 + 1))
    bottom = len(verts)
    top = bottom + 1
    verts.append((0.0, 0.0, -depth * 0.5))
    verts.append((0.0, 0.0, depth * 0.5))
    for i in range(segments):
        j = (i + 1) % segments
        faces.append((bottom, j * 2, i * 2))
        faces.append((top, i * 2 + 1, j * 2 + 1))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.validate(verbose=False)
    mesh.update()
    return bpy.data.objects.new(name, mesh)


def _cone(name, radius, depth, segments=20):
    verts = [(0.0, 0.0, depth * 0.5)]
    faces = []
    for i in range(segments):
        a = 2.0 * math.pi * i / segments
        verts.append((radius * math.cos(a), radius * math.sin(a), -depth * 0.5))
    for i in range(segments):
        j = (i + 1) % segments + 1
        faces.append((0, i + 1, j))
    faces.append(tuple(range(segments, 0, -1)))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.validate(verbose=False)
    mesh.update()
    return bpy.data.objects.new(name, mesh)


def _sphere(name, radius, segments=20, rings=12):
    verts = []
    faces = []
    for r in range(rings + 1):
        phi = math.pi * r / rings
        for s in range(segments):
            th = 2.0 * math.pi * s / segments
            verts.append(
                (
                    radius * math.sin(phi) * math.cos(th),
                    radius * math.sin(phi) * math.sin(th),
                    radius * math.cos(phi),
                )
            )
    for r in range(rings):
        for s in range(segments):
            s2 = (s + 1) % segments
            faces.append(
                (
                    r * segments + s,
                    r * segments + s2,
                    (r + 1) * segments + s2,
                    (r + 1) * segments + s,
                )
            )
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.validate(verbose=False)
    mesh.update()
    return bpy.data.objects.new(name, mesh)


def build_pilgrim(name="Pilgrim", robe=(96, 62, 46), height=1.8, face_dir=-1.0):
    """Robed monk: robe, head, wide straw hat, staff, built from primitives."""
    root = bpy.data.objects.new(name, None)
    root.empty_display_size = 0.4
    link(root)

    mat, nt, out = new_material(name + "Robe")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (300, 0)
    set_input(bsdf, "Base Color", to_linear(robe))
    set_input(bsdf, "Roughness", 0.92)
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    hat_mat, hnt, hout = new_material(name + "Hat")
    hb = hnt.nodes.new("ShaderNodeBsdfPrincipled")
    hb.location = (300, 0)
    set_input(hb, "Base Color", to_linear((196, 168, 112)))
    set_input(hb, "Roughness", 0.95)
    hnt.links.new(hb.outputs["BSDF"], hout.inputs["Surface"])

    staff_mat, snt, sout = new_material(name + "Staff")
    sb = snt.nodes.new("ShaderNodeBsdfPrincipled")
    sb.location = (300, 0)
    set_input(sb, "Base Color", to_linear((74, 52, 34)))
    set_input(sb, "Roughness", 0.6)
    snt.links.new(sb.outputs["BSDF"], sout.inputs["Surface"])

    parts = []

    robe_obj = _cylinder(name + "_Robe", 0.16, 0.34, height * 0.62)
    robe_obj.location = (0.0, 0.0, height * 0.31)
    parts.append((robe_obj, mat))

    torso = _cylinder(name + "_Torso", 0.19, 0.21, height * 0.26)
    torso.location = (0.0, 0.0, height * 0.72)
    parts.append((torso, mat))

    head = _sphere(name + "_Head", 0.105)
    head.location = (0.0, 0.0, height * 0.92)
    parts.append((head, mat))

    hat = _cone(name + "_Hat", 0.32, 0.22)
    hat.location = (0.0, 0.0, height * 0.995)
    parts.append((hat, hat_mat))

    staff = _cylinder(name + "_Staff", 0.022, 0.026, height * 1.22, segments=10)
    staff.location = (0.34 * face_dir, 0.0, height * 0.61)
    staff.rotation_euler = (0.0, math.radians(6.0), 0.0)
    parts.append((staff, staff_mat))

    ring = _cylinder(name + "_StaffRing", 0.075, 0.075, 0.02, segments=20)
    ring.location = (0.40 * face_dir, 0.0, height * 1.12)
    ring.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    parts.append((ring, staff_mat))

    for obj, material in parts:
        obj.data.materials.append(material)
        obj.parent = root
        obj.matrix_parent_inverse = root.matrix_world.inverted()
        shade_smooth(obj)
    return root


def build_staff(name="Khakkhara", length=2.05, radius=0.024, segments=12):
    """The pilgrim's tin staff, on its own so a first-person camera can hold it.

    Built around the origin with the grip near z=0, so parenting it to a camera
    and offsetting in local space puts it where a hand would be.
    """
    root = bpy.data.objects.new(name, None)
    root.empty_display_size = 0.2
    link(root)

    _wood, nt, out = new_material(name + "Wood")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (300, 0)
    set_input(bsdf, "Base Color", to_linear((88, 60, 38)))
    set_input(bsdf, "Roughness", 0.62)
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    _metal, mnt, mout = new_material(name + "Metal")
    mb = mnt.nodes.new("ShaderNodeBsdfPrincipled")
    mb.location = (300, 0)
    set_input(mb, "Base Color", to_linear((156, 148, 132)))
    set_input(mb, "Roughness", 0.35)
    set_input(mb, "Metallic", 0.85)
    mnt.links.new(mb.outputs["BSDF"], mout.inputs["Surface"])

    parts = []
    shaft = _cylinder(name + "_Shaft", radius * 0.92, radius, length, segments=segments)
    shaft.location = (0.0, 0.0, length * 0.5 - length * 0.42)
    parts.append((shaft, _wood))

    for index, (z, ring_radius) in enumerate(
        ((length * 0.30, 0.075), (length * 0.36, 0.062), (length * 0.41, 0.048))
    ):
        ring = _cylinder(
            "%s_Ring%d" % (name, index), ring_radius, ring_radius, 0.018, segments=20
        )
        ring.location = (0.0, 0.0, z)
        ring.rotation_euler = (math.radians(90.0), 0.0, 0.0)
        parts.append((ring, _metal))

    for obj, material in parts:
        obj.data.materials.append(material)
        obj.parent = root
        obj.matrix_parent_inverse = root.matrix_world.inverted()
        shade_smooth(obj)
    return root
