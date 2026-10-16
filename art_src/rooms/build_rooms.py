## Комнаты для игры: модель в Blender и рендер в спрайты (assets/rooms/).
## Вид строго сбоку, 1 клетка = 1 м, рендер 2×: 64 px на клетку.
## Запуск: blender -b -P art_src/rooms/build_rooms.py  (или Python с модулем bpy).
import os, sys, math, random
import bpy
import bmesh

HERE = os.path.dirname(os.path.abspath(__file__))
# ROOMS_OUT, ROOMS_WIDTHS=6, ROOMS_MATERIALS=stone, ROOMS_SAMPLES=24 — для быстрых проб.
OUT = os.environ.get('ROOMS_OUT') or os.path.join(HERE, '..', '..', 'assets', 'rooms')
PX = int(os.environ.get('ROOMS_PX', 64))   # пикселей на метр (клетку); ROOMS_PX=256 — крупно, основа для ChatGPT
H = 3.0           # высота комнаты
WIDTHS = [int(v) for v in os.environ.get('ROOMS_WIDTHS', '3,6,9').split(',')]
# Глины нет: автор её уберёт из игры, там остаётся рисунок кодом.
MATERIALS = os.environ.get('ROOMS_MATERIALS', 'wood,stone,brick,metal').split(',')


def reset():
    global _bumps
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _bumps = None    # текстура неровностей камня удалена вместе со сценой
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = int(os.environ.get('ROOMS_SAMPLES', 96))
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.view_settings.view_transform = 'Standard'
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    return sc


def lin(hexcol):
    """Цвет «как на экране» (sRGB, '#c87841') в линейный для Blender."""
    h = hexcol.lstrip('#')
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return tuple(out)


def mat(name, col, rough=0.6, grain=0.0, kind='wave', metal=0.0):
    """grain — сила узора: 'wave' — волокна дерева, 'noise' — пятна камня/кирпича."""
    col = lin(col) if isinstance(col, str) else col
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes['Principled BSDF']
    bsdf.inputs['Roughness'].default_value = rough
    bsdf.inputs['Metallic'].default_value = metal
    if grain > 0:
        tc = nt.nodes.new('ShaderNodeTexCoord')
        if kind == 'wave':
            # Мягкие волокна дерева: волны вдоль доски слегка меняют тон.
            tex = nt.nodes.new('ShaderNodeTexWave')
            tex.wave_type = 'BANDS'
            tex.bands_direction = 'Z'
            tex.inputs['Scale'].default_value = 2.2
            tex.inputs['Distortion'].default_value = 6.0
            tex.inputs['Detail'].default_value = 1.5
        else:
            tex = nt.nodes.new('ShaderNodeTexNoise')
            tex.inputs['Scale'].default_value = 6.0
            tex.inputs['Detail'].default_value = 4.0
        nt.links.new(tc.outputs['Object'], tex.inputs['Vector'])
        mix = nt.nodes.new('ShaderNodeMix')
        mix.data_type = 'RGBA'
        mix.inputs['Factor'].default_value = 0.0
        ramp = nt.nodes.new('ShaderNodeMapRange')
        ramp.inputs['To Min'].default_value = 0.0
        ramp.inputs['To Max'].default_value = grain
        nt.links.new(tex.outputs['Fac'], ramp.inputs['Value'])
        nt.links.new(ramp.outputs['Result'], mix.inputs['Factor'])
        mix.inputs['A'].default_value = (*col, 1)
        dark = tuple(c * 0.72 for c in col)
        mix.inputs['B'].default_value = (*dark, 1)
        nt.links.new(mix.outputs['Result'], bsdf.inputs['Base Color'])
    else:
        bsdf.inputs['Base Color'].default_value = (*col, 1)
    return m


def box(name, x0, z0, x1, z1, y0, y1, m, bevel=0.03):
    bpy.ops.mesh.primitive_cube_add()
    o = bpy.context.object
    o.name = name
    o.scale = ((x1 - x0) / 2, (y1 - y0) / 2, (z1 - z0) / 2)
    o.location = ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
    bpy.ops.object.transform_apply(scale=True)
    if bevel > 0:
        b = o.modifiers.new('bevel', 'BEVEL')
        b.width = bevel
        b.segments = 3
    o.data.materials.append(m)
    bpy.ops.object.shade_smooth()
    return o


