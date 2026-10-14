class_name ModelSprites
extends Node
## 3D-модель жителя из Blender (assets/models/blue_buddy.glb), отрисованная в позы.
## При запуске один раз ставим все позы рядом в отдельной 3D-сцене и снимаем два кадра:
## цветной (тело белое, лицо в своих цветах) и маску (где тело — там красим в цвет генов).
## Дальше жители с такой моделью рисуются кусками атласа — так же дёшево, как 2D.
## Модель — треугольник с одним глазом, без мутаций; остальные жители — рисованные.

signal baked

const MODEL := "res://assets/models/blue_buddy.glb"
## Сторона клетки атласа, пикселей.
const CELL := 200
## Сколько метров модели помещается в клетку и где в ней ступни (от низа).
const SPAN := 5.0
const FOOT := 0.45
## Высота модели от ступней до макушки, м.
const HEIGHT := 2.4
## Модель смотрит немного вбок — в сторону движения (зеркалим для другой стороны).
const YAW := 28.0
## Глаз в позе покоя (м, в осях модели) и его радиус.
const EYE := Vector3(0.0, 1.69, 0.41)
const EYE_R := 0.27
const FACE_PARTS := ["Approved_Iris", "Approved_Pupil", "Approved_Glint", "Approved_GlintSmall"]

## Позы: куда поставить суставы — [кость, "to", точка следующего сустава] (м, оси модели:
## x — вправо, y — вверх, z — к зрителю) или [кость, ось, градусы]. Сначала родитель.
## Плечи (±0.92, 2.08), бёдра (±0.26, 0.7); плечо 0.71, предплечье 0.56, бедро и голень по 0.27.
## bones — список таких групп. closed — глаза закрыты.
const STEP_R := [["Thigh.R", "to", Vector3(0.28, 0.46, 0.16)], ["Shin.R", "to", Vector3(0.28, 0.22, 0.3)],
	["Thigh.L", "to", Vector3(-0.26, 0.44, -0.08)], ["Shin.L", "to", Vector3(-0.26, 0.19, -0.2)]]
const STEP_L := [["Thigh.L", "to", Vector3(-0.28, 0.46, 0.16)], ["Shin.L", "to", Vector3(-0.28, 0.22, 0.3)],
	["Thigh.R", "to", Vector3(0.26, 0.44, -0.08)], ["Shin.R", "to", Vector3(0.26, 0.19, -0.2)]]
const PASS_R := [["Thigh.R", "to", Vector3(0.27, 0.45, 0.08)], ["Shin.R", "to", Vector3(0.27, 0.25, 0.0)]]
const PASS_L := [["Thigh.L", "to", Vector3(-0.27, 0.45, 0.08)], ["Shin.L", "to", Vector3(-0.27, 0.25, 0.0)]]
const SWING_R := [["UpperArm.R", "to", Vector3(1.3, 1.6, -0.35)], ["UpperArm.L", "to", Vector3(-1.3, 1.6, 0.35)]]
const SWING_L := [["UpperArm.L", "to", Vector3(-1.3, 1.6, -0.35)], ["UpperArm.R", "to", Vector3(1.3, 1.6, 0.35)]]
const LIFT := [["UpperArm.R", "to", Vector3(1.05, 2.72, 0.1)], ["Forearm.R", "to", Vector3(0.5, 3.12, 0.15)],
	["UpperArm.L", "to", Vector3(-1.05, 2.72, 0.1)], ["Forearm.L", "to", Vector3(-0.5, 3.12, 0.15)]]
