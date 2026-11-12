## Фон планеты из листа ChatGPT (art_src/backgrounds/planets/<планета>/sheet.png) → слои игры
## в assets/background/<планета>/: sky, mountains, hills, near, clouds.
## На листе нет настоящей прозрачности — вместо неё нарисована светлая «шахматка». Её убираем:
## нейтрально-серые светлые пиксели, связанные с верхом полосы (снежные вершины голубоватые и
## не трогаются). Края слоёв сшиваются как у земного фона (prepare.py): кусок кончается тем же
## столбцом, каким начинается, — стыкуется сам с собой и с отражением.
##   python3 art_src/backgrounds/planets/prepare_planet.py neptune mercury venus …
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


## --- Листы с настоящей прозрачностью (второй заход: Меркурий … Уран) -------------------
## Полосы на листе разделены прозрачными промежутками: первая — небо, следующие три — горы,
## холмы, ближний край, всё ниже — облака (если есть). Полоса слоя бывает уже прозрачной
## (рисунок на прозрачном) или непрозрачной — с небом за рисунком: тогда небо убираем —
## сверху вниз по столбцу, пока цвет плавно меняется и близок к цвету неба над ним; верх
## силуэта сглаживаем, отдельные клубы (дым, облака) над ним остаются.

def bands(a, thr=128):
    """Полосы листа по прозрачным промежуткам: [(y0, y1), …] (y1 — не включая)."""
    rows = (a[..., 3] > thr).mean(1) > 0.02
    out, y, h = [], 0, len(rows)
    while y < h:
        if rows[y]:
            s = y
            while y < h and rows[y]:
                y += 1
            if y - s > 20:
                out.append((s, y))
        y += 1
    return out


def sky_key(rgb, t_step=9.0, t_ref=16.0):
    """Маска рисунка (True) в полосе с небом: небо — то, что связано с верхом плавным цветом."""
    p = rgb.astype(np.float32)
    h, w = p.shape[:2]
    bg = np.zeros((h, w), bool)
    bg[0] = True
    ref = np.median(p[0], axis=0)
    for y in range(1, h):
        d_up = np.abs(p[y] - p[y - 1]).max(-1)
        d_ref = np.abs(p[y] - ref).max(-1)
        c = bg[y - 1] & (d_up < t_step) & (d_ref < t_ref)
        dl = np.zeros(w)
        dl[1:] = np.abs(p[y, 1:] - p[y, :-1]).max(-1)
        dr = np.zeros(w)
        dr[:-1] = dl[1:]
        for _ in range(3):
            lft = np.zeros(w, bool)
            lft[1:] = c[:-1]
            rgt = np.zeros(w, bool)
            rgt[:-1] = c[1:]
            c = c | (((lft & (dl < t_step)) | (rgt & (dr < t_step))) & (d_ref < t_ref))
        bg[y] = c
        if c.sum() > 20:
            ref = ref * 0.5 + np.median(p[y, c], axis=0) * 0.5
    fg = ~bg
    # Узкие «прорехи» неба, затёкшие в рисунок вдоль бледных склонов, — закрыть; дыры, не
    # связанные с верхом (небо между клубами дыма и склоном связано — остаётся), — залить.
    yy, xx = np.mgrid[-5:6, -5:6]
    disk = yy * yy + xx * xx <= 25
    fg = ndimage.binary_closing(np.pad(fg, 6, mode='edge'), structure=disk)[6:-6, 6:-6]
    sky = ~fg
    lab, n = ndimage.label(sky)
    top_ids = set(np.unique(lab[0])) - {0}
    fg = ~np.isin(lab, list(top_ids))
    # Мелкие крошки рисунка в небе — прочь.
    lab, n = ndimage.label(fg)
    sizes = ndimage.sum(np.ones_like(lab), lab, range(n + 1))
    return (sizes > 150)[lab] & fg


