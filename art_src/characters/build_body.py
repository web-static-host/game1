## Тело жителя заново — из ровных форм по силуэту прототипа ChatGPT
## (art_src/characters/prototype_chatgpt.png), вместо кривой скульптуры из BlueBuddy.blend.
## Форма задаётся полем расстояний (голова-туловище, руки дугой, кисти с пальцами, ноги,
## ступни), части сливаются плавно (smin), поверхность снимается marching cubes — получается
## гладко и строго симметрично. Кости скелета остаются на своих местах (позы в игре те же).
## Оси как у скелета Buddy_ApprovedRig: x — вправо, y — вперёд/назад (лицо к -y), z — вверх, метры.
## Пробный рендер рядом с прототипом:  python3 art_src/characters/build_body.py <папка>
import os
import sys
import numpy as np
from skimage import measure

STEP = 0.01                      # шаг сетки поля, м
BOX = ((-1.85, 1.85), (-0.6, 0.6), (-0.02, 2.48))


def smin(a, b, k):
    """Плавное объединение двух полей (k — ширина «перехода», м)."""
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b * (1 - h) + a * h - k * h * (1 - h)


def capsule(P, a, b, r):
    a = np.asarray(a, np.float32)
    ba = np.asarray(b, np.float32) - a
    pa = P - a
    h = np.clip((pa @ ba) / (ba @ ba), 0.0, 1.0)
    return np.linalg.norm(pa - h[..., None] * ba, axis=-1) - r


def ellipsoid(P, c, rad):
    q = (P - np.asarray(c, np.float32)) / np.asarray(rad, np.float32)
    k0 = np.linalg.norm(q, axis=-1)
    k1 = np.linalg.norm(q / np.asarray(rad, np.float32), axis=-1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-6)


def round_cone_2d(x, z, z1, r1, z2, r2):
    """Трапеция со скруглёнными концами (2D, ось вертикальная): круг r1 на высоте z1 (низ),
    круг r2 на z2 (верх) и касательные между ними. Расстояние в плоскости xz."""
    px, py = np.abs(x), z - z1
    h = z2 - z1
    b = (r1 - r2) / h
    a = np.sqrt(max(1 - b * b, 1e-6))
    k = -px * b + py * a
    d_low = np.sqrt(px * px + py * py) - r1
    d_up = np.sqrt(px * px + (py - h) ** 2) - r2
    d_mid = px * a + py * b - r1
    return np.where(k < 0, d_low, np.where(k > a * h, d_up, d_mid))


def extrude_round(d2, y, half, rr):
    """Профиль d2 (в плоскости xz), вытянутый по y на ±half со скруглением краёв rr."""
    wx = d2 + rr
    wy = np.abs(y) - (half - rr)
    return (np.sqrt(np.maximum(wx, 0) ** 2 + np.maximum(wy, 0) ** 2)
            + np.minimum(np.maximum(wx, wy), 0.0) - rr)


def bezier(p0, p1, p2, n):
    t = np.linspace(0.0, 1.0, n)[:, None]
    return (1 - t) ** 2 * np.asarray(p0) + 2 * (1 - t) * t * np.asarray(p1) + t * t * np.asarray(p2)


# Размеры (м) — подобраны по прототипу.
HEAD_Z, HEAD_R, HEAD_X = 2.06, 0.35, 0.78      # верх головы — широкая скруглённая перекладина
BODY = (0.78, 0.27, 1.85, 0.66)                # трапеция туловища: низ z, радиус, верх z, радиус
DEPTH, DEPTH_R = 0.40, 0.22                    # туловище: полутолщина (лицо на y = -0.40), скругление
ARM_R = (0.165, 0.135)                         # толщина руки у плеча и у запястья
LEG_R = 0.155
FOOT = ((0.0, -0.07, 0.10), (0.19, 0.27, 0.115))