const HAMMER_UP := [["UpperArm.R", "to", Vector3(1.25, 2.68, 0.2)], ["Forearm.R", "to", Vector3(1.1, 3.22, 0.35)]]
const HAMMER_MID := [["UpperArm.R", "to", Vector3(1.45, 2.3, 0.25)], ["Forearm.R", "to", Vector3(1.95, 2.5, 0.4)]]
const HAMMER_DOWN := [["UpperArm.R", "to", Vector3(1.35, 1.6, 0.3)], ["Forearm.R", "to", Vector3(1.8, 1.3, 0.5)]]
const POSES := {
	"idle": {},
	"blink": {"closed": true},
	"walk0": {"bones": [STEP_R, SWING_R]},
	"walk1": {"bones": [PASS_L]},
	"walk2": {"bones": [STEP_L, SWING_L]},
	"walk3": {"bones": [PASS_R]},
	"work0": {"bones": [HAMMER_UP]},
	"work1": {"bones": [HAMMER_MID]},
	"work2": {"bones": [HAMMER_DOWN]},
	"work3": {"bones": [HAMMER_MID]},
	"climb0": {"bones": [[["UpperArm.R", "to", Vector3(1.0, 2.76, 0.15)], ["Forearm.R", "to", Vector3(0.8, 3.3, 0.2)],
		["UpperArm.L", "to", Vector3(-1.1, 2.5, 0.15)], ["Forearm.L", "to", Vector3(-0.9, 3.0, 0.2)]], PASS_R]},
	"climb1": {"bones": [[["UpperArm.L", "to", Vector3(-1.0, 2.76, 0.15)], ["Forearm.L", "to", Vector3(-0.8, 3.3, 0.2)],
		["UpperArm.R", "to", Vector3(1.1, 2.5, 0.15)], ["Forearm.R", "to", Vector3(0.9, 3.0, 0.2)]], PASS_L]},
	"carry0": {"bones": [LIFT, STEP_R]},
	"carry1": {"bones": [LIFT, PASS_L]},
	"carry2": {"bones": [LIFT, STEP_L]},
	"carry3": {"bones": [LIFT, PASS_R]},
	"eat": {"bones": [[["UpperArm.R", "to", Vector3(0.7, 1.5, 0.6)], ["Forearm.R", "to", Vector3(0.2, 1.3, 0.8)]]]},
	"fish": {"bones": [[["UpperArm.R", "to", Vector3(1.4, 1.72, 0.4)], ["Forearm.R", "to", Vector3(1.9, 1.85, 0.6)]]]},
	"swim": {"bones": [[["UpperArm.R", "to", Vector3(1.55, 2.25, 0.2)], ["Forearm.R", "to", Vector3(2.0, 2.5, 0.3)],
		["UpperArm.L", "to", Vector3(-1.55, 2.25, 0.2)], ["Forearm.L", "to", Vector3(-2.0, 2.5, 0.3)]], PASS_R]},
	"fall": {"bones": [[["UpperArm.R", "to", Vector3(1.35, 2.65, 0.0)], ["Forearm.R", "to", Vector3(1.55, 3.18, 0.0)],
		["UpperArm.L", "to", Vector3(-1.35, 2.65, 0.0)], ["Forearm.L", "to", Vector3(-1.55, 3.18, 0.0)],
		["Thigh.R", "to", Vector3(0.4, 0.46, 0.0)], ["Thigh.L", "to", Vector3(-0.4, 0.46, 0.0)]]]},
	"sleep": {"closed": true},
}

## Включены ли 3D-жители (настройка в меню) и общий экземпляр (его создаёт UnitLayer).
static var enabled := true
static var shared: ModelSprites

var atlas: Texture2D
var mask: Texture2D
## Поза -> {region: Rect2 в атласе, foot: Vector2 — ступни в клетке, hand: Vector2 — правая кисть
## от ступней, eye: Vector2 — глаз от ступней} (всё в пикселях атласа).
var frames := {}
var is_baked := false
var material: ShaderMaterial

var _vp: SubViewport


## Подходит ли житель под модель: треугольник с одним глазом, без видимых мутаций.
static func fits(looks: Dictionary) -> bool:
	if looks.is_empty() or int(looks.get("shape", -1)) != CreatureArt.Shape.TRIANGLE or int(looks.get("eyes", 0)) != 1:
		return false
	if int(looks.get("pattern", 0)) != 0:
		return false
	for k in ["hair", "fur", "shell", "gills", "horn", "antennae", "long_arms", "glow"]:
		if looks.get(k, false):
			return false
	return true


