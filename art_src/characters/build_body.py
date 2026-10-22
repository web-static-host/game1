## Тело жителя заново — по силуэту прототипа ChatGPT (art_src/characters/prototype_chatgpt.png,
## вид спереди слева), вместо кривой скульптуры из BlueBuddy.blend.
## Голова, плечи, руки и кисти: силуэт с картинки делаем строго симметричным и «надуваем» в объём
## (тонкие части — круглого сечения, голова — плоский перед под лицом, края мягко скруглены).
## Низ туловища, ноги и ступни — гладкими формами по размерам с картинки (на «надутом» силуэте
## там получались уступы): туловище — сечения-суперэллипсы по ширине с картинки, ноги — ровные
## трубки, ступни — низкие купола; всё слито плавно (smin по нормированным полям), пах — арка.
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
# Форма: triangle — как на прототипе; square — туловище прямоугольником (BODY_SHAPE=square).
SHAPE = os.environ.get('BODY_SHAPE', 'triangle')
SQ_HALF = 0.62         # квадратный: полуширина туловища, м
SQ_BOTTOM = 0.6        # низ прямоугольника (у паха), м
SQ_LEGS = 0.42         # внешний край ног у паха (как у треугольного), м
SQ_TOP = 1.72          # выше — голова и плечи как у треугольного
SQ_ROUND = 0.24        # скругление низа к ногам, м
SQ_FILLET = 0.14       # скругление вогнутых углов под головой, м
HEIGHT = 2.41          # от пола до макушки, м
STEP = 0.01            # шаг 3D-сетки, м
DEPTH = 0.385          # полутолщина туловища (лицо — чуть впереди, на y ≈ -0.40)
RIM = 0.08             # скругление края «надутой» части (бока головы и рук), м
PROFILE = 4.0          # как резко толщина упирается в DEPTH: больше — площе перед, туже края
LOW = (1.25, 1.45)     # ниже — туловище из сечений (между — плавный переход к «надутому»)
ARMS_X = 0.85          # дальше от середины — руки и кисти («надутые»)
LOW_DEPTH = 0.36       # полутолщина туловища на высоте LOW[1] (у ног — LEG_R)
LOW_N = 3.4            # показатель суперэллипса сечения туловища (у ног — 2, круг)
CROTCH_Z = 0.64        # вершина арки паха (как на картинке)
SMOOTH_ABS = 0.12      # сглаживание |x| у середины: больше — круглее арка и мягче перед, м
ARCH_H = 0.08          # от этой высоты под вершиной просвет между ногами начинает закрываться, м
MERGE_H = 0.35         # над аркой ноги ещё столько сходятся в туловище, м
LEG_BOTTOM = 0.12      # низ ноги (центр ступни под ним)
LEG_R = 0.157          # полутолщина ноги спереди-назад, м
FOOT_R = (0.21, 0.32, 0.22)    # полуоси ступни: в стороны, вперёд-назад, вверх (центр чуть над полом)
FOOT_OUT = 0.09        # ступня смещена наружу (как на картинке)
FOOT_FWD = 0.1         # и вперёд
FOOT_LIFT = 0.04       # центр ступни над полом — бока круглые, подошва плоская
SOLE_R = 0.05          # скругление края подошвы


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
    # Верх головы на картинке слегка волнистый — заменяем его гладкой кривой (чётный многочлен
    # по x), руки по бокам не трогаем.
    cols = np.arange(sym.shape[1])
    xm = (cols - w) * scale
    top = np.array([np.argmax(sym[:, c]) if sym[:, c].any() else -1 for c in cols])
    sel = (np.abs(xm) < 1.2) & (top >= 0)
    coef = np.polyfit(xm[sel] ** 2, top[sel], 3)
    for c in cols[np.abs(xm) < 1.25]:
        t = int(round(np.polyval(coef, xm[c] ** 2)))
        k = np.clip((1.25 - abs(xm[c])) / 0.1, 0.0, 1.0)   # к краю — плавно к исходному контуру
        t = int(round(t * k + top[c] * (1 - k))) if top[c] >= 0 else t
        sym[:t, c] = False
        sym[t:top[c] + 1, c] = True if top[c] >= 0 and t < top[c] else sym[t:top[c] + 1, c]
    if SHAPE == 'square':
        sym = _square_torso(sym, scale, w, ys.max())
    return sym, scale, w, ys.max()


