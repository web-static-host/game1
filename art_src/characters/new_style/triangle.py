## Пробный гаврик в стиле заставок (треугольный): тело — перевёрнутый треугольник со скруглёнными
## углами, «подушкой», как у игрушки; большой глаз с бровью, рот с одним зубом, румянец;
## короткие ручки-варежки и короткие ножки с круглыми ступнями. В игру пока не идёт — только
## картинки для просмотра.
##   python3 art_src/characters/new_style/triangle.py <папка>   → <папка>/*.png
## Оси: x — вправо, y — вглубь (лицо к -y), z — вверх; метры; рост ~2,4 (как у модели в игре).
import math
import os
import sys

import bpy
import numpy as np
from skimage import measure

OUT = sys.argv[sys.argv.index('--') + 1] if '--' in sys.argv else (sys.argv[1] if len(sys.argv) > 1 else '.')
os.makedirs(OUT, exist_ok=True)

# --- Форма тела (SDF) ---------------------------------------------------------------------
TRI = np.array([[-0.64, 2.1], [0.64, 2.1], [0.0, 0.84]])   # треугольник до скругления (x, z)
R2D = 0.08      # скругление контура
HALF = 0.11     # полутолщина плоской части (перед — ровная «подушка»)
ROUND = 0.2     # скругление краёв подушки
STEP = 0.011


def sd_poly(px, pz, v):
    d = np.full(px.shape, np.inf)
    s = np.ones(px.shape)
    n = len(v)
    for i in range(n):
        a = v[i]
        b = v[i - 1]
        ex, ez = a[0] - b[0], a[1] - b[1]
        wx, wz = px - b[0], pz - b[1]
        t = np.clip((wx * ex + wz * ez) / (ex * ex + ez * ez), 0, 1)
        dx, dz = wx - ex * t, wz - ez * t
        d = np.minimum(d, dx * dx + dz * dz)
        c1 = pz >= b[1]
        c2 = pz < a[1]
        c3 = ex * wz > ez * wx
        flip = (c1 & c2 & c3) | (~c1 & ~c2 & ~c3)
        s = np.where(flip, -s, s)
    return s * np.sqrt(d)


def capsule(px, py, pz, a, b, r):
    a = np.array(a)
    b = np.array(b)
    ba = b - a
    pax, pay, paz = px - a[0], py - a[1], pz - a[2]
    h = np.clip((pax * ba[0] + pay * ba[1] + paz * ba[2]) / ba.dot(ba), 0, 1)
    return np.sqrt((pax - ba[0] * h) ** 2 + (pay - ba[1] * h) ** 2 + (paz - ba[2] * h) ** 2) - r


def ellipsoid(px, py, pz, c, r):
    x, y, z = (px - c[0]) / r[0], (py - c[1]) / r[1], (pz - c[2]) / r[2]
    k0 = np.sqrt(x * x + y * y + z * z)
    k1 = np.sqrt((x / r[0]) ** 2 + (y / r[1]) ** 2 + (z / r[2]) ** 2)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-6)


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b + (a - b) * h - k * h * (1 - h)


def body_sdf(px, py, pz):
    d2 = sd_poly(px, pz, TRI) - R2D
    qy = np.abs(py) - HALF
    d = np.sqrt(np.maximum(d2, 0) ** 2 + np.maximum(qy, 0) ** 2) + np.minimum(np.maximum(d2, qy), 0) - ROUND
    for s in (-1, 1):
        # Ножки — короткие трубки, ступни — округлые «ботинки» носком вперёд.
        leg = capsule(px, py, pz, (s * 0.13, 0.0, 0.66), (s * 0.15, -0.01, 0.2), 0.115)
        foot = ellipsoid(px, py, pz, (s * 0.17, -0.07, 0.125), (0.2, 0.27, 0.135))
        foot = np.maximum(foot, -pz)
        # Ручки — короткие, из боков, вниз и чуть вперёд; кисть — варежка с большим пальцем.
        # Плечо — высоко, у верхнего угла треугольника (как у квадратных и круглых на заставках).
        arm = capsule(px, py, pz, (s * 0.76, 0.0, 1.93), (s * 1.04, -0.03, 1.3), 0.088)
        hand = ellipsoid(px, py, pz, (s * 1.08, -0.06, 1.12), (0.15, 0.12, 0.17))
        thumb = capsule(px, py, pz, (s * 0.98, -0.1, 1.2), (s * 0.93, -0.17, 1.12), 0.05)
        limbs = smin(smin(arm, hand, 0.05), thumb, 0.025)
        # Пальцы варежки — три валика снизу кисти.
        for k in range(3):
            fx = s * (1.03 + 0.055 * k)
            limbs = smin(limbs, capsule(px, py, pz, (fx, -0.1, 1.08), (fx, -0.12, 0.98), 0.042), 0.02)
        d = smin(d, smin(leg, foot, 0.08), 0.06)
        d = smin(d, limbs, 0.07)
    return d