def beam(name, a, b, thick, y0, y1, m):
    """Балка от точки a до b (x, z) — для укосин; вершины считаем сами, без поворотов."""
    dx, dz = b[0] - a[0], b[1] - a[1]
    ln = math.hypot(dx, dz)
    nx, nz = -dz / ln * thick / 2, dx / ln * thick / 2
    pts = [(a[0] + nx, a[1] + nz), (b[0] + nx, b[1] + nz), (b[0] - nx, b[1] - nz), (a[0] - nx, a[1] - nz)]
    verts = [(x, y, z) for y in (y0, y1) for (x, z) in pts]
    faces = [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    bv = o.modifiers.new('bevel', 'BEVEL')
    bv.width = 0.03
    bv.segments = 3
    o.data.materials.append(m)
    for f in me.polygons:
        f.use_smooth = True
    return o


def bolt(x, z, y, m, r=0.045):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=(x, y, z), segments=12, ring_count=8)
    o = bpy.context.object
    o.scale = (1, 0.5, 1)
    o.data.materials.append(m)
    bpy.ops.object.shade_smooth()
    return o


# Объём «разрезом»: внутренность — настоящая коробка глубиной D, которую потом сжимаем
# к задней стене на постоянный отступ (вынужденная перспектива). Камера ортогональная,
# поэтому передняя рама ровно совпадает с клетками, а глубина одинакова у комнат 3/6/9.
D = 1.5                 # глубина комнаты (м)
FS, FT, FB = 0.2, 0.22, 0.14   # толщина передней рамы: бок, верх, низ
INSET = (0.3, 0.42, 0.0)       # насколько сужается к задней стене: бок, потолок, пол (0 — пол виден ребром, как на прототипе)


def warp(objs, w):
    """Сжать вершины объектов к задней стене: чем глубже (y), тем ближе к центру."""
    X0, X1, Z0, Z1 = FS, w - FS, FB, H - FT
    for o in objs:
        bpy.context.view_layer.objects.active = o
        for s in bpy.context.selected_objects:
            s.select_set(False)
        o.select_set(True)
        bpy.ops.object.convert(target='MESH')
        mw = o.matrix_world.copy()
        inv = mw.inverted()
        for v in o.data.vertices:
            p = mw @ v.co
            k = min(1.0, max(0.0, p.y / D))
            ax, at, ab = INSET[0] * k, INSET[1] * k, INSET[2] * k
            x = X0 + ax + (p.x - X0) * (X1 - X0 - 2 * ax) / (X1 - X0)
            z = Z0 + ab + (p.z - Z0) * (Z1 - Z0 - ab - at) / (Z1 - Z0)
            p.x, p.z = x, z
            v.co = inv @ p
        o.data.update()


# Материалы комнат: кладка стен, потолок, рама, стойки. Размеры — в метрах:
# wall — (длина элемента от, до; высота ряда; шов), ceil — то же для потолка (ряды в глубину).
STYLES = {
    'wood': dict(
        wall=['#d9904f', '#cc8245', '#e29c5a', '#c47a40'], wall_size=(1.6, 2.8, 0.3, .015), wall_rough=0.65,
        grain=0.35, kind='wave', bevel=.03,
        ceil=['#9c5a2e', '#a96534'], ceil_size=(1.6, 2.8, 0.375, .015), ceil_grain=0.3,
        gap='#3a1f10', post='#8a4f26', frame='#7a4422', frame_grain=0.3, iron='#3b3536',
        braces=True, joists=True, bolts=True),
    'stone': dict(
        wall=['#9a9dbb', '#8f92b0', '#a4a7c3', '#878aa8', '#9d97ad'], wall_size=(0.42, 0.95, (0.3, 0.5), .035), wall_rough=0.85,
        grain=0.3, kind='noise', bevel=.06, rubble=True,
        ceil=['#7c7f99', '#8588a2', '#827d8e'], ceil_size=(0.5, 0.9, (0.35, 0.5), .035), ceil_grain=0.3,
        gap='#3f3d4e', post='#6e4a2e', frame='#5e3d24', frame_grain=0.3, iron='#3b3940',
        braces=False, joists=False, bolts=True, wood_frame=True),
    'brick': dict(
        wall=['#c9573d', '#b94f37', '#d0644a', '#ad4632'], wall_size=(0.34, 0.38, 0.16, .02), wall_rough=0.75,
        grain=0.2, kind='noise', bevel=.02,
        ceil=['#8a4f2a', '#96582f'], ceil_size=(1.6, 2.8, 0.375, .015), ceil_grain=0.3,
        gap='#e6d6bf', post='#9a432f', frame='#6b3c22', frame_grain=0.3, iron='#3b3536',
        braces=False, joists=True, bolts=True),
    'metal': dict(
        wall=['#7f8999', '#76808f', '#8892a1'], wall_size=(1.1, 1.3, 0.66, .03), wall_rough=0.55,
        grain=0.0, kind='noise', bevel=.03, metal=0.35,
        ceil=['#687180', '#6f7887'], ceil_size=(1.1, 1.3, 0.5, .03), ceil_grain=0.0,
        gap='#262b34', post='#5c6574', frame='#4d5562', frame_grain=0.0, iron='#2f343c',
        braces=True, joists=True, bolts=True, rivets=True),
}


