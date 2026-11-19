## Чистка модели из Tripo (по картинке) под игру и просмотр:
##  - рост 2,4 м, ступни на полу, по центру; сетка уменьшена (децимация);
##  - текстура убрана: каждая грань получает плоский материал по цвету текстуры в её середине
##    (белок, радужка, зрачок, бровь, румянец, рот, язык, зубы), всё остальное — тело одного цвета
##    (его потом красим по генам) — так уходят оранжевый оттенок и серые пятна на руках и ногах;
##  - лишнее сзади (хвостик, наросты за спиной) срезается.
##   python3 clean_tripo.py <вход.glb> <выход.glb>
import colorsys
import math
import os
import sys

import bpy
import bmesh
import mathutils
import numpy as np

SRC, DST = sys.argv[1], sys.argv[2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
ob = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
bpy.context.view_layer.objects.active = ob
ob.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
me = ob.data
# Сетка из glTF разрезана по швам развёртки — сшиваем (UV на углах граней остаются).
bm0 = bmesh.new()
bm0.from_mesh(me)
bmesh.ops.remove_doubles(bm0, verts=bm0.verts, dist=1e-5)
bm0.to_mesh(me)
bm0.free()

# Текстура цвета — в numpy.
img = None
for n in me.materials[0].node_tree.nodes:
    if n.type == 'TEX_IMAGE' and 'basecolor' in n.image.name:
        img = n.image
W, H = img.size
px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)

# Масштаб и положение.
v = np.array([vv.co[:] for vv in me.vertices])
k = 2.4 / (v[:, 2].max() - v[:, 2].min())
v *= k
v[:, 0] -= (v[:, 0].max() + v[:, 0].min()) / 2
v[:, 1] -= (v[:, 1].max() + v[:, 1].min()) / 2
v[:, 2] -= v[:, 2].min()
for i, vv in enumerate(me.vertices):
    vv.co = v[i]

# Классы цвета грани.
CLASSES = ['body', 'white', 'iris', 'pupil', 'brow', 'cheek', 'mouth', 'tongue', 'tooth']
COLORS = {'body': (0.913, 0.6, 0.0), 'white': (0.92, 0.92, 0.9), 'iris': (0.05, 0.25, 0.85),
          'pupil': (0.01, 0.01, 0.012), 'brow': (0.06, 0.03, 0.02), 'cheek': (1.0, 0.33, 0.4),
          'mouth': (0.12, 0.01, 0.02), 'tongue': (0.75, 0.08, 0.1), 'tooth': (0.9, 0.88, 0.82)}


def classify(rgb, c, front, recessed):
    r, g, b = rgb
    h, s, val = colorsys.rgb_to_hsv(r, g, b)
    x, y, z = c
    if not front:
        return 'body'
    # Глаз — по геометрии: шар перед телом; зрачок и радужка — круги вокруг центра радужки.
    er = math.hypot(x - EYE_C[0], z - EYE_C[1])
    # Глаз — грани, лежащие на шаре глаза (стык с телом и наплывы краски — уже тело).
    on_ball = abs(math.dist((x, y, z), BALL_C) - BALL_R) < 0.025
    if er < EYE_R * 1.05 and on_ball:
        if er < PUPIL_R:
            return 'pupil'
        if er < IRIS_R:
            return 'iris'
        return 'white'
    # Бровь — валик над глазом: выступает вперёд из плоскости лица.
    if z > EYE_C[1] + EYE_R * 0.8 and abs(x - EYE_C[0]) < 0.48 and y < brow_surf(z) - 0.025 and er > EYE_R * 1.06:
        return 'brow'
    # Рот — по глубине: всё утопленное в нём — тёмная полость, кроме зубов и языка.
    if abs(x) < 0.15 and 1.2 < z < 1.36 and s < 0.25 and val > 0.5:
        return 'tooth'
    if abs(x) < 0.26 and 0.95 < z < 1.4 and recessed:
        if (h > 0.9 or h < 0.06) and s > 0.5 and val > 0.55 and z < 1.24:
            return 'tongue'
        return 'mouth'
    if (h > 0.9 or h < 0.04) and 0.25 < s < 0.7 and val > 0.6 and z > 1.2:
        return 'cheek'
    return 'body'


uv = me.uv_layers.active.data
bm_cls = []
ymin = v[:, 1].min()
# Передняя поверхность на высоте рта (там, где рот не утоплен — по краям).
band = (np.abs(v[:, 0]) > 0.26) & (np.abs(v[:, 0]) < 0.34) & (v[:, 2] > 1.05) & (v[:, 2] < 1.3)
MOUTH_FACE = float(v[band, 1].min()) if band.any() else -0.42

