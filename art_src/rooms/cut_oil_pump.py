## Детали нефтекачалки для анимации: режет лист ChatGPT (sheets/oil_pump_parts.webp) на детали
## в assets/furniture/oil_pump/. Оси (отверстия, втулки) найдены по листу и записаны в
## structure_layer.gd (PUMPJACK) — в пикселях вырезанной картинки.
##   python3 art_src/rooms/cut_oil_pump.py
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'sheets', 'oil_pump_parts.webp')
OUT = os.path.join(HERE, '..', '..', 'assets', 'furniture', 'oil_pump')
# Деталь: рамка на листе (x0, y0, x1, y1) — с запасом 4 px вокруг.
PARTS = {
    'frame': (49, 60, 715, 555),       # станина: ось кривошипа (232, 331), шарнир балансира (463, 35)
    'beam': (711, 29, 1490, 371),      # балансир: ось (407.3, 182), палец шатуна (53.1, 162.7), голова (775, 173)
    'crank': (870, 300, 1293, 556),    # кривошип: ось (222.3, 135.1), палец (382.3, 130.5)
    'rod': (112, 740, 569, 834),       # шатун: проушины (46.5, 46.8) и (410.2, 46.8)
    'polished': (746, 571, 866, 992),  # шток: подвес (60, 29), низ — 417
    'wellhead': (1056, 649, 1356, 958),  # устье: верх (147, 11), низ — 305
}

if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    im = Image.open(SRC).convert('RGBA')
    for name, box in PARTS.items():
        part = im.crop(box)
        # Почти прозрачная кайма листа — в ноль (иначе на тёмных стенах светлый ореол).
        px = part.load()
        for y in range(part.height):
            for x in range(part.width):
                if px[x, y][3] < 24:
                    px[x, y] = (0, 0, 0, 0)
        part.save(os.path.join(OUT, name + '.png'))
        print(name, part.size)