def _square_torso(sym, scale, w, bottom):
    """Квадратный гаврик: туловище — прямой прямоугольник (не сужается книзу), низ скруглён к
    ногам, вверху плавно переходит под голову. Голова, руки, кисти, ноги — как у треугольного."""
    H, W = sym.shape
    rr, cc = np.mgrid[0:H, 0:W]
    z = (bottom - rr) * scale
    x = np.abs(cc - w) * scale
    # Половина ширины прямоугольника по высоте: внизу — скругление к ногам.
    z0, r = SQ_BOTTOM, SQ_ROUND
    # Ноги у паха — как у треугольного (снаружи ~0.42 м); прямоугольник книзу плавно (четверть
    # эллипса) сужается ровно до них — ноги идут прямо, без перехвата.
    legs = SQ_LEGS
    t = np.clip((z0 + r - z) / r, 0.0, 1.0)
    half = legs + (SQ_HALF - legs) * np.sqrt(1.0 - t * t)
    rect = (x <= half) & (z >= z0) & (z <= SQ_TOP)
    # Прежнее туловище между ногами и головой убираем (руки дальше от середины не трогаем).
    band = (z > z0) & (z < SQ_TOP) & (x < SQ_HALF + 0.12)
    out = (sym & ~band) | rect
    # Вогнутые углы под головой — мягко (закрытие = расширение + сужение).
    k = max(1, int(round(SQ_FILLET / scale)))
    disk = np.hypot(*np.mgrid[-k:k + 1, -k:k + 1]) <= k
    closed = np.pad(out, k + 2)
    closed = ndimage.binary_erosion(ndimage.binary_dilation(closed, disk), disk)[k + 2:-k - 2, k + 2:-k - 2]
    # Только у туловища (кисти и пальцы не трогаем — иначе пальцы слипнутся).
    near = (x < SQ_HALF + 0.3) & (z > z0 - 0.05) & (z < SQ_TOP + 0.25)
    out = np.where(near, closed, out)
    return ndimage.gaussian_filter(out.astype(np.float32), 3.0) > 0.5


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


def _smin(a, b, k):
    """Плавное объединение полей (k — ширина перехода, м)."""
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b * (1 - h) + a * h - k * h * (1 - h)


def _smax(a, b, k):
    """Плавное пересечение полей."""
    return -_smin(-a, -b, k)


