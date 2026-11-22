## Уменьшить глаз и бровь модели Hunyuan (сетку вместе с текстурой на ней) к центру глаза:
##   python3 shrink_face.py <вход.glb> <выход.glb> [0.8]
## Внутри овала глаза с бровью — масштаб целиком, к краю овала — плавно до 1 (растягивается
## только жёлтое тело вокруг); верхний край головы и затылок не двигаются.
import sys

import bpy
import numpy as np

SRC, DST = sys.argv[1], sys.argv[2]
S = float(sys.argv[3]) if len(sys.argv) > 3 else 0.8
# Центр сжатия — у низа глаза на поверхности лица (м: x — вправо, -y — вперёд, z — вверх; рост
# 2.4): под глазом сразу рот, поэтому низ глаза почти не двигается — глаз сжимается вверх, бровь
# опускается следом, а переход под глазом (где сдвиг мал) ничего не мнёт.
C = np.array([0.0, -0.56, 1.60])
# Овал глаза с бровью: центр, полуширина, вверх (до верха брови), вниз (до низа глаза); переход — до RAMP.
E = 1.88
AX, AZ_UP, AZ_DOWN, RAMP = 0.42, 0.55, 0.36, 1.3


def smooth(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
ob = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
for o in bpy.context.scene.objects:
    o.select_set(o == ob)
bpy.context.view_layer.objects.active = ob
ob.parent = None
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
v = np.array([x.co[:] for x in ob.data.vertices])
k = 2.4 / np.ptp(v[:, 2])
c = np.array([(v[:, 0].max() + v[:, 0].min()) / 2, (v[:, 1].max() + v[:, 1].min()) / 2, v[:, 2].min()])
v = (v - c) * k

dz = v[:, 2] - E
r = np.sqrt((v[:, 0] / AX) ** 2 + (dz / np.where(dz > 0, AZ_UP, AZ_DOWN)) ** 2)
w = 1 - smooth((r - 1) / (RAMP - 1))
w *= smooth((-0.22 - v[:, 1]) / 0.1)          # только лицевая сторона
w *= smooth((2.41 - v[:, 2]) / 0.03)          # верхний край головы на месте
v = v + (w * (S - 1))[:, None] * (v - C)
print("сдвинуто вершин:", int((w > 0.01).sum()), "целиком:", int((w > 0.99).sum()))
ob.data.vertices.foreach_set("co", v.astype(np.float32).ravel())
ob.data.update()
bpy.ops.export_scene.gltf(filepath=DST, export_format='GLB', use_selection=True,
                          export_image_format='JPEG', export_jpeg_quality=95)
print("ok", DST)
