## Тело жителя заново — по силуэту прототипа ChatGPT (art_src/characters/prototype_chatgpt.png,
## вид спереди слева), вместо кривой скульптуры из BlueBuddy.blend.
## Силуэт берём с картинки, делаем строго симметричным и «надуваем» в объём: тонкие части
## (руки, ноги, пальцы) получают круглое сечение, широкие (голова-туловище) — плоский перед
## с мягко скруглёнными краями, на нём сидит лицо (y = -DEPTH). Ступни — отдельными
## эллипсоидами, вытянутыми вперёд. Поверхность снимается marching cubes — гладко и ровно.
## Масштаб: высота силуэта = 2,41 м; суставы скелета Buddy_ApprovedRig оказываются внутри
## рук и ног (проверено), поэтому позы в игре остаются те же.
## Оси как у скелета: x — вправо, y — вперёд/назад (лицо к -y), z — вверх, метры.
##   python3 art_src/characters/build_body.py <папка>   → <папка>/body.npz (вершины, треугольники)
import os
import sys
import numpy as np
from PIL import Image
from scipy import ndimage
from skimage import measure

HERE = os.path.dirname(os.path.abspath(__file__))
PROTO = os.path.join(HERE, 'prototype_chatgpt.png')
HEIGHT = 2.41          # от пола до макушки, м
STEP = 0.01            # шаг 3D-сетки, м
DEPTH = 0.385          # полутолщина туловища (лицо — чуть впереди, на y ≈ -0.40)
PROFILE = 4.0          # как резко толщина упирается в DEPTH: больше — площе перед, туже края
ANKLE = 0.3            # ниже — голень и ступня (силуэт ног книзу расширяется)
SHIN_R = 0.15          # толщина голени, м
FEET = ((0.29, -0.09, 0.12), (0.18, 0.27, 0.13))   # центр (x — по модулю) и полуоси ступни


def silhouette():
    """Маска силуэта спереди (симметричная), масштаб м/пиксель, центр x и низ в пикселях."""
    p = np.asarray(Image.open(PROTO).convert('RGB')).astype(int)[:, :930]
    m = (p[..., 2] - p[..., 0] > 60) & (p[..., 2] > 120)
    m = ndimage.binary_fill_holes(m)
    lab, n = ndimage.label(m)
    m = lab == (np.argmax(ndimage.sum(m, lab, range(1, n + 1))) + 1)
    ys, xs = np.nonzero(m)
    cx = (xs.min() + xs.max()) / 2.0
    # Симметрия: среднее маски и её отражения относительно центра, края сглажены.
    w = int(max(cx - xs.min(), xs.max() - cx)) + 20
    crop = m[:, int(cx) - w:int(cx) + w + 1].astype(np.float32)
    sym = ndimage.gaussian_filter((crop + crop[:, ::-1]) * 0.5, 2.5) > 0.5
    scale = HEIGHT / (ys.max() - ys.min())
    return sym, scale, w, ys.max()


def _inflate(inside):
    """«Надуть» силуэт: решение уравнения Пуассона (∇²h = -1, h = 0 на краю) даёт гладкий бугор
    без изломов; sqrt(2h) у полосы ширины 2w — ровно полукруг радиуса w (руки, ноги — круглые)."""
    from scipy.sparse import coo_matrix
    from scipy.sparse.linalg import spsolve
    idx = -np.ones(inside.shape, np.int64)
    pts = np.argwhere(inside)
    idx[inside] = np.arange(len(pts))
    rows, cols, vals = [np.arange(len(pts))], [np.arange(len(pts))], [np.full(len(pts), -4.0)]
    for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        ni, nj = pts[:, 0] + di, pts[:, 1] + dj
        ok = (ni >= 0) & (nj >= 0) & (ni < inside.shape[0]) & (nj < inside.shape[1])
        nb = np.full(len(pts), -1)
        nb[ok] = idx[ni[ok], nj[ok]]
        k = nb >= 0
        rows.append(np.arange(len(pts))[k]); cols.append(nb[k]); vals.append(np.ones(k.sum()))
    A = coo_matrix((np.concatenate(vals), (np.concatenate(rows), np.concatenate(cols)))).tocsr()
    h = spsolve(A, np.full(len(pts), -STEP * STEP))
    out = np.zeros(inside.shape)
    out[inside] = np.sqrt(2.0 * np.maximum(h, 0.0))
    return ndimage.gaussian_filter(out, 1.0)


