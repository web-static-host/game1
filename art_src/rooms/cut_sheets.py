## Мебель из листов предметов ChatGPT (art_src/rooms/sheets/<комната>_items.png, прозрачный фон)
## → отдельные спрайты assets/furniture/<комната>/<предмет>.png.
## Предмет находим по точке внутри него (связная область альфы), вырезаем по его маске
## и приводим к заданной ширине в метрах: масштаб на листах ChatGPT у предметов разный.
## Запуск: python3 art_src/rooms/cut_sheets.py  (нужны Pillow, numpy, scipy)
import os
import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', '..', 'assets', 'furniture')
PX_PER_M = 128    # пикселей на метр в спрайте (клетка в игре — 1 м, 32 px; запас под зум)

# Лист: (файл, {предмет: (точка внутри x, y на листе, ширина в метрах[, склейка деталей px])}).
# Склейка — на сколько пикселей расширять маску, чтобы детали одного предмета (листья, цепь)
# собрались вместе; у плотно стоящих предметов (ящики) — меньше, чтобы не слиплись соседи.
SHEETS = {
    'home': ('home_items.png', {
        'bed_blue': (200, 160, 1.8), 'bed_pink': (580, 160, 1.8),
        'bed_green': (950, 160, 1.8), 'bed_yellow': (1330, 160, 1.8),
        'nightstand': (218, 500, 0.5), 'bookcase': (566, 430, 0.6),
        'shelf_plant': (915, 470, 1.1), 'shelf_toy': (1310, 470, 1.05),
        'shelf_vine': (300, 715, 1.15),
        'picture_mountain': (652, 700, 0.55), 'picture_leaf': (957, 700, 0.4), 'picture_sun': (1290, 700, 0.5),
        'plush': (703, 905, 0.32),
    }),
    # Склад — строго спереди (верх полок и ящиков не виден), как комната.
    'storage': ('storage_items_front.png', {
        'rack': (400, 60, 2.0, 6), 'hoist': (1200, 80, 2.2, 8),
        'crate': (249, 427, 0.6, 2), 'crate_stone': (509, 427, 0.6, 2), 'crate_wood': (768, 427, 0.6, 2),
        'crate_brick': (1027, 427, 0.6, 2), 'crate_metal': (1287, 427, 0.6, 2),
        'crate_coal': (249, 593, 0.6, 2), 'crate_iron': (509, 593, 0.6, 2), 'crate_copper': (768, 593, 0.6, 2),
        'crate_silver': (1027, 593, 0.6, 2), 'crate_gold': (1287, 593, 0.6, 2),
        'crate_uranium': (249, 753, 0.6, 2), 'crate_diamond': (509, 753, 0.6, 2), 'crate_salt': (768, 753, 0.6, 2),
        'crate_clay': (1027, 753, 0.6, 2), 'crate_limestone': (1287, 753, 0.6, 2),
        'barrel': (640, 907, 0.55, 3), 'logs': (913, 920, 0.75, 3),
    }),
}


# Части предмета (рамки в пикселях готового спрайта) — если предмет собирают из кусков.
# Таль: брус тянется во всю комнату (StructureLayer._draw_hoist), верх у всех частей — y = 0.
PARTS = {
    'storage': {'hoist': {
        'hoist_cap': (0, 0, 24, 40),        # левый торец бруса
        'hoist_beam': (100, 0, 140, 34),    # кусок бруса — повторяется по длине
        'hoist_block': (48, 0, 102, 132),   # каретка, шкив, цепь и крюк (с куском бруса за ними)
        'hoist_winch': (180, 0, 282, 132),  # лебёдка с правым торцом и рукоятью
    }},
}


def _runs(flags):
    """Отрезки подряд идущих True: [[начало, конец], ...]."""
    out = []
    for i, f in enumerate(flags):
        if f:
            if out and i - out[-1][1] <= 1:
                out[-1][1] = i
            else:
                out.append([i, i])
    return out


