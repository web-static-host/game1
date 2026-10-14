## Комнаты для игры: модель в Blender и рендер в спрайты (assets/rooms/).
## Вид строго сбоку, 1 клетка = 1 м, рендер 2×: 64 px на клетку.
## Запуск: blender -b -P art_src/rooms/build_rooms.py  (или Python с модулем bpy).
import os, sys, math, random
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
# ROOMS_OUT, ROOMS_WIDTHS=6, ROOMS_SAMPLES=24 — для быстрых проб.
OUT = os.environ.get('ROOMS_OUT') or os.path.join(HERE, '..', '..', 'assets', 'rooms')
PX = 64           # пикселей на метр (клетку) в рендере
H = 3.0           # высота комнаты
WIDTHS = [int(v) for v in os.environ.get('ROOMS_WIDTHS', '3,6,9').split(',')]


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
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


def mat(name, col, rough=0.6, grain=0.0):
    col = lin(col) if isinstance(col, str) else col
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes['Principled BSDF']
    bsdf.inputs['Roughness'].default_value = rough
    if grain > 0:
        # Мягкие волокна дерева: волны вдоль доски слегка меняют тон.
        tc = nt.nodes.new('ShaderNodeTexCoord')
        wave = nt.nodes.new('ShaderNodeTexWave')
        wave.wave_type = 'BANDS'
        wave.bands_direction = 'Z'
        wave.inputs['Scale'].default_value = 2.2
        wave.inputs['Distortion'].default_value = 6.0
        wave.inputs['Detail'].default_value = 1.5
        nt.links.new(tc.outputs['Object'], wave.inputs['Vector'])
        mix = nt.nodes.new('ShaderNodeMix')
        mix.data_type = 'RGBA'
        mix.inputs['Factor'].default_value = 0.0
        ramp = nt.nodes.new('ShaderNodeMapRange')
        ramp.inputs['To Min'].default_value = 0.0
        ramp.inputs['To Max'].default_value = grain
        nt.links.new(wave.outputs['Fac'], ramp.inputs['Value'])
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


def bolt(x, z, y, m):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.045, location=(x, y, z), segments=12, ring_count=8)
    o = bpy.context.object
    o.scale = (1, 0.5, 1)
    o.data.materials.append(m)
    bpy.ops.object.shade_smooth()


# Объём «разрезом»: внутренность — настоящая коробка глубиной D, которую потом сжимаем
# к задней стене на постоянный отступ (вынужденная перспектива). Камера ортогональная,
# поэтому передняя рама ровно совпадает с клетками, а глубина одинакова у комнат 3/6/9.
D = 1.5                 # глубина комнаты (м)
FS, FT, FB = 0.2, 0.22, 0.14   # толщина передней рамы: бок, верх, низ
INSET = (0.36, 0.3, 0.46)      # насколько сужается к задней стене: бок, потолок, пол


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


def planks_along(name, axis, a0, a1, b0, b1, plane, side, mats, rnd, ph=0.3, t=0.06):
    """Доски поверхности. axis='x' — доски вдоль x (рядами по второй оси b),
    plane — координата поверхности по третьей оси, side — куда толщина (±1)."""
    out = []
    b = b0
    row = 0
    while b < b1 - 0.01:
        b2 = min(b1, b + ph)
        a = a0 if row % 2 == 0 else a0 - rnd.uniform(0.6, 1.4)
        while a < a1:
            ln = rnd.uniform(1.6, 2.8)
            x0, x1 = max(a0, a), min(a1, a + ln)
            if x1 - x0 > 0.05:
                c0, c1 = sorted((plane, plane + side * t))
                m = rnd.choice(mats)
                if axis == 'xz':      # задняя стена: доски по x, ряды по z, толщина по y
                    out.append(box(name, x0 + .015, b + .015, x1 - .015, b2 - .015, c0, c1, m, .03))
                elif axis == 'xy':    # пол/потолок: доски по x, ряды по y, толщина по z
                    o = box(name, x0 + .015, c0, x1 - .015, c1, b + .015, b2 - .015, m, .03)
                    out.append(o)
            a += ln
        b = b2
        row += 1
    return out


