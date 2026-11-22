## Спрайты модели Hunyuan как в игре (ортокамера): стоит (поворот 28°) и 8 кадров шага (поворот 65° —
## идёт в сторону движения, а не боком). Тело перекрашивается в цвет генов по маске на текстуре.
##   python3 sprite_hunyuan.py <glb> <папка> <#цвет>
import math
import os
import sys

import bpy
import numpy as np

GLB, OUT, COL = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)
ob = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
bpy.context.view_layer.objects.active = ob
ob.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
v = np.array([x.co[:] for x in ob.data.vertices])
k = 2.4 / (v[:, 2].max() - v[:, 2].min())
v = (v - [(v[:, 0].max() + v[:, 0].min()) / 2, (v[:, 1].max() + v[:, 1].min()) / 2, v[:, 2].min()]) * k
BASE = v


def srgb(h):
    h = h.lstrip('#')
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return [((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c]


# Перекраска: жёлтое тело (тон 0.08–0.2, насыщенное, светлое) → цвет генов с той же светлотой.
target = srgb(COL)
for m in ob.data.materials:
    nt = m.node_tree
    N, L = nt.nodes, nt.links
    bsdf = N['Principled BSDF']
    link = bsdf.inputs['Base Color'].links[0]
    src = link.from_socket
    sep = N.new('ShaderNodeSeparateColor')
    sep.mode = 'HSV'
    L.new(src, sep.inputs[0])

    def op(kind, a, b):
        n = N.new('ShaderNodeMath')
        n.operation = kind
        for i, x in enumerate((a, b)):
            if isinstance(x, (int, float)):
                n.inputs[i].default_value = x
            else:
                L.new(x, n.inputs[i])
        return n.outputs[0]
    # Тело — жёлтый тон (бровь коричневая — тон ниже 0.095); затенённые места текстуры тоже тело,
    # но красим ровно: светлоту берём не ниже 0.8 (свет и тени даёт рендер, а не краска).
    # (значения текстуры здесь линейные: жёлто-оранжевый — тон 0.03–0.25, насыщенность > 0.5)
    mask = op('MULTIPLY', op('MULTIPLY', op('GREATER_THAN', sep.outputs[0], 0.03), op('LESS_THAN', sep.outputs[0], 0.25)),
              op('MULTIPLY', op('GREATER_THAN', sep.outputs[1], 0.5), op('GREATER_THAN', sep.outputs[2], 0.2)))
    shade = op('MAXIMUM', op('DIVIDE', sep.outputs[2], 0.95), 0.85)
    rgb = N.new('ShaderNodeRGB')
    rgb.outputs[0].default_value = (*target, 1)
    tint = N.new('ShaderNodeMix')
    tint.data_type = 'RGBA'
    tint.blend_type = 'MULTIPLY'
    tint.inputs['Factor'].default_value = 1.0
    L.new(rgb.outputs[0], tint.inputs[6])
    shc = N.new('ShaderNodeCombineColor')
    for i in range(3):
        L.new(shade, shc.inputs[i])
    L.new(shc.outputs[0], tint.inputs[7])
    mix = N.new('ShaderNodeMix')
    mix.data_type = 'RGBA'
    L.new(mask, mix.inputs['Factor'])
    L.new(src, mix.inputs[6])
    L.new(tint.outputs[2], mix.inputs[7])
    L.new(mix.outputs[2], bsdf.inputs['Base Color'])
    bsdf.inputs['Roughness'].default_value = 0.6


def smooth(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


def rot_x(p, piv, ang, w):
    a = ang * w
    y, z = p[:, 1] - piv[1], p[:, 2] - piv[2]
    c, s_ = np.cos(a), np.sin(a)
    p[:, 1] = piv[1] + y * c - z * s_
    p[:, 2] = piv[2] + y * s_ + z * c


X, Z = BASE[:, 0], BASE[:, 2]
BW = 0.3 + np.clip(Z - 0.9, 0, None) * 0.45            # полуширина тела спереди
LEGW = smooth((0.78 - Z) / 0.16) * (np.abs(X) < 0.6)
ARMW = smooth((1.85 - Z) / 0.3) * smooth((np.abs(X) - BW - 0.02) / 0.1) * (Z > 0.75)


def pose(phase):
    p = BASE.copy()
    if phase is not None:
        t = 2 * math.pi * phase
        leg = math.radians(30) * math.sin(t)
        arm = math.radians(24) * math.sin(t)
        for sgn in (-1, 1):
            side = (X * sgn > 0)
            rot_x(p, (0, 0.0, 0.78), sgn * leg, LEGW * side)
            rot_x(p, (0, 0.0, 1.85), -sgn * arm, ARMW * side)
        rot_x(p, (0, 0, 0), math.radians(-4), np.ones(len(p)))
        p[:, 2] -= p[:, 2].min()
        p[:, 2] += 0.04 * abs(math.sin(t))
    for i, vv in enumerate(ob.data.vertices):
        vv.co = p[i]
    ob.data.update()


sc = bpy.context.scene


def light(name, loc, energy, col, size):
    ld = bpy.data.lights.new(name, 'AREA')
    ld.energy, ld.color, ld.size = energy, col, size
    o = bpy.data.objects.new(name, ld)
    o.location = loc
    sc.collection.objects.link(o)
    o.constraints.new('TRACK_TO').target = ob


light('Key', (-3.2, -3.6, 5.0), 330, (1.0, 0.96, 0.9), 4.5)
light('Fill', (4.0, -2.5, 1.8), 35, (0.8, 0.88, 1.0), 5.0)
light('Rim', (2.5, 4.0, 4.0), 700, (1.0, 0.98, 0.95), 2.5)
light('Rim2', (-2.8, 3.5, 2.5), 300, (0.9, 0.95, 1.0), 2.5)
w = bpy.data.worlds.new('W')
sc.world = w
w.use_nodes = True
w.node_tree.nodes['Background'].inputs['Color'].default_value = (0.6, 0.65, 0.72, 1)
w.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.12
sc.render.engine = 'CYCLES'
sc.cycles.device = 'CPU'
sc.cycles.samples = 32
sc.cycles.use_denoising = True
sc.render.film_transparent = True
sc.view_settings.view_transform = 'Standard'
cam = bpy.data.objects.new('Cam', bpy.data.cameras.new('Cam'))
cam.data.type = 'ORTHO'
cam.data.ortho_scale = 3.2
cam.location = (0, -10, 1.2)
cam.rotation_euler = (math.radians(90), 0, 0)
sc.collection.objects.link(cam)
sc.camera = cam
sc.render.resolution_x = sc.render.resolution_y = 320
# Лицом вправо: поворот против часовой (сверху).
for name, ph, yaw in [('idle', None, 28)] + [('walk%d' % i, i / 8.0, 65) for i in range(8)]:
    ob.rotation_mode = 'XYZ'
    ob.rotation_euler = (0, 0, math.radians(yaw))
    pose(ph)
    sc.render.filepath = os.path.join(OUT, name + '.png')
    bpy.ops.render.render(write_still=True)
