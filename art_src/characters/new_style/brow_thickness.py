## Толщина брови (высота дуги) — в K раз, длина та же: python3 brow_thickness.py <вход.glb> <выход.glb> [0.9]
## Каждая вершина брови сдвигается к средней линии дуги на своей высоте x; тело вокруг — плавно.
import json
import shutil
import sys

import bpy
import numpy as np

SRC, DST = sys.argv[1], sys.argv[2]
K = float(sys.argv[3]) if len(sys.argv) > 3 else 0.9
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
ob = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
bpy.context.view_layer.objects.active = ob
ob.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
me = ob.data
names = [m.name.split('.')[0] for m in me.materials]
co = np.array([v.co[:] for v in me.vertices])
is_brow = np.zeros(len(co), bool)
for p in me.polygons:
    if names[p.material_index] == 'brow':
        is_brow[list(p.vertices)] = True
B = co[is_brow]
# Средняя линия дуги: середина между верхом и низом брови в каждой полоске по x.
bins = np.linspace(B[:, 0].min(), B[:, 0].max(), 25)
mids = []
for a, b in zip(bins[:-1], bins[1:]):
    m = (B[:, 0] >= a) & (B[:, 0] <= b)
    mids.append(((a + b) / 2, (B[m, 2].max() + B[m, 2].min()) / 2 if m.any() else np.nan))
mids = np.array([m for m in mids if not np.isnan(m[1])])
zc = np.interp(co[:, 0], mids[:, 0], mids[:, 1])
half = float(np.median([np.ptp(B[(B[:, 0] >= a) & (B[:, 0] <= b), 2]) / 2 for a, b in zip(bins[4:-5], bins[5:-4])]))
new = co.copy()
new[is_brow, 2] = zc[is_brow] + (co[is_brow, 2] - zc[is_brow]) * K
# Тело вплотную к брови (кольцо) — к ней же, плавно, чтобы не было ступеньки.
near = (~is_brow) & (co[:, 0] >= B[:, 0].min() - 0.06) & (co[:, 0] <= B[:, 0].max() + 0.06) & (co[:, 1] < 0.0)
dz = np.abs(co[:, 2] - zc)
ring = near & (dz < half + 0.06) & (dz > half * 0.5)
t = np.clip((dz[ring] - half) / 0.06, 0, 1)
w = 1 - t * t * (3 - 2 * t)
shift = half * (1 - K) * w
new[ring, 2] = co[ring, 2] - np.sign(co[ring, 2] - zc[ring]) * shift
for i, v in enumerate(me.vertices):
    v.co = new[i]
me.update()
bpy.ops.export_scene.gltf(filepath=DST, export_format='GLB', use_selection=False)
shutil.copy(SRC + '.eye.json', DST + '.eye.json')
print('brow half-thickness', round(half, 3), '->', round(half * K, 3))
