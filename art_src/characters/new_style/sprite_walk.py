## Спрайты новой модели как в игре (ортокамера, поворот 28°): стоит и 8 кадров шага. python3 sprite_walk.py <glb> <папка> <#цвет>
## python3 sprite_render.py <glb> <out.png> <цвет #hex>
import math, os, sys, json
import bpy, mathutils
GLB, OUT, COL = sys.argv[1], sys.argv[2], sys.argv[3]
import numpy as np
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)
ob = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
bpy.context.view_layer.objects.active = ob; ob.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
BASE = np.array([v.co[:] for v in ob.data.vertices])
ob.rotation_euler = (0, 0, math.radians(-28))


def smooth(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


def rot_x(p, piv, ang, w):
    # поворот вокруг оси X через точку piv на угол ang*w (по вершинам)
    a = ang * w
    y, z = p[:, 1] - piv[1], p[:, 2] - piv[2]
    c, s_ = np.cos(a), np.sin(a)
    p[:, 1] = piv[1] + y * c - z * s_
    p[:, 2] = piv[2] + y * s_ + z * c


def pose(phase):
    p = BASE.copy()
    if phase is not None:
        t = 2 * math.pi * phase
        leg = math.radians(26) * math.sin(t)
        arm = math.radians(22) * math.sin(t)
        x, z = BASE[:, 0], BASE[:, 2]
        # Полуширина тела по высоте (замер по спине) — руки только снаружи неё.
        bw = np.interp(z, [0.9, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 2.0, 2.1, 2.2, 2.4],
                       [0.0, 0.21, 0.31, 0.41, 0.49, 0.56, 0.64, 0.70, 0.78, 0.84, 0.89, 0.94, 0.95, 0.95])
        legw = smooth((0.68 - z) / 0.25) * (np.abs(x) < 0.45) * smooth((np.abs(x) - 0.02) / 0.1)
        armw = smooth((1.8 - z) / 0.3) * smooth((np.abs(x) - bw - 0.03) / 0.1) * (z > 0.75)
        for sgn in (-1, 1):
            side = (x * sgn > 0)
            rot_x(p, (0, 0.0, 0.68), sgn * leg * np.ones(1), legw * side)
            rot_x(p, (0, 0.0, 1.78), -sgn * arm * np.ones(1), armw * side)
        # лёгкий наклон вперёд и покачивание
        rot_x(p, (0, 0, 0), math.radians(-3), np.ones(len(p)))
        p[:, 2] -= p[:, 2].min()
        p[:, 2] += 0.035 * abs(math.sin(t))
    for i, v in enumerate(ob.data.vertices):
        v.co = p[i]
    ob.data.update()
info = json.load(open(GLB + '.eye.json'))
mats = {m.name.split('.')[0]: m for m in ob.data.materials}
# Глаз — чёткие круги (как в просмотре).
eye = bpy.data.materials.new('EyeProc'); eye.use_nodes = True
nt = eye.node_tree; N = nt.nodes; L = nt.links
b = N['Principled BSDF']; b.inputs['Roughness'].default_value = 0.3
tc = N.new('ShaderNodeTexCoord'); sp = N.new('ShaderNodeSeparateXYZ'); L.new(tc.outputs['Object'], sp.inputs[0])
dx = N.new('ShaderNodeMath'); dx.operation = 'SUBTRACT'; L.new(sp.outputs['X'], dx.inputs[0]); dx.inputs[1].default_value = info['x']
dz = N.new('ShaderNodeMath'); dz.operation = 'SUBTRACT'; L.new(sp.outputs['Z'], dz.inputs[0]); dz.inputs[1].default_value = info['z']
cb = N.new('ShaderNodeCombineXYZ'); L.new(dx.outputs[0], cb.inputs['X']); L.new(dz.outputs[0], cb.inputs['Y'])
ln = N.new('ShaderNodeVectorMath'); ln.operation = 'LENGTH'; L.new(cb.outputs[0], ln.inputs[0])
dv = N.new('ShaderNodeMath'); dv.operation = 'DIVIDE'; L.new(ln.outputs['Value'], dv.inputs[0]); dv.inputs[1].default_value = info['eye_r']
ramp = N.new('ShaderNodeValToRGB'); L.new(dv.outputs[0], ramp.inputs['Fac'])
cr = ramp.color_ramp; R = info['eye_r']
cr.elements[0].position = 0.0; cr.elements[0].color = (0.005, 0.005, 0.006, 1)
cr.elements[1].position = 1.0; cr.elements[1].color = (0.92, 0.92, 0.9, 1)
for pos, col in ((info['pupil'] - 0.004, (0.005, 0.005, 0.006, 1)), (info['pupil'] + 0.004, (0.06, 0.32, 0.95, 1)),
                 (info['iris'] - 0.025, (0.03, 0.2, 0.8, 1)), (info['iris'] - 0.008, (0.01, 0.06, 0.3, 1)), (info['iris'] + 0.004, (0.92, 0.92, 0.9, 1))):
    e = cr.elements.new(min(pos / R, 1.0)); e.color = col
L.new(ramp.outputs['Color'], b.inputs['Base Color'])
for i, m in enumerate(ob.data.materials):
    if m.name.split('.')[0] in ('white', 'iris', 'pupil'):
        ob.data.materials[i] = eye
h = COL.lstrip('#'); c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
c = [((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92 for v in c]
mats['body'].node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (*c, 1)
sc = bpy.context.scene
def light(name, loc, energy, col, size):
    ld = bpy.data.lights.new(name, 'AREA'); ld.energy = energy; ld.color = col; ld.size = size
    o = bpy.data.objects.new(name, ld); o.location = loc; sc.collection.objects.link(o)
    o.constraints.new('TRACK_TO').target = ob
light('Key', (-3.2, -3.6, 5.0), 330, (1.0, 0.96, 0.9), 4.5)
light('Fill', (4.0, -2.5, 1.8), 35, (0.8, 0.88, 1.0), 5.0)
light('Rim', (2.5, 4.0, 4.0), 700, (1.0, 0.98, 0.95), 2.5)
light('Rim2', (-2.8, 3.5, 2.5), 300, (0.9, 0.95, 1.0), 2.5)
w = bpy.data.worlds.new('W'); sc.world = w; w.use_nodes = True
w.node_tree.nodes['Background'].inputs['Color'].default_value = (0.6, 0.65, 0.72, 1)
w.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.12
sc.render.engine = 'CYCLES'; sc.cycles.device = 'CPU'; sc.cycles.samples = 48; sc.cycles.use_denoising = True
sc.render.film_transparent = True; sc.view_settings.view_transform = 'Standard'
cam = bpy.data.objects.new('Cam', bpy.data.cameras.new('Cam')); cam.data.type = 'ORTHO'; cam.data.ortho_scale = 3.2
cam.location = (0, -10, 1.2); cam.rotation_euler = (math.radians(90), 0, 0); sc.collection.objects.link(cam); sc.camera = cam
sc.render.resolution_x = sc.render.resolution_y = 320
sc.cycles.samples = 32
os.makedirs(OUT, exist_ok=True)
frames = [('idle', None)] + [('walk%d' % i, i / 8.0) for i in range(8)]
for name, ph in frames:
    pose(ph)
    sc.render.filepath = os.path.join(OUT, name + '.png')
    bpy.ops.render.render(write_still=True)
