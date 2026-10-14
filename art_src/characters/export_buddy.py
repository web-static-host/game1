## Экспорт модели жителя в игру: assets/models/blue_buddy.glb.
## Только сцена Buddy_Studio (скелет и его меши), риг в начало координат, тело упрощено до 30%
## (в игре житель ~40 px), у вершин кисти и пальцев снят вес кости Body.
import os, sys
# bpy: pip install bpy (или запуск внутри Blender: blender -b -P export_buddy.py).
HERE = os.path.dirname(os.path.abspath(__file__))
import bpy
bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE, 'BlueBuddy.blend'))
scene = bpy.data.scenes['Buddy_Studio']
bpy.context.window.scene = scene
rig = bpy.data.objects['Buddy_ApprovedRig']
rig.location = (0, 0, 0)
keep = [rig] + [o for o in scene.objects if o.parent == rig]
body = bpy.data.objects['Buddy_FinalBody']
# Внешние пальцы (у бока) автовеса зацепили кость Body — палец тянулся за телом.
# У вершин кисти и пальцев убираем вес Body.
names = {g.index: g.name for g in body.vertex_groups}
bg = body.vertex_groups['Body']
fixed = 0
for v in body.data.vertices:
    gs = [names[g.group] for g in v.groups if g.weight > 0.0]
    if 'Body' in gs and any(n.startswith('Finger') or n.startswith('Hand') for n in gs):
        bg.remove([v.index])
        fixed += 1
print('fixed weights', fixed)
dec = body.modifiers.new('Decimate', 'DECIMATE')
dec.ratio = 0.3
# Упрощение — до модификатора скелета.
bpy.context.view_layer.objects.active = body
while body.modifiers.find('Decimate') > 0:
    with bpy.context.temp_override(object=body):
        bpy.ops.object.modifier_move_up(modifier='Decimate')
print('mods', [m.name for m in body.modifiers])
for o in scene.objects:
    o.select_set(o in keep)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(filepath=os.path.join(HERE, '..', '..', 'assets', 'models', 'blue_buddy.glb'), export_format='GLB',
    use_selection=True, use_active_scene=True, export_skins=True, export_animations=False, export_apply=True,
    export_lights=False, export_cameras=False, export_yup=True)
