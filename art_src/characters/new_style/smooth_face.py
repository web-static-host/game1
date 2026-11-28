## Тело модели Hunyuan без лица: глаз, бровь и рот (выпуклости и впадина рта) убираются, лицевая
## сторона — идеально гладкая. На такое тело лицо кладёт игра (слоем, как у старых моделей:
## мутации глаз, моргание, грустный рот работают). Текстура убирается — тело одного цвета.
##   python3 smooth_face.py <hunyuan.glb> <выход.glb>
## Как: тело переводится в объём (воксели, точное расстояние до поверхности со знаком). Лицевая
## сторона — карта глубины спереди; на месте глаза, брови и рта она достраивается бигармонически
## по настоящей поверхности вокруг (на границе совпадают и высота, и наклон — шва нет). Внутри лица
## всё, что впереди достроенной стороны, срезается, впадины за ней (рот, ложбинки) заполняются.
## Поверхность строится заново из объёма (marching cubes).
import sys

import bpy
import numpy as np
from scipy import ndimage
from scipy.spatial import cKDTree
from skimage import measure
from scipy import sparse
from scipy.sparse.linalg import spsolve

SRC, DST = sys.argv[1], sys.argv[2]


def smooth(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


H = 0.007          # воксель, м
# Где на лице рельеф (м: x — вправо, -y — вперёд, z — вверх; рост 2.4): овалы глаза с бровью и рта
# с запасом; самый верх (скругление к макушке) не трогаем.
EYE_OVAL = (0.0, 1.915, 0.47, 0.5)      # выпуклость глаза — от 1.42 (ниже белка) до макушки
MOUTH_OVAL = (0.0, 1.30, 0.31, 0.215)
TOP_KEEP = 2.43
# Профиль поперёк (по чистым бокам): до какой |x| на этой высоте рельеф.
ROW = 0.02


def feat_x(z):
    return 0.27 + 0.1 * smooth((z - 1.45) / 0.15)


def clean_w(z):
    """Ширина чистой полосы сбоку: до скругления края тела (край — 0.3 + (z − 0.75)·0.55)."""
    return np.clip(0.3 + (z - 0.75) * 0.55 - 0.08 - (feat_x(z) + 0.04), 0.06, 0.2)


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
ob = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
for o in bpy.context.scene.objects:
    o.select_set(o == ob)
bpy.context.view_layer.objects.active = ob
ob.parent = None
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
me = ob.data
v = np.array([p.co[:] for p in me.vertices])
k = 2.4 / np.ptp(v[:, 2])
c = np.array([(v[:, 0].max() + v[:, 0].min()) / 2, (v[:, 1].max() + v[:, 1].min()) / 2, v[:, 2].min()])
v = (v - c) * k
me.calc_loop_triangles()
tri = np.zeros(len(me.loop_triangles) * 3, dtype=np.int64)
me.loop_triangles.foreach_get("vertices", tri)
P = v[tri.reshape(-1, 3)]                    # (T, 3, 3)

# --- Объём: внутри/снаружи по чётности пересечений лучей вдоль y (через центры столбцов) -------
lo = np.array([-1.12, -0.75, -0.05])
n = np.ceil((np.array([1.12, 0.75, 2.47]) - lo) / H).astype(int)
gx = lo[0] + (np.arange(n[0]) + 0.5) * H
gy = lo[1] + (np.arange(n[1]) + 0.5) * H
gz = lo[2] + (np.arange(n[2]) + 0.5) * H
px, pz = P[:, :, 0], P[:, :, 2]
i0 = np.ceil((px.min(1) - lo[0]) / H - 0.5).astype(int)
i1 = np.floor((px.max(1) - lo[0]) / H - 0.5).astype(int)
k0 = np.ceil((pz.min(1) - lo[2]) / H - 0.5).astype(int)
k1 = np.floor((pz.max(1) - lo[2]) / H - 0.5).astype(int)
cols, ys = [], []
span = np.maximum(i1 - i0 + 1, 0) * np.maximum(k1 - k0 + 1, 0)
for s in range(1, span.max() + 1):
    sel = np.nonzero(span == s)[0]
    if len(sel) == 0:
        continue
    wi = i1[sel] - i0[sel] + 1
    a, b, cc = P[sel, 0], P[sel, 1], P[sel, 2]
    d = (b[:, 0] - a[:, 0]) * (cc[:, 2] - a[:, 2]) - (cc[:, 0] - a[:, 0]) * (b[:, 2] - a[:, 2])
    dd = np.where(d == 0, 1, d)
    for j in range(s):
        ii = i0[sel] + j % wi
        kk = k0[sel] + j // wi
        qx, qz = gx[np.clip(ii, 0, n[0] - 1)], gz[np.clip(kk, 0, n[2] - 1)]
        w1 = ((qx - a[:, 0]) * (cc[:, 2] - a[:, 2]) - (cc[:, 0] - a[:, 0]) * (qz - a[:, 2])) / dd
        w2 = ((b[:, 0] - a[:, 0]) * (qz - a[:, 2]) - (qx - a[:, 0]) * (b[:, 2] - a[:, 2])) / dd
        w0 = 1 - w1 - w2
        ins = (d != 0) & (w0 >= 0) & (w1 > 0) & (w2 >= 0) & (ii >= 0) & (ii < n[0]) & (kk >= 0) & (kk < n[2])
        if ins.any():
            cols.append((ii * n[2] + kk)[ins])
            ys.append((w0 * a[:, 1] + w1 * b[:, 1] + w2 * cc[:, 1])[ins])
cols = np.concatenate(cols)
ys = np.concatenate(ys)
o = np.lexsort((ys, cols))
cols, ys = cols[o], ys[o]
occ = np.zeros((n[0], n[2], n[1]), dtype=bool)
hf = np.full((n[0], n[2]), np.nan)          # глубина передней поверхности по столбцам
bad = np.zeros((n[0], n[2]), dtype=bool)
starts = np.r_[0, np.nonzero(np.diff(cols))[0] + 1, len(cols)]
for s0, s1 in zip(starts[:-1], starts[1:]):
    ci, ck = divmod(int(cols[s0]), int(n[2]))
    yy = ys[s0:s1]
    if len(yy) % 2:
        bad[ci, ck] = True
        continue
    hf[ci, ck] = yy[0]
    row = occ[ci, ck]
    for ya, yb in zip(yy[0::2], yy[1::2]):
        row[int(np.ceil((ya - lo[1]) / H - 0.5)):int(np.floor((yb - lo[1]) / H - 0.5)) + 1] = True
# Столбцы с нечётным числом пересечений (луч прошёл по ребру) — как у соседей.
NB = ((-1, 0), (1, 0), (0, -1), (0, 1))
for ci, ck in zip(*np.nonzero(bad)):
    around = [(ci + di, ck + dk) for di, dk in NB if 0 <= ci + di < n[0] and 0 <= ck + dk < n[2] and not bad[ci + di, ck + dk]]
    if around:
        occ[ci, ck] = np.mean([occ[i, j] for i, j in around], 0) > 0.5
        hs = [hf[i, j] for i, j in around if not np.isnan(hf[i, j])]
        hf[ci, ck] = np.mean(hs) if hs else np.nan
print("воксели %s, столбцов по соседям: %d" % (tuple(int(t) for t in n), int(bad.sum())))
occ = occ.transpose(0, 2, 1)                 # (x, y, z)

# --- Точное расстояние до поверхности (м, + внутри) -----------------------------------------
sd = (ndimage.distance_transform_edt(occ) - ndimage.distance_transform_edt(~occ)) * H
sd = np.where(occ, sd - 0.5 * H, sd + 0.5 * H)


def tri_dist(p, a, b, c):
    """Расстояние от точек p до треугольников abc (поштучно), по Эриксону."""
    ab, ac = b - a, c - a
    d1, d2 = (ab * (p - a)).sum(1), (ac * (p - a)).sum(1)
    d3, d4 = (ab * (p - b)).sum(1), (ac * (p - b)).sum(1)
    d5, d6 = (ab * (p - c)).sum(1), (ac * (p - c)).sum(1)
    va, vb, vc = d3 * d6 - d5 * d4, d5 * d2 - d1 * d6, d1 * d4 - d3 * d2
    den = va + vb + vc
    den = np.where(den == 0, 1e-12, den)
    q = a + ab * (vb / den)[:, None] + ac * (vc / den)[:, None]

    def safe(num, de):
        return np.where(de == 0, 0, num / np.where(de == 0, 1, de))
    tab, tac = safe(d1, d1 - d3), safe(d2, d2 - d6)
    tbc = safe(d4 - d3, (d4 - d3) + (d5 - d6))
    q = np.where(((va <= 0) & (d4 - d3 >= 0) & (d5 - d6 >= 0))[:, None], b + (c - b) * tbc[:, None], q)
    q = np.where(((vb <= 0) & (d2 >= 0) & (d6 <= 0))[:, None], a + ac * tac[:, None], q)
    q = np.where(((vc <= 0) & (d1 >= 0) & (d3 <= 0))[:, None], a + ab * tab[:, None], q)
    q = np.where(((d6 >= 0) & (d5 <= d6))[:, None], c, q)
    q = np.where(((d3 >= 0) & (d4 <= d3))[:, None], b, q)
    q = np.where(((d1 <= 0) & (d2 <= 0))[:, None], a, q)
    return np.linalg.norm(p - q, axis=1), q


band = np.nonzero(np.abs(sd) < 3.5 * H)
q = np.stack([gx[band[0]], gy[band[1]], gz[band[2]]], 1)
# Знак у поверхности — по нормали ближайшего треугольника (надёжнее чётности: та ошибается на
# мелких дырах сетки и даёт ямки).
tn = np.cross(P[:, 1] - P[:, 0], P[:, 2] - P[:, 0])
if (np.einsum('ij,ij->i', P.mean(1) - v.mean(0), tn)).sum() < 0:
    tn = -tn                                 # нормали — наружу
tn /= np.maximum(np.linalg.norm(tn, axis=1, keepdims=True), 1e-12)
# Кандидаты — по густым точкам на треугольниках (через ~4 мм: в сетке есть треугольники до 11 см,
# по одним центрам ближайший находится не всегда — отсюда были ямки).
edge = np.max([np.linalg.norm(P[:, i] - P[:, (i + 1) % 3], axis=1) for i in range(3)], 0)
nsub = np.clip(np.ceil(edge / 0.004).astype(int), 1, 40)
spts, sid = [P.mean(1)], [np.arange(len(P))]
for m in range(2, nsub.max() + 1):
    t = np.nonzero(nsub == m)[0]
    if len(t) == 0:
        continue
    bb = np.array([(i / m, j / m) for i in range(m + 1) for j in range(m + 1 - i)])
    pts_ = P[t, 0][:, None] * (1 - bb[:, 0] - bb[:, 1])[None, :, None] + P[t, 1][:, None] * bb[None, :, 0, None] \
        + P[t, 2][:, None] * bb[None, :, 1, None]
    spts.append(pts_.reshape(-1, 3))
    sid.append(np.repeat(t, len(bb)))
spts, sid = np.concatenate(spts), np.concatenate(sid)
tree = cKDTree(spts)
dist = np.empty(len(q))
inside = np.empty(len(q), dtype=bool)
for s0 in range(0, len(q), 200000):
    qq = q[s0:s0 + 200000]
    _, nb = tree.query(qq, k=12, workers=-1)
    nb = sid[nb]
    best = np.full(len(qq), np.inf)
    side = np.zeros(len(qq))
    for j in range(nb.shape[1]):
        t = nb[:, j]
        dj, cj = tri_dist(qq, P[t, 0], P[t, 1], P[t, 2])
        sj = np.einsum('ij,ij->i', qq - cj, tn[t])
        better = dj < best - 1e-9
        best = np.where(better, dj, best)
        side = np.where(better, sj, side)
    dist[s0:s0 + 200000] = best
    inside[s0:s0 + 200000] = np.where(np.abs(side) > 1e-4, side < 0, occ[tuple(b[s0:s0 + 200000] for b in band)])
print("знак у поверхности: не совпал с чётностью в %d вокселях" % int((inside != occ[band]).sum()))
sd[band] = np.where(inside, dist, -dist)

# --- Лицевая сторона без рельефа: бигармоническое достраивание карты глубины ---------------------
def biharmonic_fill(img, known):
    """Неизвестные клетки — решение Δ²u = 0 (гладко по высоте и наклону) при известных остальных."""
    ny, nx = img.shape
    N = ny * nx
    idx = np.arange(N).reshape(ny, nx)
    rows, colsl, vals = [], [], []
    for (dy, dx) in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        src = idx[max(0, -dy):ny - max(0, dy), max(0, -dx):nx - max(0, dx)].ravel()
        dst = idx[max(0, dy):ny - max(0, -dy) or None, max(0, dx):nx - max(0, -dx) or None].ravel()
        rows += [src, src]
        colsl += [dst, src]
        vals += [np.ones(len(src)), -np.ones(len(src))]
    L = sparse.csr_matrix((np.concatenate(vals), (np.concatenate(rows), np.concatenate(colsl))), shape=(N, N))
    M = (L.T @ L).tocsr()
    u = ~known.ravel()
    kk = known.ravel()
    x = img.ravel().astype(float).copy()
    rhs = -M[u][:, kk] @ x[kk]
    x[u] = spsolve(M[u][:, u].tocsc(), rhs)
    return x.reshape(ny, nx)


GX, GZ = np.meshgrid(gx, gz, indexing='ij')


def oval(o):
    return np.sqrt(((GX - o[0]) / o[2]) ** 2 + ((GZ - o[1]) / o[3]) ** 2)


r = np.minimum(oval(EYE_OVAL), oval(MOUTH_OVAL))
# Овалы, перемычка глаз—рот и полоса у макушки во всю ширину лица (край овала не должен
# пересекать скругление к макушке — там была бы зазубрина).
hole = ((r < 1) | ((np.abs(GX) < 0.32) & (GZ > 1.25) & (GZ < 1.65)) | ((np.abs(GX) < 0.45) & (GZ > 2.25))) & (GZ < TOP_KEEP)
win = (np.abs(GX) < 0.62) & (GZ > 0.95) & (GZ < 2.42)
known = win & ~hole & ~np.isnan(hf) & (hf < 0)
ix = np.nonzero(win.any(1))[0]
kz = np.nonzero(win.any(0))[0]
sub = (slice(ix[0], ix[-1] + 1), slice(kz[0], kz[-1] + 1))
# Основа — профиль поперёк по каждой высоте: y = a + b·x² по чистым бокам, сглажен по высоте
# (ровная лицевая сторона без горбов); поверх — бигармоническая поправка до настоящей поверхности
# вокруг (стык без шва).
AXc = np.abs(GX)
zs = np.arange(0.9, 2.46, ROW)
A, B = [], []
for zz in zs:
    kk = np.abs(gz - zz) < ROW * 0.75
    lo_x = float(feat_x(zz)) + 0.04
    m = kk[None, :] & (AXc > lo_x) & (AXc < lo_x + float(clean_w(zz))) & ~np.isnan(hf) & (hf < 0)
    if m.sum() < 6:
        A.append(np.nan)
        B.append(np.nan)
        continue
    (a_, b_), *_ = np.linalg.lstsq(np.stack([np.ones(m.sum()), AXc[m] ** 2], 1), hf[m], rcond=None)
    A.append(a_)
    B.append(b_)
A, B = np.array(A), np.array(B)
ok = ~np.isnan(A)
A = np.interp(zs, zs[ok], A[ok])
B = np.interp(zs, zs[ok], B[ok])
g = np.exp(-0.5 * (np.arange(-6, 7) * ROW / 0.035) ** 2)
g /= g.sum()
A = np.convolve(np.pad(A, 6, mode='edge'), g, 'same')[6:-6]
B = np.convolve(np.pad(B, 6, mode='edge'), g, 'same')[6:-6]
prof = np.interp(GZ, zs, A) + np.interp(GZ, zs, B) * AXc ** 2
resid = np.where(known, hf - prof, 0.0)
# Где тела нет (над макушкой, сбоку) — поправка 0: иначе она уходит туда свободно и тянет лицо.
pin = known | (win & np.isnan(hf))
corr = biharmonic_fill(resid[sub], pin[sub])
base = np.full((n[0], n[2]), np.nan)
base[sub] = prof[sub] + corr
ring = known & (r > 1) & (r < 1.25)
print("профиль у края лица: расхождение ср %.4f макс %.4f м (его снимает поправка)" % (
    np.abs(resid[ring]).mean(), np.abs(resid[ring]).max()))
print("лицо достроено: столбцов %d" % int(hole.sum()))

# Доля лица по столбцам: внутри овалов — целиком, за краем — плавно (там base = настоящая сторона).
wf = np.clip(ndimage.gaussian_filter(ndimage.binary_dilation(hole, iterations=3).astype(float), 2.0) * 1.6, 0, 1)
wf = np.where(np.isnan(base) | ~win, 0, wf)
base = np.where(np.isnan(base), 0, base)

# --- Срезать впереди, заполнить впадины за ней ------------------------------------------------
Y = gy[None, :, None]
Z = gz[None, None, :]
plane = Y - base[:, None, :]                 # + за лицевой стороной (внутри)
# Заполнить за лицевой стороной (впадина рта, ложбинки у глаза и брови), кроме самого верха:
# у макушки тело само скругляется назад.
depth = 0.4 * smooth((2.33 - Z) / 0.08)
slab = np.minimum(plane, depth - plane)
face = np.minimum(np.maximum(sd, slab), plane)
w = wf[:, None, :] * (Y < 0.1)
f = sd + w * (face - sd)
del plane, slab, face, w
verts, faces, _, _ = measure.marching_cubes(f, 0.0, spacing=(H, H, H))
verts += lo + 0.5 * H
print("новая сетка: вершин", len(verts), "граней", len(faces))

nm = bpy.data.meshes.new("Body")
nm.from_pydata(verts.tolist(), [], faces[:, ::-1].tolist())
nm.update()
new = bpy.data.objects.new("Body", nm)
bpy.context.scene.collection.objects.link(new)
bpy.data.objects.remove(ob, do_unlink=True)
for o in bpy.context.scene.objects:
    o.select_set(o == new)
bpy.context.view_layer.objects.active = new
sm = new.modifiers.new("Smooth", 'SMOOTH')
sm.factor = 0.5
sm.iterations = 2
bpy.ops.object.modifier_apply(modifier="Smooth")
bpy.ops.object.shade_smooth()

# Без текстуры: один материал, тело красит игра.
mat = bpy.data.materials.new("Body")
mat.use_nodes = True
mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.92, 0.92, 0.92, 1)
mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.6
nm.materials.append(mat)
bpy.ops.export_scene.gltf(filepath=DST, export_format='GLB', use_selection=True)
print("ok", DST)