def field(P, bones):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    # Голова-туловище: перекладина сверху + трапеция вниз, вытянуто в толщину со скруглением.
    head2 = np.sqrt(np.maximum(np.abs(x) - HEAD_X, 0.0) ** 2 + (z - HEAD_Z) ** 2) - HEAD_R
    body2 = round_cone_2d(x, z, *BODY)
    d = extrude_round(smin(head2, body2, 0.12), y, DEPTH, DEPTH_R)
    for s in (1, -1):
        # Рука — дугой от края головы наружу и вниз, к запястью.
        wr = bones['Hand.R'][0]
        pts = np.vstack([bezier((0.95, 0.0, 2.02), (1.40, 0.0, 2.12), (1.38, 0.0, 1.40), 10),
                         bezier((1.38, 0.0, 1.40), (1.38, 0.0, 1.15), (wr[0], wr[1], wr[2]), 4)[1:]])
        pts[:, 0] *= s
        arm = None
        for i in range(len(pts) - 1):
            r = ARM_R[0] + (ARM_R[1] - ARM_R[0]) * i / (len(pts) - 2)
            c = capsule(P, pts[i], pts[i + 1], r)
            arm = c if arm is None else np.minimum(arm, c)
        d = smin(d, arm, 0.10)
        # Кисть: ладонь и четыре пальца (по костям пальцев).
        hc = bones['Hand.R']
        palm = ellipsoid(P, (s * hc[0][0], -0.02, 0.86), (0.15, 0.085, 0.13))
        hand = smin(palm, capsule(P, (s * wr[0], wr[1], wr[2]), (s * hc[1][0], -0.02, 0.86), 0.12), 0.04)
        for f in range(1, 5):
            h0, t0 = bones['Finger%d.R' % f]
            t = np.asarray(h0) + (np.asarray(t0) - np.asarray(h0)) * 0.92
            hand = smin(hand, capsule(P, (s * h0[0], -0.02, h0[2]), (s * t[0], -0.03, t[2]), 0.048), 0.03)
        d = smin(d, hand, 0.05)
        # Нога и ступня.
        th = bones['Thigh.R'][0]
        an = bones['Shin.R'][1]
        leg = capsule(P, (s * th[0], 0.0, th[2] + 0.1), (s * an[0], 0.0, an[2] + 0.04), LEG_R)
        fc = (s * an[0] + FOOT[0][0], FOOT[0][1], FOOT[0][2])
        leg = smin(leg, ellipsoid(P, fc, FOOT[1]), 0.07)
        d = smin(d, leg, 0.10)
    return d


# Кости правой стороны (голова, хвост) — как в Buddy_ApprovedRig; левая — зеркально.
BONES = {
    'Forearm.R': ((1.38, 0.0, 1.54), (1.38, 0.0, 0.98)),
    'Hand.R': ((1.38, 0.0, 0.98), (1.38, -0.02, 0.81)),
    'Finger1.R': ((1.27, -0.01, 0.89), (1.13, -0.03, 0.65)),
    'Finger2.R': ((1.35, -0.01, 0.89), (1.30, -0.03, 0.54)),
    'Finger3.R': ((1.42, -0.01, 0.89), (1.47, -0.03, 0.54)),
    'Finger4.R': ((1.50, -0.01, 0.89), (1.64, -0.03, 0.65)),
    'Thigh.R': ((0.26, 0.0, 0.70), (0.27, 0.0, 0.43)),
    'Shin.R': ((0.27, 0.0, 0.43), (0.29, 0.0, 0.17)),
}


def build_mesh(bones=BONES, step=STEP):
    """Вершины и треугольники тела (оси скелета, метры)."""
    axes = [np.arange(lo, hi + step * 0.5, step, dtype=np.float32) for lo, hi in BOX]
    X, Y, Z = np.meshgrid(*axes, indexing='ij')
    P = np.stack([X, Y, Z], -1)
    d = field(P, bones)
    verts, faces, _, _ = measure.marching_cubes(d, 0.0, spacing=(step, step, step))
    verts += np.array([BOX[0][0], BOX[1][0], BOX[2][0]], np.float32)
    return verts, faces


if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else '.'
    v, f = build_mesh()
    np.savez(os.path.join(out, 'body.npz'), v=v, f=f)
    print('verts', len(v), 'faces', len(f))