## Масштаб: пикселей экрана на пиксель атласа для жителя высотой h.
static func draw_scale(h: float) -> float:
	return h / HEIGHT / (CELL / SPAN)


func _ready() -> void:
	shared = self
	# Без видеокарты (тесты, сервер) рисовать нечем — жители остаются рисованными.
	if DisplayServer.get_name() == "headless" or not ResourceLoader.exists(MODEL):
		return
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/model_tint.gdshader")
	_bake.call_deferred()


func _bake() -> void:
	var names: Array = POSES.keys()
	var cols := 6
	var rows := ceili(names.size() / float(cols))
	_vp = SubViewport.new()
	_vp.size = Vector2i(cols * CELL, rows * CELL)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.78, 0.9)
	env.environment.ambient_light_energy = 0.55
	_vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -32, 0)
	key.light_energy = 1.1
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_energy = 0.45
	_vp.add_child(rim)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = rows * SPAN
	cam.position = Vector3(0, 0, 20)
	_vp.add_child(cam)
	cam.current = true

	var w := cols * SPAN
	var h := rows * SPAN
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.92, 0.92, 0.92)
	white.roughness = 0.45
	white.metallic_specular = 0.35
	var flat_white := StandardMaterial3D.new()
	flat_white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var flat_black := StandardMaterial3D.new()
	flat_black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flat_black.albedo_color = Color.BLACK
	var scene: PackedScene = load(MODEL)
	var meshes := []
	for i in names.size():
		var pose: Dictionary = POSES[names[i]]
		var c := i % cols
		var r := i / cols
		var model: Node3D = scene.instantiate()
		_vp.add_child(model)
		model.position = Vector3(-w * 0.5 + (c + 0.5) * SPAN, h * 0.5 - (r + 1) * SPAN + FOOT, 0)
		model.rotation_degrees.y = YAW
		var skel: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
		pose_skeleton(skel, pose.get("bones", []))
		skel.force_update_all_bone_transforms()
		var closed: bool = pose.get("closed", false)
		for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			var body := mi.name == "Buddy_FinalBody" or (closed and mi.name == "Approved_EyeWhite")
			if closed and mi.name in FACE_PARTS:
				mi.visible = false
			meshes.append([mi, white if body else null, flat_white if body else flat_black])
		var foot := cam.unproject_position(model.position)
		var hand := cam.unproject_position(skel.to_global(skel.get_bone_global_pose(skel.find_bone("Hand.R")).origin))
		var eye := cam.unproject_position(model.to_global(EYE))
		var cell := Vector2(c * CELL, r * CELL)
		frames[names[i]] = {"region": Rect2(cell, Vector2(CELL, CELL)), "foot": foot - cell, "hand": hand - foot, "eye": eye - foot}

	for m in meshes:
		(m[0] as MeshInstance3D).material_override = m[1]
	var color := await _shot()
	for m in meshes:
		(m[0] as MeshInstance3D).material_override = m[2]
	key.visible = false
	rim.visible = false
	var shape := await _shot()
	_vp.queue_free()
	_vp = null
	if color == null or shape == null or color.is_empty():
		return
	color.generate_mipmaps()
	shape.generate_mipmaps()
	atlas = ImageTexture.create_from_image(color)
	mask = ImageTexture.create_from_image(shape)
	material.set_shader_parameter("mask", mask)
	is_baked = true
	baked.emit()


func _shot() -> Image:
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	return _vp.get_texture().get_image()


## Поставить скелет в позу: [кость, ось, градусы] или [кость, "to", точка] — направить кость
## так, чтобы следующий сустав (локоть, запястье, колено…) оказался у точки (м, оси модели).
static func pose_skeleton(skel: Skeleton3D, groups: Array) -> void:
	for group in groups:
		for b in group:
			if b[1] is String:
				aim_bone(skel, b[0], b[2])
			else:
				rotate_bone(skel, b[0], b[1], b[2])
	skel.force_update_all_bone_transforms()


