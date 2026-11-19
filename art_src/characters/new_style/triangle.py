## Пробный гаврик в стиле заставок (треугольный, за основу — жёлтый со «Склада»; матовый): тело — перевёрнутый треугольник со скруглёнными
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
TRI = np.array([[-0.66, 2.12], [0.66, 2.12], [0.0, 0.86]])   # треугольник до скругления (x, z)
R2D = 0.1       # скругление контура
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


## На сколько тело опущено к земле (ножки короткие, как на листе ракурсов).
LIFT = 0.2


def body_sdf(px, py, pz0):
    pz = pz0 + LIFT
    # Толстая «подушка»: к середине толще (выпуклый перед и зад), у края — мягко скруглена.
    d2 = sd_poly(px, pz, TRI) - R2D
    # Клин (как на листе ракурсов): вверху толстый, к нижнему углу тоньше.
    hy = 0.08 + 0.17 * np.clip((pz - 0.86) / 1.26, 0, 1)
    qy = np.abs(py) - hy
    d = np.sqrt(np.maximum(d2, 0) ** 2 + np.maximum(qy, 0) ** 2) + np.minimum(np.maximum(d2, qy), 0) - ROUND
    for s in (-1, 1):
        # Ножки — короткие трубки, ступни — округлые «ботинки» носком вперёд.
        leg = capsule(px, py, pz0, (s * 0.15, 0.0, 0.95 - LIFT), (s * 0.19, -0.01, 0.2), 0.105)
        foot = ellipsoid(px, py, pz0, (s * 0.23, -0.07, 0.12), (0.2, 0.28, 0.13))
        foot = np.maximum(foot, -pz0)
        # Ручки — короткие, из боков, вниз и чуть вперёд; кисть — варежка с большим пальцем.
        # Рука — толстая трубка из бока (чуть выше, чем на «Складе»), с локтем.
        sh, el, wr = (s * 0.6, 0.0, 1.86), (s * 0.84, -0.03, 1.5), (s * 0.94, -0.05, 1.24)
        arm = smin(capsule(px, py, pz, sh, el, 0.115), capsule(px, py, pz, el, wr, 0.105), 0.03)
        # Кисть — раскрытая ладонь к зрителю: четыре длинных пальца врозь, большой — к телу.
        hc = np.array([s * 0.97, -0.06, 1.1])
        palm = ellipsoid(px, py, pz, tuple(hc), (0.15, 0.08, 0.14))
        limbs = smin(arm, palm, 0.04)
        for k, ang in enumerate((-34, -12, 10, 32)):
            a = math.radians(ang) * s
            ln = (0.15, 0.18, 0.17, 0.13)[k]
            base = hc + np.array([math.sin(a) * 0.08, 0.0, -math.cos(a) * 0.08])
            tip = base + np.array([math.sin(a) * ln, -0.02, -math.cos(a) * ln])
            limbs = smin(limbs, capsule(px, py, pz, tuple(base), tuple(tip), 0.055), 0.015)
        tb = hc + np.array([-s * 0.09, -0.01, 0.0])
        thumb = capsule(px, py, pz, tuple(tb), tuple(tb + np.array([-s * 0.07, -0.03, 0.03])), 0.055)
        limbs = smin(limbs, thumb, 0.012)
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
    """Точка на переднем крае тела при (x, z) и нормаль там (z — до опускания тела)."""
    z = z - LIFT
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
    # Матовые, как мягкий пластилин/софт-тач: блики широкие и слабые.
    m_body = mat('Body', body_col, rough=0.6, sss=0.12)
    m_body.node_tree.nodes['Principled BSDF'].inputs['Specular IOR Level'].default_value = 0.35
    dark = srgb('#2a1a17')
    m_brow = mat('Brow', dark, rough=0.7)
    m_white = mat('White', (0.95, 0.95, 0.94), rough=0.35, coat=0.3)
    m_iris = mat('Iris', srgb('#2f86ff'), rough=0.2, coat=0.6)
    m_ring = mat('Ring', srgb('#0b2a6b'), rough=0.3)
    m_pupil = mat('Pupil', (0.01, 0.01, 0.015), rough=0.1, coat=0.8)
    m_glint = mat('Glint', (1, 1, 1), emit=6.0)
    m_mouth = mat('Mouth', srgb('#4a0d14'), rough=0.7)
    m_tongue = mat('Tongue', srgb('#d93a4a'), rough=0.6)
    m_tooth = mat('Tooth', (0.96, 0.95, 0.9), rough=0.4)
    m_cheek = mat('Cheek', srgb('#ff8a9c'), rough=0.85)

    body = build_mesh('Body', body_sdf, (-1.35, -0.6, -0.02), (1.35, 0.6, 2.5))
    body.data.materials.append(m_body)

    # Глаз — большой выпуклый шар в верхней трети, зрачок чуть в сторону (как на «Складе»).
    EZ = 1.76
    EX = 0.0
    p, n = surface(EX, EZ)
    q = facing(n)
    nv = np.array(n)
    p = p + nv * -0.05
    # Глаз — шар, утоплен в тело на треть; радужка крупная, у края (смотрит вбок).
    ER = 0.31
    blob('EyeWhite', p, (ER, ER, ER), m_white, q)
    from mathutils import Vector
    def on_eye(dx, dz, extra=0.0):
        v = np.array([dx, -math.sqrt(max(0.0, 1 - dx * dx - dz * dz)), dz])
        return p + v * (ER + extra), facing(v)
    ip, iq = on_eye(0.12, -0.06, 0.0)
    blob('IrisRing', ip, (0.15, 0.035, 0.15), m_ring, iq)
    ip, iq = on_eye(0.12, -0.06, 0.012)
    blob('Iris', ip, (0.13, 0.03, 0.13), m_iris, iq)
    ip, iq = on_eye(0.13, -0.06, 0.03)
    blob('Pupil', ip, (0.065, 0.016, 0.065), m_pupil, iq)
    ip, iq = on_eye(0.2, 0.02, 0.045)
    blob('Glint', ip, (0.03, 0.008, 0.03), m_glint, iq)

    def tube(name, pts, r, m):
        bpy.ops.curve.primitive_bezier_curve_add()
        cu = bpy.context.object
        cu.name = name
        spl = cu.data.splines[0]
        spl.bezier_points.add(len(pts) - 2)
        for bpt, c in zip(spl.bezier_points, pts):
            bpt.co = c
            bpt.handle_left_type = 'AUTO'
            bpt.handle_right_type = 'AUTO'
        cu.data.bevel_depth = r
        cu.data.bevel_resolution = 8
        cu.data.use_fill_caps = True
        cu.data.materials.append(m)
        return cu
    # Бровь — толстая дуга над глазом.
    # Бровь — толстая дуга над глазом, концы скруглены.
    bpts = [surface(EX + x, EZ + 0.36 + 0.08 * (1 - (x / 0.3) ** 2))[0] + np.array([0, -0.05, 0]) for x in (-0.3, 0.0, 0.3)]
    tube('Brow', bpts, 0.058, m_brow)
    for e in (bpts[0], bpts[-1]):
        blob('BrowEnd', e, (0.058, 0.058, 0.058), m_brow)
    # Ресницы по верхнему краю глаза: у мальчиков — маленькие, у девочек — длинные, загнутые.
    girl = os.environ.get('SEX', 'm') == 'f'
    lash_n = 5 if girl else 3
    lash_len = 0.11 if girl else 0.045
    eye_c = p
    # Верхнее веко — тонкая тёмная дуга по верхнему краю глаза, вплотную к белку; ресницы
    # растут из неё: у мальчика — 3 совсем коротких у наружного края, у девочки — 5 подлиннее.
    fwd = nv / np.linalg.norm(nv)
    up = np.array([0.0, 0.0, 1.0]) - fwd * fwd[2]
    up /= np.linalg.norm(up)
    right = np.cross(up, fwd)
    def rim(t, extra=0.0):
        # Точка, где шар глаза уходит в тело (стык белка и тела), — по этому стыку и идёт веко.
        side = right * math.sin(t) + up * math.cos(t)
        best = math.radians(70)
        for k in range(200):
            ph = math.radians(40 + k * 0.25)
            q_ = p + (fwd * math.cos(ph) + side * math.sin(ph)) * ER
            if body_sdf(np.array([q_[0]]), np.array([q_[1]]), np.array([q_[2]]))[0] < 0:
                best = ph
                break
        d = fwd * math.cos(best) + side * math.sin(best)
        return p + d * (ER + extra), d
    lid = [rim(math.radians(a), 0.01)[0] for a in range(-85, 71, 13)]
    tube('Lid', lid, 0.02, m_brow)
    for e in (lid[0], lid[-1]):
        blob('LidEnd', e, (0.02, 0.02, 0.02), m_brow)
    angs = ()   # ресниц нет — только линия века
    lash_len = 0.07 if girl else 0.04
    for a in angs:
        t = math.radians(a)
        root, d = rim(t, 0.01)
        out = d * 0.5 + (right * math.sin(t) + up * math.cos(t)) * 0.9
        out /= np.linalg.norm(out)
        side = right * math.cos(t) - up * math.sin(t)
        mid = root + out * lash_len * 0.6
        tip = root + out * lash_len - side * lash_len * 0.35
        r = 0.013 if girl else 0.011
        tube('Lash', [root, mid, tip], r, m_brow)
        blob('LashEnd', tip, (r, r, r), m_brow)
    # Рот — широкая открытая улыбка: два зуба сверху, язык снизу.
    mp, mn = surface(0.0, 1.34)
    mq = facing(mn)
    mnv = np.array(mn)
    blob('Mouth', mp + mnv * -0.035, (0.19, 0.06, 0.11), m_mouth, mq)
    blob('Tongue', mp + mnv * -0.005 + np.array([0, 0, -0.06]), (0.12, 0.03, 0.05), m_tongue, mq)
    for tx in (-0.045, 0.045):
        bpy.ops.mesh.primitive_cube_add(location=mp + mnv * 0.012 + np.array([tx, 0, 0.06]))
        tooth = bpy.context.object
        tooth.name = 'Tooth'
        tooth.scale = (0.038, 0.018, 0.045)
        tooth.rotation_mode = 'QUATERNION'
        tooth.rotation_quaternion = mq
        bv = tooth.modifiers.new('Bevel', 'BEVEL')
        bv.width = 0.014
        bv.segments = 5
        tooth.data.materials.append(m_tooth)
    # Румянец — крупные круги под глазом по бокам.
    for s_ in (-1, 1):
        cp, cn = surface(s_ * 0.36, 1.45)
        blob('Cheek', cp, (0.09, 0.014, 0.075), m_cheek, facing(cn))

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
    # Свет как в студии у мультяшных рендеров: один большой мягкий ключевой сверху-слева
    # (даёт плавный переход в тень — объём), слабая холодная заливка справа, контровой сзади
    # (светлый край силуэта), снизу — отражённый от пола тёплый свет.
    light('Key', 'AREA', (-3.2, -3.6, 5.0), float(os.environ.get('KEY', '330')), (1.0, 0.96, 0.9), 4.5)
    light('Fill', 'AREA', (4.0, -2.5, 1.8), float(os.environ.get('FILL', '35')), (0.8, 0.88, 1.0), 5.0)
    light('Rim', 'AREA', (2.5, 4.0, 4.0), 700, (1.0, 0.98, 0.95), 2.5)
    light('Rim2', 'AREA', (-2.8, 3.5, 2.5), 300, (0.9, 0.95, 1.0), 2.5)
    light('Bounce', 'AREA', (0.0, -2.5, -0.6), 60, (1.0, 0.92, 0.8), 4.0)
    w = bpy.data.worlds.new('W')
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes['Background'].inputs['Color'].default_value = (0.6, 0.65, 0.72, 1)
    w.node_tree.nodes['Background'].inputs['Strength'].default_value = float(os.environ.get('AMB', '0.12'))
    # Пол и задник — светлые, мягкая тень.
    bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0))
    bpy.context.object.is_shadow_catcher = True
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = 128
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    # Обычная цветопередача (цвет насыщенный), объём — от контрастного света: сильный ключевой,
    # слабые заливка и окружение.
    sc.view_settings.view_transform = os.environ.get('VT', 'Standard')
    if os.environ.get('LOOK'):
        sc.view_settings.look = os.environ['LOOK']
    sc.view_settings.exposure = float(os.environ.get('EXPO', '0'))
    return body


