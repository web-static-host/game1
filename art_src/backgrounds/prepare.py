## Слои фона для игры: картинки ChatGPT → assets/background/.
## Каждый слой режем по рисунку и сшиваем края так, что любые варианты слоя в любом
## порядке и с отражением стыкуются без шва: все варианты начинаются и кончаются тем же
## столбцом, что и первый. На краях столбцы плавно «перетекают»: силуэт тянется по высоте
## к общему, цвет смешивается, поэтому двойных контуров нет.
## Запуск: python3 art_src/backgrounds/prepare.py  (нужны Pillow и numpy)
import os
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', '..', 'assets', 'background')
EDGE = 0.22   # доля ширины на перетекание у каждого края
PAD = 0.3     # снизу дорисовываем столько (доля высоты): переход в ровный цвет низа.
              # Шейдер ниже картинки повторяет последнюю строку — она однотонная, без полос.

LAYERS = {
    'mountains': ['mountains_1', 'mountains_2'],
    'forest': ['forest_1', 'forest_2'],
    'hills': ['hills_1', 'hills_2'],
}
# Облака — рамки (x0, y0, x1, y1) в clouds.png.
CLOUDS = [(41, 96, 724, 404), (828, 98, 1515, 413), (471, 413, 1105, 682), (904, 659, 1496, 956), (49, 692, 815, 959)]
CLOUD_CELL = (384, 160)   # клетка атласа облаков (облако вписано в неё, по низу)


def load(name):
    a = np.asarray(Image.open(os.path.join(HERE, name + '.png')).convert('RGBA')).astype(np.float32) / 255.0
    a[..., :3] *= a[..., 3:4]   # премультиплицированный цвет — смешивать без тёмной каймы
    return a


def save(a, path):
    a = a.copy()
    al = a[..., 3:4]
    a[..., :3] = np.where(al > 1e-4, a[..., :3] / np.maximum(al, 1e-4), 0.0)
    Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)).save(path)


def top_of(col):
    """Верх силуэта в столбце (дробная строка, где альфа переходит 0.5)."""
    al = col[:, 3]
    idx = np.nonzero(al > 0.5)[0]
    if len(idx) == 0:
        return float(len(al))
    i = idx[0]
    if i == 0:
        return 0.0
    a0, a1 = al[i - 1], al[i]
    return i - 1 + (0.5 - a0) / max(1e-4, a1 - a0)


def stretch(col, top, target):
    """Растянуть столбец по высоте так, чтобы верх силуэта встал на target, низ — на месте."""
    h = len(col)
    r = np.arange(h, dtype=np.float32)
    s = top + (r - target) * (h - top) / max(1e-3, h - target)
    s = np.clip(s, 0, h - 1)
    i0 = np.floor(s).astype(int)
    i1 = np.minimum(i0 + 1, h - 1)
    f = (s - i0)[:, None]
    return col[i0] * (1 - f) + col[i1] * f


def morph(p, q, t):
    """Столбец между p и q (t: 0 → p, 1 → q)."""
    t = t * t * (3 - 2 * t)
    tp, tq = top_of(p), top_of(q)
    tg = tp + (tq - tp) * t
    return stretch(p, tp, tg) * (1 - t) + stretch(q, tq, tg) * t


def seam_layer(names):
    imgs = [load(n) for n in names]
    # Общая обрезка сверху: по самому высокому рисунку среди вариантов.
    y0 = min(int(np.nonzero(im[..., 3].max(axis=1) > 0.02)[0][0]) for im in imgs)
    y0 = max(0, y0 - 4)
    imgs = [im[y0:] for im in imgs]
    a = imgs[0]
    w = a.shape[1]
    e = int(w * EDGE)
    wo = w - e
    out = []
    for x in imgs:
        o = x[:, :wo].copy()
        # Начало: от столбца A[w-e+j] (им кончается первый вариант) к своему рисунку.
        for j in range(e):
            o[:, j] = morph(a[:, w - e + j], x[:, j], j / e)
        # Конец: от своего рисунка к A[wo-e+j], чтобы последний столбец был A[wo-1].
        if x is not a:
            for j in range(e):
                k = wo - e + j
                o[:, k] = morph(o[:, k], a[:, k], (j + 1) / e)
        out.append(o)
    return out, y0


def pad_bottom(imgs):
    """Продлить низ всех вариантов: нижние строки плавно уходят в общий средний цвет."""
    h = imgs[0].shape[0]
    n = int(h * PAD)
    base = np.mean([im[-max(4, h // 12):].reshape(-1, 4).mean(axis=0) for im in imgs], axis=0)
    out = []
    for im in imgs:
        last = im[-1]
        t = (np.arange(1, n + 1, dtype=np.float32) / n)[:, None, None]
        t = t * t * (3 - 2 * t)
        ext = last[None] * (1 - t) + base[None, None] * t
        out.append(np.concatenate([im, ext], axis=0))
    return out


def clouds():
    src = Image.open(os.path.join(HERE, 'clouds.png')).convert('RGBA')
    cw, ch = CLOUD_CELL
    atlas = Image.new('RGBA', (cw * len(CLOUDS), ch), (0, 0, 0, 0))
    for i, (x0, y0, x1, y1) in enumerate(CLOUDS):
        c = src.crop((x0, y0, x1, y1))
        bb = c.getchannel('A').point(lambda v: 255 if v > 8 else 0).getbbox()
        c = c.crop(bb)
        k = min((cw - 8) / c.width, (ch - 6) / c.height)
        c = c.resize((max(1, int(c.width * k)), max(1, int(c.height * k))), Image.LANCZOS)
        atlas.alpha_composite(c, (i * cw + (cw - c.width) // 2, ch - 3 - c.height))
    atlas.save(os.path.join(OUT, 'clouds.png'))
    print('clouds', atlas.size)


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    for layer, names in LAYERS.items():
        imgs, y0 = seam_layer(names)
        imgs = pad_bottom(imgs)
        for i, im in enumerate(imgs):
            save(im, os.path.join(OUT, '%s_%d.png' % (layer, i + 1)))
        print(layer, len(imgs), 'x', imgs[0].shape[1], imgs[0].shape[0], 'crop y0', y0, 'pad', imgs[0].shape[0] - (1024 - y0))
    clouds()