def build_mesh():
    mask, s, cxp, bottom = silhouette()
    inside = ndimage.distance_transform_edt(mask) * s
    outside = ndimage.distance_transform_edt(~mask) * s
    sd2 = ndimage.gaussian_filter(outside - inside, 3.0)   # < 0 внутри силуэта; без ступенек пикселей
    # 3D-сетка в метрах → координаты в пикселях маски.
    xs = np.arange(-cxp * s, cxp * s, STEP)
    zs = np.arange(-0.02, HEIGHT + 0.06, STEP)
    ys = np.arange(-0.62, 0.62, STEP)
    X2, Z2 = np.meshgrid(xs, zs, indexing='ij')
    d2 = ndimage.map_coordinates(sd2, [bottom - Z2 / s, cxp + X2 / s], order=1, mode='nearest')
    g = _inflate(d2 < 0.0)
    g = (np.maximum(g, 1e-6) ** -PROFILE + DEPTH ** -PROFILE) ** (-1.0 / PROFILE)   # толще DEPTH не бывает — плоский перед
    Y = ys[None, :, None]
    F = np.maximum(np.abs(Y) - g[:, None, :], d2[:, None, :])
    # Ступни с картинки плоские (вид спереди) и расширяются книзу — ноги плавно обрезаем выше
    # щиколоток (скруглённый торец), ступни ставим объёмные.
    X3, Y3, Z3 = np.meshgrid(xs, ys, zs, indexing='ij')
    cut = ANKLE - Z3
    k = 0.06
    h = np.clip(0.5 + 0.5 * (cut - F) / k, 0.0, 1.0)
    F = F * (1 - h) + cut * h + k * h * (1 - h)
    # Голень от обреза до ступни — ровная, той же толщины, что нога на картинке.
    for sx in (1, -1):
        a = np.array([sx * FEET[0][0], 0.0, ANKLE + 0.15])
        ba = np.array([0.0, FEET[0][1] * 0.3, FEET[0][2] - ANKLE - 0.15])
        pa = np.stack([X3 - a[0], Y3 - a[1], Z3 - a[2]], -1)
        t = np.clip((pa @ ba) / (ba @ ba), 0.0, 1.0)
        shin = np.linalg.norm(pa - t[..., None] * ba, axis=-1) - SHIN_R
        h = np.clip(0.5 + 0.5 * (shin - F) / 0.05, 0.0, 1.0)
        F = shin * (1 - h) + F * h - 0.05 * h * (1 - h)
    # Ступни — вытянутые вперёд эллипсоиды, плавно слиты с ногами.
    for sx in (1, -1):
        c, r = FEET
        q = np.stack([(X3 - sx * c[0]) / r[0], (Y3 - c[1]) / r[1], (Z3 - c[2]) / r[2]], -1)
        k0 = np.linalg.norm(q, axis=-1)
        k1 = np.linalg.norm(q / np.array(r), axis=-1)
        foot = k0 * (k0 - 1.0) / np.maximum(k1, 1e-6)
        h = np.clip(0.5 + 0.5 * (foot - F) / 0.1, 0.0, 1.0)
        F = foot * (1 - h) + F * h - 0.1 * h * (1 - h)
    verts, faces, _, _ = measure.marching_cubes(F, 0.0, spacing=(STEP, STEP, STEP))
    verts += np.array([xs[0], ys[0], zs[0]])
    return verts.astype(np.float32), faces


if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else '.'
    v, f = build_mesh()
    np.savez(os.path.join(out, 'body.npz'), v=v, f=f)
    print('verts', len(v), 'faces', len(f), 'x', v[:, 0].min(), v[:, 0].max(), 'z', v[:, 2].min(), v[:, 2].max())