def shoot(path, yaw, res=(900, 1000), dist=7.2, height=1.35, lens=55, tx=0.0):
    sc = bpy.context.scene
    cam_d = bpy.data.cameras.new('Cam')
    cam_d.lens = lens
    cam = bpy.data.objects.new('Cam', cam_d)
    sc.collection.objects.link(cam)
    a = math.radians(yaw)
    cam.location = (tx + math.sin(a) * dist, -math.cos(a) * dist, height + 0.6 * dist / 7.2)
    tgt = bpy.data.objects.new('T', None)
    tgt.location = (tx, 0, height)
    sc.collection.objects.link(tgt)
    con = cam.constraints.new('TRACK_TO')
    con.target = tgt
    sc.camera = cam
    # Свет поворачивается вместе с камерой: с любого ракурса освещён одинаково (как на листе).
    for ob in sc.objects:
        if ob.type == 'LIGHT':
            if 'base' not in ob:
                ob['base'] = list(ob.location)
            bx, by, bz = ob['base']
            ob.location = (bx * math.cos(a) - by * math.sin(a), bx * math.sin(a) + by * math.cos(a), bz)
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)
    bpy.data.objects.remove(tgt)


if __name__ == '__main__':
    colors = os.environ.get('COLORS', '#f5bd00').split(',')
    for col in colors:
        build(col)
        tag = col.lstrip('#') + os.environ.get('SEX', 'm')
        for yaw in [int(v) for v in os.environ.get('YAWS', '-28').split(',')]:
            shoot(os.path.join(OUT, 'tri_%s_%d.png' % (tag, yaw)), yaw)
        if os.environ.get('CLOSE'):
            shoot(os.path.join(OUT, 'tri_%s_face.png' % tag), -20, (700, 700), 2.4, 1.78, 60)
            shoot(os.path.join(OUT, 'tri_%s_hand.png' % tag), -40, (700, 700), 1.3, 1.08, 60, -1.03)