def build_mesh(name, sdf, lo, hi, step=STEP):
    xs = np.arange(lo[0], hi[0], step)
    ys = np.arange(lo[1], hi[1], step)
    zs = np.arange(lo[2], hi[2], step)
    X, Y, Z = np.meshgrid(xs, ys, zs, indexing='ij')
    vol = sdf(X, Y, Z)
    verts, faces, _, _ = measure.marching_cubes(vol, 0.0, spacing=(step, step, step))
    verts += np.array(lo)
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts.tolist(), [], faces[:, ::-1].tolist())
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for p in me.polygons:
        p.use_smooth = True
    return ob


def surface(x, z, sdf=body_sdf):
    """Точка на переднем крае тела при (x, z) и нормаль там."""
    ys = np.linspace(-0.7, 0.2, 2000)
    d = sdf(np.full_like(ys, x), ys, np.full_like(ys, z))
    i = np.argmax(d < 0)
    y = ys[i]
    e = 1e-3
    g = np.array([
        sdf(np.array([x + e]), np.array([y]), np.array([z]))[0] - sdf(np.array([x - e]), np.array([y]), np.array([z]))[0],
        sdf(np.array([x]), np.array([y + e]), np.array([z]))[0] - sdf(np.array([x]), np.array([y - e]), np.array([z]))[0],
        sdf(np.array([x]), np.array([y]), np.array([z + e]))[0] - sdf(np.array([x]), np.array([y]), np.array([z - e]))[0]])
    return np.array([x, y, z]), g / np.linalg.norm(g)


# --- Материалы ------------------------------------------------------------------------------
def mat(name, col, rough=0.4, sss=0.0, emit=0.0, coat=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = (*col, 1)
    b.inputs['Roughness'].default_value = rough
    if sss > 0:
        b.inputs['Subsurface Weight'].default_value = sss
        b.inputs['Subsurface Radius'].default_value = (0.3, 0.15, 0.1)
        b.inputs['Subsurface Scale'].default_value = 0.08
    if coat > 0:
        b.inputs['Coat Weight'].default_value = coat
        b.inputs['Coat Roughness'].default_value = 0.15
    if emit > 0:
        b.inputs['Emission Color'].default_value = (*col, 1)
        b.inputs['Emission Strength'].default_value = emit
    return m


def srgb(h):
    h = h.lstrip('#')
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92 for v in c)


def blob(name, c, r, m, rot=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, location=c)
    ob = bpy.context.object
    ob.name = name
    ob.scale = r
    if rot is not None:
        ob.rotation_mode = 'QUATERNION'
        ob.rotation_quaternion = rot
    bpy.ops.object.shade_smooth()
    ob.data.materials.append(m)
    return ob


def facing(n):
    """Поворот, при котором ось -y смотрит по нормали n (наружу)."""
    from mathutils import Vector
    return Vector((0, -1, 0)).rotation_difference(Vector(n))


