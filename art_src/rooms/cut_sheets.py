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

# Листы: [(комната, файл, {предмет: (точка внутри x, y на листе, ширина в метрах[, склейка px])})].
# Склейка — на сколько пикселей расширять маску, чтобы детали одного предмета (листья, цепь)
# собрались вместе; у плотно стоящих предметов (ящики) — меньше, чтобы не слиплись соседи.
SHEETS = [
    # Всё строго спереди (верх предметов не виден), как комната. Старые листы в 3/4 (home_items.png,
    # storage_items.png) не используются.
    ('home', 'home_items_front.png', {
        'bed_blue': (194, 169, 1.85), 'bed_pink': (579, 169, 1.85),
        'bed_green': (962, 169, 1.85), 'bed_yellow': (1337, 170, 1.85),
        'nightstand': (197, 472, 0.5), 'bookcase': (545, 440, 0.6),
        'shelf_plant': (909, 481, 1.1), 'shelf_toy': (1318, 490, 1.0),
        'shelf_vine': (216, 764, 1.15),
        'picture_mountain': (699, 744, 0.6), 'picture_sun': (1034, 744, 0.5), 'picture_leaf': (1371, 744, 0.45),
        'plush': (769, 940, 0.3),
    }),
    # Склад — строго спереди (верх полок и ящиков не виден), как комната.
    ('storage', 'storage_items_front.png', {
        'hoist': (1200, 80, 2.2, 8),
        'crate': (249, 427, 0.6, 2), 'crate_stone': (509, 427, 0.6, 2), 'crate_wood': (768, 427, 0.6, 2),
        'crate_brick': (1027, 427, 0.6, 2), 'crate_metal': (1287, 427, 0.6, 2),
        'crate_coal': (249, 593, 0.6, 2), 'crate_iron': (509, 593, 0.6, 2), 'crate_copper': (768, 593, 0.6, 2),
        'crate_silver': (1027, 593, 0.6, 2), 'crate_gold': (1287, 593, 0.6, 2),
        'crate_uranium': (249, 753, 0.6, 2), 'crate_diamond': (509, 753, 0.6, 2), 'crate_salt': (768, 753, 0.6, 2),
        'crate_clay': (1027, 753, 0.6, 2), 'crate_limestone': (1287, 753, 0.6, 2),
        'barrel': (640, 907, 0.55, 3), 'logs': (913, 920, 0.75, 3),
    }),
    # Массивный стеллаж — перерисован отдельно (на листе он был из тонких планок).
    ('storage', 'storage_rack_front_thick.png', {
        'rack': (760, 170, 2.0, 6),
    }),
    # Амбар: стеллаж того же вида, что на складе (растягивается так же), корзины — как ящики.
    ('granary', 'granary_items_front.png', {
        'rack': (425, 211, 2.0, 6), 'rod': (1152, 205, 1.8, 6),
        'basket': (210, 549, 0.6, 3), 'basket_fish': (594, 520, 0.6, 3),
        'basket_mushroom': (966, 519, 0.6, 3), 'basket_berries': (1336, 520, 0.6, 3),
        'hang_fish': (181, 827, 0.2), 'hang_garlic': (460, 836, 0.22), 'hang_pepper': (747, 840, 0.3),
        'hang_herbs': (1048, 848, 0.28), 'hang_onion': (1351, 842, 0.3),
    }),
    # Ферма: грядка 2 м, грибы трёх стадий в том же масштабе, что грядка на листе (760 px = 2 м).
    ('farm', 'farm_items_front.png', {
        'bed': (420, 160, 2.0), 'shoots_1': (1165, 177, 655 / 380), 'shoots_2': (394, 409, 745 / 380),
        'shoots_3': (1151, 396, 714 / 380),
        'lamp_off': (410, 636, 1.7), 'lamp_on': (1128, 635, 1.7),
        'can': (248, 861, 0.45), 'tools': (566, 832, 0.6), 'gauge': (948, 866, 0.32), 'hose': (1307, 863, 0.45),
    }),
]


# Части предмета (рамки в пикселях готового спрайта) — если предмет собирают из кусков.
# Таль: брус тянется во всю комнату (StructureLayer._draw_hoist), верх у всех частей — y = 0.
PARTS = {
    'storage': {'hoist': {
        'hoist_cap': (0, 0, 24, 40),        # левый торец бруса
        'hoist_beam': (100, 0, 140, 34),    # кусок бруса — повторяется по длине
        'hoist_block': (48, 0, 102, 132),   # каретка, шкив, цепь и крюк (с куском бруса за ними)
        'hoist_winch': (180, 0, 282, 132),  # лебёдка с правым торцом и рукоятью
    }},
    # Жердь амбара: тянется во всю комнату — торцы с верёвками и повторяющийся кусок.
    'granary': {'rod': {
        'rod_l': (0, 0, 30, 66), 'rod_mid': (40, 0, 190, 66), 'rod_r': (200, 0, 230, 66),
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
        ys, xs = np.nonzero(mask & (a[..., 3] >= 24))
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        item = a[y0:y1, x0:x1].copy()
        # Слабую дымку вокруг предметов (ChatGPT рисует ореолы) — убираем.
        item[..., 3] = np.where(mask[y0:y1, x0:x1] & (item[..., 3] >= 24), item[..., 3], 0)
        w = round(width_m * PX_PER_M)
        h = round(item.shape[0] * w / item.shape[1])
        sprite = Image.fromarray(item, 'RGBA').resize((w, h), Image.LANCZOS)
        sprite.save(os.path.join(OUT, room, name + '.png'))
        print(room, name, (w, h), '%.2f×%.2f м' % (width_m, h / PX_PER_M))
        for part, box in PARTS.get(room, {}).get(name, {}).items():
            sprite.crop(box).save(os.path.join(OUT, room, part + '.png'))
        if name == 'rack':
            tall, levels = stretch_rack(sprite, 0.48)
            tall.save(os.path.join(OUT, room, 'rack_tall.png'))
            print(room, 'rack_tall', tall.size, '— верх планок над полом, м:', levels)


if __name__ == '__main__':
    for room, sheet, items in SHEETS:
        if os.path.exists(os.path.join(HERE, 'sheets', sheet)):
            cut(room, sheet, items)
