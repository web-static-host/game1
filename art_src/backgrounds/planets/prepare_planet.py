## Фон планеты из листа ChatGPT (art_src/backgrounds/planets/<планета>/sheet.png) → слои игры
## в assets/background/<планета>/: sky, mountains, hills, near, clouds.
## На листе нет настоящей прозрачности — вместо неё нарисована светлая «шахматка». Её убираем:
## нейтрально-серые светлые пиксели, связанные с верхом полосы (снежные вершины голубоватые и
## не трогаются). Края слоёв сшиваются как у земного фона (prepare.py): кусок кончается тем же
## столбцом, каким начинается, — стыкуется сам с собой и с отражением.
##   python3 art_src/backgrounds/planets/prepare_planet.py neptune
import os
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..'))
import prepare as P  # noqa: E402

OUT_ROOT = os.path.join(HERE, '..', '..', '..', 'assets', 'background')

## Рамки на листе (x0, y0, x1, y1) — с отступом внутрь от края панели.
SHEETS = {
    'neptune': {
        'sky': (8, 6, 784, 338),
        'clouds': (806, 2, 1534, 342),
        'mountains': (8, 346, 1528, 572),
        'hills': (8, 578, 1530, 782),
        'near': (8, 786, 1530, 1022),
    },
}


def checker(a):
    """Пиксели нарисованной шахматки: светлые и нейтрально-серые."""
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    return (np.abs(b - r) <= 5) & (np.abs(g - r) <= 5) & (a[..., :3].min(-1) > 222)


def cut_layer(rgb, closed=False):
    """Полоса слоя: фон — шахматка, связанная с верхним краем; мягкий край в 1 px."""
    a = rgb.astype(np.int32)
    bg = checker(a)
    lab, _ = ndimage.label(bg)
    top = set(np.unique(lab[:3])) - {0}
    # и с боковыми краями в верхней половине (между вершинами)
    h = a.shape[0]
    top |= set(np.unique(lab[:h // 2, :2])) - {0}
    top |= set(np.unique(lab[:h // 2, -2:])) - {0}
    if closed:
        top |= set(np.unique(lab[-3:])) - {0}
        top |= set(np.unique(lab[:, :2])) - {0}
        top |= set(np.unique(lab[:, -2:])) - {0}
    mask = ~np.isin(lab, list(top))
    # Края листа (низ и бока у полос) — не край рисунка: продлеваем маску наружу, иначе
    # эрозия и размытие делают их прозрачными.
    P_ = 6
    pm = np.pad(mask, P_, mode='edge')
    if closed:
        pm = np.pad(mask, P_, constant_values=False)
    pm = ndimage.binary_opening(pm, iterations=1)
    er1 = ndimage.binary_erosion(pm, iterations=1)
    er2 = ndimage.binary_erosion(pm, iterations=2)
    alpha = np.maximum(ndimage.gaussian_filter(er1.astype(np.float32), 0.7), er2)[P_:-P_, P_:-P_]
    mask = pm[P_:-P_, P_:-P_]
    # Цвет у края — от ближайшего пикселя изнутри (без светлой каймы шахматки).
    inner = er2[P_:-P_, P_:-P_]
    _, (iy, ix) = ndimage.distance_transform_edt(~inner, return_indices=True)
    col = rgb[iy, ix].astype(np.float32) / 255.0
    out = np.concatenate([col, alpha[..., None]], axis=-1)
    # Сверху — до рисунка.
    ys = np.nonzero(alpha.max(axis=1) > 0.02)[0]
    return out[max(0, ys[0] - 4):]


def premul(a):
    a = a.copy()
    a[..., :3] *= a[..., 3:4]
    return a


def seam(a):
    """Сшить края одного слоя (как P.seam_layer для одного варианта)."""
    w = a.shape[1]
    e = int(w * P.EDGE)
    wo = w - e
    o = a[:, :wo].copy()
    for j in range(e):
        o[:, j] = P.morph(a[:, w - e + j], a[:, j], j / e)
    return o


def clouds(rgb, out):
    a = rgb.astype(np.int32)
    mask = ~checker(a)
    mask = ndimage.binary_opening(mask, iterations=2)
    lab, n = ndimage.label(mask)
    boxes = sorted([s for s in ndimage.find_objects(lab) if (s[0].stop - s[0].start) * (s[1].stop - s[1].start) > 4000],
                   key=lambda s: -(s[0].stop - s[0].start) * (s[1].stop - s[1].start))[:5]
    cw, ch = P.CLOUD_CELL
    atlas = Image.new('RGBA', (cw * 5, ch), (0, 0, 0, 0))
    for i, s in enumerate(boxes):
        y0, y1 = max(0, s[0].start - 6), min(rgb.shape[0], s[0].stop + 6)
        x0, x1 = max(0, s[1].start - 6), min(rgb.shape[1], s[1].stop + 6)
        # Вокруг облака — шахматка со всех сторон: светлая рамка, чтобы фон был связан с верхом.
        sub = cut_layer(np.pad(rgb[y0:y1, x0:x1], ((8, 8), (8, 8), (0, 0)), constant_values=250), closed=True)
        im = Image.fromarray((np.clip(sub, 0, 1) * 255 + 0.5).astype(np.uint8))
        bb = im.getchannel('A').point(lambda v: 255 if v > 8 else 0).getbbox()
        im = im.crop(bb)
        k = min((cw - 8) / im.width, (ch - 6) / im.height)
        im = im.resize((max(1, int(im.width * k)), max(1, int(im.height * k))), Image.LANCZOS)
        atlas.alpha_composite(im, (i * cw + (cw - im.width) // 2, ch - 3 - im.height))
    atlas.save(os.path.join(out, 'clouds.png'))


def main(planet):
    src = np.asarray(Image.open(os.path.join(HERE, planet, 'sheet.png')).convert('RGB'))
    out = os.path.join(OUT_ROOT, planet)
    os.makedirs(out, exist_ok=True)
    boxes = SHEETS[planet]
    for name, (x0, y0, x1, y1) in boxes.items():
        part = src[y0:y1, x0:x1]
        if name == 'sky':
            Image.fromarray(part).save(os.path.join(out, 'sky.png'))
        elif name == 'clouds':
            clouds(part, out)
        else:
            lay = seam(premul(cut_layer(part)))
            lay = P.pad_bottom([lay])[0]
            P.save(lay, os.path.join(out, name + '.png'))
        im = Image.open(os.path.join(out, name + '.png'))
        print(planet, name, im.size)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'neptune')
