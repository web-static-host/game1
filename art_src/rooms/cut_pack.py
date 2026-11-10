## Комплект спрайтов 8 комнат от ChatGPT (art_src/rooms/sheets/pack_v1/*.png, README там же):
## режет листы на предметы в assets/furniture/<комната>/<имя>.png, 128 px на метр, как вся мебель.
## Рамки — найденные куски листов (с запасом), ширина — в метрах по прототипам комнат.
##   python3 art_src/rooms/cut_pack.py
import os
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'sheets', 'pack_v1')
OUT = os.path.join(HERE, '..', '..', 'assets', 'furniture')
PX = 128

## лист -> [(папка, имя, рамка x0 y0 x1 y1, ширина в метрах), ...]
PARTS = {
    'oil_storage_items_front': [
        ('oil_storage', 'tank', (120, 24, 528, 621), 1.45),
        ('oil_storage', 'tank_small', (660, 291, 986, 615), 1.0),
        ('oil_storage', 'gauge', (1110, 286, 1385, 615), 0.45),
        ('oil_storage', 'pipe_v', (646, 726, 761, 973), 0.2),
        ('oil_storage', 'lamp', (1288, 709, 1452, 988), 0.32),
        ('oil_storage', 'pipe_h', (73, 812, 551, 932), 1.2),
        ('oil_storage', 'cross', (866, 732, 1183, 973), 0.55),
    ],
    'oil_storage_animation_parts': [
        ('oil_storage', 'valve', (182, 36, 676, 538), 0.34),
        ('oil_storage', 'valve_small', (921, 109, 1279, 476), 0.26),
        ('oil_storage', 'needle', (376, 593, 481, 975), 0.05),
        ('oil_storage', 'lever', (931, 715, 1337, 876), 0.42),
    ],
    'oil_refinery_items_front': [
        ('refinery', 'column', (120, 12, 422, 629), 0.85),
        ('refinery', 'condenser', (502, 210, 849, 626), 0.95),
        ('refinery', 'pump', (922, 341, 1188, 621), 0.7),
        ('refinery', 'canister', (1287, 322, 1464, 621), 0.42),
        ('refinery', 'pipe_h', (44, 793, 498, 900), 1.2),
        ('refinery', 'pipe_v', (627, 712, 723, 949), 0.22),
        ('refinery', 'gauge', (867, 726, 1053, 960), 0.4),
        ('refinery', 'tee', (1138, 750, 1478, 907), 0.8),
    ],
    'oil_refinery_animation_parts': [
        ('refinery', 'valve', (69, 33, 513, 481), 0.34),
        ('refinery', 'valve_small', (641, 86, 980, 429), 0.26),
        ('refinery', 'valve_gold', (1134, 116, 1415, 403), 0.24),
        ('refinery', 'needle', (475, 545, 584, 944), 0.05),
        ('refinery', 'capsule', (888, 534, 1099, 956), 0.2),
    ],
    'uranium_enrichment_items_front': [
        ('enrichment', 'centrifuge', (43, 93, 486, 614), 1.15),
        ('enrichment', 'cabinet', (570, 239, 813, 609), 0.62),
        ('enrichment', 'panel', (883, 273, 1168, 599), 0.75),
        ('enrichment', 'canister', (1232, 246, 1467, 593), 0.55),
        ('enrichment', 'sign', (81, 706, 321, 954), 0.5),
        ('enrichment', 'pipe_h', (410, 764, 754, 893), 0.9),
        ('enrichment', 'elbow', (871, 720, 1057, 919), 0.4),
        ('enrichment', 'lights', (1153, 747, 1473, 904), 0.7),
    ],
    'uranium_enrichment_animation_parts': [
        ('enrichment', 'wheel', (86, 79, 607, 602), 0.5),
        ('enrichment', 'wheel_small', (697, 167, 1038, 517), 0.33),
        ('enrichment', 'drum', (1167, 88, 1415, 616), 0.36),
        ('enrichment', 'belt', (95, 762, 630, 840), 1.0),
        ('enrichment', 'wheel3', (734, 665, 999, 937), 0.3),
        ('enrichment', 'needle', (1240, 669, 1341, 903), 0.05),
    ],
    'diesel_generator_items_front': [
        ('diesel', 'engine', (90, 89, 897, 563), 1.55),
        ('diesel', 'generator', (964, 231, 1449, 562), 0.9),
        ('diesel', 'canister', (65, 702, 212, 917), 0.3),
        ('diesel', 'filter', (239, 707, 488, 916), 0.48),
        ('diesel', 'pipe_h', (559, 761, 848, 862), 0.9),
        ('diesel', 'pipe_v', (895, 661, 1002, 917), 0.2),
        ('diesel', 'box', (1064, 667, 1275, 916), 0.42),
        ('diesel', 'gauge', (1327, 703, 1475, 913), 0.3),
    ],
    'diesel_generator_animation_parts': [
        ('diesel', 'flywheel', (51, 28, 587, 578), 0.82),
        ('diesel', 'gear', (636, 133, 974, 474), 0.5),
        ('diesel', 'shaft', (1026, 224, 1476, 384), 0.6),
        ('diesel', 'valve', (151, 629, 481, 967), 0.3),
        ('diesel', 'lever', (1131, 606, 1314, 947), 0.3),
    ],
    'oil_pump_items_front': [
        ('oil_pump', 'sight', (903, 255, 1050, 601), 0.32),
        ('oil_pump', 'barrel', (1098, 343, 1283, 601), 0.55),
        ('oil_pump', 'barrel2', (1313, 343, 1497, 601), 0.55),
        ('oil_pump', 'pipe_h', (36, 786, 372, 885), 0.9),
        ('oil_pump', 'pipe_v', (438, 648, 531, 958), 0.2),
        ('oil_pump', 'valve_pipe', (839, 756, 1133, 914), 0.7),
        ('oil_pump', 'gauge_pipe', (1188, 750, 1499, 918), 0.72),
        ('oil_pump', 'elbow', (594, 771, 769, 948), 0.36),
    ],
    'spaceship_interior_items_front': [
        ('ship', 'bunk', (48, 166, 504, 509), 2.0),
        ('ship', 'console', (999, 159, 1482, 509), 1.55),
        ('ship', 'bed', (555, 308, 951, 508), 1.8),
        ('ship', 'nightstand', (99, 662, 288, 855), 0.48),
        ('ship', 'lamp', (362, 648, 528, 849), 0.36),
        ('ship', 'shelf', (588, 635, 972, 842), 1.15),
        ('ship', 'light', (1032, 703, 1455, 774), 1.2),
    ],
    'teleport_3m_items_front': [
        ('teleport', 'pedestal', (203, 100, 1329, 462), 2.2),
        ('teleport', 'ring', (199, 556, 597, 954), 1.0),
        ('teleport', 'panel', (723, 590, 867, 900), 0.3),
        ('teleport', 'ball_gold', (1002, 699, 1104, 801), 0.1),
        ('teleport', 'ball_purple', (1228, 699, 1332, 804), 0.1),
    ],
    'cosmodrome_9m_items_front': [
        ('cosmodrome', 'table', (40, 225, 1497, 400), 8.7),
        ('cosmodrome', 'console', (39, 563, 364, 824), 1.35),
        ('cosmodrome', 'crate', (396, 676, 555, 829), 0.62),
        ('cosmodrome', 'cylinder', (586, 632, 693, 824), 0.4),
        ('cosmodrome', 'workbench', (717, 671, 1003, 830), 1.25),
        ('cosmodrome', 'pipe', (1024, 700, 1355, 790), 1.3),
        ('cosmodrome', 'lever', (1371, 663, 1496, 823), 0.45),
    ],
    'cosmodrome_launch_flames': [
        ('cosmodrome', 'flame_orange', (233, 77, 760, 945), 2.0),
        ('cosmodrome', 'flame_blue', (956, 81, 1268, 932), 1.2),
    ],
}

if __name__ == '__main__':
    for sheet, parts in PARTS.items():
        im = Image.open(os.path.join(SRC, sheet + '.png')).convert('RGBA')
        for room, name, (x0, y0, x1, y1), meters in parts:
            p = 3
            a = np.asarray(im.crop((x0 - p, y0 - p, x1 + p, y1 + p))).copy()
            a[a[..., 3] < 24] = 0
            part = Image.fromarray(a)
            k = meters * PX / (x1 - x0)
            part = part.resize((max(1, round(part.width * k)), max(1, round(part.height * k))), Image.LANCZOS)
            os.makedirs(os.path.join(OUT, room), exist_ok=True)
            part.save(os.path.join(OUT, room, name + '.png'))
            print(room, name, part.size)