def soft(mask, rgb):
    """RGBA 0..1 из маски: край в 1 px мягкий, цвет у края — изнутри."""
    pad = 6
    pm = np.pad(mask, pad, mode='edge')
    pm = ndimage.binary_opening(pm, iterations=1)
    er1 = ndimage.binary_erosion(pm, iterations=1)
    er2 = ndimage.binary_erosion(pm, iterations=2)
    alpha = np.maximum(ndimage.gaussian_filter(er1.astype(np.float32), 0.7), er2)[pad:-pad, pad:-pad]
    inner = er2[pad:-pad, pad:-pad]
    _, (iy, ix) = ndimage.distance_transform_edt(~inner, return_indices=True)
    col = rgb[iy, ix].astype(np.float32) / 255.0
    return np.concatenate([col, alpha[..., None]], axis=-1)


def strip_layer(a):
    """Слой из полосы листа (RGBA 0..255): обрезка по бокам, небо — прочь, сверху — до рисунка."""
    xs = np.nonzero((a[..., 3] > 128).mean(0) > 0.5)[0]
    a = a[3:-2, xs[0] + 3:xs[-1] - 2]
    if (a[:4, :, 3] > 200).mean() > 0.95:
        out = soft(sky_key(a[..., :3]), a[..., :3])
        # Дым и облака, упёршиеся в верх полосы, — не срезаны ровной линией, а тают кверху.
        fade = np.clip(np.arange(out.shape[0], dtype=np.float32) / 30.0, 0.0, 1.0)
        out[..., 3] *= (fade * fade * (3 - 2 * fade))[:, None]
    else:
        out = a.astype(np.float32) / 255.0
        # Низ и бока полосы — край листа, не рисунка: там рисунок сплошной.
        out[-3:, :, 3] = np.maximum(out[-3:, :, 3], out[-4:-3, :, 3])
    ys = np.nonzero(out[..., 3].max(axis=1) > 0.02)[0]
    return out[max(0, ys[0] - 4):]


def rgba_clouds(a, out):
    """Облака с прозрачного куска листа → атлас 5 штук (как у Земли)."""
    al = a[..., 3] > 40
    lab, n = ndimage.label(ndimage.binary_closing(al, iterations=3))
    objs = [s for s in ndimage.find_objects(lab) if s is not None]
    objs = sorted(objs, key=lambda s: -(s[0].stop - s[0].start) * (s[1].stop - s[1].start))[:5]
    objs = sorted(objs, key=lambda s: (s[0].start // 80, s[1].start))
    cw, ch = P.CLOUD_CELL
    atlas = Image.new('RGBA', (cw * 5, ch), (0, 0, 0, 0))
    for i, s in enumerate(objs):
        im = Image.fromarray(a[s]).copy()
        k = min((cw - 8) / im.width, (ch - 6) / im.height)
        im = im.resize((max(1, int(im.width * k)), max(1, int(im.height * k))), Image.LANCZOS)
        atlas.alpha_composite(im, (i * cw + (cw - im.width) // 2, ch - 3 - im.height))
    atlas.save(os.path.join(out, 'clouds.png'))


def main_auto(planet):
    a = np.asarray(Image.open(os.path.join(HERE, planet, 'sheet.png')).convert('RGBA'))
    out = os.path.join(OUT_ROOT, planet)
    os.makedirs(out, exist_ok=True)
    bs = bands(a)
    y0, y1 = bs[0]
    xs = np.nonzero((a[y0:y1, :, 3] > 128).mean(0) > 0.5)[0]
    Image.fromarray(a[y0 + 4:y1 - 4, xs[0] + 4:xs[-1] - 4, :3]).save(os.path.join(out, 'sky.png'))
    for name, (y0, y1) in zip(['mountains', 'hills', 'near'], bs[1:4]):
        lay = seam(premul(strip_layer(a[y0:y1])))
        lay = P.pad_bottom([lay])[0]
        P.save(lay, os.path.join(out, name + '.png'))
    cl = os.path.join(out, 'clouds.png')
    if len(bs) > 4:
        rgba_clouds(a[bs[4][0]:], out)
    elif os.path.exists(cl):
        os.remove(cl)
    for name in ['sky', 'mountains', 'hills', 'near', 'clouds']:
        f = os.path.join(out, name + '.png')
        if os.path.exists(f):
            print(planet, name, Image.open(f).size)


def main(planet):
    if planet not in SHEETS:
        main_auto(planet)
        return
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
    for pl in (sys.argv[1:] or ['neptune']):
        main(pl)
