## Рендер glb-модели гаврика тем же светом, что и в листах: python3 view_model.py <glb> <папка> [tex|clay]
## mode: tex — как есть; clay — без текстуры, тело одним цветом.
import math, os, sys
import bpy
GLB, OUT = sys.argv[1], sys.argv[2]
MODE = sys.argv[3] if len(sys.argv) > 3 else 'tex'
os.makedirs(OUT, exist_ok=True)
sys.path.insert(0, '/home/user/game1/art_src/characters/new_style')
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)
ob = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
# Масштаб: рост 2.4 м, ступни на полу, по центру.
import mathutils
bb = [ob.matrix_world @ mathutils.Vector(c) for c in ob.bound_box]
h = max(v.z for v in bb) - min(v.z for v in bb)
k = 2.4 / h
ob.scale = [s * k for s in ob.scale]
bpy.context.view_layer.update()
bb = [ob.matrix_world @ mathutils.Vector(c) for c in ob.bound_box]
cx = (max(v.x for v in bb) + min(v.x for v in bb)) / 2
cy = (max(v.y for v in bb) + min(v.y for v in bb)) / 2
ob.location.x -= cx; ob.location.y -= cy; ob.location.z -= min(v.z for v in bb)
if MODE == 'clay':
    m = bpy.data.materials.new('Clay'); m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = (0.913, 0.51, 0.0, 1)
    b.inputs['Roughness'].default_value = 0.6
    ob.data.materials.clear(); ob.data.materials.append(m)
else:
    mats = {m.name.split('.')[0]: m for m in ob.data.materials}
    if 'white' in mats and os.environ.get('EYE', '1') == '1':
        import json
        info = json.load(open(GLB + '.eye.json'))
        ex, ez, ir, pr = info['x'] * k, info['z'] * k, info['iris'] * k, info['pupil'] * k
        eye = bpy.data.materials.new('EyeProc'); eye.use_nodes = True
        nt = eye.node_tree; N = nt.nodes; L = nt.links
        b = N['Principled BSDF']; b.inputs['Roughness'].default_value = 0.3
        geo = N.new('ShaderNodeNewGeometry')
        sep = N.new('ShaderNodeSeparateXYZ'); L.new(geo.outputs['Position'], sep.inputs[0])
        # координаты: модель уже сдвинута/отмасштабирована объектом — переведём в объектные
        tc = N.new('ShaderNodeTexCoord'); sep2 = N.new('ShaderNodeSeparateXYZ'); L.new(tc.outputs['Object'], sep2.inputs[0])
        dx = N.new('ShaderNodeMath'); dx.operation = 'SUBTRACT'; L.new(sep2.outputs['X'], dx.inputs[0]); dx.inputs[1].default_value = info['x']
        dz = N.new('ShaderNodeMath'); dz.operation = 'SUBTRACT'; L.new(sep2.outputs['Z'], dz.inputs[0]); dz.inputs[1].default_value = info['z']
        cmb = N.new('ShaderNodeCombineXYZ'); L.new(dx.outputs[0], cmb.inputs['X']); L.new(dz.outputs[0], cmb.inputs['Y'])
        ln = N.new('ShaderNodeVectorMath'); ln.operation = 'LENGTH'; L.new(cmb.outputs[0], ln.inputs[0])
        dv = N.new('ShaderNodeMath'); dv.operation = 'DIVIDE'; L.new(ln.outputs['Value'], dv.inputs[0]); dv.inputs[1].default_value = info['eye_r']
        ramp = N.new('ShaderNodeValToRGB'); L.new(dv.outputs[0], ramp.inputs['Fac'])
        cr = ramp.color_ramp; cr.interpolation = 'LINEAR'
        R = info['eye_r']
        def stop(pos, col):
            e = cr.elements.new(min(pos / R, 1.0)); e.color = col
        cr.elements[0].position = 0.0; cr.elements[0].color = (0.005, 0.005, 0.006, 1)
        cr.elements[1].position = 1.0; cr.elements[1].color = (0.92, 0.92, 0.9, 1)
        stop(info['pupil'] - 0.004, (0.005, 0.005, 0.006, 1)); stop(info['pupil'] + 0.004, (0.06, 0.32, 0.95, 1))
        stop(info['iris'] - 0.025, (0.03, 0.2, 0.8, 1)); stop(info['iris'] - 0.008, (0.01, 0.06, 0.3, 1))
        stop(info['iris'] + 0.004, (0.92, 0.92, 0.9, 1))
        L.new(ramp.outputs['Color'], b.inputs['Base Color'])
        for i, m in enumerate(ob.data.materials):
            if m.name.split('.')[0] in ('white', 'iris', 'pupil'):
                ob.data.materials[i] = eye
    if os.environ.get('BODY'):
        h = os.environ['BODY'].lstrip('#')
        c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
        c = [((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92 for v in c]
        for m in ob.data.materials:
            if m.name.split('.')[0] == 'body':
                m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (*c, 1)
sc = bpy.context.scene
def light(name, loc, energy, col, size):
    ld = bpy.data.lights.new(name, 'AREA'); ld.energy = energy; ld.color = col; ld.size = size
    o = bpy.data.objects.new(name, ld); o.location = loc; sc.collection.objects.link(o)
    c = o.constraints.new('TRACK_TO'); c.target = ob
    o['base'] = list(loc)
light('Key', (-3.2, -3.6, 5.0), 330, (1.0, 0.96, 0.9), 4.5)
light('Fill', (4.0, -2.5, 1.8), 35, (0.8, 0.88, 1.0), 5.0)
light('Rim', (2.5, 4.0, 4.0), 700, (1.0, 0.98, 0.95), 2.5)
light('Rim2', (-2.8, 3.5, 2.5), 300, (0.9, 0.95, 1.0), 2.5)
light('Bounce', (0.0, -2.5, -0.6), 60, (1.0, 0.92, 0.8), 4.0)
w = bpy.data.worlds.new('W'); sc.world = w; w.use_nodes = True
w.node_tree.nodes['Background'].inputs['Color'].default_value = (0.6, 0.65, 0.72, 1)
w.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.12
bpy.ops.mesh.primitive_plane_add(size=40); bpy.context.object.is_shadow_catcher = True
sc.render.engine = 'CYCLES'; sc.cycles.device = 'CPU'; sc.cycles.samples = int(os.environ.get('SAMPLES', '32')); sc.cycles.use_denoising = True
sc.render.film_transparent = True; sc.view_settings.view_transform = 'Standard'
cam = bpy.data.objects.new('Cam', bpy.data.cameras.new('Cam')); cam.data.lens = 55; sc.collection.objects.link(cam)
t = bpy.data.objects.new('T', None); t.location = (0, 0, 1.2); sc.collection.objects.link(t)
cam.constraints.new('TRACK_TO').target = t; sc.camera = cam
sc.render.resolution_x, sc.render.resolution_y = 700, 800
# Где «перед» у модели: пробуем — Tripo обычно смотрит в -Y.
for yaw in [int(x) for x in os.environ.get('YAWS', '0,-40,-90,180').split(',')]:
    a = math.radians(yaw)
    cam.location = (math.sin(a) * 7.2, -math.cos(a) * 7.2, 1.8)
    for o in sc.objects:
        if o.type == 'LIGHT':
            bx, by, bz = o['base']; o.location = (bx * math.cos(a) - by * math.sin(a), bx * math.sin(a) + by * math.cos(a), bz)
    sc.render.filepath = os.path.join(OUT, '%s%s_%d.png' % (MODE, os.environ.get('BODY', '').lstrip('#'), yaw))
    bpy.ops.render.render(write_still=True)
