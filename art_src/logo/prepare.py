## Логотип и иконки «Гаврики» из картинки ChatGPT (art_src/logo/super_gavrik_cave.webp, Супер-Гаврик
## с киркой в пещере, 1254×1254) → assets/logo/logo.png (заставка, небольшая, по центру) и assets/icon/ (иконка).
## Адаптивная иконка Android обрезает края (видна середина ~66 %), поэтому картинку вписываем
## меньше и дополняем края размытым продолжением той же пещеры.
## Запуск: python3 art_src/logo/prepare.py  (нужен Pillow)
import os
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..', '..')
src = Image.open(os.path.join(HERE, 'super_gavrik_cave.webp')).convert('RGB')


def padded(size, inner):
    """Картинка size×size: середина — вся картинка размером inner, края — размытая пещера."""
    bg = src.resize((size, size), Image.LANCZOS).filter(ImageFilter.GaussianBlur(size * 0.04))
    bg.paste(src.resize((inner, inner), Image.LANCZOS), ((size - inner) // 2, (size - inner) // 2))
    return bg


# Заставка: небольшая картинка со скруглёнными углами по центру тёмного экрана (не на весь экран).
LOGO = 420
logo = src.resize((LOGO, LOGO), Image.LANCZOS).convert('RGBA')
mask = Image.new('L', (LOGO * 4, LOGO * 4), 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, LOGO * 4 - 1, LOGO * 4 - 1), LOGO * 4 // 8, fill=255)
logo.putalpha(mask.resize((LOGO, LOGO), Image.LANCZOS))
logo.save(os.path.join(ROOT, 'assets', 'logo', 'logo.png'))
src.resize((512, 512), Image.LANCZOS).save(os.path.join(ROOT, 'assets', 'icon', 'icon_512.png'))
padded(432, 312).save(os.path.join(ROOT, 'assets', 'icon', 'icon_fg_432.png'))
src.resize((432, 432), Image.LANCZOS).filter(ImageFilter.GaussianBlur(18)).save(os.path.join(ROOT, 'assets', 'icon', 'icon_bg_432.png'))
print('ok')
