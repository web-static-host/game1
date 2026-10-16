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

# Лист: {предмет: (точка внутри x, y на листе, ширина в метрах)}.
SHEETS = {
    'home': {
        'bed_blue': (200, 160, 1.8), 'bed_pink': (580, 160, 1.8),
        'bed_green': (950, 160, 1.8), 'bed_yellow': (1330, 160, 1.8),
        'nightstand': (218, 500, 0.5), 'bookcase': (566, 430, 0.6),
        'shelf_plant': (915, 470, 1.1), 'shelf_toy': (1310, 470, 1.05),
        'shelf_vine': (300, 715, 1.15),
        'picture_mountain': (652, 700, 0.55), 'picture_leaf': (957, 700, 0.4), 'picture_sun': (1290, 700, 0.5),
        'plush': (703, 905, 0.32),
    },
    'storage': {
        'rack': (436, 100, 2.0), 'hoist': (1066, 75, 2.2),
        'crate': (300, 430, 0.6), 'crate_stone': (535, 430, 0.6), 'crate_wood': (769, 430, 0.6),
        'crate_brick': (1001, 430, 0.6), 'crate_metal': (1235, 430, 0.6),
        'crate_coal': (300, 580, 0.6), 'crate_iron': (535, 580, 0.6), 'crate_copper': (769, 580, 0.6),
        'crate_silver': (1001, 580, 0.6), 'crate_gold': (1235, 580, 0.6),
        'crate_uranium': (300, 735, 0.6), 'crate_diamond': (535, 735, 0.6), 'crate_salt': (769, 735, 0.6),
        'crate_clay': (1001, 735, 0.6), 'crate_limestone': (1235, 735, 0.6),
        'drum_oil': (320, 900, 0.42), 'tank_methane': (582, 900, 0.36),
        'barrel': (865, 900, 0.55), 'logs': (1185, 900, 0.75),
    },
}


# Части предмета (рамки в пикселях готового спрайта): таль режем, чтобы брус тянулся во всю комнату.
PARTS = {
    'storage': {'hoist': {
        'hoist_cap': (0, 0, 27, 48),        # левый торец бруса
        'hoist_beam': (30, 0, 58, 48),      # кусок бруса — повторяется по длине
        'hoist_block': (58, 0, 102, 136),   # блок с цепью и крюком (с куском бруса за ним)
        'hoist_winch': (196, 0, 282, 90),   # лебёдка с правым торцом
    }},
}


def cut(room, items):
    a = np.asarray(Image.open(os.path.join(HERE, 'sheets', room + '_items.png')).convert('RGBA'))
    solid = a[..., 3] > 20
    # Детали одного предмета (листья, цепь, флажки) соединяем небольшим расширением.
    lab, _ = ndimage.label(ndimage.binary_dilation(solid, iterations=6))
    os.makedirs(os.path.join(OUT, room), exist_ok=True)
    for name, (x, y, width_m) in items.items():
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


if __name__ == '__main__':
    for room, items in SHEETS.items():
        if os.path.exists(os.path.join(HERE, 'sheets', room + '_items.png')):
            cut(room, items)