def _smooth(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


def _metric(f):
    """Поле → примерно расстояние (делим на длину градиента): иначе плавные слияния неровные."""
    gx, gy, gz = np.gradient(f, STEP)
    return f / np.maximum(np.sqrt(gx * gx + gy * gy + gz * gz), 0.05)


def _center_halfwidth(mask, s, cxp, bottom, z):
    """Полуширина туловища на высоте z (участок силуэта, содержащий середину), м."""
    row = mask[int(round(bottom - z / s))]
    l = r = cxp
    while l > 0 and row[l - 1]:
        l -= 1
    while r < len(row) - 1 and row[r + 1]:
        r += 1
    return (r - l + 1) * 0.5 * s


def _leg_profiles(mask, s, cxp, bottom):
    """Гладкие кривые по высоте: внешний край (туловище и ноги) и внутренний край ног, м от середины.
    Внешний — с картинки (участок у середины), ниже щиколоток (там уже ступни) — продолжение
    прямой ноги; внутренний край ног — прямая по картинке."""
    from scipy.interpolate import UnivariateSpline
    zs, outs, ins = [], [], []
    for z in np.arange(0.3, LOW[1] + 0.15, 0.01):
        row = mask[int(round(bottom - z / s))]
        on = np.nonzero(row[cxp - int(0.75 / s):cxp + int(0.75 / s)])[0] - int(0.75 / s)
        if len(on) == 0:
            continue
        zs.append(z)
        outs.append((np.abs(on).max() + 0.5) * s)
        ins.append((np.abs(on).min() - 0.5) * s if not row[cxp] else 0.0)
    zs, outs, ins = np.array(zs), np.array(outs), np.array(ins)
    leg = zs < 0.55
    po = np.polyfit(zs[leg], outs[leg], 1)
    pi = np.polyfit(zs[leg & (ins > 0)], ins[leg & (ins > 0)], 1)
    zz = np.concatenate([np.arange(0.0, 0.3, 0.01), zs])
    oo = np.concatenate([np.polyval(po, np.arange(0.0, 0.3, 0.01)), outs])
    spl = UnivariateSpline(zz, oo, s=len(zz) * 0.004 ** 2)
    outer = lambda z: spl(np.clip(z, 0.0, LOW[1] + 0.12))
    inner = lambda z: np.polyval(pi, z)
    return outer, inner


def _foot(x, y, z, side):
    """Поле ступни (ось ноги — x = 0, y = 0; side — к внешней стороне): низкий купол — половина
    эллипсоида с плоской подошвой и скруглённым краем; с ногой сливается плавной галтелью."""
    c = np.array([side * FOOT_OUT, -FOOT_FWD, FOOT_LIFT])
    r = np.array(FOOT_R)
    q = np.stack([(x - c[0]) / r[0], (y - c[1]) / r[1], (z - c[2]) / r[2]], -1)
    k0 = np.linalg.norm(q, axis=-1)
    k1 = np.linalg.norm(q / r, axis=-1)
    d = k0 * (k0 - 1.0) / np.maximum(k1, 1e-6)
    k = SOLE_R      # подошва: пересечение с полупространством z > 0 со скруглением
    h = np.clip(0.5 + 0.5 * (-z - d) / k, 0.0, 1.0)
    return d * (1 - h) + (-z) * h + k * h * (1 - h)


def build_mesh():
    mask, s, cxp, bottom = silhouette()
    inside = ndimage.distance_transform_edt(mask) * s
    outside = ndimage.distance_transform_edt(~mask) * s
    sd2 = ndimage.gaussian_filter(outside - inside, 3.0)   # < 0 внутри силуэта; без ступенек пикселей
    # Верх головы и плечи — без мелких бугорков с картинки: там контур сглаживаем сильнее
    # (пальцы и лицо ниже — не трогаем).
    H = sd2.shape[0]
    zrow = (bottom - np.arange(H)) * s
    wtop = np.clip((zrow - 1.75) / 0.2, 0.0, 1.0)[:, None]
    sd2 = sd2 * (1 - wtop) + ndimage.gaussian_filter(outside - inside, 14.0) * wtop
    # 3D-сетка в метрах → координаты в пикселях маски.
    xs = np.arange(-cxp * s, cxp * s, STEP)
    zs = np.arange(-0.02, HEIGHT + 0.06, STEP)
    ys = np.arange(-0.62, 0.62, STEP)
    X2, Z2 = np.meshgrid(xs, zs, indexing='ij')
    d2 = ndimage.map_coordinates(sd2, [bottom - Z2 / s, cxp + X2 / s], order=1, mode='nearest')
    g = _inflate(d2 < 0.0)
    # Толщина считается по клеточкам — у края ступеньки; над плечами (рука и голова, пальцев нет)
    # сглаживаем сильнее, иначе по верху головы мелкие бугорки.
    wtop = np.clip((Z2 - 1.6) / 0.2, 0.0, 1.0)
    g = g * (1 - wtop) + ndimage.gaussian_filter(g, 4.0) * wtop
    # Толще DEPTH не бывает — плоский перед под лицом.
    g = (np.maximum(g, 1e-6) ** -PROFILE + DEPTH ** -PROFILE) ** (-1.0 / PROFILE)
    Y = ys[None, :, None]
    # Край: где толщина и контур сходятся — скругляем (иначе по бокам две полоски-ребра); |y| —
    # сглаженный (иначе по середине края полоска), толщина при этом ровно g.
    F_up = _smax(np.sqrt(Y * Y + 0.04 ** 2) - np.sqrt(g[:, None, :] ** 2 + 0.04 ** 2), np.broadcast_to(d2[:, None, :], (len(xs), len(ys), len(zs))), RIM)
    X3, Y3, Z3 = np.meshgrid(xs, ys, zs, indexing='ij')
    F_up = _metric(F_up)
    w = _smooth((Z3 - LOW[0]) / (LOW[1] - LOW[0]))
    arms = np.abs(X3) > ARMS_X
    # Низ туловища с ногами — одна гладкая форма: сечение по высоте — «две трубки» (ноги), которые
    # кверху толстеют и сходятся к середине, сливаясь в туловище (суперэллипс с плоским передом).
    # Трубки построены по сглаженному |x| (sqrt(x² + E²)) — слияние без складок и колец, а верх
    # просвета между ногами сам выходит скруглённой аркой. Внешний край = контур картинки, внутренний
    # край ног = просвет с картинки; всё — гладкие кривые по высоте.
    from scipy.interpolate import PchipInterpolator
    outer, inner = _leg_profiles(mask, s, cxp, bottom)
    zz = zs
    E = SMOOTH_ABS
    oc = np.sqrt(outer(zz) ** 2 + E * E)              # c + a: внешний край ровно по контуру
    z1, z2 = CROTCH_Z - ARCH_H, CROTCH_Z + MERGE_H
    kz = np.concatenate([np.arange(0.0, z1 + 1e-6, 0.05), [CROTCH_Z], np.arange(z2, LOW[1] + 0.2, 0.05)])
    kh = np.concatenate([np.sqrt(inner(np.arange(0.0, z1 + 1e-6, 0.05)) ** 2 + E * E), [E],
                         -np.sqrt(outer(np.arange(z2, LOW[1] + 0.2, 0.05)) ** 2 + E * E)])
    h = PchipInterpolator(kz, kh)(np.clip(zz, 0.0, LOW[1] + 0.15))   # c - a
    c3 = ((oc + h) / 2)[None, None, :]
    a3 = ((oc - h) / 2)[None, None, :]
    t = _smooth((zz - (CROTCH_Z - 0.1)) / (LOW[1] - CROTCH_Z + 0.1))[None, None, :]
    b3 = LEG_R + (LOW_DEPTH - LEG_R) * t
    n3 = 2.0 + (LOW_N - 2.0) * t
    u = np.sqrt(X3 * X3 + E * E) - c3
    q = (np.abs(u) / a3) ** n3 + (np.abs(Y3) / b3) ** n3
    F_lo = _metric(q ** (1.0 / n3) - 1.0)
    F_lo = _smax(F_lo, LEG_BOTTOM - Z3, 0.1)          # ноги кончаются в ступнях, не у пола
    F = np.where(arms, F_up, F_lo * (1 - w) + F_up * w)
    foot_x = float(np.sqrt(np.maximum(c3[0, 0, np.argmin(np.abs(zz - LEG_BOTTOM))] ** 2 - E * E, 0.0)))
    for sx in (1, -1):
        # Ступня — низкий купол с плоской подошвой, шире ноги (в стороны и вперёд), как на прототипе.
        F = _smin(F, _metric(_foot(X3 - sx * foot_x, Y3, Z3, sx)), 0.14)
    verts, faces, _, _ = measure.marching_cubes(F, 0.0, spacing=(STEP, STEP, STEP))
    verts += np.array([xs[0], ys[0], zs[0]])
    return verts.astype(np.float32), faces


if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else '.'
    v, f = build_mesh()
    np.savez(os.path.join(out, 'body.npz'), v=v, f=f)
    print('verts', len(v), 'faces', len(f), 'x', v[:, 0].min(), v[:, 0].max(), 'z', v[:, 2].min(), v[:, 2].max())
