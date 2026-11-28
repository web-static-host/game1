## Модель Hunyuan -> модель для игры: облегчить сетку, уменьшить текстуру, надеть скелет старой
## модели (те же имена костей — позы игры работают), кости переставить под новое тело.
##   python3 rig_hunyuan.py <hunyuan.glb> <старая модель со скелетом.glb> <выход.glb> [граней]
import sys

import bpy
import numpy as np

SRC, RIG, DST = sys.argv[1], sys.argv[2], sys.argv[3]
FACES = int(sys.argv[4]) if len(sys.argv) > 4 else 40000
TEX = 1024

# Суставы нового тела (м; x — вправо от гаврика, -y — вперёд, z — вверх), правая сторона:
# плечо у верха руки, рука висит почти отвесно, кисть 0.72–0.98; бедро, колено, щиколотка, носок.
JOINTS = {
    "Root": ((0, 0, 0), (0, 0, 0.78)),
    "Body": ((0, 0, 0.78), (0, 0, 1.6)),
    "Thigh": ((0.18, 0.02, 0.78), (0.19, 0.02, 0.48)),
    "Shin": ((0.19, 0.02, 0.48), (0.21, 0.02, 0.2)),
    "Foot": ((0.21, 0.02, 0.2), (0.26, -0.24, 0.08)),
    "UpperArm": ((0.86, 0.07, 1.7), (0.87, 0.0, 1.27)),
    "Forearm": ((0.87, 0.0, 1.27), (0.86, -0.04, 0.98)),
    "Hand": ((0.86, -0.04, 0.98), (0.87, -0.05, 0.86)),
}

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=RIG)
arm = [o for o in bpy.context.scene.objects if o.type == 'ARMATURE'][0]
for o in list(bpy.context.scene.objects):
    if o != arm:
        bpy.data.objects.remove(o, do_unlink=True)
arm.animation_data_clear()
for pb in arm.pose.bones:
    pb.matrix_basis.identity()

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
if abs(k - 1) < 1e-3:
    c[:] = 0      # уже в нужных осях (тело без лица из smooth_face.py: без глаза рамка по глубине другая)
ob.data.vertices.foreach_set("co", ((v - c) * k).astype(np.float32).ravel())
ob.data.update()

m = ob.modifiers.new("Dec", 'DECIMATE')
m.ratio = min(1.0, FACES / len(ob.data.polygons))
m.use_collapse_triangulate = True
bpy.ops.object.modifier_apply(modifier="Dec")
print("faces", len(ob.data.polygons))

# Материал: только цвет (матовый), текстура поменьше; карты нормалей и металла не нужны.
for mat in ob.data.materials:
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    if not bsdf.inputs["Base Color"].links:
        continue                  # тело без текстуры (smooth_face.py)
    base = bsdf.inputs["Base Color"].links[0].from_node
    for n in list(nt.nodes):
        if n not in (bsdf, base) and n.type != 'OUTPUT_MATERIAL':
            nt.nodes.remove(n)
    bsdf.inputs["Roughness"].default_value = 0.6
    bsdf.inputs["Metallic"].default_value = 0.0
    base.image.scale(TEX, TEX)
    base.image.name = "buddy_triangle_color"
ob.name = ob.data.name = "Buddy_FinalBody"

# Кости — на новые суставы (пальцы — под кистью, тело не двигают).
bpy.context.view_layer.objects.active = arm
for o in bpy.context.scene.objects:
    o.select_set(o == arm)
bpy.ops.object.mode_set(mode='EDIT')
eb = arm.data.edit_bones
for name, (h, t) in JOINTS.items():
    for sd, sx in ((".R", 1), (".L", -1)) if name not in ("Root", "Body") else (("", 1),):
        b = eb[name + sd]
        b.use_connect = False
        b.head = (h[0] * sx, h[1], h[2])
        b.tail = (t[0] * sx, t[1], t[2])
for sd, sx in ((".R", 1), (".L", -1)):
    for i in range(1, 5):
        b = eb["Finger%d%s" % (i, sd)]
        x = 0.8 + (i - 1) * 0.04 if sd == ".R" else 0.8 + (4 - i) * 0.04
        b.head = (x * sx, -0.05, 0.86)
        b.tail = (x * sx, -0.06, 0.76)
bpy.ops.object.mode_set(mode='OBJECT')
for b in arm.data.bones:
    b.use_deform = not b.name.startswith(("Finger", "Root"))

# Привязка: веса по геометрии (автоматические «по теплу» на этой сетке не находятся). Рука отделена
# от тела щелью ниже 1.45 м: всё, что дальше края тела, — рука (у плеча плавно переходит в тело);
# ниже 0.8 м — ноги (у середины — тело). Вдоль руки и ноги — по высоте суставов, с плавными стыками.
def smooth(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


def split(z, cuts, names, blend):
    """Доли костей по высоте: cuts — высоты стыков сверху вниз."""
    out = {}
    prev = np.ones_like(z)
    for cut, name, bl in zip(cuts, names, blend):
        below = smooth((cut + bl - z) / (2 * bl))
        out[name] = prev * (1 - below)
        prev = prev * below
    out[names[-1]] = prev
    return out


co = np.array([x.co[:] for x in ob.data.vertices])
ax, z = np.abs(co[:, 0]), co[:, 2]
# Граница — середина щели между телом и рукой (ниже 1.45 м), выше — плечо: шире и плавнее.
edge = np.interp(z, [1.0, 1.2, 1.4, 1.6, 1.8], [0.54, 0.62, 0.68, 0.74, 0.8])
width = 0.03 + smooth((z - 1.4) / 0.3) * 0.1
armw = smooth((ax - edge) / width + 0.5) * smooth((1.85 - z) / 0.25) * (z > 0.6)
legw = smooth((0.8 - z) / 0.15) * smooth(ax / 0.07) * (ax < 0.6)
w = {"Body": 1 - armw - legw}
for sd, on in ((".R", co[:, 0] > 0), (".L", co[:, 0] <= 0)):
    for n, part in split(z, (1.27, 0.98), ("UpperArm", "Forearm", "Hand"), (0.07, 0.04)).items():
        w[n + sd] = part * armw * on
    for n, part in split(z, (0.48, 0.2), ("Thigh", "Shin", "Foot"), (0.06, 0.04)).items():
        w[n + sd] = part * legw * on
for o in bpy.context.scene.objects:
    o.select_set(o in (arm, ob))
ob.parent = arm
mod = ob.modifiers.new("Armature", 'ARMATURE')
mod.object = arm
for name, ws in w.items():
    g = ob.vertex_groups.new(name=name)
    for i in np.nonzero(ws > 0.002)[0]:
        g.add([int(i)], float(ws[i]), 'REPLACE')
    print(name, int((ws > 0.5).sum()))

for o in bpy.context.scene.objects:
    o.select_set(o in (arm, ob))
bpy.ops.export_scene.gltf(filepath=DST, export_format='GLB', use_selection=True, export_animations=False,
                          export_image_format='JPEG', export_jpeg_quality=90, export_skins=True)
print("ok", DST)
