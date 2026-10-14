## Комнаты для игры: модель в Blender и рендер в спрайты (assets/rooms/).
## Вид строго сбоку, 1 клетка = 1 м, рендер 2×: 64 px на клетку.
## Запуск: blender -b -P art_src/rooms/build_rooms.py  (или Python с модулем bpy).
import os, sys, math, random
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', '..', 'assets', 'rooms')
PX = 64           # пикселей на метр (клетку) в рендере
H = 3.0           # высота комнаты
WIDTHS = [3, 6, 9]


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 96
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


def wood_room(w):
    rnd = random.Random(w)
    tones = ['#d9904f', '#cc8245', '#e29c5a', '#c47a40']
    planks = [mat('plank%d' % i, c, 0.65, 0.35) for i, c in enumerate(tones)]
    gap = mat('gap', '#3a1f10', 0.9)
    post = mat('post', '#8a4f26', 0.55, 0.3)
    floor = mat('floor', '#a8653a', 0.5, 0.3)
    iron = mat('iron', '#3b3536', 0.35)
    # Задняя стена: горизонтальные доски со сдвинутыми стыками; за ними тёмная щель.
    box('back', 0, 0, w, H, 0.32, 0.4, gap, 0)
    ph = 0.3
    z = 0.0
    row = 0
    while z < H - 0.01:
        x = 0.0 if row % 2 == 0 else -rnd.uniform(0.6, 1.4)
        while x < w:
            ln = rnd.uniform(1.6, 2.8)
            x0, x1 = max(0.0, x), min(w, x + ln)
            if x1 - x0 > 0.05:
                box('p', x0 + 0.015, z + 0.015, x1 - 0.015, z + ph - 0.015, 0.18, 0.32, rnd.choice(planks), 0.035)
            x += ln
        z += ph
        row += 1
    # Пол — толстая доска, потолок — балка; по бокам и через 3 м — стойки с укосинами.
    box('floor', -0.02, 0.0, w + 0.02, 0.2, -0.25, 0.3, floor, 0.04)
    box('ceil', -0.02, H - 0.24, w + 0.02, H, -0.2, 0.3, post, 0.04)
    xs = list(range(0, w + 1, 3))
    for x in xs:
        x0 = x - 0.0 if x == 0 else (x - 0.24 if x == w else x - 0.12)
        x0 = 0.0 if x == 0 else x0
        box('post', x0, 0.18, x0 + 0.24, H - 0.2, -0.18, 0.28, post, 0.04)
        for side in (-1, 1):
            if (x == 0 and side < 0) or (x == w and side > 0):
                continue
            px = x0 + (0.24 if side > 0 else 0.0)
            beam('brace', (px - side * 0.08, H - 0.8), (px + side * 0.6, H - 0.18), 0.13, -0.12, 0.22, post)
            bolt(px + side * 0.07, H - 0.64, -0.19, iron)
        bolt(x0 + 0.12, H - 0.12, -0.21, iron)
        bolt(x0 + 0.12, 0.1, -0.26, iron)


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
