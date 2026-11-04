## Постройки для игры, которые раньше рисовались кодом: ракеты, башня космодрома, корпус корабля,
## арка телепорта. Модель в Blender и рендер в спрайты (assets/structures/), как комнаты
## (art_src/rooms/build_rooms.py): вид строго сбоку, 1 клетка = 1 м, 64 px на метр, тот же свет.
## Оси: x — вправо, z — вверх, камера смотрит из -y. У каждого спрайта своя рамка (м), её низ и
## опорная точка записаны в STRUCTURES — игра ставит спрайт по ним.
## Запуск: python3 art_src/structures/build_structures.py  (модуль bpy); STRUCT_ONLY=rocket_chem — один.
import os, sys, math
import bpy
import bmesh

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'rooms'))
import build_rooms as R  # noqa: E402  (mat, box, bolt, lin, reset)

OUT = os.environ.get('STRUCT_OUT') or os.path.join(HERE, '..', '..', 'assets', 'structures')
PX = int(os.environ.get('STRUCT_PX', 64))
ONLY = [s for s in os.environ.get('STRUCT_ONLY', '').split(',') if s]


def cyl(name, r, z0, z1, m, x=0.0, y=0.0, verts=48, r2=None):
    """Цилиндр (или конус, если r2) вдоль z."""
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=z1 - z0, location=(x, y, (z0 + z1) / 2))
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r2, depth=z1 - z0, location=(x, y, (z0 + z1) / 2))
    o = bpy.context.object
    o.name = name
    o.data.materials.append(m)
    bpy.ops.object.shade_smooth()
    return o


def cyl_x(name, r, x0, x1, m, z=0.0, y=0.0, r2=None, verts=48):
    """Цилиндр (конус) вдоль x."""
    o = cyl(name, r, x0, x1, m, verts=verts, r2=r2)
    o.rotation_euler = (0, math.radians(90), 0)
    o.location = ((x0 + x1) / 2, y, z)
    return o