static func aim_bone(skel: Skeleton3D, bone: String, target: Vector3) -> void:
	var b := skel.find_bone(bone)
	var kids := skel.get_bone_children(b)
	if b < 0 or kids.is_empty():
		return
	skel.force_update_all_bone_transforms()
	var from := skel.get_bone_global_pose(b).origin
	var dir := skel.get_bone_global_pose(kids[0]).origin - from
	var want := target - from
	var axis := dir.cross(want)
	if axis.length() < 0.0001:
		return
	rotate_bone(skel, bone, axis, rad_to_deg(dir.angle_to(want)))


## Повернуть кость вокруг оси мира (в осях модели) на deg градусов — вместе с дочерними.
static func rotate_bone(skel: Skeleton3D, bone: String, axis: Vector3, deg: float) -> void:
	var b := skel.find_bone(bone)
	if b < 0:
		return
	skel.force_update_all_bone_transforms()
	var parent := skel.get_bone_parent(b)
	var pg := skel.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis()
	var local := Basis(skel.get_bone_pose_rotation(b))
	var nb := pg.inverse() * Basis(axis.normalized(), deg_to_rad(deg)) * pg * local
	skel.set_bone_pose_rotation(b, nb.get_rotation_quaternion())


func _exit_tree() -> void:
	if shared == self:
		shared = null


## Нарисовать жителя моделью, если она готова, включена и подходит ему; иначе false —
## тогда рисуем как раньше (CreatureArt). w — ширина туловища, как у рисованного жителя.
static func draw_creature(ci: CanvasItem, pose: String, at: Vector2, w: float, looks: Dictionary, t := 1.0) -> bool:
	var m := shared
	if m == null or not m.is_baked or not enabled or not fits(looks):
		return false
	if ci.material != m.material:
		ci.material = m.material
		ci.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var h := CreatureArt.height_of(w, looks)
	var is_super: bool = looks.get("super", false)
	CreatureArt._ellipse(ci, at + Vector2(0, w * 0.015), Vector2(w * 0.5, w * 0.08), Color(0, 0, 0, 0.2))
	if is_super:
		CreatureArt._aura(ci, at + Vector2(0, -h * 0.55), w, t)
	m.draw(ci, pose, at, h, body_color(looks))
	if is_super:
		CreatureArt._sparkles(ci, at + Vector2(0, -h * 0.55), w, t)
	return true


## Цвет тела, как у рисованного жителя.
static func body_color(looks: Dictionary) -> Color:
	if looks.get("melanist", false):
		return Color(0.16, 0.15, 0.19)
	if looks.get("albino", false):
		return Color(0.97, 0.94, 0.93)
	if looks.get("super", false):
		return CreatureArt.SUPER_A.lerp(CreatureArt.SUPER_B, 0.45)
	return looks.get("color", Color(0.9, 0.4, 0.3))


## Нарисовать жителя-модель: ступни в at, h — его высота в пикселях, col — цвет тела.
func draw(ci: CanvasItem, pose: String, at: Vector2, h: float, col: Color) -> void:
	var f: Dictionary = frames.get(pose, frames["idle"])
	var k := draw_scale(h)
	var region: Rect2 = f["region"]
	var foot: Vector2 = f["foot"]
	ci.draw_texture_rect_region(atlas, Rect2(at - foot * k, region.size * k), region, col)
	if POSES.get(pose, {}).get("closed", false):
		# Закрытый глаз: веко цвета тела и дуга ресниц.
		var e: Vector2 = at + (f["eye"] as Vector2) * k
		var r := EYE_R * (CELL / SPAN) * k
		ci.draw_arc(e + Vector2(0, -r * 0.35), r * 0.85, 0.35, PI - 0.35, 12, CreatureArt.PUPIL, maxf(1.0, r * 0.22), true)


## Где правая кисть относительно ступней (пиксели экрана) — для инструмента в руке.
func hand_pos(pose: String, h: float) -> Vector2:
	var f: Dictionary = frames.get(pose, frames["idle"])
	return (f["hand"] as Vector2) * draw_scale(h)