def stretch_rack(sprite, gap_m, rail_m=None, post_m=None):
    """Стеллаж выше (и, если заданы post_m / rail_m, массивнее — стойки и планки толще), промежутки
    между планками растянуты до gap_m — ящики встают между планками. Ширина та же.
    Возвращает картинку и высоты верха планок над полом (м)."""
    w, h = sprite.size
    a = np.asarray(sprite)[..., 3] > 128
    # По горизонтали: стойки шире, середина (только планки) — сжимается.
    posts = _runs(a.mean(0) > 0.85)
    (l0, l1), (r0, r1) = posts[0], posts[-1]
    post = round(post_m * PX_PER_M) if post_m else l1 - l0 + 1
    left = sprite.crop((0, 0, l1 + 1, h)).resize((l0 + post, h), Image.LANCZOS)
    right = sprite.crop((r0, 0, w, h)).resize((post + (w - 1 - r1), h), Image.LANCZOS)
    mid = sprite.crop((l1 + 1, 0, r0, h)).resize((w - left.width - right.width, h), Image.LANCZOS)
    wide = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    wide.alpha_composite(left, (0, 0))
    wide.alpha_composite(mid, (left.width, 0))
    wide.alpha_composite(right, (left.width + mid.width, 0))
    # По вертикали: планки толще, промежутки — под ящик.
    a = np.asarray(wide)[..., 3] > 128
    rails = _runs(a[:, w // 4: 3 * w // 4].mean(1) > 0.9)
    gap = round(gap_m * PX_PER_M)
    pieces, y = [], 0          # (кусок, это планка?)
    for i, (t0, t1) in enumerate(rails):
        if t0 > y:
            above = wide.crop((0, y, w, t0))
            pieces.append((above.resize((w, gap), Image.LANCZOS) if i else above, False))
        plank = wide.crop((0, t0, w, t1 + 1))
        pieces.append((plank.resize((w, round(rail_m * PX_PER_M)), Image.LANCZOS) if rail_m else plank, True))
        y = t1 + 1
    pieces.append((wide.crop((0, y, w, h)), False))
    out = Image.new('RGBA', (w, sum(pc.height for pc, _ in pieces)), (0, 0, 0, 0))
    yy, tops = 0, []
    for pc, is_rail in pieces:
        out.alpha_composite(pc, (0, yy))
        if is_rail:
            tops.append(yy)
        yy += pc.height
    levels = [round((out.height - t) / PX_PER_M, 3) for t in tops]
    inner = (w - 2 * post - l0 - (w - 1 - r1)) / PX_PER_M
    print('  между стойками %.2f м' % inner)
    return out, levels


def cut(room, sheet, items):
    a = np.asarray(Image.open(os.path.join(HERE, 'sheets', sheet)).convert('RGBA'))
    solid = a[..., 3] > 20
    labels = {}
    os.makedirs(os.path.join(OUT, room), exist_ok=True)
    for name, spec in items.items():
        x, y, width_m = spec[:3]
        grow = spec[3] if len(spec) > 3 else 6
        if grow not in labels:
            labels[grow] = ndimage.label(ndimage.binary_dilation(solid, iterations=grow))[0]
        lab = labels[grow]
        k = lab[y, x]
        if k == 0:
            raise SystemExit('%s/%s: в точке %d,%d пусто' % (room, name, x, y))
        mask = lab == k
        ys, xs = np.nonzero(mask & (a[..., 3] > 0))
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        item = a[y0:y1, x0:x1].copy()
        item[..., 3] = np.where(mask[y0:y1, x0:x1], item[..., 3], 0)
        w = round(width_m * PX_PER_M)
        h = round(item.shape[0] * w / item.shape[1])
        sprite = Image.fromarray(item, 'RGBA').resize((w, h), Image.LANCZOS)
        sprite.save(os.path.join(OUT, room, name + '.png'))
        print(room, name, (w, h), '%.2f×%.2f м' % (width_m, h / PX_PER_M))
        for part, box in PARTS.get(room, {}).get(name, {}).items():
            sprite.crop(box).save(os.path.join(OUT, room, part + '.png'))
        if name == 'rack':
            tall, levels = stretch_rack(sprite, 0.5)
            tall.save(os.path.join(OUT, room, 'rack_tall.png'))
            print(room, 'rack_tall', tall.size, '— верх планок над полом, м:', levels)


if __name__ == '__main__':
    for room, (sheet, items) in SHEETS.items():
        if os.path.exists(os.path.join(HERE, 'sheets', sheet)):
            cut(room, sheet, items)
