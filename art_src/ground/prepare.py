## Текстуры земли для игры: картинки ChatGPT → assets/ground/.
## - rock_1..3: серые пласты породы. Сшиты по обеим осям (бесшовные), уменьшены до 512 px,
##   яркость приведена к среднему MEAN — игра красит их цветом породы, умножая на цвет / MEAN.
## - fog: фактура неразведанной земли (картинка ChatGPT fog.png), одна на весь мир —
##   по ней нельзя угадать, что под землёй. Обрабатывается как rock_*.
## - grass_edge, snow_edge: кромка поверх земли. Обрезаны по рисунку, сшиты по горизонтали.
## Запуск: python3 art_src/ground/prepare.py  (нужны Pillow и numpy)
import os
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', '..', 'assets', 'ground')
EDGE = 0.12      # доля размера на перетекание при сшивке
MEAN = 0.7       # средняя яркость текстуры породы (как в ChunkView.ROCK_MEAN)
REL_STD = 0.12   # разброс яркости относительно среднего — полосы видны, но не пестрят
FOG_REL_STD = 0.06   # туман занимает почти весь экран — фактура вдвое мягче
ROCK_SIZE = 512
# Кромки: (файл, строки рисунка от–до, строка «линии земли» в исходнике).
EDGES = [('grass_edge', 470, 646, 560), ('snow_edge', 588, 681, 630)]
EDGE_W = 1024    # ширина кромки в текстуре


def seam_x(a, e):
    """Бесшовность по x: первые e столбцов перетекают из столбцов за краем."""
    w = a.shape[1]
    out = a[:, :w - e].copy()
    t = (np.arange(e, dtype=np.float32) / e)
    t = t * t * (3 - 2 * t)
    t = t.reshape((1, e) + (1,) * (a.ndim - 2))
    out[:, :e] = a[:, w - e:] * (1 - t) + a[:, :e] * t
    return out


def rock(name):
    g = np.asarray(Image.open(os.path.join(HERE, name + '.png')).convert('L')).astype(np.float32) / 255.0
    n = min(g.shape)
    g = g[:n, :n]
    e = int(n * EDGE)
    g = seam_x(g, e)
    g = seam_x(g.T, e).T
    m, s = g.mean(), g.std()
    g = MEAN + (g - m) / s * (MEAN * (FOG_REL_STD if name == 'fog' else REL_STD))
    im = Image.fromarray((np.clip(g, 0, 1) * 255 + 0.5).astype(np.uint8)).resize((ROCK_SIZE, ROCK_SIZE), Image.LANCZOS)
    im.convert('RGB').save(os.path.join(OUT, name + '.png'))
    print(name, 'mean', round(float(m), 3), '->', MEAN)


def edge(name, y0, y1, line):
    a = np.asarray(Image.open(os.path.join(HERE, name + '.png')).convert('RGBA')).astype(np.float32) / 255.0
    a = a[y0:y1]
    a[..., :3] *= a[..., 3:4]      # смешиваем в премультиплицированном виде
    a = seam_x(a, int(a.shape[1] * EDGE))
    al = a[..., 3:4]
    a[..., :3] = np.where(al > 1e-4, a[..., :3] / np.maximum(al, 1e-4), 0)
    h = round(EDGE_W * a.shape[0] / a.shape[1])
    im = Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)).resize((EDGE_W, h), Image.LANCZOS)
    im.save(os.path.join(OUT, name + '.png'))
    print(name, im.size, 'линия земли на доле высоты', round((line - y0) / (y1 - y0), 3))


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    for n in ('rock_1', 'rock_2', 'rock_3', 'fog'):
        if os.path.exists(os.path.join(HERE, n + '.png')):
            rock(n)
    for e in EDGES:
        edge(*e)