def courses(a0, a1, b0, b1, size, rnd):
    """Кладка вразбежку: [(a0, a1, b0, b1)] — элементы рядами по b, длиной по a."""
    lo, hi, ph, g = size
    out = []
    b = b0
    row = 0
    while b < b1 - 0.01:
        # Высота ряда — число или (от, до): у бутовой кладки ряды разной высоты.
        h = rnd.uniform(*ph) if isinstance(ph, tuple) else ph
        b2 = min(b1, b + h)
        if b1 - b2 < 0.12:
            b2 = b1
        a = a0 if row % 2 == 0 else a0 - rnd.uniform(lo * 0.35, lo * 0.65)
        while a < a1:
            ln = rnd.uniform(lo, hi)
            x0, x1 = max(a0, a), min(a1, a + ln)
            if x1 - x0 > 0.05:
                out.append((x0 + g, x1 - g, b + g, b2 - g))
            a += ln
        b = b2
        row += 1
    return out


_bumps = None


def _clip(poly, px, pz, nx, nz, c):
    """Отрезать от выпуклого многоугольника часть, где nx*x + nz*z > c."""
    out = []
    for i in range(len(poly)):
        a, b = poly[i], poly[(i + 1) % len(poly)]
        da, db = a[0] * nx + a[1] * nz - c, b[0] * nx + b[1] * nz - c
        if da <= 0:
            out.append(a)
        if (da < 0) != (db < 0) and da != db:
            t = da / (da - db)
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


def stone_cells(u0, u1, v0, v1, rnd, size=0.42, gap=0.035):
    """Неровные камни на прямоугольнике: ячейки Вороного вокруг случайных точек
    (разного размера), чуть ужатые к центру — между ними шов."""
    pts = []
    tries = 0
    while tries < 4000:
        tries += 1
        p = (rnd.uniform(u0 - 0.2, u1 + 0.2), rnd.uniform(v0 - 0.2, v1 + 0.2))
        r = size * rnd.uniform(0.6, 1.25)
        if all((p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2 > (0.5 * (r + q[2])) ** 2 for q in pts):
            pts.append((p[0], p[1], r))
    cells = []
    for i, (x, z, r) in enumerate(pts):
        poly = [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
        for j, (x2, z2, r2) in enumerate(pts):
            if i == j or (x2 - x) ** 2 + (z2 - z) ** 2 > (3 * size) ** 2:
                continue
            # Граница смещена к меньшему камню — крупные камни занимают больше места.
            nx, nz = x2 - x, z2 - z
            ln = math.hypot(nx, nz)
            nx, nz = nx / ln, nz / ln
            k = r / (r + r2)
            mx, mz = x + (x2 - x) * k, z + (z2 - z) * k
            poly = _clip(poly, x, z, nx, nz, mx * nx + mz * nz - gap / 2)
            if len(poly) < 3:
                break
        if len(poly) >= 3:
            cells.append(poly)
    return cells


def stone_mesh(name, poly, to3d, thick, m):
    """Камень из многоугольника: выдавлен на thick в сторону комнаты, скруглён и бугрист."""
    global _bumps
    if _bumps is None:
        _bumps = bpy.data.textures.new('bumps', 'CLOUDS')
        _bumps.noise_scale = 0.15
    n = len(poly)
    verts = [to3d(u, v, 0.0) for u, v in poly] + [to3d(u, v, thick) for u, v in poly]
    faces = [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))]
    faces += [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.validate()
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)   # обход мог развернуться при переносе в 3D
    bm.to_mesh(me)
    bm.free()
    me.update()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    bv = o.modifiers.new('bevel', 'BEVEL')
    bv.width = thick * 0.45
    bv.segments = 2
    bv.limit_method = 'NONE'
    sub = o.modifiers.new('sub', 'SUBSURF')
    sub.levels = 2
    sub.render_levels = 2
    d = o.modifiers.new('bumps', 'DISPLACE')
    d.texture = _bumps
    d.texture_coords = 'GLOBAL'
    d.strength = 0.05
    o.data.materials.append(m)
    for f in me.polygons:
        f.use_smooth = True
    return o


