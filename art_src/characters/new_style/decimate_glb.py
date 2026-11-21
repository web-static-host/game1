## Облегчить glb (сетка в долю RATIO, текстура и развёртка сохраняются): python3 decimate_glb.py <вход> <выход> [0.25]
import sys

import bpy

SRC, DST = sys.argv[1], sys.argv[2]
RATIO = float(sys.argv[3]) if len(sys.argv) > 3 else 0.25
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
for ob in [o for o in bpy.context.scene.objects if o.type == 'MESH']:
    bpy.context.view_layer.objects.active = ob
    before = len(ob.data.polygons)
    m = ob.modifiers.new('Dec', 'DECIMATE')
    m.ratio = RATIO
    m.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier='Dec')
    print(ob.name, before, '->', len(ob.data.polygons))
bpy.ops.export_scene.gltf(filepath=DST, export_format='GLB', export_image_format='JPEG', export_jpeg_quality=92)
