"""Слитки металлов: значок слитка (ingot_base.png) перекрашивается по яркости в цвета металла.
Самородки (прежние значки металлов) — значки руды: <металл>_ore.png.
    python3 art_src/icons/make_ingots.py
"""
from pathlib import Path
from PIL import Image

ICONS = Path(__file__).resolve().parents[2] / "assets" / "icons"
BASE = Path(__file__).resolve().parent / "ingot_base.png"

# Металл -> (тень, середина, блик).
PALETTE = {
    "iron": ((36, 38, 44), (92, 96, 106), (170, 176, 188)),
    "copper": ((92, 38, 18), (196, 98, 52), (255, 196, 150)),
    "silver": ((110, 116, 126), (196, 202, 212), (255, 255, 255)),
    "gold": ((120, 72, 8), (232, 172, 36), (255, 240, 150)),
    "uranium": ((24, 70, 18), (92, 196, 52), (214, 255, 160)),
}


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def tint(img, shade, mid, light):
    out = Image.new("RGBA", img.size)
    src = img.load()
    dst = out.load()
    for y in range(img.size[1]):
        for x in range(img.size[0]):
            r, g, b, a = src[x, y]
            v = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            # Яркость слитка — от тени через середину к блику (чуть растянута для контраста).
            v = min(1.0, max(0.0, (v - 0.25) / 0.7))
            c = lerp(shade, mid, v / 0.5) if v < 0.5 else lerp(mid, light, (v - 0.5) / 0.5)
            dst[x, y] = (*c, a)
    return out


def main():
    base = Image.open(BASE).convert("RGBA")
    for name, pal in PALETTE.items():
        tint(base, *pal).save(ICONS / f"{name}.png")


if __name__ == "__main__":
    main()
