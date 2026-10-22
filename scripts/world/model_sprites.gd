class_name ModelSprites
extends Node
## 3D-модели гавриков из Blender (assets/models/*.glb, по одной на форму тела), отрисованные в позы.
## Тела у моделей разные, а скелет, лицо и позы — общие.
## Мутации — слоями. Тело (форма, длинные руки, пальцы, шерсть) снимается целиком, а лицо (глаза
## и рот), узор, жабры, волосы, рог, усики и панцирь — отдельными небольшими листами, которые в
## игре кладутся поверх тела (панцирь — под ним). В каждом листе — все позы, и при съёмке слой
## закрыт телом там, где тело впереди (рукой, головой), поэтому наложение — как цельная модель.
## Сочетания мутаций ничего не стоят: листы общие. Лист снимается, когда впервые нужен; пока он
## не готов, гаврик рисованный.
## Лист — одна текстура: слева кадры (тело белое, остальное в своих цветах), справа маска тех же
## кадров: R — силуэт, G — где красить в цвет (тела или волос). Позы снимаются каждая в своём
## маленьком окне со своей 3D-сценой — так соседние позы не заходят друг к другу в кадр.

signal baked

## Форма тела -> модель.
const MODELS := {
	CreatureArt.Shape.TRIANGLE: "res://assets/models/blue_buddy.glb",
	CreatureArt.Shape.SQUARE: "res://assets/models/buddy_square.glb",
	CreatureArt.Shape.ROUND: "res://assets/models/buddy_round.glb",
}
## Клетка тела: SPAN метров, ступни — в FOOT от низа; BODY_PPM пикселей на метр.
const SPAN := 5.0
const FOOT := 0.45
const BODY_PPM := 40.0
## Высота модели от ступней до макушки, м.
const HEIGHT := 2.4
## Модель смотрит немного вбок — в сторону движения (зеркалим для другой стороны).
const YAW := 28.0
## Клеток листа в ряду.
const COLS := 6
## Глаз в позе покоя (центр белка, м, в осях модели) и его радиус; в рисованном гаврике радиус
## глаза — 0,12 ширины, отсюда ширина рисованного в метрах модели (для раскладки глаз).
const EYE := Vector3(0.0, 1.69, 0.413)
const EYE_R := 0.27
const ART_W := EYE_R / 0.12
const FACE_PARTS := ["Approved_Iris", "Approved_Pupil", "Approved_Glint", "Approved_GlintSmall"]
const EYE_PARTS := ["Approved_EyeWhite", "Approved_Iris", "Approved_Pupil", "Approved_Glint", "Approved_GlintSmall", "Approved_Brow"]
const MOUTH_PARTS := ["Approved_Smile", "Approved_Tongue", "Approved_Tooth"]
const BLUSH_PARTS := ["Approved_Blush", "Approved_Blush_001"]
## Рот у одного глаза: его высота по раскладке рисованного (низ глаза + 0,06 ширины) и верхний
## край рта модели (по нему рот грустного переворачивается).
const MOUTH_Y := 1.285
const MOUTH_TOP := 1.31
## Середина брови и на сколько градусов её повернуть у грустного (наклон в другую сторону).
const BROW := Vector3(0.0, 2.02, 0.4)
const SAD_BROW := 16.0
## Радужка: обычная (как в модели), альбинос, меланист — как у рисованного.
const IRIS := [Color(0, 0, 0, 0), Color(0.85, 0.35, 0.45), Color(0.95, 0.7, 0.15)]
## Участки листов (м, в плоскости камеры от ступней: x — вправо, y — вверх) и чёткость (пикс/м).
const CROPS := {
	"body": [Rect2(-SPAN * 0.5, -FOOT, SPAN, SPAN), BODY_PPM],
	"face": [Rect2(-1.0, 0.9, 2.2, 1.5), 80.0],
	"pattern": [Rect2(-1.3, 0.45, 2.7, 2.15), 60.0],
	"gills": [Rect2(-1.3, 0.45, 2.7, 2.15), 60.0],
	"hair": [Rect2(-1.6, 1.3, 3.3, 1.85), 60.0],
	"horn": [Rect2(-0.6, 2.05, 1.3, 1.1), 80.0],
	"antennae": [Rect2(-1.1, 2.05, 2.4, 1.25), 80.0],
	"shell": [Rect2(-1.9, 0.15, 3.9, 3.1), 50.0],
}
## Чем красить слой: цветом тела, цветом волос или никак (рог, панцирь — свои цвета).
enum Tint { BODY, HAIR, NONE }
## Длинные руки: суставы дальше по кости во столько раз (руки — почти до земли, как у рисованного).
const LONG_FOREARM := 1.42
const LONG_HAND := 1.54
## Пальцы: какие прятать, когда их меньше четырёх (1 — внутренний, 4 — наружный); лишние — по
## краям веера. Пальцы тела сделаны по прототипу и стоят не по костям: их корни (м, правая рука).
const FINGER_ROOT_IN := Vector2(1.07, 0.8)
const FINGER_ROOT_OUT := Vector2(1.51, 0.8)
const HIDE_FINGERS := {3: [4], 2: [1, 4]}
const MAX_FINGERS := 8
## Шерсть: столько оболочек, на столько метров.
const FUR_SHELLS := 12
const FUR_LEN := 0.11

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


