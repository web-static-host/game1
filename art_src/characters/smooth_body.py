## Сглаживание тела жителя под прототип ChatGPT (art_src/characters/prototype_chatgpt.png):
## тело симметричное и гладкое (без бугров), руки и ноги толще, ступни крупнее, глаз больше.
## Исходник BlueBuddy.blend не меняется — всё делается над копией перед экспортом (export_buddy.py).
import bpy
import bmesh
from mathutils import Vector

VOXEL = 0.025        # шаг пересборки сетки, м (пальцы ~0,1 м толщиной — остаются)
ARM_GROW = 0.045     # на сколько толще руки (по нормали), м
LEG_GROW = 0.04      # ноги
FOOT_SCALE = 1.35    # ступни крупнее
EYE_SCALE = 1.15     # глаз крупнее (вокруг центра белка)


def _apply(obj, mod):
    with bpy.context.temp_override(object=obj, active_object=obj):
        bpy.ops.object.modifier_apply(modifier=mod.name)


def _weights(obj, names):
    """Сумма весов групп names по вершинам."""
    idx = {obj.vertex_groups[n].index for n in names if n in obj.vertex_groups}
    out = [0.0] * len(obj.data.vertices)
    for v in obj.data.vertices:
        out[v.index] = sum(g.weight for g in v.groups if g.group in idx)
    return out


def smooth_body(body, rig):
    """Пересобрать тело гладким и симметричным, веса костей — с исходного тела."""
    src = body.copy()
    src.data = body.data.copy()
    src.modifiers.clear()
    bpy.context.scene.collection.objects.link(src)
    # Скелет — только для перенесённых весов; форма — в позе покоя.
    arm_mods = [m for m in body.modifiers if m.type == 'ARMATURE']
    for m in list(body.modifiers):
        body.modifiers.remove(m)
    # 1) Симметрия: правая половина (x > 0) отражается на левую.
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bmesh.ops.symmetrize(bm, input=bm.verts[:] + bm.edges[:] + bm.faces[:], direction='X')
    bm.to_mesh(body.data)
    bm.free()
    # 2) Ровная сетка без складок и бугров.
    rm = body.modifiers.new('Remesh', 'REMESH')
    rm.mode = 'VOXEL'
    rm.voxel_size = VOXEL
    rm.adaptivity = 0.0
    _apply(body, rm)
    print('remesh', len(body.data.vertices), flush=True)
    # Веса с исходного тела (ближайшая грань) — чтобы знать, где руки, ноги, пальцы.
    _transfer(body, src)
    keep = _weights(body, ['Hand.L', 'Hand.R'] + ['Finger%d.%s' % (i, s) for i in range(1, 5) for s in 'LR'])
    # 3) Сгладить всё, кроме кистей (пальцы бы растаяли).
    vg = body.vertex_groups.new(name='_smooth')
    for v in body.data.vertices:
        vg.add([v.index], max(0.0, 1.0 - keep[v.index] * 1.5), 'REPLACE')
    sm = body.modifiers.new('Lap', 'LAPLACIANSMOOTH')
    sm.iterations = 12
    sm.lambda_factor = 1.2
    sm.use_volume_preserve = True
    sm.vertex_group = '_smooth'
    _apply(body, sm)
    print('smoothed', flush=True)
    # 4) Толще руки и ноги, крупнее ступни.
    arms = _weights(body, ['UpperArm.L', 'UpperArm.R', 'Forearm.L', 'Forearm.R'])
    legs = _weights(body, ['Thigh.L', 'Thigh.R', 'Shin.L', 'Shin.R'])
    feet = {s: _weights(body, ['Foot.' + s]) for s in 'LR'}
    me = body.data
    me.update()
    print('grow', flush=True)
    for v in me.vertices:
        grow = ARM_GROW * min(1.0, arms[v.index]) + LEG_GROW * min(1.0, legs[v.index])
        v.co += v.normal * grow
    for s, w in feet.items():
        bone = rig.data.bones['Foot.' + s]
        c = (bone.head_local + bone.tail_local) * 0.5
        c.z = 0.0
        for v in me.vertices:
            k = min(1.0, w[v.index])
            if k > 0.0:
                v.co = v.co.lerp(c + (v.co - c) * FOOT_SCALE, k)
    # Мягкий финальный проход — стыки после утолщения.
    sm2 = body.modifiers.new('Sm', 'SMOOTH')
    sm2.factor = 0.5
    sm2.iterations = 4
    _apply(body, sm2)
    print('smooth2', flush=True)
    for poly in me.polygons:
        poly.use_smooth = True
    _transfer(body, src)
    for m in arm_mods:
        nm = body.modifiers.new(m.name, 'ARMATURE')
        nm.object = m.object
    print('weights', flush=True)
    bpy.data.objects.remove(src)


def _transfer(dst, src):
    for g in list(dst.vertex_groups):
        dst.vertex_groups.remove(g)
    for g in src.vertex_groups:
        dst.vertex_groups.new(name=g.name)
    dt = dst.modifiers.new('DT', 'DATA_TRANSFER')
    dt.object = src
    dt.use_vert_data = True
    dt.data_types_verts = {'VGROUP_WEIGHTS'}
    dt.vert_mapping = 'POLYINTERP_NEAREST'
    dt.layers_vgroup_select_src = 'ALL'
    dt.layers_vgroup_select_dst = 'NAME'
    _apply(dst, dt)


def bigger_eye(parts):
    """Глаз (белок, радужка, зрачок, блики) крупнее вокруг центра белка."""
    white = next(o for o in parts if o.name == 'Approved_EyeWhite')
    vs = [white.matrix_world @ v.co for v in white.data.vertices]
    c = sum(vs, Vector()) / len(vs)
    for o in parts:
        inv = o.matrix_world.inverted()
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            w = Vector((c.x + (w.x - c.x) * EYE_SCALE, w.y, c.z + (w.z - c.z) * EYE_SCALE))
            v.co = inv @ w
