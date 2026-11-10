## Движущиеся детали комнат (листы ChatGPT в art_src/rooms/sheets/anim_*.png, правило анимации): режет на детали в
## assets/furniture/anim/, приводит к 128 px на метр (как вся мебель), а топки печей, окно газового
## двигателя и нутро вентилятора делает прозрачными — за ними игра рисует огонь и лопасти.
## Печатает таблицу осей и топок для structure_layer.gd (ANIM).
##   python3 art_src/rooms/cut_anim.py
import os
import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'sheets')
OUT = os.path.join(HERE, '..', '..', 'assets', 'furniture', 'anim')
PX = 128

SHEETS = {
    'pump': 'anim_pump.png',
    'flame': 'anim_flames.png',
    'gas': 'anim_gas_generator.png',
    'gauge': 'anim_gauge.png',
    'vent': 'anim_vent.png',
    'coal': 'anim_coal_generator.png',
    'stoves': 'anim_stoves.png',
}
## Деталь: лист, рамка на листе, ширина в метрах (None — своя: огонь), ось (на листе), топка/окно
## (рамка тёмного места на листе — станет прозрачным), круг нутра (центр, радиус — тёмное внутри
## станет прозрачным).
PARTS = {
    'pump_body': ['pump', (68, 87, 829, 919), 1.2, (619, 554)],
    'pump_wheel': ['pump', (935, 322, 1451, 843), 1.2 * 516 / 761 * 0.7, None],
    'flame_orange': ['flame', (163, 221, 670, 762), None, None],
    'flame_blue': ['flame', (853, 223, 1367, 762), None, None],
    'gas_body': ['gas', (164, 45, 857, 439), 1.3, (658, 233), (321, 202, 458, 324)],
    'gas_dynamo': ['gas', (982, 73, 1321, 438), 0.62, None],
    'gas_flywheel': ['gas', (77, 534, 481, 947), 0.8, None],
    'gas_pulley': ['gas', (558, 637, 761, 844), 0.32, None],
    'gas_belt': ['gas', (832, 717, 1462, 768), 1.0, None],
    'gauge_dial': ['gauge', (182, 235, 723, 790), 0.35, (452, 512)],
    'gauge_needle': ['gauge', (1112, 403, 1260, 550), 0.35 * 148 / 541, (1136, 526)],
    'vent_housing': ['vent', (48, 164, 915, 828), 1.6, (381, 486), None, ((381, 486), 250)],
    'vent_blades': ['vent', (932, 215, 1475, 764), 1.6 * 543 / 867, None],
    'coal_body': ['coal', (229, 15, 626, 477), 0.9, (545, 380), (311, 292, 436, 405)],
    'coal_dynamo': ['coal', (943, 133, 1300, 472), 0.7, None],
    'coal_flywheel': ['coal', (78, 567, 472, 969), 0.8, None],
    'coal_pulley': ['coal', (623, 667, 829, 874), 0.32, None],
    'coal_belt': ['coal', (966, 750, 1460, 787), 1.0, None],
    'stove_stone': ['stoves', (93, 98, 450, 450), 1.0, None, (178, 203, 364, 354)],
    'stove_brick': ['stoves', (572, 98, 933, 451), 1.0, None, (661, 205, 845, 352)],
    'stove_kiln': ['stoves', (1039, 24, 1456, 506), 1.2, None, (1176, 358, 1319, 455)],
    'stove_forge': ['stoves', (135, 540, 727, 1001), 1.4, None, (441, 764, 609, 883)],
    'stove_boiler': ['stoves', (939, 556, 1219, 986), 0.95, None, (1015, 804, 1140, 914)],
}


def lum(a):
    return a[..., 0] * 0.3 + a[..., 1] * 0.59 + a[..., 2] * 0.11


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    sheets = {k: np.asarray(Image.open(os.path.join(SRC, v)).convert('RGBA')).copy() for k, v in SHEETS.items()}
    meta = {}
    for name, spec in PARTS.items():
        sheet, box, meters, pivot = spec[:4]
        mouth = spec[4] if len(spec) > 4 else None
        hole = spec[5] if len(spec) > 5 else None
        x0, y0, x1, y1 = box
        a = sheets[sheet][y0 - 4:y1 + 4, x0 - 4:x1 + 4].copy()
        a[a[..., 3] < 24] = 0
        ox, oy = x0 - 4, y0 - 4
        if mouth is not None:
            # Тёмное нутро топки (связное с её серединой) — прозрачное; край — мягко.
            mx0, my0, mx1, my1 = mouth
            dark = lum(a) < 60
            sub = np.zeros_like(dark)
            sub[my0 - oy - 6:my1 - oy + 6, mx0 - ox - 6:mx1 - ox + 6] = True
            lab, n = ndimage.label(dark & sub)
            core = lab == lab[(my0 + my1) // 2 - oy, (mx0 + mx1) // 2 - ox]
            core = ndimage.binary_closing(core, iterations=3)
            soft = ndimage.gaussian_filter(core.astype(float), 1.2)
            a[..., 3] = (a[..., 3] * (1.0 - np.clip(soft * 1.4, 0, 1))).astype(np.uint8)
        if hole is not None:
            (hx, hy), hr = hole
            yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
            inside = (xx - (hx - ox)) ** 2 + (yy - (hy - oy)) ** 2 < hr ** 2
            dark = inside & (lum(a) < 55)
            a[dark, 3] = 0
        im = Image.fromarray(a)
        k = (meters * PX / (x1 - x0)) if meters else (256.0 / (x1 - x0))
        im = im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)
        im.save(os.path.join(OUT, name + '.png'))
        m = {'size': im.size}
        # Верх (куда подходит труба): середина непрозрачного в верхних строках.
        al = np.asarray(im)[..., 3] > 128
        ys, xs = np.nonzero(al)
        top = ys.min()
        m['top'] = float(xs[ys <= top + 4].mean())
        if pivot is not None:
            m['pivot'] = ((pivot[0] - ox) * k, (pivot[1] - oy) * k)
        else:
            m['pivot'] = (im.width / 2, im.height / 2)
        if mouth is not None:
            m['mouth'] = ((mouth[0] - ox) * k, (mouth[1] - oy) * k, (mouth[2] - mouth[0]) * k, (mouth[3] - mouth[1]) * k)
        meta[name] = m
    print('const ANIM := {')
    for name, m in meta.items():
        line = '\t"%s": {"pivot": Vector2(%.1f, %.1f), "top": %.1f' % (name, m['pivot'][0], m['pivot'][1], m['top'])
        if 'mouth' in m:
            line += ', "mouth": Rect2(%.1f, %.1f, %.1f, %.1f)' % m['mouth']
        print(line + '},')
    print('}')