## Жабры: x щелей и высота верхней (м) — у каждой формы туловище своей ширины.
const GILLS := {
	CreatureArt.Shape.TRIANGLE: Vector2(0.27, 1.14),
	CreatureArt.Shape.SQUARE: Vector2(0.44, 1.16),
	CreatureArt.Shape.ROUND: Vector2(0.44, 1.16),
}
## Панцирь за спиной — выпуклая «подушка» (суперэллипсоид): полуоси, центр и показатель (больше —
## квадратнее); выглядывает из-за головы и боков туловища, как у рисованного.
const SHELL_AXES := Vector3(1.12, 1.08, 0.5)
const SHELL_AT := Vector3(0.0, 1.5, -0.28)
const SHELL_POW := 3.0
## Лишние пальцы: радиус и длина (м), шаг корней по ладони и угол между пальцами.
const FINGER_R := 0.058
const FINGER_LEN := 0.32
const FINGER_ANGLE := 0.5

## Включены ли 3D-гаврики (настройка в меню) и общий экземпляр (его создаёт UnitLayer).
static var enabled := true
static var shared: ModelSprites
## Что с моделью: готовится / готово / почему не вышло (показываем в «Меню»).
static var status := "готовится…"
## Во сколько раз чётче снимать листы (для разглядывания в тестах; в игре — 1).
static var detail := 1.0

## Ключ листа -> {tex: Texture2D, ppm: float — пикселей на метр, frames: поза -> {region: Rect2 —
## кадр (в левой половине), foot: Vector2 — ступни в кадре, hand: Vector2 — правая кисть от ступней,
## eyes: [Vector2] — глаза от ступней, eye_r: float — радиус глаза}} (всё в пикселях листа).
var sheets := {}
## Готовы ли тела всех форм и обычное лицо (до этого все гаврики рисованные).
var is_baked := false
var material: ShaderMaterial

var _queue: Array[String] = []
var _failed := {}
var _busy := false
var _error := ""
var _uv_meshes := {}
var _shaders := {}
var _flats := {}


## Слои гаврика по порядку отрисовки: [ключ листа, чем красить].
static func layers_of(looks: Dictionary, sad := false) -> Array:
	var shape := int(looks.get("shape", 0))
	var out := []
	if looks.get("shell", false):
		out.append(["shell", Tint.NONE])
	out.append([body_key(looks), Tint.BODY])
	var pattern := int(looks.get("pattern", 0))
	if pattern > 0:
		out.append(["pattern/%d/%d" % [shape, pattern], Tint.BODY])
	if looks.get("gills", false):
		out.append(["gills/%d" % shape, Tint.BODY])
	var iris := 1 if looks.get("albino", false) else 2 if looks.get("melanist", false) else 0
	out.append(["face/%d/%d/%d/%d" % [clampi(int(looks.get("eyes", 1)), 0, 9), iris,
		1 if looks.get("female", false) else 0, 1 if sad else 0], Tint.BODY])
	if looks.get("hair", false):
		out.append(["hair", Tint.HAIR])
	if looks.get("horn", false):
		out.append(["horn", Tint.NONE])
	if looks.get("antennae", false):
		out.append(["antennae", Tint.BODY])
	return out


## Лист тела: форма, длинные руки, число пальцев, шерсть.
static func body_key(looks: Dictionary) -> String:
	return "body/%d/%d/%d/%d" % [int(looks.get("shape", 0)), 1 if looks.get("long_arms", false) else 0,
		clampi(int(looks.get("fingers", 4)), 2, MAX_FINGERS), 1 if looks.get("fur", false) else 0]


## Можно ли нарисовать гаврика моделью: все его листы готовы. Недостающие — заказываем
## (пока снимаются, гаврик рисованный).
static func fits(looks: Dictionary) -> bool:
	var m := shared
	if looks.is_empty() or m == null or not m.is_baked:
		return false
	var ready := true
	for l in layers_of(looks):
		if m.sheets.has(l[0]):
			continue
		if m._failed.has(l[0]):
			return false
		m._want(l[0])
		ready = false
	return ready


func _ready() -> void:
	shared = self
	# Без видеокарты (тесты, сервер) рисовать нечем — гаврики остаются рисованными.
	if DisplayServer.get_name() == "headless":
		status = "нет видеокарты"
		return
	for s in MODELS:
		if not ResourceLoader.exists(MODELS[s]):
			status = "нет файла модели"
			return
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/model_tint.gdshader")
	_start.call_deferred()


## Сначала — тела всех форм и обычное лицо: без них 3D не включаем.
func _start() -> void:
	var base: Array[String] = []
	for s in MODELS:
		base.append("body/%d/0/4/0" % s)
	base.append("face/1/0/0/0")
	for attempt in 3:
		var ok := true
		for key in base:
			var sheet = await _bake(key, attempt)
			if sheet == null:
				ok = false
				break
			sheets[key] = sheet
		if ok and await _selftest():
			status = "готово"
			is_baked = true
			baked.emit()
			_pump()
			return
		if ok:
			_error = status
		status = _error
		sheets.clear()
	push_warning("ModelSprites: " + status)


func _want(key: String) -> void:
	if not key in _queue:
		_queue.append(key)
	if not _busy:
		_pump.call_deferred()