# --- Сцена ----------------------------------------------------------------------------------
def build(color_hex):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    body_col = srgb(color_hex)
    m_body = mat('Body', body_col, rough=0.3, sss=0.08, coat=0.3)
    dark = (0.02, 0.018, 0.022)
    m_brow = mat('Brow', dark, rough=0.45)
    m_white = mat('White', (0.95, 0.95, 0.94), rough=0.18, coat=0.5)
    m_iris = mat('Iris', srgb('#2f86ff'), rough=0.2, coat=0.6)
    m_ring = mat('Ring', srgb('#0b2a6b'), rough=0.3)
    m_pupil = mat('Pupil', (0.01, 0.01, 0.015), rough=0.1, coat=0.8)
    m_glint = mat('Glint', (1, 1, 1), emit=6.0)
    m_mouth = mat('Mouth', srgb('#3a0b14'), rough=0.5)
    m_tongue = mat('Tongue', srgb('#e2566e'), rough=0.4)
    m_tooth = mat('Tooth', (0.96, 0.95, 0.9), rough=0.25, coat=0.4)
    m_cheek = mat('Cheek', srgb('#ff7f98'), rough=0.6)

    body = build_mesh('Body', body_sdf, (-1.35, -0.6, -0.02), (1.35, 0.6, 2.5))
    body.data.materials.append(m_body)

    # Глаз — большой, в верхней трети; бровь лежит прямо на нём (взгляд чуть исподлобья).
    EZ = 1.76
    p, n = surface(0.0, EZ)
    q = facing(n)
    nv = np.array(n)
    blob('EyeWhite', p, (0.31, 0.08, 0.28), m_white, q)
    blob('IrisRing', p + nv * 0.066 + np.array([0.0, 0, -0.03]), (0.175, 0.03, 0.175), m_ring, q)
    blob('Iris', p + nv * 0.074 + np.array([0.0, 0, -0.03]), (0.15, 0.03, 0.15), m_iris, q)
    blob('Pupil', p + nv * 0.096 + np.array([0.0, 0, -0.03]), (0.075, 0.018, 0.075), m_pupil, q)
    blob('Glint', p + nv * 0.112 + np.array([0.06, 0, 0.03]), (0.035, 0.01, 0.035), m_glint, q)
    blob('Glint2', p + nv * 0.11 + np.array([-0.05, 0, -0.08]), (0.016, 0.008, 0.016), m_glint, q)

    def bar(name, c, size, m, qq, bevel):
        bpy.ops.mesh.primitive_cube_add(location=c)
        ob = bpy.context.object
        ob.name = name
        ob.scale = size
        ob.rotation_mode = 'QUATERNION'
        ob.rotation_quaternion = qq
        bv = ob.modifiers.new('Bevel', 'BEVEL')
        bv.width = bevel
        bv.segments = 5
        ob.data.materials.append(m)
        return ob
    # Бровь — прямой тёмный брусок над глазом.
    bp, bn = surface(0.0, EZ + 0.27)
    bar('Brow', bp + np.array(bn) * 0.07, (0.31, 0.035, 0.055), m_brow, facing(bn), 0.03)
    # Рот — тонкая линия, под ней один зуб.
    mp, mn = surface(0.0, 1.36)
    mq = facing(mn)
    mnv = np.array(mn)
    bar('Mouth', mp + mnv * 0.006, (0.12, 0.012, 0.014), m_mouth, mq, 0.008)
    bar('Tooth', mp + mnv * 0.012 + np.array([0, 0, -0.052]), (0.05, 0.016, 0.042), m_tooth, mq, 0.014)
    # Румянец по бокам глаза, чуть ниже.
    for s_ in (-1, 1):
        cp, cn = surface(s_ * 0.44, EZ - 0.2)
        blob('Cheek', cp, (0.11, 0.012, 0.07), m_cheek, facing(cn))

    # Свет: тёплый ключевой сверху-слева, холодная заливка справа, контровой сзади.
    def light(name, kind, loc, energy, col, size=2.0):
        ld = bpy.data.lights.new(name, kind)
        ld.energy = energy
        ld.color = col
        if kind == 'AREA':
            ld.size = size
        ob = bpy.data.objects.new(name, ld)
        ob.location = loc
        sc.collection.objects.link(ob)
        con = ob.constraints.new('TRACK_TO')
        con.target = body
        return ob
    light('Key', 'AREA', (-3.0, -4.0, 4.5), 420, (1.0, 0.95, 0.88), 3.0)
    light('Fill', 'AREA', (3.5, -3.0, 2.0), 130, (0.85, 0.9, 1.0), 4.0)
    light('Rim', 'AREA', (1.5, 3.5, 3.5), 450, (1.0, 1.0, 1.0), 2.0)
    w = bpy.data.worlds.new('W')
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes['Background'].inputs['Color'].default_value = (0.55, 0.62, 0.72, 1)
    w.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.5
    # Пол и задник — светлые, мягкая тень.
    bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0))
    bpy.context.object.data.materials.append(mat('Floor', srgb('#9fb0c2'), rough=0.9))
    bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 6, 0), rotation=(math.radians(90), 0, 0))
    bpy.context.object.data.materials.append(mat('Back', srgb('#8fa2b8'), rough=0.9))
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = 48
    sc.cycles.use_denoising = True
    sc.render.film_transparent = False
    sc.view_settings.view_transform = 'Standard'
    return body


def shoot(path, yaw, res=(900, 1000), dist=7.2, height=1.35, lens=55):
    sc = bpy.context.scene
    cam_d = bpy.data.cameras.new('Cam')
    cam_d.lens = lens
    cam = bpy.data.objects.new('Cam', cam_d)
    sc.collection.objects.link(cam)
    a = math.radians(yaw)
    cam.location = (math.sin(a) * dist, -math.cos(a) * dist, height + 0.6)
    tgt = bpy.data.objects.new('T', None)
    tgt.location = (0, 0, height)
    sc.collection.objects.link(tgt)
    con = cam.constraints.new('TRACK_TO')
    con.target = tgt
    sc.camera = cam
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)
    bpy.data.objects.remove(tgt)


if __name__ == '__main__':
    colors = os.environ.get('COLORS', '#3b6fe0').split(',')
    for col in colors:
        build(col)
        tag = col.lstrip('#')
        for yaw in [int(v) for v in os.environ.get('YAWS', '-28').split(',')]:
            shoot(os.path.join(OUT, 'tri_%s_%d.png' % (tag, yaw)), yaw)