def disc(name, r, depth, x, z, y, m, verts=32):
    """Диск лицом к камере (ось — y)."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=(x, y, z), rotation=(math.radians(90), 0, 0))
    o = bpy.context.object
    o.name = name
    o.data.materials.append(m)
    bpy.ops.object.shade_smooth()
    return o


def plate(name, pts, y0, y1, m, bevel=0.03):
    """Пластина-многоугольник pts (x, z), толщина по y от y0 до y1."""
    n = len(pts)
    verts = [(x, y0, z) for x, z in pts] + [(x, y1, z) for x, z in pts]
    faces = [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))] + [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    if bevel > 0:
        b = o.modifiers.new('bevel', 'BEVEL')
        b.width = bevel
        b.segments = 3
    o.data.materials.append(m)
    return o


def fin_radial(name, pts, m, thick=0.12):
    """Стабилизатор, смотрящий на зрителя: многоугольник (y, z) — от корпуса к камере, толщина по x."""
    n = len(pts)
    verts = [(-thick / 2, y, z) for y, z in pts] + [(thick / 2, y, z) for y, z in pts]
    faces = [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))] + [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    b = o.modifiers.new('bevel', 'BEVEL')
    b.width = 0.03
    b.segments = 3
    o.data.materials.append(m)
    return o


def ring(name, r, z0, z1, m):
    return cyl(name, r, z0, z1, m)


# --- Ракеты ---------------------------------------------------------------------------

def rocket(nuclear):
    """Ракета на столе космодрома: корпус, нос, стабилизаторы, иллюминатор. Низ — z = 0."""
    hull = R.mat('hull', '#e9ecf0', 0.32, metal=0.25)
    seam = R.mat('seam', '#9aa2ad', 0.5, metal=0.3)
    red = R.mat('red', '#d94a3c', 0.4)
    green = R.mat('green', '#3fb36b', 0.4)
    accent = green if nuclear else red
    dark = R.mat('dark', '#3a3f47', 0.45, metal=0.5)
    glass = R.mat('glass', '#7cc7f2', 0.08)
    yellow = R.mat('yellow', '#f2c230', 0.4)
    black = R.mat('black', '#1d1f24', 0.5)
    rad = 1.3 if nuclear else 1.2
    top = 12.0 if nuclear else 11.5
    cyl('body', rad, 0.35, top, hull)
    cyl('skirt', rad + 0.05, 0.0, 0.4, dark)
    for z in (2.6, 5.2, 7.8, 10.2):
        ring('seam', rad + 0.008, z, z + 0.05, seam)
    ring('band', rad + 0.012, top - 0.9, top - 0.5, accent)
    cyl('nose', rad, top, top + (2.3 if nuclear else 2.5), accent, r2=0.0)
    # Иллюминатор спереди.
    disc('port_ring', 0.44, 0.12, 0.0, top - 2.3, -rad + 0.02, dark)
    disc('port', 0.33, 0.14, 0.0, top - 2.3, -rad - 0.01, glass)
    # Стабилизаторы: по бокам и один на зрителя.
    fins = R.mat('fin', '#5b8f73' if nuclear else '#d94a3c', 0.65)
    for sx in (-1, 1):
        pts = [(rad - 0.2, 3.3), (rad + 1.0, 0.7), (rad + 1.0, 0.0), (rad - 0.2, 0.25)]
        plate('fin', [(sx * x, z) for x, z in pts], -0.06, 0.06, fins)
    fin_radial('fin_front', [(-rad + 0.2, 3.3), (-rad - 1.0, 0.7), (-rad - 1.0, 0.0), (-rad + 0.2, 0.25)], fins)
    if nuclear:
        # Реакторный отсек: жёлто-чёрные полосы и знак радиации.
        ring('hazard', rad + 0.015, 0.9, 1.6, yellow)
        for k in range(10):
            a = k * math.tau / 10
            bpy.ops.mesh.primitive_cube_add(size=1, location=(math.sin(a) * (rad + 0.02), -math.cos(a) * (rad + 0.02), 1.25),
                                            rotation=(math.radians(28), 0, a))
            o = bpy.context.object
            o.scale = (0.16, 0.04, 0.95)
            o.data.materials.append(black)
        disc('trefoil_bg', 0.42, 0.06, 0.0, 3.6, -rad - 0.005, yellow)
        disc('trefoil_c', 0.08, 0.08, 0.0, 3.6, -rad - 0.04, black)
        for k in range(3):
            a0 = math.radians(90 + k * 120 - 30)
            pts = [(0.12 * math.cos(a0), 0.12 * math.sin(a0))]
            for j in range(7):
                a = a0 + math.radians(60) * j / 6
                pts.append((0.36 * math.cos(a), 0.36 * math.sin(a)))
            pts.append((0.12 * math.cos(a0 + math.radians(60)), 0.12 * math.sin(a0 + math.radians(60))))
            plate('trefoil', [(x, 3.6 + z) for x, z in pts], -rad - 0.06, -rad - 0.035, black, 0)


def tower():
    """Башня обслуживания: решётчатая ферма с площадками и стрелами к ракете (влево)."""
    steel = R.mat('steel', '#c0483a', 0.45, metal=0.3)
    white = R.mat('white', '#e8e8e8', 0.45)
    dark = R.mat('dark', '#3a3f47', 0.45, metal=0.5)
    H = 14.75
    for x in (-0.42, 0.42):
        R.box('rail', x - 0.07, 0, x + 0.07, H, -0.07, 0.07, steel, 0.02)
    z = 0.0
    k = 0
    while z < H - 0.3:
        z1 = min(H, z + 1.2)
        R.beam('brace', (-0.42, z), (0.42, z1), 0.07, -0.05, 0.05, steel if k % 3 else white)
        R.beam('brace', (0.42, z), (-0.42, z1), 0.07, -0.05, 0.05, steel if k % 3 else white)
        R.box('rung', -0.45, z - 0.04, 0.45, z + 0.04, -0.07, 0.07, steel, 0.01)
        z = z1
        k += 1
    for zz in (4.5, 8.5, 12.5):
        R.box('deck', -0.5, zz - 0.06, 0.5, zz + 0.06, -0.3, 0.3, dark, 0.02)
        R.box('arm', -1.7, zz - 0.07, -0.45, zz + 0.07, -0.08, 0.08, steel, 0.02)
        R.beam('arm_brace', (-1.2, zz), (-0.42, zz - 0.8), 0.06, -0.05, 0.05, steel)
    R.box('cap', -0.5, H - 0.1, 0.5, H, -0.3, 0.3, dark, 0.02)
    cyl('light', 0.09, H, H + 0.18, R.mat('lamp', '#ff5a4a', 0.3))


# --- Корабль -------------------------------------------------------------------------------

def ship_hull():
    """Корпус корабля снаружи (комната 9×3 — внутри, её рисует игра поверх): обшивка чуть шире
    комнаты, нос справа, стабилизаторы и сопло слева."""
    hull = R.mat('hull', '#e4e7ec', 0.32, metal=0.25)
    seam = R.mat('seam', '#9aa2ad', 0.5, metal=0.3)
    red = R.mat('red', '#d94a3c', 0.4)
    dark = R.mat('dark', '#3a3f47', 0.45, metal=0.5)
    rr = 1.68
    cyl_x('body', rr, 0.0, 9.0, hull, z=1.5, y=0.9)
    for x in (0.05, 3.0, 6.0, 8.95):
        cyl_x('seam', rr + 0.01, x - 0.03, x + 0.03, seam, z=1.5, y=0.9)
    cyl_x('nose_band', rr + 0.015, 8.6, 9.0, red, z=1.5, y=0.9)
    cyl_x('nose', rr, 9.0, 11.3, hull, z=1.5, y=0.9, r2=0.25)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.27, location=(11.3, 0.9, 1.5))
    tip = bpy.context.object
    tip.data.materials.append(red)
    bpy.ops.object.shade_smooth()
    cyl_x('nozzle', 1.0, -1.1, 0.0, dark, z=1.5, y=0.9, r2=1.35)
    for sz in (1, -1):
        pts = [(2.2, 1.5 + sz * 1.55), (0.3, 1.5 + sz * 1.55), (-1.5, 1.5 + sz * 2.6), (-0.6, 1.5 + sz * 2.6)]
        if sz < 0:
            # Нижний стабилизатор — опора: до земли, не ниже.
            pts = [(2.2, 0.1), (0.3, 0.1), (-1.4, -0.05), (-0.6, -0.05)]
        plate('fin', pts, 0.5, 0.7, R.mat('fin', '#d94a3c', 0.65))


def teleport():
    """Арка телепорта: тёмная металлическая арка на постаменте, по дуге — рубины и аметисты.
    Свечение портала рисует игра (под аркой)."""
    frame = R.mat('frame', '#4a4256', 0.4, metal=0.6)
    base = R.mat('base', '#3a3346', 0.5, metal=0.4)
    rim = R.mat('rim', '#ff4d7e', 0.3)
    ruby = R.mat('ruby', '#e5143a', 0.05)
    ame = R.mat('ame', '#a24dff', 0.05)
    w, h = 1.15, 2.55
    R.box('base', -1.25, 0.0, 1.25, 0.18, -0.4, 0.4, base, 0.04)
    R.box('rim', -0.85, 0.18, 0.85, 0.26, -0.3, 0.3, rim, 0.02)
    # Арка: эллипс из сегментов-брусков.
    n = 22
    pts = [(math.cos(math.pi - math.pi * i / n) * w, 0.2 + math.sin(math.pi * i / n) * (h - 0.2)) for i in range(n + 1)]
    for i in range(n):
        R.beam('arch', pts[i], pts[i + 1], 0.2, -0.12, 0.12, frame)
    for i in range(9):
        a = math.pi - math.pi * i / 8
        x, z = math.cos(a) * w, 0.2 + math.sin(a) * (h - 0.2)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=4, ring_count=2, radius=0.17, location=(x, -0.14, z))
        g = bpy.context.object
        g.scale = (0.8, 0.6, 1.1)
        g.data.materials.append(ruby if i % 2 == 0 else ame)


# --- Крепь и лестницы по материалам -------------------------------------------------------------

## Материал крепи и лестниц: [цвет, шероховатость, металличность, узор ('wave' — волокна дерева,
## 'noise' — пятна камня), сила узора, грани (алмаз — плоские фаски)].
BEAM_LOOK = {
    'wood': ['#a8713f', 0.6, 0.0, 'wave', 0.35, False],
    'stone': ['#a3a6b4', 0.85, 0.0, 'noise', 0.3, False],
    'brick': ['#b9533a', 0.75, 0.0, 'noise', 0.25, False],
    'iron': ['#7d8796', 0.4, 0.5, 'noise', 0.0, False],
    'silver': ['#d9dee6', 0.2, 0.7, 'noise', 0.0, False],
    'gold': ['#e6b444', 0.3, 0.8, 'noise', 0.0, False],
    'diamond': ['#bdeefa', 0.06, 0.15, 'noise', 0.0, True],
}


def beam_mat(m):
    c, rough, metal, kind, grain, _ = BEAM_LOOK[m]
    return R.mat('beam_' + m, c, rough, grain, kind, metal)


def _bar(name, x0, z0, x1, z1, y0, y1, m, look):
    """Брус крепи: у алмаза — гранёный (плоские фаски), у остальных — скруглённый."""
    return R.box(name, x0, z0, x1, z1, y0, y1, m, 0.035, 1 if BEAM_LOOK[look][5] else 3)


def support(look):
    """Рама тоннеля 1×1 м: две стойки и верхняя балка (у дерева — с укосинами), болты."""
    m = beam_mat(look)
    bolt = R.mat('bolt', '#3b3940', 0.35, metal=0.5)
    for sx in (-1, 1):
        _bar('post', sx * 0.25 - 0.07, 0.0, sx * 0.25 + 0.07, 0.86, -0.07, 0.07, m, look)
    _bar('cap', -0.42, 0.84, 0.42, 0.98, -0.08, 0.08, m, look)
    if look == 'wood':
        for sx in (-1, 1):
            R.beam('brace', (sx * 0.25, 0.62), (sx * 0.06, 0.86), 0.07, -0.05, 0.05, m)
    for sx in (-1, 1):
        R.bolt(sx * 0.25, 0.91, -0.09, bolt, 0.03)


def slice_frame(look):
    """Рама шахты на метр (срез 1×3 м): стойки у краёв и верхняя балка во всю ширину."""
    m = beam_mat(look)
    bolt = R.mat('bolt', '#3b3940', 0.35, metal=0.5)
    for sx in (-1, 1):
        _bar('post', sx * 0.375 - 0.07, 0.0, sx * 0.375 + 0.07, 2.86, -0.07, 0.07, m, look)
    _bar('cap', -0.5, 2.82, 0.5, 2.98, -0.08, 0.08, m, look)
    for sx in (-1, 1):
        R.bolt(sx * 0.375, 2.9, -0.09, bolt, 0.03)
        R.bolt(sx * 0.375, 1.5, -0.08, bolt, 0.025)


def ladder(look):
    """Звено лестницы 1 м (повторяется по высоте): тетивы и три ступени."""
    m = beam_mat(look)
    for sx in (-1, 1):
        _bar('rail', sx * 0.25 - 0.05, -0.02, sx * 0.25 + 0.05, 1.02, -0.05, 0.05, m, look)
    for z in (1 / 6, 0.5, 5 / 6):
        _bar('rung', -0.23, z - 0.035, 0.23, z + 0.035, -0.035, 0.035, m, look)


# --- Бур, геоскважина, лифт -------------------------------------------------------------------

def drill(look):
    """Бур 3×3, смотрит вправо (игра поворачивает): корпус с мотором (x 0..2) и сверло (x 2..3).
    Лампу и вращение сверла рисует игра."""
    body_c = '#e09a2a' if look == 'base' else BEAM_LOOK[look][0]
    body = R.mat('body', body_c, 0.45, metal=0.2 if look == 'base' else 0.4)
    dark = R.mat('dark', '#5a3a12' if look == 'base' else '#2f6273', 0.6)
    steel = R.mat('steel', '#9aa0aa' if look == 'base' else '#d6f7ff', 0.25 if look == 'base' else 0.06, metal=0.7 if look == 'base' else 0.15)
    R.box('body', 0.1, 0.1, 1.9, 2.9, -0.6, 0.6, body, 0.14)
    for k in range(3):
        R.box('grille', 0.7 + k * 0.25, 0.9, 0.8 + k * 0.25, 2.1, -0.62, -0.58, dark, 0.02)
    R.box('mount', 1.8, 0.55, 2.1, 2.45, -0.45, 0.45, steel, 0.06)
    cyl_x('bit', 1.3, 2.0, 2.97, steel, z=1.5, y=0.0, r2=0.03)
    for x in (2.25, 2.5, 2.72):
        rr = 1.3 * (2.97 - x) / 0.97
        cyl_x('flute', rr + 0.01, x - 0.025, x + 0.025, dark, z=1.5, y=0.0)
    R.bolt(0.32, 2.62, -0.62, dark, 0.07)


def probe():
    """Геоскважина 2×2: вышка-тренога с перекладинами, мотор внизу, блок наверху."""
    steel = R.mat('steel', '#949aa6', 0.35, metal=0.6)
    motor = R.mat('motor', '#e09a2a', 0.45, metal=0.2)
    dark = R.mat('dark', '#3a3f47', 0.45, metal=0.5)
    top = (0.0, 1.9)
    for sx in (-1, 1):
        R.beam('leg', (sx * 0.86, 0.02), top, 0.09, -0.06, 0.06, steel)
    R.beam('leg_back', (0.0, 0.02), top, 0.08, 0.25, 0.37, steel)
    for k in (0.4, 0.7):
        z = 0.02 + (top[1] - 0.02) * k
        half = 0.86 * (1 - k)
        R.box('bar', -half, z - 0.03, half, z + 0.03, -0.04, 0.04, steel, 0.01)
    R.box('motor', -0.28, 0.04, 0.28, 0.46, -0.25, 0.25, motor, 0.06)
    disc('pulley', 0.12, 0.08, 0.0, 1.82, -0.08, dark)


def cab(width, cargo):
    """Кабина лифта (клетка: видно, кто внутри): рама, крыша, пол, поручень."""
    frame = R.mat('frame', '#7f8a96' if cargo else '#dc9e38', 0.4, metal=0.4 if cargo else 0.2)
    dark = R.mat('dark', '#3a3f47', 0.45, metal=0.5)
    w = width
    for x in (-w / 2 + 0.06, w / 2 - 0.06):
        R.box('post', x - 0.06, 0.0, x + 0.06, 2.0, -0.08, 0.08, frame, 0.02)
    R.box('roof', -w / 2, 1.86, w / 2, 2.0, -0.4, 0.1, frame, 0.03)
    R.box('floor', -w / 2, 0.0, w / 2, 0.1, -0.4, 0.1, dark, 0.02)
    R.box('rail', -w / 2 + 0.06, 0.95, w / 2 - 0.06, 1.0, -0.06, 0.0, frame, 0.01)
    R.box('hook', -0.06, 2.0, 0.06, 2.12, -0.05, 0.05, dark, 0.01)


def rail(look):
    """Звено направляющей лифта 1 м (повторяется): рельс-тавр и кронштейн с болтами."""
    m = beam_mat(look)
    bolt = R.mat('bolt', '#3b3940', 0.35, metal=0.5)
    _bar('web', -0.03, -0.02, 0.03, 1.02, -0.06, 0.06, m, look)
    _bar('flange', -0.08, -0.02, 0.08, 1.02, 0.03, 0.07, m, look)
    _bar('bracket', -0.1, 0.42, 0.1, 0.58, -0.08, 0.08, m, look)
    R.bolt(0.0, 0.5, -0.09, bolt, 0.025)


# --- Сборка и рендер -------------------------------------------------------------------------

## Имя: [построить, рамка (x0, x1, z0, z1) в метрах]. Опорная точка спрайта — x = 0, z = 0.
STRUCTURES = {
    'rocket_chem': [lambda: rocket(False), (-2.5, 2.5, -0.1, 14.3)],
    'rocket_nuclear': [lambda: rocket(True), (-2.6, 2.6, -0.1, 14.6)],
    'launch_tower': [tower, (-2.0, 0.8, -0.1, 15.1)],
    'ship_hull': [ship_hull, (-2.6, 11.7, -0.3, 4.4)],
    'teleport': [teleport, (-1.5, 1.5, -0.05, 2.95)],
}
STRUCTURES.update({
    'drill': [lambda: drill('base'), (0.0, 3.0, 0.0, 3.0)],
    'drill_diamond': [lambda: drill('diamond'), (0.0, 3.0, 0.0, 3.0)],
    'probe': [probe, (-1.0, 1.0, 0.0, 2.0)],
    'cab_passenger': [lambda: cab(2.0, False), (-1.0, 1.0, 0.0, 2.15)],
    'cab_cargo': [lambda: cab(3.0, True), (-1.5, 1.5, 0.0, 2.15)],
})
for _m in BEAM_LOOK:
    STRUCTURES['support_' + _m] = [lambda m=_m: support(m), (-0.5, 0.5, 0.0, 1.0)]
    STRUCTURES['slice_' + _m] = [lambda m=_m: slice_frame(m), (-0.5, 0.5, 0.0, 3.0)]
    STRUCTURES['ladder_' + _m] = [lambda m=_m: ladder(m), (-0.5, 0.5, 0.0, 1.0)]
    STRUCTURES['rail_' + _m] = [lambda m=_m: rail(m), (-0.15, 0.15, 0.0, 1.0)]


def light_and_camera(frame):
    x0, x1, z0, z1 = frame
    sc = bpy.context.scene
    world = bpy.data.worlds.new('w')
    sc.world = world
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.9, 0.85, 0.8, 1)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.45
    bpy.ops.object.light_add(type='SUN')
    key = bpy.context.object
    key.data.energy = 2.6
    key.data.angle = math.radians(25)
    key.data.color = (1.0, 0.92, 0.82)
    key.rotation_euler = (math.radians(50), math.radians(-25), 0)
    bpy.ops.object.light_add(type='SUN')
    fill = bpy.context.object
    fill.data.energy = 0.8
    fill.data.angle = math.radians(60)
    fill.rotation_euler = (math.radians(85), math.radians(15), 0)
    w, h = x1 - x0, z1 - z0
    bpy.ops.object.camera_add(location=((x0 + x1) / 2, -30, (z0 + z1) / 2), rotation=(math.radians(90), 0, 0))
    cam = bpy.context.object
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = max(w, h)
    cam.data.clip_end = 100
    sc.camera = cam
    sc.render.resolution_x = int(round(w * PX))
    sc.render.resolution_y = int(round(h * PX))


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    for name, (build, frame) in STRUCTURES.items():
        if ONLY and name not in ONLY:
            continue
        R.reset()
        build()
        light_and_camera(frame)
        bpy.context.scene.render.filepath = os.path.join(OUT, name + '.png')
        bpy.ops.render.render(write_still=True)
        print('rendered', name)