## Снимать заказанные листы по одному; каждый готовый — сразу в дело.
func _pump() -> void:
	if _busy or not is_baked:
		return
	_busy = true
	while not _queue.is_empty():
		var key: String = _queue.pop_front()
		if sheets.has(key) or _failed.has(key):
			continue
		var sheet = await _bake(key, 0)
		if sheet == null:
			_failed[key] = true
			push_warning("ModelSprites: лист %s: %s" % [key, _error])
			continue
		sheets[key] = sheet
		baked.emit()
	_busy = false


## Снять лист key (см. layers_of): каждая поза — в своём окне; null — не вышло (_error).
func _bake(key: String, attempt: int):
	var p := key.split("/")
	var kind := p[0]
	var crop: Rect2 = CROPS[kind][0]
	var ppm: float = CROPS[kind][1] * detail
	var shape := int(p[1]) if kind in ["body", "pattern", "gills"] else CreatureArt.Shape.TRIANGLE
	var cell := Vector2i(roundi(crop.size.x * ppm), roundi(crop.size.y * ppm))
	# Кадры — в 2 раза крупнее и потом уменьшаются: так края гладкие без MSAA.
	var ss := 2
	var names: Array = POSES.keys()
	var rows := ceili(names.size() / float(COLS))
	var scene: PackedScene = load(MODELS[shape])
	var stages := []
	var parts := []
	var frames := {}
	for i in names.size():
		var pose: Dictionary = POSES[names[i]]
		var vp := SubViewport.new()
		vp.size = cell * ss
		vp.transparent_bg = false
		vp.own_world_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(vp)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color(0.8, 0.8, 0.8)
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color(0.75, 0.78, 0.9)
		env.environment.ambient_light_energy = 0.55
		vp.add_child(env)
		var key_light := DirectionalLight3D.new()
		key_light.rotation_degrees = Vector3(-38, -32, 0)
		key_light.light_energy = 1.1
		vp.add_child(key_light)
		var rim := DirectionalLight3D.new()
		rim.rotation_degrees = Vector3(-20, 150, 0)
		rim.light_energy = 0.45
		vp.add_child(rim)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = crop.size.y
		cam.position = Vector3(crop.get_center().x, crop.get_center().y, 20)
		vp.add_child(cam)
		cam.current = true
		var model: Node3D = scene.instantiate()
		vp.add_child(model)
		model.rotation_degrees.y = YAW
		var skel: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
		var meshes := {}
		for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			meshes[String(mi.name)] = mi
			mi.visible = false
		var body: MeshInstance3D = meshes["Buddy_FinalBody"]
		body.mesh = _uv_mesh(MODELS[shape], body.mesh)
		pose_skeleton(skel, pose.get("bones", []))
		if kind == "body":
			# Длинные руки — после позы: суставы повёрнуты как у обычных, руки просто длиннее.
			_rig_arms(skel, p[2] == "1")
		var closed: bool = pose.get("closed", false)
		var eye_pts := []
		var eye_r := 0.0
		var black := _flat(Color.BLACK)
		var tinted := _flat(Color(1, 1, 0))
		var kept := _flat(Color(1, 0, 0))
		if kind != "body" and kind != "shell":
			# Тело закрывает слой там, где оно впереди; само в слой не попадает.
			parts.append([body, black, black])
		match kind:
			"body":
				if int(p[3]) < 4:
					var prm := {"hide_fingers": _hidden_fingers(int(p[3]))}
					parts.append([body, _fx(8, false, Color(0.92, 0.92, 0.92), prm), _fx(8, true, Color(1, 1, 0), prm)])
				else:
					parts.append([body, _white(), tinted])
				if int(p[3]) > 4:
					parts.append_array(_extra_fingers(skel, int(p[3])))
				if p[4] == "1":
					for s in FUR_SHELLS:
						var k := float(s + 1) / FUR_SHELLS
						var prm := {"grow": FUR_LEN * k, "shell": k}
						parts.append([_dup(body), _fx(4, false, Color(0.92, 0.92, 0.92), prm), _fx(4, true, Color(1, 1, 0), prm)])
			"face":
				var face := _face_parts(model, meshes, int(p[1]), int(p[2]), closed, p[3] == "1", p[4] == "1")
				parts.append_array(face[0])
				eye_pts = face[1]
				eye_r = face[2]
			"pattern", "gills":
				var eff := int(p[2]) if kind == "pattern" else 3
				var prm := {"grow": 0.004, "gill": GILLS[shape]}
				var a := 0.72 if kind == "pattern" else 0.45
				parts.append([_dup(body), _fx(eff, false, Color(a, a, a), prm), _fx(eff, true, Color(1, 1, 0), prm)])
			"hair":
				for mesh: Mesh in _hair_meshes():
					parts.append([_copy(model, mesh, Transform3D()), _fx(5, false, Color(1, 1, 1), {}, false), _fx(5, true, Color(1, 1, 0), {}, false)])
			"horn":
				parts.append([_copy(model, _horn_mesh(), Transform3D()), _fx(7, false, Color(0.98, 0.93, 0.8), {}, false), kept])
			"antennae":
				for sx in [-1.0, 1.0]:
					var root := Vector3(sx * 0.27, 2.32, 0.02)
					var tip := Vector3(sx * 0.56, 2.95, 0.06)
					var pts := PackedVector3Array()
					var rs := PackedFloat32Array()
					for j in 13:
						var t := j / 12.0
						var u := 1.0 - t
						pts.append(root * u * u * u + (root + Vector3(0, 0.34, 0)) * 3.0 * u * u * t
							+ (tip + Vector3(-sx * 0.22, 0, 0)) * 3.0 * u * t * t + tip * t * t * t)
						rs.append(0.036)
					parts.append([_copy(model, _tube_mesh(pts, rs), Transform3D()), _fx(0, false, Color(0.8, 0.8, 0.8), {}, false), tinted])
					var ball := SphereMesh.new()
					ball.radius = 0.11
					ball.height = 0.22
					parts.append([_copy(model, ball, Transform3D(Basis(), tip)), _white(), _flat(Color(1, 0.55, 0))])
			"shell":
				parts.append([_copy(model, _shell_mesh(), Transform3D()), _fx(6, false, Color(0.55, 0.42, 0.25)), kept])
		var foot := cam.unproject_position(model.global_position) / ss
		var hand := cam.unproject_position(skel.to_global(skel.get_bone_global_pose(skel.find_bone("Hand.R")).origin)) / ss
		var eyes: Array[Vector2] = []
		for e: Vector3 in eye_pts:
			eyes.append(cam.unproject_position(model.to_global(e)) / ss - foot)
		var at := Vector2((i % COLS) * cell.x, (i / COLS) * cell.y)
		frames[names[i]] = {"region": Rect2(at, cell), "foot": foot, "hand": hand - foot, "eyes": eyes, "eye_r": eye_r * ppm}
		stages.append([vp, env, [key_light, rim]])

	for pt in parts:
		(pt[0] as MeshInstance3D).material_override = pt[1]
		(pt[0] as MeshInstance3D).visible = true
	var colors := await _shots(stages, 2 + attempt * 2)
	for pt in parts:
		(pt[0] as MeshInstance3D).material_override = pt[2]
	for st in stages:
		for l: Light3D in st[2]:
			l.visible = false
		var env: Environment = (st[1] as WorldEnvironment).environment
		env.background_color = Color.BLACK
		env.ambient_light_energy = 0.0
	var masks := await _shots(stages, 2 + attempt * 2)
	for st in stages:
		(st[0] as Node).queue_free()
	var img := Image.create_empty(COLS * cell.x * 2, rows * cell.y, false, Image.FORMAT_RGBA8)
	for i in names.size():
		for half in 2:
			var src: Image = colors[i] if half == 0 else masks[i]
			if src == null or src.is_empty():
				_error = "не удалось снять кадр модели"
				return null
			src.convert(Image.FORMAT_RGBA8)
			src.resize(cell.x, cell.y, Image.INTERPOLATE_BILINEAR)
			img.blit_rect(src, Rect2i(Vector2i.ZERO, cell), Vector2i(half * COLS * cell.x + (i % COLS) * cell.x, (i / COLS) * cell.y))
	# Проверка: в середине тела позы покоя — тело (R и G), в глазу — не тело (только R).
	var idle: Dictionary = frames["idle"]
	var at0: Vector2 = (idle["region"] as Rect2).position + (idle["foot"] as Vector2) + Vector2(COLS * cell.x, 0)
	if kind == "body":
		var px := img.get_pixelv(Vector2i(at0 + Vector2(0, -1.0 * ppm)))
		if px.r < 0.5 or px.g < 0.5:
			_error = "кадр модели пустой (тело %.2f/%.2f)" % [px.r, px.g]
			return null
	elif kind == "face" and not (idle["eyes"] as Array).is_empty():
		var px := img.get_pixelv(Vector2i(at0 + (idle["eyes"][0] as Vector2)))
		if px.r < 0.5 or px.g > 0.5:
			_error = "кадр лица пустой (глаз %.2f/%.2f)" % [px.r, px.g]
			return null
	img.generate_mipmaps()
	return {"tex": ImageTexture.create_from_image(img), "ppm": ppm, "frames": frames}