def stones(name, u0, u1, v0, v1, to3d, mats, rnd, size=0.42):
    out = []
    for poly in stone_cells(u0, u1, v0, v1, rnd, size):
        # Нормаль грани наружу зависит от обхода; делаем обход против часовой.
        area = sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1] for i in range(len(poly)))
        if area < 0:
            poly = poly[::-1]
        out.append(stone_mesh(name, poly, to3d, rnd.uniform(0.09, 0.16), rnd.choice(mats)))
    return out


def room(material, w):
    st = STYLES[material]
    rnd = random.Random(w)
    metal = st.get('metal', 0.0)
    walls = [mat('wall%d' % i, c, st['wall_rough'], st['grain'], st['kind'], metal) for i, c in enumerate(st['wall'])]
    ceils = [mat('ceil%d' % i, c, st['wall_rough'], st['ceil_grain'], 'wave' if material in ('wood', 'brick') else 'noise', metal)
             for i, c in enumerate(st['ceil'])]
    gap = mat('gap', st['gap'], 0.9)
    dark_gap = mat('dark_gap', st.get('ceil_gap', '#2a1d16'), 0.9)
    # Рама и стойки: у кирпича и камня — деревянные (волокна), у остальных — как стены.
    fkind = 'wave' if material == 'brick' or st.get('wood_frame') else st['kind']
    post = mat('post', st['post'], 0.55, st['frame_grain'], fkind, metal)
    frame = mat('frame', st['frame'], 0.5, st['frame_grain'], fkind, metal)
    iron = mat('iron', st['iron'], 0.35, metal=0.5)
    bev = st['bevel']
    t = 0.06
    X0, X1, Z0, Z1 = FS, w - FS, FB, H - FT
    inner = []
    # Подложка за кладкой стен — в швах (у кирпича светлая, раствор); у потолка всегда тёмная.
    inner.append(box('back_gap', X0 - .1, Z0 - .1, X1 + .1, Z1 + .1, D + 0.06, D + 0.12, gap, 0))
    inner.append(box('floor_gap', X0 - .1, Z0 - .14, X1 + .1, Z0 - .06, -0.1, D + .1, dark_gap, 0))
    inner.append(box('ceil_gap', X0 - .1, Z1 + .06, X1 + .1, Z1 + .14, -0.1, D + .1, dark_gap, 0))
    # Задняя стена: элементы по x, ряды по z.
    rivet_at = []
    if st.get('rubble'):
        # Камни задней стены: плоскость y = D, толщина — к зрителю (y меньше).
        inner += stones('back', X0, X1, Z0, Z1, lambda u, v, d: (u, D + t - d, v), walls, rnd)
    for (a0, a1, b0, b1) in ([] if st.get('rubble') else courses(X0, X1, Z0, Z1, st['wall_size'], rnd)):
        inner.append(box('back', a0, b0, a1, b1, D, D + t, rnd.choice(walls), bev))
        if st.get('rivets'):
            for (rx, rz) in ((a0 + .07, b0 + .07), (a1 - .07, b0 + .07), (a0 + .07, b1 - .07), (a1 - .07, b1 - .07)):
                rivet_at.append((rx, rz))
    for (rx, rz) in rivet_at:
        inner.append(bolt(rx, rz, D - 0.005, iron, 0.03))
    # Потолок: ряды в глубину (по y), элементы по x.
    if st.get('rubble'):
        inner += stones('ceil', X0, X1, -0.05, D + 0.05, lambda u, v, d: (u, v, Z1 + t - d), ceils, rnd)
    for (a0, a1, b0, b1) in ([] if st.get('rubble') else courses(X0, X1, 0.0, D, st['ceil_size'], rnd)):
        inner.append(box('ceil', a0, Z1, a1, Z1 + t, b0, b1, rnd.choice(ceils), bev))
    # Боковые стены: ряды по высоте, элементы в глубину.
    for x, sd in ((X0, -1), (X1, 1)):
        g0, g1 = sorted((x + sd * .06, x + sd * .12))
        inner.append(box('side_gap', g0, Z0 - .1, g1, Z1 + .1, -0.1, D + .1, gap, 0))
        c0, c1 = sorted((x, x + sd * t))
        if st.get('rubble'):
            # Боковые камни: плоскость x = стена, толщина — внутрь комнаты.
            xs = x + sd * t
            inner += stones('side', -0.05, D + 0.05, Z0, Z1, lambda u, v, d, xs=xs, sd=sd: (xs - sd * d, u, v), walls, rnd)
            continue
        for (a0, a1, b0, b1) in courses(-0.05, D + 0.02, Z0, Z1, st['wall_size'], rnd):
            inner.append(box('side', c0, b0, c1, b1, a0, a1, rnd.choice(walls), bev))
    # Стойки в задних углах, балки по рёбрам потолка и низ задней стены.
    for x in (X0, X1 - 0.2):
        inner.append(box('corner', x, Z0, x + 0.2, Z1, D - 0.2, D, post, .04))
    inner.append(box('back_top', X0, Z1 - 0.16, X1, Z1, D - 0.16, D, post, .04))
    inner.append(box('back_low', X0, Z0, X1, Z0 + 0.1, D - 0.1, D, post, .03))
    for x in (X0, X1 - 0.16):
        inner.append(box('ceil_edge', x, Z1 - 0.16, x + 0.16, Z1, 0.0, D, post, .04))
    # Через 3 м — стойки на задней стене (у дерева и металла — с укосинами).
    for x in range(3, w, 3):
        inner.append(box('post', x - 0.1, Z0, x + 0.1, Z1, D - 0.14, D, post, .04))
        if not st['braces']:
            continue
        for side in (-1, 1):
            px = x + side * 0.1
            inner.append(beam('brace', (px - side * 0.06, Z1 - 0.7), (px + side * 0.5, Z1 - 0.12), 0.12, D - 0.12, D - 0.02, post))
            inner.append(bolt(px + side * 0.06, Z1 - 0.56, D - 0.13, iron))
    # Потолочные балки поперёк, в глубину.
    if st['joists']:
        for x in range(3, w, 3):
            inner.append(box('joist', x - 0.09, Z1 - 0.14, x + 0.09, Z1, 0.0, D, post, .04))
    warp(inner, w)
    # Передняя рама — толстые брусья поверх разреза.
    box('f_left', 0, 0, FS, H, -0.2, 0.06, frame, .05)
    box('f_right', w - FS, 0, w, H, -0.2, 0.06, frame, .05)
    box('f_top', 0, H - FT, w, H, -0.22, 0.04, frame, .05)
    box('f_bot', 0, 0, w, FB, -0.24, 0.04, frame, .04)
    if not st['bolts']:
        return
    for x in (FS / 2, w - FS / 2):
        for z in (H - FT / 2, FB / 2 + 0.01):
            bolt(x, z, -0.24, iron)
    step = 0.75 if st.get('rivets') else 3
    x = step
    while x < w - 0.3:
        bolt(x, H - FT / 2, -0.24, iron)
        if st.get('rivets'):
            bolt(x, FB / 2 + 0.01, -0.26, iron, 0.035)
        x += step


