## Нарезка листов иконок ChatGPT в отдельные PNG для игры (assets/icons/).
## Каждая иконка — по рамке своей клетки сетки, обрезана по рисунку и вписана в квадрат.
## Запуск: python3 art_src/icons/cut_icons.py  (нужен Pillow)
import os
from collections import deque
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', '..', 'assets', 'icons')
SIZE = 96      # сторона иконки в игре (px); в интерфейсе они 20–40 px, с запасом под зум

SHEETS = [
    # (файл, столбцов, строк, имена по строкам)
    ('resources_sheet.png', 5, 5, [
        'wood', 'stone', 'clay', 'food', 'berries',
        'coal', 'iron', 'copper', 'silver', 'gold',
        'uranium', 'diamond', 'salt', 'oil', 'limestone',
        'brick', 'metal', 'methane', 'soil', 'sand',
        'gravel', 'people', 'power', 'health', 'science']),
    ('weather_sheet.png', 4, 2, [
        'weather_sun', 'weather_sun_cloud', 'weather_cloud', 'weather_rain',
        'weather_snow', 'weather_storm', 'weather_fog', 'weather_moon']),
]


def clean(cell):
    """Убрать из клетки обрезки соседних иконок: мелкие пятна у края клетки.
    Отдельные детали внутри (снежинки, капли, звёзды) остаются."""
    a = np.asarray(cell.getchannel('A')) > 24
    h, w = a.shape
    lab = np.zeros((h, w), dtype=np.int32)
    sizes, edge = [0], [False]
    for y0, x0 in zip(*np.nonzero(a)):
        if lab[y0, x0]:
            continue
        n = len(sizes)
        lab[y0, x0] = n
        q = deque([(y0, x0)])
        cnt, touch = 0, False
        while q:
            y, x = q.popleft()
            cnt += 1
            touch |= y == 0 or x == 0 or y == h - 1 or x == w - 1
            for yy, xx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                if 0 <= yy < h and 0 <= xx < w and a[yy, xx] and not lab[yy, xx]:
                    lab[yy, xx] = n
                    q.append((yy, xx))
        sizes.append(cnt)
        edge.append(touch)
    big = max(sizes)
    keep = np.zeros(len(sizes), dtype=bool)
    for i in range(1, len(sizes)):
        keep[i] = sizes[i] >= 0.3 * big or (not edge[i] and sizes[i] >= 20)
    arr = np.array(cell)
    # Полупрозрачная кайма (альфа <= 24) у выброшенных пятен — тоже убрать: оставляем
    # только пиксели рядом с сохранёнными областями.
    kept = keep[lab]
    grown = kept.copy()
    for _ in range(3):
        g = grown.copy()
        g[1:] |= grown[:-1]; g[:-1] |= grown[1:]; g[:, 1:] |= grown[:, :-1]; g[:, :-1] |= grown[:, 1:]
        grown = g
    arr[..., 3] = np.where(grown, np.array(cell)[..., 3], 0)
    return Image.fromarray(arr)


def cut(sheet, cols, rows, names):
    im = Image.open(os.path.join(HERE, sheet)).convert('RGBA')
    cw, ch = im.width / cols, im.height / rows
    for i, name in enumerate(names):
        cx, cy = i % cols, i // cols
        cell = clean(im.crop((round(cx * cw), round(cy * ch), round((cx + 1) * cw), round((cy + 1) * ch))))
        bb = cell.getchannel('A').point(lambda v: 255 if v > 24 else 0).getbbox()
        icon = cell.crop(bb)
        side = max(icon.width, icon.height)
        sq = Image.new('RGBA', (side, side), (0, 0, 0, 0))
        sq.alpha_composite(icon, ((side - icon.width) // 2, (side - icon.height) // 2))
        sq.resize((SIZE, SIZE), Image.LANCZOS).save(os.path.join(OUT, name + '.png'))
    print(sheet, len(names))


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    for s in SHEETS:
        cut(*s)