# Передняя поверхность тела по высоте (по бокам от рта) — от неё меряем, утоплена ли грань.
_zb = np.arange(0.8, 1.6, 0.02)
_sy = []
for z0 in _zb:
    m = (np.abs(v[:, 0]) > 0.27) & (np.abs(v[:, 0]) < 0.36) & (np.abs(v[:, 2] - z0) < 0.02)
    _sy.append(v[m, 1].min() if m.any() else -0.4)


def surf_y(z):
    return float(np.interp(z, _zb, _sy))


# Плоскость лица над глазом (по краям, где брови нет) — от неё меряем, выступает ли бровь.
_bz = np.arange(1.9, 2.45, 0.02)
_by = []
for z0 in _bz:
    m = (np.abs(v[:, 0]) > 0.5) & (np.abs(v[:, 0]) < 0.6) & (np.abs(v[:, 2] - z0) < 0.02) & (v[:, 1] < 0)
    _by.append(v[m, 1].min() if m.any() else -0.3)


def brow_surf(z):
    return float(np.interp(z, _bz, _by))


# Глаз: центр радужки — по синим граням текстуры; радиусы — по их разбросу.
fc = []
fhsv = []
for p in me.polygons:
    uvs = np.array([uv[li].uv[:] for li in p.loop_indices]).mean(0)
    rgb = px[int(np.clip(uvs[1], 0, 1) * (H - 1)), int(np.clip(uvs[0], 0, 1) * (W - 1)), :3]
    fc.append(p.center[:])
    fhsv.append(colorsys.rgb_to_hsv(*rgb))
fc = np.array(fc)
fhsv = np.array(fhsv)
blue = (fc[:, 2] > 1.4) & (fhsv[:, 0] > 0.52) & (fhsv[:, 0] < 0.72) & (fhsv[:, 1] > 0.35) & (fc[:, 1] < ymin + 0.1)
EYE_C = (float(np.median(fc[blue, 0])), float(np.median(fc[blue, 2])))
br = np.hypot(fc[blue, 0] - EYE_C[0], fc[blue, 2] - EYE_C[1])
IRIS_R = float(np.percentile(br, 97))
PUPIL_R = IRIS_R * 0.45
white = (fc[:, 2] > 1.4) & (fhsv[:, 1] < 0.18) & (fhsv[:, 2] > 0.6) & (fc[:, 1] < ymin + 0.45)
wr = np.hypot(fc[white, 0] - EYE_C[0], fc[white, 2] - EYE_C[1])
EYE_R = float(np.percentile(wr, 97))
EYE_FRONT = float(np.percentile(fc[white, 1], 97)) + 0.01
# Шар глаза: центр и радиус по белым граням середины глаза (наименьшие квадраты).
sel = white & (np.hypot(fc[:, 0] - EYE_C[0], fc[:, 2] - EYE_C[1]) < EYE_R * 0.8)
P = fc[sel]
A = np.c_[2 * P, np.ones(len(P))]
bsol = (P ** 2).sum(1)
sol = np.linalg.lstsq(A, bsol, rcond=None)[0]
BALL_C = tuple(sol[:3])
BALL_R = float(np.sqrt(sol[3] + (sol[:3] ** 2).sum()))
print('ball', np.round(BALL_C, 3), round(BALL_R, 3))
print('eye', np.round(EYE_C, 3), 'R', round(EYE_R, 3), 'iris', round(IRIS_R, 3), 'front', round(EYE_FRONT, 3))
for p in me.polygons:
    uvs = np.array([uv[li].uv[:] for li in p.loop_indices]).mean(0)
    x = int(np.clip(uvs[0], 0, 1) * (W - 1))
    y = int(np.clip(uvs[1], 0, 1) * (H - 1))
    rgb = px[y, x, :3]
    c = p.center
    # «Перед» — сторона лица (-Y у Tripo, поэтому ближе к ymin).
    front = c.y < -0.02
    bm_cls.append(CLASSES.index(classify(rgb, c, front, c.y > surf_y(c.z) + 0.06)))

# Сглаживание классов: грань берёт класс большинства соседей (убирает «шум» на краях).
adj = {}
for e in me.edges:
    pass
edge_faces = {}
for p in me.polygons:
    for ek in p.edge_keys:
        edge_faces.setdefault(ek, []).append(p.index)
nb = [[] for _ in me.polygons]
for fs in edge_faces.values():
    for a in fs:
        for b in fs:
            if a != b:
                nb[a].append(b)
