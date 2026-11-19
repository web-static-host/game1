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
    if er < EYE_R and y < EYE_FRONT and not (0.08 < h < 0.16 and s > 0.5 and er > IRIS_R):
        if er < PUPIL_R:
            return 'pupil'
        if er < IRIS_R:
            return 'iris'
        return 'white'
    # Бровь — валик над глазом: выступает вперёд из плоскости лица.
    if z > EYE_C[1] + EYE_R * 0.8 and abs(x - EYE_C[0]) < 0.48 and y < brow_surf(z) - 0.025:
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

# Децимация.
dec = ob.modifiers.new('Dec', 'DECIMATE')
dec.ratio = float(os.environ.get('RATIO', '0.15'))
bpy.ops.object.modifier_apply(modifier='Dec')
for p in me.polygons:
    p.use_smooth = True
# UV и текстуры больше не нужны.
while me.uv_layers:
    me.uv_layers.remove(me.uv_layers[0])
for im in list(bpy.data.images):
    bpy.data.images.remove(im)
print('faces:', len(me.polygons))
cnt = {}
for p in me.polygons:
    cnt[CLASSES[p.material_index]] = cnt.get(CLASSES[p.material_index], 0) + 1
print('classes', cnt)
bpy.ops.export_scene.gltf(filepath=DST, export_format='GLB', use_selection=False)
import json
json.dump({'x': EYE_C[0], 'z': EYE_C[1], 'iris': IRIS_R, 'pupil': PUPIL_R, 'eye_r': EYE_R}, open(DST + '.eye.json', 'w'))