def wood_room(w):
    rnd = random.Random(w)
    tones = ['#d9904f', '#cc8245', '#e29c5a', '#c47a40']
    planks = [mat('plank%d' % i, c, 0.65, 0.35) for i, c in enumerate(tones)]
    floor_t = [mat('fl%d' % i, c, 0.5, 0.3) for i, c in enumerate(['#b06a3a', '#a5613a', '#b9743f'])]
    ceil_t = [mat('cl%d' % i, c, 0.6, 0.3) for i, c in enumerate(['#9c5a2e', '#a96534'])]
    gap = mat('gap', '#3a1f10', 0.9)
    post = mat('post', '#8a4f26', 0.55, 0.3)
    frame = mat('frame', '#7a4422', 0.5, 0.3)
    iron = mat('iron', '#3b3536', 0.35)
    X0, X1, Z0, Z1 = FS, w - FS, FB, H - FT
    inner = []
    # Тёмная подложка за всеми досками — в щелях между ними.
    inner.append(box('back_gap', X0 - .1, Z0 - .1, X1 + .1, Z1 + .1, D + 0.06, D + 0.12, gap, 0))
    inner.append(box('floor_gap', X0 - .1, Z0 - .14, X1 + .1, Z0 - .06, -0.1, D + .1, gap, 0))
    inner.append(box('ceil_gap', X0 - .1, Z1 + .06, X1 + .1, Z1 + .14, -0.1, D + .1, gap, 0))
    # Задняя стена, пол, потолок — доски.
    inner += planks_along('back', 'xz', X0, X1, Z0, Z1, D, 1, planks, rnd)
    inner += planks_along('floor', 'xy', X0, X1, 0.0, D, Z0, -1, floor_t, rnd, ph=0.3)
    inner += planks_along('ceil', 'xy', X0, X1, 0.0, D, Z1, 1, ceil_t, rnd, ph=0.375)
    # Боковые стены: доски вдоль глубины, рядами по высоте.
    for x, sd in ((X0, -1), (X1, 1)):
        g0, g1 = sorted((x + sd * .06, x + sd * .12))
        inner.append(box('side_gap', g0, Z0 - .1, g1, Z1 + .1, -0.1, D + .1, gap, 0))
        z = Z0
        while z < Z1 - 0.01:
            z2 = min(Z1, z + 0.3)
            c0, c1 = sorted((x, x + sd * 0.06))
            inner.append(box('side', c0, z + .015, c1, z2 - .015, -0.05, D + .02, rnd.choice(planks), .03))
            z = z2
    # Стойки в задних углах и балки по рёбрам потолка и пола.
    for x in (X0, X1 - 0.2):
        inner.append(box('corner', x, Z0, x + 0.2, Z1, D - 0.2, D, post, .04))
    inner.append(box('back_top', X0, Z1 - 0.16, X1, Z1, D - 0.16, D, post, .04))
    inner.append(box('back_low', X0, Z0, X1, Z0 + 0.1, D - 0.1, D, post, .03))
    for x in (X0, X1 - 0.16):
        inner.append(box('ceil_edge', x, Z1 - 0.16, x + 0.16, Z1, 0.0, D, post, .04))
    # Через 3 м — стойки на задней стене с укосинами под потолочной балкой.
    for x in range(3, w, 3):
        inner.append(box('post', x - 0.1, Z0, x + 0.1, Z1, D - 0.14, D, post, .04))
        for side in (-1, 1):
            px = x + side * 0.1
            inner.append(beam('brace', (px - side * 0.06, Z1 - 0.7), (px + side * 0.5, Z1 - 0.12), 0.12, D - 0.12, D - 0.02, post))
            bolt(px + side * 0.06, Z1 - 0.56, D - 0.13, iron)
            inner.append(bpy.context.object)
    # Потолочные балки поперёк, в глубину.
    for x in range(3, w, 3):
        inner.append(box('joist', x - 0.09, Z1 - 0.14, x + 0.09, Z1, 0.0, D, post, .04))
    warp(inner, w)
    # Передняя рама — толстые брусья поверх разреза, с болтами в углах.
    box('f_left', 0, 0, FS, H, -0.2, 0.06, frame, .05)
    box('f_right', w - FS, 0, w, H, -0.2, 0.06, frame, .05)
    box('f_top', 0, H - FT, w, H, -0.22, 0.04, frame, .05)
    box('f_bot', 0, 0, w, FB, -0.24, 0.04, frame, .04)
    for x in (FS / 2, w - FS / 2):
        for z in (H - FT / 2, FB / 2 + 0.01):
            bolt(x, z, -0.24, iron)
    for x in range(3, w, 3):
        bolt(x, H - FT / 2, -0.24, iron)


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
    for w in WIDTHS:
        reset()
        wood_room(w)
        light_and_camera(w)
        bpy.context.scene.render.filepath = os.path.join(OUT, 'wood_%d.png' % w)
        bpy.ops.render.render(write_still=True)
        print('rendered', w)
