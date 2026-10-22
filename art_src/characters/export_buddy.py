## Экспорт модели жителя в игру: assets/models/blue_buddy.glb.
## Только сцена Buddy_Studio (скелет и его меши), риг в начало координат, тело упрощено до 30%
## (в игре житель ~40 px), у вершин кисти и пальцев снят вес кости Body.
## BUDDY_NEW_BODY=<папка с body.npz> — тело новое, по прототипу (build_body.py; текущее —
## art_src/characters/body/): меш заменяется, упрощается, веса костей переносятся со старого тела.
## BUDDY_OUT — куда писать .glb. Сборка игровой модели:
##   BUDDY_NEW_BODY=art_src/characters/body python3 art_src/characters/export_buddy.py
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
NEW = os.environ.get('BUDDY_NEW_BODY')
if NEW:
    import numpy as np
    d = np.load(os.path.join(NEW, 'body.npz'))
    # Веса костей — с исходного тела (оно отлично привязано, формы близки): каждой вершине нового
    # тела — веса ближайшего места старого. Автовеса Blender на этой сетке ломаются.
    old = body.copy()
    old.data = body.data.copy()
    scene.collection.objects.link(old)
    me = bpy.data.meshes.new('NewBody')
    me.from_pydata(d['v'].tolist(), [], d['f'].tolist())
    for m in body.data.materials:
        me.materials.append(m)
    body.data = me
    for m in list(body.modifiers):
        if m.type != 'ARMATURE':
            body.modifiers.remove(m)
    for g in old.vertex_groups:
        body.vertex_groups.new(name=g.name)
    bpy.context.view_layer.objects.active = body
    with bpy.context.temp_override(object=body, active_object=body, selected_objects=[body], selected_editable_objects=[body]):
        dm = body.modifiers.new('Dec', 'DECIMATE')
        dm.ratio = 0.12
        bpy.ops.object.modifier_apply(modifier='Dec')
        sm = body.modifiers.new('Sm', 'SMOOTH')
        sm.factor = 0.6
        sm.iterations = 16
        bpy.ops.object.modifier_apply(modifier='Sm')
        for m in [m for m in old.modifiers]:
            old.modifiers.remove(m)
        dt = body.modifiers.new('DT', 'DATA_TRANSFER')
        dt.object = old
        dt.use_vert_data = True
        dt.data_types_verts = {'VGROUP_WEIGHTS'}
        dt.vert_mapping = 'POLYINTERP_NEAREST'
        dt.layers_vgroup_select_src = 'ALL'
        dt.layers_vgroup_select_dst = 'NAME'
        while body.modifiers.find('DT') > 0:
            bpy.ops.object.modifier_move_up(modifier='DT')
        bpy.ops.object.modifier_apply(modifier='DT')
        bpy.ops.object.vertex_group_normalize_all(lock_active=False)
    bpy.data.objects.remove(old)
    # Живот круглого шире старого тела — ближе к рукам, чем к старому туловищу, и брал бы их веса
    # (живот тянулся бы за рукой). Ниже плеч и ближе к середине, чем висят руки, — без весов рук.
    arm_groups = [g.index for g in body.vertex_groups if g.name.split('.')[0] in ('UpperArm', 'Forearm', 'Hand') or g.name.startswith(('Finger', 'Thumb'))]
    stripped = 0
    for v in me.vertices:
        if abs(v.co.x) < 0.9 and v.co.z < 1.65 and v.co.z > 0.5:
            hit = [g.group for g in v.groups if g.group in arm_groups and g.weight > 0.0]
            for gi in hit:
                body.vertex_groups[gi].remove([v.index])
            if hit:
                stripped += 1
                if not any(g.weight > 0.0 for g in v.groups):
                    body.vertex_groups['Body'].add([v.index], 1.0, 'REPLACE')
    if stripped:
        with bpy.context.temp_override(object=body, active_object=body, selected_objects=[body], selected_editable_objects=[body]):
            bpy.ops.object.vertex_group_normalize_all(lock_active=False)
    print('arm weights stripped from torso', stripped, flush=True)
    me.shade_smooth()
    print('new body', len(me.vertices), 'verts,', len(body.vertex_groups), 'groups', [m.type for m in body.modifiers], flush=True)
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
dec.ratio = 1.0 if NEW else 0.3
# Упрощение — до модификатора скелета.
bpy.context.view_layer.objects.active = body
while body.modifiers.find('Decimate') > 0:
    with bpy.context.temp_override(object=body):
        bpy.ops.object.modifier_move_up(modifier='Decimate')
print('mods', [m.name for m in body.modifiers])
for o in scene.objects:
    o.select_set(o in keep)
bpy.context.view_layer.objects.active = rig
OUT = os.environ.get('BUDDY_OUT', os.path.join(HERE, '..', '..', 'assets', 'models', 'blue_buddy.glb'))
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB',
    use_selection=True, use_active_scene=True, export_skins=True, export_animations=False, export_apply=True,
    export_lights=False, export_cameras=False, export_yup=True)
