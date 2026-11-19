## Уменьшить (или увеличить) глаз и бровь на модели: python3 resize_face.py <вход.glb> <выход.glb> [0.9]
## Глаз (белок, радужка, зрачок) масштабируется вокруг центра шара глаза, бровь — вокруг своей
## середины и опускается вслед за верхом глаза. Тело вокруг подтягивается плавно (без складок).
## Рядом с .glb лежит .eye.json (центр и радиусы глаза для просмотра) — пересчитывается.
import json
import math
import sys

import bpy
import numpy as np

SRC, DST = sys.argv[1], sys.argv[2]
K = float(sys.argv[3]) if len(sys.argv) > 3 else 0.9
info = json.load(open(SRC + '.eye.json'))
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
ob = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
bpy.context.view_layer.objects.active = ob
ob.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
me = ob.data
names = [m.name.split('.')[0] for m in me.materials]
co = np.array([v.co[:] for v in me.vertices])
nv = len(co)
is_eye = np.zeros(nv, bool)
is_brow = np.zeros(nv, bool)
for p in me.polygons:
    n = names[p.material_index]
    if n in ('white', 'iris', 'pupil'):
        is_eye[list(p.vertices)] = True
    elif n == 'brow':
        is_brow[list(p.vertices)] = True
# Шар глаза — по вершинам белка (наименьшие квадраты).
P = co[is_eye]
A = np.c_[2 * P, np.ones(len(P))]
sol = np.linalg.lstsq(A, (P ** 2).sum(1), rcond=None)[0]
C = sol[:3]
R = math.sqrt(sol[3] + (C ** 2).sum())
print('ball', np.round(C, 3), round(R, 3))
new = co.copy()
# Глаз — целиком в K раз.
new[is_eye] = C + (co[is_eye] - C) * K
# Тело вокруг глаза: кольцо шириной RING плавно тянется к глазу (по плоскости лица).
RING = 0.12
d = np.hypot(co[:, 0] - C[0], co[:, 2] - C[2])
eye_edge = np.percentile(np.hypot(P[:, 0] - C[0], P[:, 2] - C[2]), 99)
ring = (~is_eye) & (~is_brow) & (co[:, 1] < C[1] + 0.25) & (d < eye_edge + RING)
t = np.clip((d[ring] - eye_edge) / RING, 0, 1)
w = 1 - t * t * (3 - 2 * t)
f = 1 + (K - 1) * w * (eye_edge / np.maximum(d[ring], 1e-6))
new[ring, 0] = C[0] + (co[ring, 0] - C[0]) * np.where(d[ring] < eye_edge, K, f)
new[ring, 2] = C[2] + (co[ring, 2] - C[2]) * np.where(d[ring] < eye_edge, K, f)
# Бровь — в K раз вокруг своей середины и вниз вслед за верхом глаза.
B = co[is_brow]
bc = B.mean(0)
drop = R * (1 - K)
new[is_brow] = bc + (B - bc) * K + np.array([0, 0, -drop])
for i, v in enumerate(me.vertices):
    v.co = new[i]
me.update()
bpy.ops.export_scene.gltf(filepath=DST, export_format='GLB', use_selection=False)
# Пересчёт описания глаза: всё — к центру шара.
ex = C[0] + (info['x'] - C[0]) * K
ez = C[2] + (info['z'] - C[2]) * K
json.dump({'x': ex, 'z': ez, 'iris': info['iris'] * K, 'pupil': info['pupil'] * K, 'eye_r': info['eye_r'] * K},
          open(DST + '.eye.json', 'w'))
print('ok')