def light_and_camera(w):
    sc = bpy.context.scene
    world = bpy.data.worlds.new('w')
    sc.world = world
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.9, 0.85, 0.8, 1)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.35
    # Тёплый свет сверху-слева-спереди и мягкая заливка спереди.
    bpy.ops.object.light_add(type='SUN')
    key = bpy.context.object
    key.data.energy = 2.2
    key.data.angle = math.radians(25)
    key.data.color = (1.0, 0.88, 0.72)
    key.rotation_euler = (math.radians(50), math.radians(-25), 0)
    bpy.ops.object.light_add(type='SUN')
    fill = bpy.context.object
    fill.data.energy = 0.6
    fill.data.angle = math.radians(60)
    fill.rotation_euler = (math.radians(85), math.radians(15), 0)
    # Тёплый рассеянный свет внутри, под потолком у передней рамы.
    bpy.ops.object.light_add(type='AREA', location=(w / 2, 0.4, H - 0.45))
    inner = bpy.context.object
    inner.data.shape = 'RECTANGLE'
    inner.data.size = w * 0.8
    inner.data.size_y = 0.6
    inner.data.energy = 14 * w
    inner.data.color = (1.0, 0.82, 0.6)
    bpy.ops.object.camera_add(location=(w / 2, -20, H / 2), rotation=(math.radians(90), 0, 0))
    cam = bpy.context.object
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = max(w, H)
    sc.camera = cam
    sc.render.resolution_x = int(w * PX)
    sc.render.resolution_y = int(H * PX)


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    for material in MATERIALS:
        for w in WIDTHS:
            reset()
            room(material, w)
            light_and_camera(w)
            bpy.context.scene.render.filepath = os.path.join(OUT, '%s_%d.png' % (material, w))
            bpy.ops.render.render(write_still=True)
            print('rendered', material, w)