func _shots(stages: Array, wait: int) -> Array:
	for st in stages:
		(st[0] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for i in wait:
		await RenderingServer.frame_post_draw
	var out := []
	for st in stages:
		var vp: SubViewport = st[0]
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		out.append(vp.get_texture().get_image())
	return out


## Самопроверка всей цепочки (лист + шейдер): рисуем позу покоя белым в маленькое окно на
## чёрном фоне и смотрим, что середина тела светлая, а угол клетки — чёрный.
func _selftest() -> bool:
	var n := 64
	var vp := SubViewport.new()
	vp.size = Vector2i(n, n)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.size = Vector2(n, n)
	vp.add_child(bg)
	var sheet: Dictionary = sheets["body/%d/0/4/0" % CreatureArt.Shape.TRIANGLE]
	var idle: Dictionary = sheet["frames"]["idle"]
	var region: Rect2 = idle["region"]
	var k := float(n) / region.size.x
	var node := Node2D.new()
	node.material = material
	node.draw.connect(func() -> void: node.draw_texture_rect_region(sheet["tex"], Rect2(0, 0, n, n), region, Color.WHITE))
	vp.add_child(node)
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		status = "проверка: нет кадра"
		return false
	var body := img.get_pixelv(Vector2i(((idle["foot"] as Vector2) + Vector2(0, -1.0 * float(sheet["ppm"]))) * k))
	var corner := img.get_pixel(1, 1)
	if body.get_luminance() < 0.35 or corner.get_luminance() > 0.2:
		status = "проверка не прошла (тело %.2f, фон %.2f)" % [body.get_luminance(), corner.get_luminance()]
		return false
	return true


# --- Части слоёв ---------------------------------------------------------------------

## Длинные руки — локоть и запястье дальше по кости (трубка руки тянется на стыках, не толстея).
func _rig_arms(skel: Skeleton3D, long: bool) -> void:
	if not long:
		return
	for sd in [".L", ".R"]:
		for j in [["Forearm", LONG_FOREARM], ["Hand", LONG_HAND]]:
			var b := skel.find_bone(j[0] + sd)
			skel.set_bone_pose_position(b, skel.get_bone_rest(b).origin * float(j[1]))
	skel.force_update_all_bone_transforms()


## Меньше четырёх пальцев: крайние вырезает шейдер тела (их вершины частью привязаны к кисти —
## костью не убрать). -> маска пальцев для шейдера (x — внутренний, w — наружный).
static func _hidden_fingers(fingers: int) -> Vector4:
	var mask := Vector4.ZERO
	for f: int in HIDE_FINGERS.get(fingers, []):
		mask[f - 1] = 1.0
	return mask


## Лишние пальцы (больше четырёх): по очереди снаружи веера и внутри, держатся за кисть.
func _extra_fingers(skel: Skeleton3D, fingers: int) -> Array:
	var out := []
	for sd in [".L", ".R"]:
		var sx := -1.0 if sd == ".L" else 1.0
		var hand := skel.find_bone("Hand" + sd)
		var rest := skel.get_bone_global_rest(hand)
		var ba := BoneAttachment3D.new()
		ba.bone_name = "Hand" + sd
		skel.add_child(ba)
		for k in fingers - 4:
			var outer := k % 2 == 0
			var step := k / 2 + 1
			var r := FINGER_ROOT_OUT if outer else FINGER_ROOT_IN
			# Внутренний — круче: иначе под углом камеры сливается с соседним.
			var a := (0.62 + FINGER_ANGLE * step) if outer else -(0.85 + FINGER_ANGLE * step)
			var dir := Vector3(sin(a) * sx, -cos(a), 0.06).normalized()
			var cap := CapsuleMesh.new()
			cap.radius = FINGER_R
			cap.height = FINGER_LEN
			var mi := MeshInstance3D.new()
			mi.mesh = cap
			# Корень — на краю ладони, палец растёт из неё наружу веера.
			var root := Vector3(r.x * sx, r.y, 0.0)
			mi.transform = rest.affine_inverse() * Transform3D(Basis(Quaternion(Vector3.UP, dir)), root + dir * (FINGER_LEN * 0.5 - 0.05))
			ba.add_child(mi)
			out.append([mi, _white(), _flat(Color(1, 1, 0))])
	skel.force_update_all_bone_transforms()
	return out


## Лицо: n глаз по раскладке рисованного (с бровями), рот под нижним глазом (без глаз — крупнее
## и выше), румянец у рта. Закрытые глаза — веки цвета тела. У самки — ресницы у внешних уголков,
## грустный — рот перевёрнут (без зуба) и брови наклонены наоборот, как у рисованного.
## -> [части, центры глаз, радиус глаза].
func _face_parts(model: Node3D, meshes: Dictionary, n: int, iris: int, closed: bool, female: bool, sad: bool) -> Array:
	var parts := []
	var lay := CreatureArt.eye_layout(Vector2.ZERO, ART_W, n)
	var spots: Array = lay[0]
	var er: float = lay[1]
	var pts := []
	var low := EYE.y
	for s: Vector2 in spots:
		pts.append(Vector3(s.x, EYE.y - s.y, EYE.z))
		low = minf(low, EYE.y - s.y)
	var iris_mat: StandardMaterial3D = null
	var ic: Color = IRIS[iris]
	if ic.a > 0.0:
		iris_mat = StandardMaterial3D.new()
		iris_mat.albedo_color = ic
		iris_mat.roughness = 0.4
	var sc := er / EYE_R
	var keep := _flat(Color(1, 0, 0))
	for part in EYE_PARTS:
		if closed and part in FACE_PARTS:
			continue
		var lid: bool = closed and part == "Approved_EyeWhite"
		for pt: Vector3 in pts:
			var xf := Transform3D(Basis.from_scale(Vector3.ONE * sc), pt - EYE * sc)
			if sad and part == "Approved_Brow":
				# Брови грустного — наклон в другую сторону (поворот вокруг середины брови).
				var c := xf * BROW
				xf = Transform3D(Basis(Vector3.BACK, deg_to_rad(SAD_BROW)), c - Basis(Vector3.BACK, deg_to_rad(SAD_BROW)) * c) * xf
			var mi := _copy(model, (meshes[part] as MeshInstance3D).mesh, xf)
			var cm: Material = _white() if lid else iris_mat if part == "Approved_Iris" else null
			parts.append([mi, cm, _flat(Color(1, 1, 0)) if lid else keep])
	if female and not closed:
		for p: Vector3 in pts:
			var sides := [-1.0, 1.0]
			if pts.size() >= 2 and p.x < -0.01:
				sides = [-1.0]
			elif pts.size() >= 2 and p.x > 0.01:
				sides = [1.0]
			for sx: float in sides:
				for k in [0.25, 0.6]:
					parts.append([_copy(model, _lash(p, er, sx, k), Transform3D()), _lash_mat(), keep])
	var my := (low - er - 0.06 * ART_W) if n > 0 else (EYE.y - 0.06 * ART_W)
	var dy := my - MOUTH_Y
	var ms := 1.0 if n > 0 else 1.47
	var mc := Vector3(0.0, MOUTH_Y - 0.05, 0.0)
	for part in MOUTH_PARTS:
		if sad and part == "Approved_Tooth":
			continue
		var mesh: Mesh = (meshes[part] as MeshInstance3D).mesh
		var xf := Transform3D(Basis.from_scale(Vector3(ms, ms, 1.0)), mc - mc * ms + Vector3(0, dy, 0))
		var cm: Material = null
		if sad:
			# Рот вверх дном: отражаем по верхнему краю (и мельче), опускаем — как у рисованного.
			var top := mc.y + (MOUTH_TOP - mc.y) * ms + dy
			xf = Transform3D(Basis.from_scale(Vector3(1, -0.6, 1)), Vector3(0, top * 1.6 - 0.1, 0)) * xf
			var src := mesh.surface_get_material(0)
			if src is BaseMaterial3D:
				cm = (src as BaseMaterial3D).duplicate()
				(cm as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
		parts.append([_copy(model, mesh, xf), cm, keep])
	for part in BLUSH_PARTS:
		parts.append([_copy(model, (meshes[part] as MeshInstance3D).mesh, Transform3D(Basis(), Vector3(0, dy, 0))), null, keep])
	return [parts, pts, er]


## Ресница у внешнего уголка глаза p (радиус er): короткая, загнута наружу, как у рисованной самки.
static func _lash(p: Vector3, er: float, sx: float, k: float) -> ArrayMesh:
	var from := p + Vector3(sx * cos(k) * er, sin(k) * er * 1.05, 0.03 * er / EYE_R)
	var dir := Vector3(sx * 0.9, 0.55 + k * 0.5, 0.0).normalized()
	var tip := from + dir * er * 0.42
	var c1 := from + dir * er * 0.2
	var c2 := tip + Vector3(0, -er * 0.05, 0)
	var pts := PackedVector3Array()
	var rs := PackedFloat32Array()
	for j in 7:
		var t := j / 6.0
		var u := 1.0 - t
		pts.append(from * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + tip * t * t * t)
		rs.append(er * 0.065 * (1.0 - 0.5 * t))
	return _tube_mesh(pts, rs)


func _lash_mat() -> StandardMaterial3D:
	if not _flats.has("lash"):
		var m := StandardMaterial3D.new()
		m.albedo_color = CreatureArt.PUPIL
		m.roughness = 0.5
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_flats["lash"] = m
	return _flats["lash"]


## Причёска по прототипу автора (art_src/characters/hair/prototype_hair.png): «цветок» из семи
## гладких загнутых лепестков из одной точки на макушке — средний вверх с кончиком вправо, по паре
## вверх-в стороны и вбок, нижняя пара спадает вперёд по бокам лба. Лепестки: [корень, изгиб,
## кончик (м, оси модели), полуширина] — сняты с картинки (ширина причёски — 1,6 м), сзади вперёд.
const HAIR_PETALS := [
	[Vector3(-0.049, 2.384, 0.0), Vector3(-0.348, 2.82, 0.025), Vector3(-0.65, 2.652, 0.05), 0.11],
	[Vector3(0.073, 2.425, 0.0), Vector3(0.357, 2.778, 0.025), Vector3(0.609, 2.595, 0.05), 0.11],
	[Vector3(-0.122, 2.36, 0.12), Vector3(-0.593, 2.682, 0.21), Vector3(-0.804, 2.173, 0.3), 0.11],
	[Vector3(0.171, 2.376, 0.12), Vector3(0.573, 2.67, 0.21), Vector3(0.796, 2.181, 0.3), 0.11],
	[Vector3(0.0, 2.36, 0.2), Vector3(-0.171, 2.713, 0.22), Vector3(0.341, 2.823, 0.24), 0.16],
	[Vector3(-0.057, 2.352, 0.3), Vector3(-0.406, 2.558, 0.39), Vector3(-0.463, 2.035, 0.48), 0.11],
	[Vector3(0.057, 2.352, 0.3), Vector3(0.364, 2.582, 0.39), Vector3(0.414, 2.051, 0.48), 0.11],
]


func _hair_meshes() -> Array:
	if _uv_meshes.has("hair"):
		return _uv_meshes["hair"]
	var out := []
	# Голова в игре повёрнута — по ширине причёску чуть растягиваем, чтобы смотрелась как на картинке.
	var k := Vector3(1.1, 1.0, 1.0)
	for t in HAIR_PETALS:
		out.append(_petal(t[0] * k, t[1] * k, t[2] * k, t[3] * 1.3))
	_uv_meshes["hair"] = out
	return out


## Лепесток: плоский жгут по дуге корень → изгиб → кончик; у корня узкий (все сходятся в одну
## точку), толще всего на трети длины, к кончику острый.
static func _petal(root: Vector3, mid: Vector3, tip: Vector3, hw: float) -> ArrayMesh:
	var pts := PackedVector3Array()
	var rs := PackedFloat32Array()
	var n := 18
	for j in n + 1:
		var t := float(j) / n
		var u := 1.0 - t
		pts.append(root * u * u + mid * 2.0 * u * t + tip * t * t)
		rs.append(hw * 2.5 * sqrt(t + 0.01) * pow(1.0 - t, 0.9) + 0.004)
	return _tube_mesh(pts, rs, 0.75)


## Панцирь: сфера, вытянутая в суперэллипсоид (у краёв плоский и широкий, как у черепахи).
func _shell_mesh() -> ArrayMesh:
	if _uv_meshes.has("shell"):
		return _uv_meshes["shell"]
	var sm := SphereMesh.new()
	sm.radial_segments = 48
	sm.rings = 32
	var st := SurfaceTool.new()
	st.create_from(sm, 0)
	var arr := st.commit_to_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var e := 2.0 / SHELL_POW
	for i in v.size():
		var q := v[i] / 0.5
		v[i] = SHELL_AT + Vector3(signf(q.x) * pow(absf(q.x), e), signf(q.y) * pow(absf(q.y), e), signf(q.z) * pow(absf(q.z), e)) * SHELL_AXES
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = null
	st = SurfaceTool.new()
	st.create_from_arrays(arr)
	st.generate_normals()
	var out := st.commit()
	_uv_meshes["shell"] = out
	return out


## Рог: изогнутый конус на макушке (кольца рисует шейдер).
func _horn_mesh() -> ArrayMesh:
	var pts := PackedVector3Array()
	var rs := PackedFloat32Array()
	for j in 15:
		var t := j / 14.0
		pts.append(Vector3(0.16 * t * t, 2.26 + 0.86 * t, 0.06 + 0.06 * t))
		rs.append(0.21 * pow(1.0 - t, 0.9) + 0.014)
	return _tube_mesh(pts, rs)


## Трубка по линии pts с радиусами rs и крышками; UV.y — доля длины. flat — во сколько раз она
## тоньше к зрителю, чем поперёк (плоские пряди).
static func _tube_mesh(pts: PackedVector3Array, rs: PackedFloat32Array, flat := 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 16
	var rings := []
	for i in pts.size():
		var d := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := d.cross(Vector3(0, 0, 1))
		if side.length() < 0.01:
			side = d.cross(Vector3(1, 0, 0))
		side = side.normalized()
		var up := side.cross(d).normalized()
		var ring := []
		for j in n + 1:
			var a := TAU * j / n
			var nrm := (side * cos(a) + up * sin(a) / flat).normalized()
			ring.append([pts[i] + (side * cos(a) + up * sin(a) * flat) * rs[i], nrm, Vector2(float(j) / n, float(i) / (pts.size() - 1))])
		rings.append(ring)
	for i in pts.size() - 1:
		for j in n:
			for v in [rings[i][j], rings[i + 1][j], rings[i + 1][j + 1], rings[i][j], rings[i + 1][j + 1], rings[i][j + 1]]:
				st.set_normal(v[1])
				st.set_uv(v[2])
				st.add_vertex(v[0])
	for e in [[0, -1.0], [pts.size() - 1, 1.0]]:
		var c: Vector3 = pts[e[0]]
		var d := (pts[mini(e[0] + 1, pts.size() - 1)] - pts[maxi(e[0] - 1, 0)]).normalized() * float(e[1])
		for j in n:
			for v in [[c, Vector2(0.5, float(e[0]) / (pts.size() - 1))], [rings[e[0]][j][0], rings[e[0]][j][2]], [rings[e[0]][j + 1][0], rings[e[0]][j + 1][2]]]:
				st.set_normal(d)
				st.set_uv(v[1])
				st.add_vertex(v[0])
	return st.commit()


## Копия тела на том же скелете (для узора, жабр, волос, шерсти).
func _dup(body: MeshInstance3D) -> MeshInstance3D:
	var d: MeshInstance3D = body.duplicate()
	body.get_parent().add_child(d)
	return d


## Неподвижная деталь модели (на кости туловища, которая в позах не двигается).
func _copy(model: Node3D, mesh: Mesh, xf: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xf
	model.add_child(mi)
	return mi


## Тело с координатами позы покоя в UV (x, y) и UV2 (z): узор, жабры, волосы и шерсть рисуются
## по ним и в позах остаются на своих местах.
func _uv_mesh(path: String, mesh: Mesh) -> Mesh:
	if _uv_meshes.has(path):
		return _uv_meshes[path]
	var arr := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	uv.resize(v.size())
	uv2.resize(v.size())
	for i in v.size():
		uv[i] = Vector2(v[i].x, v[i].y)
		uv2[i] = Vector2(v[i].z, 0.0)
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	var flags := 0
	var bones = arr[Mesh.ARRAY_BONES]
	if bones != null and bones.size() == v.size() * 8:
		flags = Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
	_uv_meshes[path] = out
	return out


func _white() -> StandardMaterial3D:
	if not _flats.has("white"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.92, 0.92, 0.92)
		m.roughness = 0.45
		m.metallic_specular = 0.35
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_flats["white"] = m
	return _flats["white"]


## Ровный цвет без света — для маски.
func _flat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _flats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c
		# Без отсечения: рот и румянец — плоские наклейки, видны и с изнанки.
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_flats[key] = m
	return _flats[key]


## Материал с узором/шерстью/волосами… (effect — см. shaders/model_bake.gdshaderinc): для кадра
## (со светом) или для маски (ровный albedo, та же форма).
func _fx(effect: int, mask: bool, albedo: Color, params := {}, cull := true) -> ShaderMaterial:
	var sk := "%s%s" % [mask, cull]
	if not _shaders.has(sk):
		var sh := Shader.new()
		sh.code = "shader_type spatial;\nrender_mode %s%s;\n%s#include \"res://shaders/model_bake.gdshaderinc\"\n" % [
			"unshaded, " if mask else "", "cull_back" if cull else "cull_disabled", "#define MASK\n" if mask else ""]
		_shaders[sk] = sh
	var m := ShaderMaterial.new()
	m.shader = _shaders[sk]
	m.set_shader_parameter("effect", effect)
	m.set_shader_parameter("albedo", albedo)
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


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


## Нарисовать гаврика моделью, если она готова, включена и все его листы сняты; иначе false —
## тогда рисуем как раньше (CreatureArt). w — ширина туловища, как у рисованного гаврика;
## поза с «|sad» — грустный.
static func draw_creature(ci: CanvasItem, pose: String, at: Vector2, w: float, looks: Dictionary, t := 1.0) -> bool:
	var m := shared
	if m == null or not m.is_baked or not enabled or not fits(looks):
		return false
	if ci.material != m.material:
		ci.material = m.material
		ci.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var h := CreatureArt.height_of(w, looks)
	var is_super: bool = looks.get("super", false)
	var glow: bool = looks.get("glow", false)
	var mid := at + Vector2(0, -h * 0.55)
	var col := body_color(looks)
	CreatureArt._ellipse(ci, at + Vector2(0, w * 0.015), Vector2(w * 0.5, w * 0.08), Color(0, 0, 0, 0.2))
	if is_super:
		CreatureArt._aura(ci, mid, w, t)
	if glow:
		# Светится: мягкое свечение вокруг, как у рисованного.
		for i in 7:
			ci.draw_circle(mid, w * (1.05 - i * 0.09), Color(col.lightened(0.6), 0.06))
	m.draw(ci, pose, at, h, looks)
	if glow:
		for i in 6:
			var a := TAU * i / 6.0 + t * 0.5
			ci.draw_circle(mid + Vector2(cos(a) * w * 0.7, sin(a) * h * 0.6), w * 0.018, Color(1, 1, 0.8, 0.7))
	if is_super:
		CreatureArt._sparkles(ci, mid, w, t)
	return true


## Цвет тела, как у рисованного гаврика (светящийся — чуть светлее).
static func body_color(looks: Dictionary) -> Color:
	var col: Color = looks.get("color", Color(0.9, 0.4, 0.3))
	if looks.get("melanist", false):
		col = Color(0.16, 0.15, 0.19)
	elif looks.get("albino", false):
		col = Color(0.97, 0.94, 0.93)
	elif looks.get("super", false):
		col = CreatureArt.SUPER_A.lerp(CreatureArt.SUPER_B, 0.45)
	if looks.get("glow", false):
		col = col.lerp(Color(1, 1, 0.85), 0.2)
	return col


## Нарисовать гаврика-модель: ступни в at, h — его высота в пикселях. Слои — по порядку.
## Грустное лицо («|sad» в позе) снимается отдельно; пока его нет — обычное.
func draw(ci: CanvasItem, pose: String, at: Vector2, h: float, looks: Dictionary) -> void:
	var sad := pose.ends_with("|sad")
	pose = pose.split("|")[0]
	var col := body_color(looks)
	var hair: Color = looks.get("hair_color", col.darkened(0.4))
	var face := {}
	var face_k := 1.0
	for l in layers_of(looks, sad):
		var key: String = l[0]
		if not sheets.has(key):
			if not _failed.has(key):
				_want(key)
			key = key.left(key.length() - 1) + "0"
		var s: Dictionary = sheets[key]
		var f := _frame(s, pose)
		var k := h / HEIGHT / float(s["ppm"])
		var region: Rect2 = f["region"]
		var tint := col if l[1] == Tint.BODY else hair if l[1] == Tint.HAIR else Color.WHITE
		ci.draw_texture_rect_region(s["tex"], Rect2(at - (f["foot"] as Vector2) * k, region.size * k), region, tint)
		if key.begins_with("face/"):
			face = f
			face_k = k
	if POSES.get(pose, {}).get("closed", false) and not face.is_empty():
		# Закрытые глаза: веки цвета тела (в листе) и дуги ресниц.
		var r := float(face["eye_r"]) * face_k
		for e: Vector2 in face["eyes"]:
			ci.draw_arc(at + e * face_k + Vector2(0, -r * 0.35), r * 0.85, 0.35, PI - 0.35, 12, CreatureArt.PUPIL, maxf(1.0, r * 0.22), true)


## Где правая кисть относительно ступней (пиксели экрана) — для инструмента в руке.
func hand_pos(pose: String, h: float, looks: Dictionary) -> Vector2:
	pose = pose.split("|")[0]
	var s: Dictionary = sheets.get(body_key(looks), sheets["body/%d/0/4/0" % CreatureArt.Shape.TRIANGLE])
	return (_frame(s, pose)["hand"] as Vector2) * (h / HEIGHT / float(s["ppm"]))


static func _frame(sheet: Dictionary, pose: String) -> Dictionary:
	var frames: Dictionary = sheet["frames"]
	return frames.get(pose, frames["idle"])