for _ in range(3):
    new = list(bm_cls)
    for i in range(len(bm_cls)):
        if not nb[i]:
            continue
        cnt = {}
        for j in nb[i]:
            cnt[bm_cls[j]] = cnt.get(bm_cls[j], 0) + 1
        best = max(cnt, key=cnt.get)
        if cnt[best] >= 2 and best != bm_cls[i] and cnt.get(bm_cls[i], 0) <= 1:
            new[i] = best
    bm_cls = new

me.materials.clear()
for name in CLASSES:
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = (*COLORS[name], 1)
    b.inputs['Roughness'].default_value = 0.6 if name == 'body' else 0.35
    me.materials.append(m)
    m['eye_c'] = [EYE_C[0], EYE_C[1]]
    m['iris_r'] = IRIS_R
    m['pupil_r'] = PUPIL_R
for p, c in zip(me.polygons, bm_cls):
    p.material_index = c

# Срезаем то, что торчит за спиной (хвостик): спина — плоская, всё дальше неё на середине тела.
bm = bmesh.new()
bm.from_mesh(me)
# Плоская спина — на уровне спины верхней части тела; всё, что за ней ниже, — хвостик.
upper = [vv.co.y for vv in bm.verts if vv.co.z > 1.6 and abs(vv.co.x) < 0.4]
back = float(np.max(upper))
kill = [f for f in bm.faces if f.calc_center_median().y > back + 0.008 and 0.5 < f.calc_center_median().z < 1.5]
bmesh.ops.delete(bm, geom=kill, context='FACES')
# Мелкие оторванные куски — убрать.
bm.verts.ensure_lookup_table()
seen = set()
parts = []
for f0 in bm.faces:
    if f0 in seen:
        continue
    stack = [f0]
    part = []
    seen.add(f0)
    while stack:
        f = stack.pop()
        part.append(f)
        for e in f.edges:
            for g in e.link_faces:
                if g not in seen:
                    seen.add(g)
                    stack.append(g)
    parts.append(part)
parts.sort(key=len, reverse=True)
small = [f for part in parts[1:] if len(part) < len(parts[0]) * 0.02 for f in part]
bmesh.ops.delete(bm, geom=small, context='FACES')
# Дыры после срезания — заделать.
bnd = [e for e in bm.edges if e.is_boundary]
bmesh.ops.holes_fill(bm, edges=bnd, sides=0)
bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
print('boundary edges filled:', len(bnd))
bm.to_mesh(me)
bm.free()
print('removed tail faces:', len(kill), 'small parts:', len(small))

# Тело — клином, как на листе ракурсов: спина уходит назад тем дальше, чем выше (у нижнего угла
# толщина прежняя). Сначала спину ровняем (срезает бугорок от хвостика), потом сдвигаем.
# Руки и ноги не трогаем: только то, что внутри треугольника тела.
THICK = float(os.environ.get('THICK', '0.3'))
co = np.array([vv.co[:] for vv in me.vertices])
back0 = float(np.percentile(co[co[:, 2] > 1.6, 1], 99.5))
mid = back0 - 0.35   # отсюда к спине сдвиг растёт от 0 до полного


def body_w(z):
    return np.clip((z - 0.95) * 0.73, 0.0, 0.96)


# Вес сдвига — по расстоянию до контура треугольника тела (внутри — полный, к краю плавно
# меньше): спина становится «подушкой» без рёбер.
TRI_B = np.array([[-0.97, 2.36], [0.97, 2.36], [0.0, 0.92]])


def tri_sd(x, z):
    d = np.full(x.shape, np.inf)
    sgn = np.ones(x.shape)
    for i in range(3):
        a, b = TRI_B[i], TRI_B[i - 1]
        ex, ez = a[0] - b[0], a[1] - b[1]
        wx, wz = x - b[0], z - b[1]
        t = np.clip((wx * ex + wz * ez) / (ex * ex + ez * ez), 0, 1)
        d = np.minimum(d, (wx - ex * t) ** 2 + (wz - ez * t) ** 2)
        c1, c2, c3 = z >= b[1], z < a[1], ex * wz > ez * wx
        sgn = np.where((c1 & c2 & c3) | (~c1 & ~c2 & ~c3), -sgn, sgn)
    return sgn * np.sqrt(d)


din = -tri_sd(co[:, 0], co[:, 2])
inside = np.clip((din + 0.05) / 0.4, 0, 1)
inside = inside * inside * (3 - 2 * inside)
co[:, 1] = np.where(inside > 0, np.minimum(co[:, 1], back0), co[:, 1])

wy = np.clip((co[:, 1] - mid) / (back0 - mid), 0, 1)
wy = wy * wy * (3 - 2 * wy)
extra = THICK * np.clip((co[:, 2] - 0.95) / 1.35, 0, 1) ** 1.2
co[:, 1] += extra * wy * inside
for i, vv in enumerate(me.vertices):
    vv.co = co[i]
