"""Probe Blender 5.2 API surface used by the desert scenes.

Run:  blender -b --factory-startup --python probe_api.py
Prints prop names so the scene builder never has to guess.
"""

import bpy


def props(rna):
    return sorted(p.identifier for p in rna.properties)


mat = bpy.data.materials.new("probe")
mat.use_nodes = True
nt = mat.node_tree

sky = nt.nodes.new("ShaderNodeTexSky")
print("SKY_PROPS:", props(sky.bl_rna))
for key in ("sky_type",):
    if key in sky.bl_rna.properties:
        enum = sky.bl_rna.properties[key].enum_items
        print("SKY_TYPE_ITEMS:", [e.identifier for e in enum])

bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
print("PRINCIPLED_INPUTS:", [i.identifier for i in bsdf.inputs])

vol = nt.nodes.new("ShaderNodeVolumeScatter")
print("VOLSCATTER_INPUTS:", [i.identifier for i in vol.inputs])

out = nt.nodes.new("ShaderNodeOutputWorld")
print("WORLDOUT_INPUTS:", [i.identifier for i in out.inputs])

sun = bpy.data.lights.new("probe_sun", type="SUN")
print("SUN_PROPS:", props(sun.bl_rna))

world = bpy.data.worlds.new("probe_world")
print("WORLD_PROPS:", props(world.bl_rna))

scene = bpy.context.scene
print("ENGINES:", [e.identifier for e in scene.render.bl_rna.properties["engine"].enum_items])
print("CAMERA_PROPS:", props(bpy.data.cameras.new("probe_cam").bl_rna))

cy = scene.cycles
print("CYCLES_DENOISER_ITEMS:", [e.identifier for e in cy.bl_rna.properties["denoiser"].enum_items])
print("CYCLES_DEVICE_ITEMS:", [e.identifier for e in cy.bl_rna.properties["device"].enum_items])

addon = bpy.context.preferences.addons.get("cycles")
print("CYCLES_ADDON:", addon is not None)
if addon:
    prefs = addon.preferences
    prefs.get_devices()
    print("DEVICES:", [(d.name, d.type, d.use) for d in prefs.devices])
    print(
        "COMPUTE_ITEMS:",
        [e.identifier for e in prefs.bl_rna.properties["compute_device_type"].enum_items],
    )

print("PROBE_DONE")