# Место, где был хвостик, — сгладить (заплатка становится ровной частью спины).
vg = ob.vertex_groups.new(name='stub')
rr2 = np.hypot(co[:, 0], co[:, 2] - 0.98)
for i in np.where((rr2 < 0.28) & (co[:, 1] > 0.03))[0]:
    vg.add([int(i)], float(np.clip(1.5 - rr2[i] / 0.28 * 1.5, 0, 1)), 'REPLACE')
sm = ob.modifiers.new('Smooth', 'SMOOTH')
sm.vertex_group = 'stub'
sm.factor = 1.0
sm.iterations = 120
bpy.context.view_layer.objects.active = ob
bpy.ops.object.modifier_apply(modifier='Smooth')
print('thickened: back', round(back0, 3), 'mid', round(mid, 3))

# Децимация.
dec = ob.modifiers.new('Dec', 'DECIMATE')
dec.ratio = float(os.environ.get('RATIO', '0.15'))
bpy.ops.object.modifier_apply(modifier='Dec')
for p in me.polygons:
    p.use_smooth = True
# Верхнее веко — тёмная тонкая дуга по стыку глаза и тела. По умолчанию выключено (LID=1 — включить).
if os.environ.get('LID') == '1':
    from mathutils.bvhtree import BVHTree
    bvh = BVHTree.FromObject(ob, bpy.context.evaluated_depsgraph_get())
    lid = []
    for a in np.linspace(-1.2, 1.2, 25):
        best = None
        for k in range(80):
            r = EYE_R * (0.85 + k * 0.004)
            o = mathutils.Vector((EYE_C[0] + r * math.sin(a), -3.0, EYE_C[1] + r * math.cos(a)))
            hit = bvh.ray_cast(o, mathutils.Vector((0, 1, 0)))
            if hit[0] is None:
                continue
            if hit[2] is not None and hit[3] is not None:
                m_i = me.polygons[hit[2]].material_index
                if CLASSES[m_i] != 'white':
                    best = hit[0]
                    break
        if best is not None:
            lid.append((a, math.hypot(best.x - EYE_C[0], best.z - EYE_C[1]), best.y))
    # Ровная дуга: радиус — средний по стыку, глубина — сглаженная.
    la = np.array([q[0] for q in lid])
    lr = float(np.median([q[1] for q in lid]))
    ly = np.array([q[2] for q in lid])
    ly = np.convolve(np.pad(ly, 3, mode='edge'), np.ones(7) / 7, mode='valid')
    lid = [mathutils.Vector((EYE_C[0] + lr * math.sin(a), y - 0.012, EYE_C[1] + lr * math.cos(a))) for a, y in zip(la, ly)]
    cu = bpy.data.curves.new('Lid', 'CURVE')
    cu.dimensions = '3D'
    sp = cu.splines.new('NURBS')
    sp.use_endpoint_u = True
    sp.order_u = 4
    sp.points.add(len(lid) - 1)
    for pt, c in zip(sp.points, lid):
        pt.co = (c.x, c.y, c.z, 1)
    cu.bevel_depth = 0.016
    cu.bevel_resolution = 4
    cu.use_fill_caps = True
    lid_ob = bpy.data.objects.new('Lid', cu)
    bpy.context.scene.collection.objects.link(lid_ob)
    lm = bpy.data.materials.new('lid')
    lm.use_nodes = True
    lm.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.06, 0.03, 0.02, 1)
    cu.materials.append(lm)
    bpy.ops.object.select_all(action='DESELECT')
    lid_ob.select_set(True)
    bpy.context.view_layer.objects.active = lid_ob
    bpy.ops.object.convert(target='MESH')
    for p in lid_ob.data.polygons:
        p.use_smooth = True
    lid_ob.select_set(True)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.join()
    print('lid points', len(lid))

# UV и текстуры больше не нужны.
while me.uv_layers:
    me.uv_layers.remove(me.uv_layers[0])
for im in list(bpy.data.images):
    bpy.data.images.remove(im)
print('faces:', len(me.polygons))
cnt = {}
for p in me.polygons:
    nm = me.materials[p.material_index].name
    cnt[nm] = cnt.get(nm, 0) + 1
print('classes', cnt)
bpy.ops.export_scene.gltf(filepath=DST, export_format='GLB', use_selection=False)
import json
json.dump({'x': EYE_C[0], 'z': EYE_C[1], 'iris': IRIS_R, 'pupil': PUPIL_R, 'eye_r': EYE_R}, open(DST + '.eye.json', 'w'))
