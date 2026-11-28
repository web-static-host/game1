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
	CreatureArt.Shape.TRIANGLE: "res://assets/models/buddy_triangle.glb",
	CreatureArt.Shape.SQUARE: "res://assets/models/buddy_square.glb",
	CreatureArt.Shape.ROUND: "res://assets/models/buddy_round.glb",
}
## Модели нового вида (тело — по модели Hunyuan): скелет с теми же именами костей, но суставы в
## других местах — позы переносятся направлениями со старой модели (FACE_MODEL); лицо — слоем
## своего вида (FACE1), лишние пальцы-капсулы старой модели не ставятся.
const NEW_RIG := [CreatureArt.Shape.TRIANGLE]
## Модели с лицом в текстуре (тело красится по маске текстуры, shaders/model_skin.gdshader; лица
## слоем нет — без мутаций глаз). Сейчас таких нет: прежняя такая модель — в art_src
## (buddy_triangle_textured.glb).
const TEXTURED := []
## Старая модель: из неё лицо, волосы, рог, усики, панцирь (общие для всех форм) и позы.
const FACE_MODEL := "res://assets/models/blue_buddy.glb"
## Лицо новых моделей — как у прототипа (жёлтый треугольный с заставок): глаз-шар с крупной
## голубой радужкой, большим зрачком и бликом (на 20% меньше, чем у модели Hunyuan), толстая
## тёмно-коричневая бровь-дуга со скруглёнными концами, широкий открытый рот буквой D с двумя
## зубами и языком, круглый розовый румянец по бокам. Всё — на выпуклой лицевой стороне тела.
const FACE1_EYE := Vector3(0.0, 1.835, 0.0)
const FACE1_ER := 0.245
## Лицевая сторона: глубина z (к зрителю) в точке (x, y), м — снята с модели (ошибка ~4 мм):
## c0 + c1·x² + c2·y + c3·y² + c4·x²·y + c5·x⁴ + c6·y³.
const FACE1_Z := [-0.646, -1.11234, 1.63187, -0.80379, 0.40844, 0.10162, 0.12766]
## Наклейки (рот, румянец) и бровь — над поверхностью на столько (м): с запасом на её неточность.
const FACE1_LIFT := 0.02
## Глаз: насколько выступает (доля радиуса) и глубина шара (доля радиуса).
const FACE1_EYE_OUT := 0.62
const FACE1_EYE_DEPTH := 0.92
## Куда смотрит (в осях модели: x — вправо, y — вверх, z — к зрителю), радиусы радужки и зрачка
## (доли радиуса шара).
const FACE1_GAZE := Vector3(0.26, 0.07, 1.0)
const FACE1_IRIS_R := 0.52
const FACE1_PUPIL_R := 0.28
const FACE1_IRIS := Color(0.24, 0.5, 0.9)
const FACE1_BROW := Color(0.3, 0.16, 0.1)
## Рот: от низа нижнего глаза до верха рта, полуширина и высота (м).
const FACE1_MOUTH_GAP := 0.06
const FACE1_MOUTH_HW := 0.165
const FACE1_MOUTH_H := 0.25
const FACE1_MOUTH := Color(0.34, 0.05, 0.1)
const FACE1_LIP := Color(0.22, 0.03, 0.07)
const FACE1_TONGUE := Color(0.88, 0.14, 0.22)
const FACE1_TOOTH := Color(0.98, 0.97, 0.93)
## Румянец: по бокам от нижнего глаза (от его центра, доли радиуса глаза; без глаз — у рта), радиус.
const FACE1_BLUSH_X := 1.38
const FACE1_BLUSH_DROP := 0.85
const FACE1_BLUSH_R := 0.1
const FACE1_BLUSH := Color(1.0, 0.52, 0.56)
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
	"tool": [Rect2(-SPAN * 0.5, -FOOT, 6.6, SPAN), BODY_PPM],
}
## Чем красить слой: цветом тела, цветом волос или никак (рог, панцирь — свои цвета).
enum Tint { BODY, HAIR, NONE, PATTERN }
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
	# Полив (ферма): правая рука вперёд-вниз с лейкой, чуть качается.
	"water0": {"bones": [[["UpperArm.R", "to", Vector3(1.35, 1.55, 0.45)], ["Forearm.R", "to", Vector3(1.9, 1.25, 0.6)]]]},
	"water1": {"bones": [[["UpperArm.R", "to", Vector3(1.35, 1.5, 0.45)], ["Forearm.R", "to", Vector3(1.88, 1.1, 0.62)]]]},
	# Учёный разглядывает колбу у лица.
	"study0": {"bones": [[["UpperArm.R", "to", Vector3(0.95, 1.55, 0.6)], ["Forearm.R", "to", Vector3(0.62, 2.05, 0.9)]]]},
	"study1": {"bones": [[["UpperArm.R", "to", Vector3(0.95, 1.55, 0.6)], ["Forearm.R", "to", Vector3(0.7, 2.12, 0.85)]]]},
	# Печь: подкидывает уголь лопатой — зачерпнул внизу, закинул вверх.
	"shovel0": {"bones": [[["UpperArm.R", "to", Vector3(1.3, 1.6, 0.45)], ["Forearm.R", "to", Vector3(1.85, 1.15, 0.6)]]]},
	"shovel1": {"bones": [[["UpperArm.R", "to", Vector3(1.35, 2.25, 0.4)], ["Forearm.R", "to", Vector3(1.85, 2.55, 0.5)]]]},
	# Нефтезавод: крутит вентиль гаечным ключом на уровне груди.
	"turn0": {"bones": [[["UpperArm.R", "to", Vector3(1.3, 1.95, 0.5)], ["Forearm.R", "to", Vector3(1.85, 2.05, 0.6)]]]},
	"turn1": {"bones": [[["UpperArm.R", "to", Vector3(1.3, 1.85, 0.5)], ["Forearm.R", "to", Vector3(1.82, 1.7, 0.62)]]]},
	# Обогатительная: водит дозиметром перед собой.
	"scan0": {"bones": [[["UpperArm.R", "to", Vector3(1.3, 1.75, 0.5)], ["Forearm.R", "to", Vector3(1.85, 1.55, 0.6)]]]},
	"scan1": {"bones": [[["UpperArm.R", "to", Vector3(1.28, 1.7, 0.55)], ["Forearm.R", "to", Vector3(1.8, 1.32, 0.7)]]]},
}
## Инструменты в правой руке (держатся за кость кисти) и позы, в которых их видно.
const TOOL_POSES := {
	"pickaxe": ["work0", "work1", "work2", "work3"], "hammer": ["work0", "work1", "work2", "work3"],
	"axe": ["work0", "work1", "work2", "work3"], "can": ["water0", "water1"], "flask": ["study0", "study1"],
	"rod": ["fish"], "shovel": ["shovel0", "shovel1"], "wrench": ["turn0", "turn1"], "geiger": ["scan0", "scan1"],
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
## Снятые листы живут, пока работает игра: новый мир (вход, другая планета) не снимает их заново
## (раньше после каждой загрузки гаврики сначала были рисованными, потом становились 3D).
static var _sheet_cache := {}
static var _baked_once := false
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
var _skins := {}


## Слои гаврика по порядку отрисовки: [ключ листа, чем красить].
static func layers_of(looks: Dictionary, sad := false) -> Array:
	var shape := int(looks.get("shape", 0))
	var out := []
	if looks.get("shell", false):
		out.append(["shell", Tint.NONE])
	out.append([body_key(looks), Tint.BODY])
	var pattern := int(looks.get("pattern", 0))
	if pattern > 0:
		out.append(["pattern/%d/%d" % [shape, pattern], Tint.PATTERN])
	if looks.get("gills", false):
		out.append(["gills/%d" % shape, Tint.BODY])
	var iris := 1 if looks.get("albino", false) else 2 if looks.get("melanist", false) else 0
	if not shape in TEXTURED:
		out.append(["face/%d/%d/%d/%d/%d" % [clampi(int(looks.get("eyes", 1)), 0, 9), iris,
			1 if looks.get("female", false) else 0, 1 if shape in NEW_RIG else 0, 1 if sad else 0], Tint.BODY])
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


## Для экрана загрузки: какая доля листов этих гавриков готова (0..1); недостающие заказывает.
## 1 — готово или 3D нет (выключено, нет видеокарты, не вышло).
static func load_progress(all_looks: Array) -> float:
	var m := shared
	if not enabled or m == null or (not m.is_baked and status != "готовится…"):
		return 1.0
	if not m.is_baked:
		return 0.0
	var need := {}
	for looks: Dictionary in all_looks:
		for l in layers_of(looks):
			need[l[0]] = true
	if need.is_empty():
		return 1.0
	var have := 0
	for key: String in need:
		if m.sheets.has(key) or m._failed.has(key):
			have += 1
		else:
			m._want(key)
	return float(have) / need.size()


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
	for path in MODELS.values() + [FACE_MODEL]:
		if not ResourceLoader.exists(path):
			status = "нет файла модели"
			return
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/model_tint.gdshader")
	sheets = _sheet_cache
	if _baked_once:
		status = "готово"
		is_baked = true
		baked.emit.call_deferred()
		return
	_start.call_deferred()


## Сначала — тела всех форм и обычное лицо: без них 3D не включаем.
func _start() -> void:
	var base: Array[String] = []
	for s in MODELS:
		base.append("body/%d/0/4/0" % s)
	base.append("face/1/0/0/0/0")
	if not NEW_RIG.is_empty():
		base.append("face/1/0/0/1/0")
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
			_baked_once = true
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
	var shape := int(p[1]) if kind in ["body", "pattern", "gills"] else int(p[2]) if kind == "tool" else CreatureArt.Shape.TRIANGLE
	var cell := Vector2i(roundi(crop.size.x * ppm), roundi(crop.size.y * ppm))
	# Кадры — в 2 раза крупнее и потом уменьшаются: так края гладкие без MSAA.
	var ss := 2
	# Инструмент — только в своих позах (лист маленький).
	var names: Array = TOOL_POSES[p[1]] if kind == "tool" else POSES.keys()
	var rows := ceili(names.size() / float(COLS))
	# Лицо нового вида снимается на своём теле (оно закрывает лицо там, где впереди).
	var face_style := int(p[4]) if kind == "face" else 0
	var path: String = MODELS[shape] if kind in ["body", "pattern", "gills", "tool"] \
		else MODELS[CreatureArt.Shape.TRIANGLE] if face_style == 1 else FACE_MODEL
	var scene: PackedScene = load(path)
	var skin: bool = shape in TEXTURED and path == MODELS[shape]
	var new_rig := _is_new_rig(path)
	# Части лица (Approved_*) — из старой модели.
	var face_meshes := {}
	# Скелет старой модели — для переноса поз (стоит скрытым в первом окне).
	var ref: Skeleton3D = null
	var stages := []
	var parts := []
	var frames := {}
	for i in names.size():
		var pose: Dictionary = POSES[names[i]]
		var tip_local = null
		var vp := SubViewport.new()
		vp.size = cell * ss
		vp.transparent_bg = false
		vp.own_world_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(vp)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		# Лицо — на чёрном (и тело под ним чёрное): края частей тогда «предумножены» и потом
		# восстанавливаются (_unpremul) — без тёмной каймы вокруг глаза и румянца.
		env.environment.background_color = Color.BLACK if kind == "face" else Color(0.8, 0.8, 0.8)
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
		if new_rig and ref == null:
			var rm: Node3D = (load(FACE_MODEL) as PackedScene).instantiate()
			rm.visible = false
			vp.add_child(rm)
			ref = rm.find_children("*", "Skeleton3D", true, false)[0]
			for mi: MeshInstance3D in rm.find_children("*", "MeshInstance3D", true, false):
				face_meshes[String(mi.name)] = mi
		var model: Node3D = scene.instantiate()
		vp.add_child(model)
		model.rotation_degrees.y = YAW
		var skel: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
		var meshes := {}
		for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			meshes[String(mi.name)] = mi
			mi.visible = false
		if not new_rig:
			face_meshes = meshes
		var body: MeshInstance3D = meshes["Buddy_FinalBody"]
		if skin and not _skins.has(path):
			var src := body.mesh.surface_get_material(0)
			_skins[path] = [_skin_mat(src, false), _skin_mat(src, true)]
		body.mesh = _uv_mesh(path, body.mesh)
		if ref != null:
			ref.reset_bone_poses()
		pose_skeleton(skel, pose.get("bones", []), ref)
		if kind == "body" or kind == "tool":
			# Длинные руки — после позы: суставы повёрнуты как у обычных, руки просто длиннее.
			_rig_arms(skel, p[2 if kind == "body" else 3] == "1")
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
				if skin:
					# Пальцы и шерсть у новых моделей пока не меняются.
					parts.append([body, _skins[path][0], _skins[path][1]])
				elif int(p[3]) < 4 and not new_rig:
					var prm := {"hide_fingers": _hidden_fingers(int(p[3]))}
					parts.append([body, _fx(8, false, Color(0.92, 0.92, 0.92), prm), _fx(8, true, Color(1, 1, 0), prm)])
				else:
					parts.append([body, _white(), tinted])
				if int(p[3]) > 4 and not new_rig:
					parts.append_array(_extra_fingers(skel, int(p[3])))
				if p[4] == "1" and not skin:
					for s in FUR_SHELLS:
						var k := float(s + 1) / FUR_SHELLS
						var prm := {"grow": FUR_LEN * k, "shell": k}
						parts.append([_dup(body), _fx(4, false, Color(0.92, 0.92, 0.92), prm), _fx(4, true, Color(1, 1, 0), prm)])
			"face":
				var face := _face_parts(model, face_meshes, int(p[1]), int(p[2]), closed, p[3] == "1", p[5] == "1", face_style)
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
			"tool":
				# В ладонь правой кисти (в позе), рукоять — под углом позы в плоскости гаврика.
				var palm := skel.get_bone_global_pose(skel.find_bone("Hand.R")) * GRIP
				var place := Transform3D(Basis(Vector3.BACK, deg_to_rad(TOOL_ANGLE.get(names[i], 0.0))), palm)
				for t in _tool_parts(p[1]):
					parts.append([_copy(model, t[0], place * (t[1] as Transform3D)), t[2], kept])
				if p[1] == "rod":
					tip_local = place * ROD_TIP
		var foot := cam.unproject_position(model.global_position) / ss
		var hand := cam.unproject_position(skel.to_global(skel.get_bone_global_pose(skel.find_bone("Hand.R")).origin)) / ss
		var eyes: Array[Vector2] = []
		for e: Vector3 in eye_pts:
			eyes.append(cam.unproject_position(model.to_global(e)) / ss - foot)
		var at := Vector2((i % COLS) * cell.x, (i / COLS) * cell.y)
		frames[names[i]] = {"region": Rect2(at, cell), "foot": foot, "hand": hand - foot, "eyes": eyes, "eye_r": eye_r * ppm}
		if tip_local != null:
			# Кончик удочки (от него игра тянет леску).
			frames[names[i]]["tip"] = cam.unproject_position(model.to_global(tip_local as Vector3)) / ss - foot
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
	var idle: Dictionary = frames.get("idle", frames[names[0]])
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
	if kind == "face":
		img = await _unpremul(img)
	img.generate_mipmaps()
	return {"tex": ImageTexture.create_from_image(img), "ppm": ppm, "frames": frames}


## Цвет кадров листа (левая половина), снятый на чёрном, — разделить на силуэт маски (правая
## половина, R): на краях частей остаётся их цвет, а не смесь с чёрным. На видеокарте, одним проходом.
func _unpremul(img: Image) -> Image:
	var vp := SubViewport.new()
	vp.size = img.get_size()
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var rect := ColorRect.new()
	rect.size = Vector2(img.get_size())
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform sampler2D src : filter_nearest;
uniform vec2 px = vec2(0.001);
void fragment() {
	vec4 c = texture(src, UV);
	if (UV.x < 0.5) {
		float a = texture(src, UV + vec2(0.5, 0.0)).r;
		if (a > 0.03) {
			c.rgb = min(c.rgb / a, vec3(1.0));
		} else {
			// Вокруг частей — цвет ближайшей (до 3 пикселей): фильтр текстуры на краю не
			// подмешает чёрный.
			float best = 0.0;
			vec3 col = c.rgb;
			for (int y = -3; y <= 3; y++) {
				for (int x = -3; x <= 3; x++) {
					vec2 o = vec2(float(x), float(y)) * px;
					float b = texture(src, UV + o + vec2(0.5, 0.0)).r / (1.0 + 0.15 * float(x * x + y * y));
					if (b > best && b > 0.03) {
						best = b;
						col = min(texture(src, UV + o).rgb / texture(src, UV + o + vec2(0.5, 0.0)).r, vec3(1.0));
					}
				}
			}
			c.rgb = col;
		}
	}
	COLOR = vec4(c.rgb, 1.0);
}
"""
	mat.shader = sh
	mat.set_shader_parameter("src", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("px", Vector2.ONE / Vector2(img.get_size()))
	rect.material = mat
	vp.add_child(rect)
	for i in 3:
		await RenderingServer.frame_post_draw
	var out := vp.get_texture().get_image()
	vp.queue_free()
	if out == null or out.is_empty():
		return img
	out.convert(Image.FORMAT_RGBA8)
	return out


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
## style 1 — лицо нового вида (_face1_parts).
func _face_parts(model: Node3D, meshes: Dictionary, n: int, iris: int, closed: bool, female: bool, sad: bool, style := 0) -> Array:
	if style == 1:
		return _face1_parts(model, n, iris, closed, female, sad)
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


## Лицо нового вида (FACE1): n глаз по раскладке рисованного, бровь над каждым, рот под нижним
## (без глаз — крупнее и выше), румянец по бокам. Закрытые глаза — веки цвета тела; у самки —
## ресницы; грустный — рот вверх дном без зубов, брови наклонены. -> [части, центры глаз, радиус].
func _face1_parts(model: Node3D, n: int, iris: int, closed: bool, female: bool, sad: bool) -> Array:
	var parts := []
	var lay := CreatureArt.eye_layout(Vector2.ZERO, FACE1_ER / 0.12, n)
	var er: float = lay[1]
	var keep := _flat(Color(1, 0, 0))
	var pts := []
	var low := FACE1_EYE.y
	var ic: Color = IRIS[iris] if (IRIS[iris] as Color).a > 0.0 else FACE1_IRIS
	for s: Vector2 in lay[0]:
		var c := Vector2(s.x, FACE1_EYE.y - s.y)
		low = minf(low, c.y)
		var front := face1_z(c.x, c.y)
		pts.append(Vector3(c.x, c.y, front + er * FACE1_EYE_OUT * 0.6))
		var ball := SphereMesh.new()
		ball.radius = 1.0
		ball.height = 2.0
		ball.radial_segments = 48
		ball.rings = 24
		var at := Vector3(c.x, c.y, front + er * (FACE1_EYE_OUT - FACE1_EYE_DEPTH))
		var mi := _copy(model, ball, Transform3D(Basis.from_scale(Vector3(er, er * 1.03, er * FACE1_EYE_DEPTH)), at))
		if closed:
			parts.append([mi, _white(), _flat(Color(1, 1, 0))])
		else:
			parts.append([mi, _eye_mat(ic), keep])
		# Тень у основания глаза — тонкое кольцо цвета тела, темнее (красится цветом тела).
		var ring := PackedVector2Array()
		var hole := PackedVector2Array()
		for i in 48:
			var d := Vector2.from_angle(TAU * i / 48.0)
			ring.append(c + d * Vector2(er * 0.99, er * 1.02))
			hole.append(c + d * Vector2(er * 0.92, er * 0.95))
		for poly in Geometry2D.clip_polygons(ring, hole):
			if not Geometry2D.is_polygon_clockwise(poly):
				parts.append([_copy(model, _sticker(poly, FACE1_LIFT * 0.5), Transform3D()), _paint(Color(0.62, 0.62, 0.62)), _flat(Color(1, 1, 0))])
		parts.append_array(_brow1(model, c, er, sad))
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
	# Рот: буква D — верх почти прямой (уголки чуть выше), низ круглый; у грустного — вверх дном.
	var k := 1.0 if n > 0 else 1.3
	var top := (low - er * 1.03 - FACE1_MOUTH_GAP) if n > 0 else (FACE1_EYE.y - 0.12)
	var hw := FACE1_MOUTH_HW * k
	var h := FACE1_MOUTH_H * k
	var mouth := PackedVector2Array()
	for i in 25:
		var x := -hw + 2.0 * hw * i / 24.0
		mouth.append(Vector2(x, top - 0.045 * k + 0.045 * k * pow(absf(x / hw), 2.2)))
	for i in range(1, 32):
		var a := PI * i / 32.0
		mouth.append(Vector2(hw * cos(a), top - h * pow(sin(a), 0.65)))
	var teeth := []
	var tongue := PackedVector2Array()
	if not sad:
		for sx in [-1.0, 1.0]:
			var tw := 0.082 * k
			var cx: float = sx * 0.046 * k
			var t0 := top - 0.04 * k
			var tooth := PackedVector2Array()
			for i in 9:
				var a := PI * i / 8.0
				tooth.append(Vector2(cx + tw * 0.5 * cos(a + PI), t0 - 0.1 * k + 0.02 * k - 0.02 * k * sin(a)))
			tooth.append(Vector2(cx + tw * 0.5, t0 + 0.03 * k))
			tooth.append(Vector2(cx - tw * 0.5, t0 + 0.03 * k))
			teeth.append_array(Geometry2D.intersect_polygons(tooth, mouth))
		for i in 32:
			var a := TAU * i / 32.0
			tongue.append(Vector2(-0.04 * k + 0.085 * k * cos(a), top - h + 0.045 * k + 0.055 * k * sin(a)))
	if sad:
		# Вверх дном, мельче, ниже — как у рисованного.
		var mid := top - h * 0.5
		for i in mouth.size():
			mouth[i] = Vector2(mouth[i].x * 0.8, mid + (mid - mouth[i].y) * 0.6 - h * 0.15)
	var lip := Geometry2D.offset_polygon(mouth, 0.011 * k)
	if not lip.is_empty():
		parts.append([_copy(model, _sticker(lip[0], FACE1_LIFT), Transform3D()), _paint(FACE1_LIP), keep])
	parts.append([_copy(model, _sticker(mouth, FACE1_LIFT + 0.002), Transform3D()), _paint(FACE1_MOUTH), keep])
	if not tongue.is_empty():
		for poly in Geometry2D.intersect_polygons(tongue, mouth):
			parts.append([_copy(model, _sticker(poly, FACE1_LIFT + 0.004), Transform3D()), _paint(FACE1_TONGUE, 0.5, 0.4), keep])
	for poly in teeth:
		parts.append([_copy(model, _sticker(poly, FACE1_LIFT + 0.006), Transform3D()), _paint(FACE1_TOOTH, 0.35), keep])
	var eye_c := Vector2(0.0, low) if n > 0 else Vector2(0.0, top + 0.12)
	var ber := er if n > 0 else FACE1_ER
	for sx in [-1.0, 1.0]:
		var blush := PackedVector2Array()
		var bx: float = float(sx) * maxf(FACE1_BLUSH_X * ber, absf(_side_eye_x(lay[0], sx)) + ber * 1.15)
		var bc := Vector2(bx, eye_c.y - FACE1_BLUSH_DROP * ber)
		for i in 36:
			blush.append(bc + Vector2.from_angle(TAU * i / 36.0) * FACE1_BLUSH_R)
		parts.append([_copy(model, _sticker(blush, FACE1_LIFT), Transform3D()), _paint(FACE1_BLUSH, 0.6, 0.9), keep])
	return [parts, pts, er]


## Самый крайний глаз с этой стороны (x его центра; 0 — если глаз один посередине).
static func _side_eye_x(spots: Array, sx: float) -> float:
	var best := 0.0
	for s: Vector2 in spots:
		if s.x * sx > best * sx:
			best = s.x
	return best


## Глубина лицевой стороны нового тела в точке (x, y) и её нормаль (оси модели).
static func face1_z(x: float, y: float) -> float:
	var c: Array = FACE1_Z
	var x2 := x * x
	return c[0] + c[1] * x2 + c[2] * y + c[3] * y * y + c[4] * x2 * y + c[5] * x2 * x2 + c[6] * y * y * y


static func face1_normal(x: float, y: float) -> Vector3:
	var e := 0.005
	var dx := (face1_z(x + e, y) - face1_z(x - e, y)) / (2.0 * e)
	var dy := (face1_z(x, y + e) - face1_z(x, y - e)) / (2.0 * e)
	return Vector3(-dx, -dy, 1.0).normalized()


## Плоская фигура (x, y) на лицевой стороне: сетка лежит по выпуклости (треугольники мельче 2 см).
static func _sticker(poly: PackedVector2Array, lift: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx := Geometry2D.triangulate_polygon(poly)
	var stack := []
	for i in range(0, idx.size(), 3):
		stack.append([poly[idx[i]], poly[idx[i + 1]], poly[idx[i + 2]]])
	while not stack.is_empty():
		var t: Array = stack.pop_back()
		var a: Vector2 = t[0]
		var b: Vector2 = t[1]
		var c: Vector2 = t[2]
		if maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a))) > 0.02:
			var ab := (a + b) * 0.5
			var bc := (b + c) * 0.5
			var ca := (c + a) * 0.5
			stack.append_array([[a, ab, ca], [ab, b, bc], [ca, bc, c], [ab, bc, ca]])
			continue
		for q: Vector2 in [a, b, c]:
			st.set_normal(face1_normal(q.x, q.y))
			st.add_vertex(Vector3(q.x, q.y, face1_z(q.x, q.y) + lift))
	return st.commit()


## Бровь над глазом c (радиус er): толстая дуга шире глаза, к концам ниже и чуть тоньше, концы
## круглые; по выпуклой лицевой стороне. У грустного — наклонена (как у старой модели).
func _brow1(model: Node3D, c: Vector2, er: float, sad: bool) -> Array:
	var pts := PackedVector3Array()
	var rs := PackedFloat32Array()
	for j in 17:
		var t := j / 16.0 * 2.0 - 1.0
		var x := c.x + t * er * 0.84
		var y := c.y + er * (1.45 - 0.36 * t * t) + (t * er * 0.3 if sad else 0.0)
		pts.append(Vector3(x, y, face1_z(x, y) + FACE1_LIFT))
		rs.append(er * (0.26 - 0.05 * t * t))
	var out := [[_copy(model, _tube_mesh(pts, rs, 0.6), Transform3D()), _paint(FACE1_BROW), _flat(Color(1, 0, 0))]]
	for e in [0, pts.size() - 1]:
		var cap := SphereMesh.new()
		cap.radius = 1.0
		cap.height = 2.0
		out.append([_copy(model, cap, Transform3D(Basis.from_scale(Vector3(rs[e], rs[e], rs[e] * 0.6)), pts[e])),
			_paint(FACE1_BROW), _flat(Color(1, 0, 0))])
	return out


## Краска лица: со светом, без отсечения (наклейки и трубки видны с обеих сторон).
## glow — подсветка своим цветом (румянец и язык под светом листа иначе тускнеют до сиреневого).
func _paint(c: Color, rough := 0.6, glow := 0.0) -> StandardMaterial3D:
	var key := "paint" + c.to_html() + str(rough) + str(glow)
	if not _flats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		if glow > 0.0:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = glow
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_flats[key] = m
	return _flats[key]


## Глаз нового вида: белый блестящий шар, радужка (светлее к центру, тёмный ободок), зрачок и
## блик — по направлению на шаре (в осях самого шара), чётко при любом размере.
func _eye_mat(iris: Color) -> ShaderMaterial:
	var key := "eye" + iris.to_html()
	if not _shaders.has(key):
		var sh: Shader = _shaders.get("eye_shader")
		if sh == null:
			sh = Shader.new()
			sh.code = EYE_SHADER
			_shaders["eye_shader"] = sh
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("iris_col", iris)
		m.set_shader_parameter("gaze", FACE1_GAZE)
		m.set_shader_parameter("iris_r", FACE1_IRIS_R)
		m.set_shader_parameter("pupil_r", FACE1_PUPIL_R)
		_shaders[key] = m
	return _shaders[key]


const EYE_SHADER := """shader_type spatial;
uniform vec3 iris_col : source_color = vec3(0.24, 0.5, 0.9);
uniform vec3 gaze = vec3(0.26, 0.07, 1.0);
uniform float iris_r = 0.47;
uniform float pupil_r = 0.25;
varying vec3 lp;
void vertex() {
	lp = VERTEX;
}
float disk(vec3 p, vec3 dir, float r, float soft) {
	vec3 d = normalize(dir);
	float off = length(p - d * dot(p, d));
	return (1.0 - smoothstep(r - soft, r, off)) * step(0.0, dot(p, d));
}
void fragment() {
	vec3 p = normalize(lp);
	vec3 g = normalize(gaze);
	float off = length(p - g * dot(p, g));
	float t = off / iris_r;
	vec3 c = vec3(0.97, 0.97, 0.98);
	vec3 ic = mix(iris_col * 1.2, iris_col * 0.62, smoothstep(0.3, 0.95, t));
	c = mix(c, ic, disk(p, g, iris_r, 0.015));
	c = mix(c, iris_col * 0.32, disk(p, g, iris_r, 0.015) * smoothstep(0.84, 0.97, t));
	c = mix(c, vec3(0.02, 0.02, 0.04), disk(p, g, pupil_r, 0.012));
	float glint = disk(p, g + vec3(-0.17, 0.19, 0.0), 0.075, 0.012) + disk(p, g + vec3(0.1, -0.1, 0.0), 0.035, 0.01);
	c = mix(c, vec3(1.0), clamp(glint, 0.0, 1.0));
	ALBEDO = c;
	EMISSION = vec3(clamp(glint, 0.0, 1.0) * 0.4);
	ROUGHNESS = 0.22;
	SPECULAR = 0.6;
}
"""


static func _is_new_rig(path: String) -> bool:
	for s in NEW_RIG:
		if MODELS[s] == path:
			return true
	return false


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


## Инструменты строятся в своих осях (хват — в нуле, рукоять — вдоль +x, боёк — поперёк, по y)
## и ставятся в ладонь правой кисти под углом позы в плоскости гаврика (x — вперёд, y — вверх):
## так боёк всегда виден сбоку, а замах читается — над головой, вверх, вперёд-вниз.
## TOOL_ANGLE — угол рукояти по позе (градусы, 0 — вперёд, 90 — вверх). -> [[сетка, положение, материал]].
const TOOL_ANGLE := {"work0": 160.0, "work1": 80.0, "work2": -40.0, "work3": 80.0, "water0": -35.0, "water1": -45.0,
	"study0": 0.0, "study1": 0.0, "fish": 40.0, "shovel0": -25.0, "shovel1": 35.0, "turn0": 95.0, "turn1": 25.0,
	"scan0": 0.0, "scan1": -10.0}
## Ладонь — на столько по кисти от запястья; кончик удочки (в осях инструмента).
const GRIP := Vector3(0.0, 0.13, 0.0)
const ROD_TIP := Vector3(2.2, 0.0, 0.0)


func _tool_parts(name: String) -> Array:
	var wood := _tool_mat("wood", Color(0.6, 0.38, 0.2), 0.6, 0.0)
	var steel := _tool_mat("steel", Color(0.62, 0.66, 0.72), 0.3, 0.7)
	var out := []
	var handle := func(len: float, r: float) -> void:
		var pts := PackedVector3Array([Vector3(-0.18, 0, 0), Vector3(len, 0, 0)])
		out.append([_tube_mesh(pts, PackedFloat32Array([r, r * 0.9])), Transform3D(), wood])
	match name:
		"hammer":
			handle.call(1.05, 0.06)
			var head := BoxMesh.new()
			head.size = Vector3(0.24, 0.5, 0.24)
			out.append([head, Transform3D(Basis(), Vector3(1.0, 0.04, 0)), steel])
		"pickaxe":
			handle.call(1.15, 0.06)
			var pts := PackedVector3Array()
			var rs := PackedFloat32Array()
			for j in 13:
				var k := j / 12.0 * 2.0 - 1.0
				pts.append(Vector3(1.12 - 0.28 * k * k, k * 0.6, 0))
				rs.append(0.09 * (1.0 - absf(k)) + 0.015)
			out.append([_tube_mesh(pts, rs), Transform3D(), steel])
		"axe":
			handle.call(1.05, 0.06)
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			# Лезвие — плоский клин у конца рукояти, остриём вниз (в сторону удара).
			var poly := [Vector2(0.8, 0.0), Vector2(1.08, 0.0), Vector2(1.16, -0.38), Vector2(0.98, -0.5), Vector2(0.72, -0.4)]
			for z in [-0.04, 0.04]:
				for j in range(1, poly.size() - 1):
					for v in [poly[0], poly[j], poly[j + 1]]:
						st.set_normal(Vector3(0, 0, signf(z)))
						st.add_vertex(Vector3(v.x, v.y, z))
			out.append([st.commit(), Transform3D(), steel])
		"can":
			# Лейка висит под рукой за ручку, носик — вперёд-вверх (в позе наклонена — льёт).
			var green := _tool_mat("can", Color(0.3, 0.62, 0.42), 0.4, 0.3)
			var body := CylinderMesh.new()
			body.top_radius = 0.24
			body.bottom_radius = 0.27
			body.height = 0.42
			out.append([body, Transform3D(Basis(), Vector3(0.05, -0.42, 0)), green])
			var spout := PackedVector3Array([Vector3(0.25, -0.45, 0), Vector3(0.75, -0.22, 0)])
			out.append([_tube_mesh(spout, PackedFloat32Array([0.05, 0.035])), Transform3D(), green])
			var rose := CylinderMesh.new()
			rose.top_radius = 0.08
			rose.bottom_radius = 0.04
			rose.height = 0.08
			out.append([rose, Transform3D(Basis(Vector3.BACK, deg_to_rad(-65)), Vector3(0.78, -0.2, 0)), green])
			var arc := PackedVector3Array()
			var rs := PackedFloat32Array()
			for j in 9:
				var a := PI * j / 8.0
				arc.append(Vector3(0.05 - cos(a) * 0.17, -0.2 + sin(a) * 0.17, 0))
				rs.append(0.035)
			out.append([_tube_mesh(arc, rs), Transform3D(), green])
		"flask":
			# Круглая колба с зелёным раствором над пальцами, горлышко — в руке.
			var glass := _tool_mat("glass", Color(0.85, 0.96, 1.0), 0.05, 0.0)
			var liquid := _tool_mat("liquid", Color(0.3, 0.85, 0.4), 0.15, 0.0)
			var bulb := SphereMesh.new()
			bulb.radius = 0.22
			bulb.height = 0.44
			out.append([bulb, Transform3D(Basis(), Vector3(0, 0.3, 0.05)), liquid])
			var shine := SphereMesh.new()
			shine.radius = 0.06
			shine.height = 0.12
			out.append([shine, Transform3D(Basis(), Vector3(-0.08, 0.38, 0.25)), glass])
			var neck := CylinderMesh.new()
			neck.top_radius = 0.065
			neck.bottom_radius = 0.07
			neck.height = 0.2
			out.append([neck, Transform3D(Basis(), Vector3(0, 0.02, 0.05)), glass])
		"rod":
			var pts := PackedVector3Array([Vector3(-0.2, 0, 0), Vector3(0.4, 0, 0), ROD_TIP])
			out.append([_tube_mesh(pts, PackedFloat32Array([0.06, 0.045, 0.014])), Transform3D(), wood])
		"shovel":
			handle.call(1.05, 0.055)
			# Совок — пластина на конце черенка, чуть загнута (лицом к зрителю, видно сбоку).
			var blade := BoxMesh.new()
			blade.size = Vector3(0.5, 0.42, 0.05)
			out.append([blade, Transform3D(Basis(), Vector3(1.25, 0.0, 0)), steel])
			# Уголь на совке.
			var coal := SphereMesh.new()
			coal.radius = 0.12
			coal.height = 0.2
			out.append([coal, Transform3D(Basis(), Vector3(1.28, 0.05, 0.06)), _tool_mat("coal", Color(0.12, 0.11, 0.12), 0.8, 0.0)])
		"wrench":
			var pts := PackedVector3Array([Vector3(-0.12, 0, 0), Vector3(0.62, 0, 0)])
			out.append([_tube_mesh(pts, PackedFloat32Array([0.05, 0.045])), Transform3D(), steel])
			for jy in [-0.12, 0.12]:
				var jaw := BoxMesh.new()
				jaw.size = Vector3(0.2, 0.07, 0.08)
				out.append([jaw, Transform3D(Basis(), Vector3(0.72, jy, 0)), steel])
			var back := BoxMesh.new()
			back.size = Vector3(0.07, 0.3, 0.08)
			out.append([back, Transform3D(Basis(), Vector3(0.6, 0, 0)), steel])
		"geiger":
			# Жёлтый прибор со стрелочной шкалой и щупом на проводе.
			var yellow := _tool_mat("geiger", Color(0.95, 0.78, 0.2), 0.45, 0.1)
			var dark := _tool_mat("dark", Color(0.18, 0.19, 0.22), 0.5, 0.3)
			var box := BoxMesh.new()
			box.size = Vector3(0.6, 0.42, 0.28)
			out.append([box, Transform3D(Basis(), Vector3(0.15, 0.25, 0)), yellow])
			var dial := CylinderMesh.new()
			dial.top_radius = 0.13
			dial.bottom_radius = 0.13
			dial.height = 0.03
			out.append([dial, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.08, 0.28, 0.15)), _tool_mat("dial", Color(0.95, 0.95, 0.9), 0.4, 0.0)])
			var wand := PackedVector3Array([Vector3(0.45, 0.25, 0), Vector3(0.85, 0.05, 0)])
			out.append([_tube_mesh(wand, PackedFloat32Array([0.035, 0.035])), Transform3D(), dark])
	return out


func _tool_mat(key: String, c: Color, rough: float, metal: float) -> StandardMaterial3D:
	if not _flats.has("tool_" + key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_flats["tool_" + key] = m
	return _flats["tool_" + key]


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
	var flags := 0
	# Развёртка текстуры (у моделей с текстурой) — в CUSTOM0: UV заняты позой покоя.
	var tex_uv = arr[Mesh.ARRAY_TEX_UV]
	if tex_uv != null and (tex_uv as PackedVector2Array).size() == v.size():
		var c0 := PackedFloat32Array()
		c0.resize(v.size() * 2)
		for i in v.size():
			c0[i * 2] = tex_uv[i].x
			c0[i * 2 + 1] = tex_uv[i].y
		arr[Mesh.ARRAY_CUSTOM0] = c0
		flags |= Mesh.ARRAY_CUSTOM_RG_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	uv.resize(v.size())
	uv2.resize(v.size())
	for i in v.size():
		uv[i] = Vector2(v[i].x, v[i].y)
		uv2[i] = Vector2(v[i].z, 0.0)
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	var bones = arr[Mesh.ARRAY_BONES]
	if bones != null and bones.size() == v.size() * 8:
		flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
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


## Тело с текстурой (модели TEXTURED): тело (жёлтое в текстуре) — белое со светотенью текстуры,
## остальное (глаза, рот, подошвы) — как есть; для маски — G там, где тело.
func _skin_mat(src: Material, mask: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/model_skin.gdshader")
	var tex: Texture2D = (src as BaseMaterial3D).albedo_texture if src is BaseMaterial3D else null
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("mask", mask)
	return m


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
## ref — скелет старой модели, под который написаны позы: тогда кость направляется так же, как
## у него (от своего сустава в ту же сторону) — для моделей с суставами в других местах.
static func pose_skeleton(skel: Skeleton3D, groups: Array, ref: Skeleton3D = null) -> void:
	for group in groups:
		for b in group:
			if b[1] is String:
				var target: Vector3 = b[2]
				if ref != null:
					ref.force_update_all_bone_transforms()
					skel.force_update_all_bone_transforms()
					var from := ref.get_bone_global_pose(ref.find_bone(b[0])).origin
					aim_bone(ref, b[0], target)
					target = skel.get_bone_global_pose(skel.find_bone(b[0])).origin + (target - from)
				aim_bone(skel, b[0], target)
			else:
				if ref != null:
					rotate_bone(ref, b[0], b[1], b[2])
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


## Поза строкой: «work0», с «@hammer» — с инструментом в руке, с «|sad» в конце — грустный.
static func base_pose(pose: String) -> String:
	return pose.get_slice("|", 0).get_slice("@", 0)


static func tool_of(pose: String) -> String:
	var i := pose.find("@")
	return "" if i < 0 else pose.substr(i + 1).get_slice("|", 0)


## Лист инструмента: свой у каждой формы (тело закрывает его по-разному) и у длинных рук.
static func tool_key(looks: Dictionary, tool: String) -> String:
	return "tool/%s/%d/%d" % [tool, int(looks.get("shape", 0)), 1 if looks.get("long_arms", false) else 0]


## Инструмент модели в этой позе готов (иначе — заказать; пока рисуйте его по-старому).
func tool_ready(looks: Dictionary, tool: String, pose: String) -> bool:
	if tool.is_empty() or not TOOL_POSES.has(tool) or not base_pose(pose) in TOOL_POSES[tool]:
		return false
	var key := tool_key(looks, tool)
	if sheets.has(key):
		return true
	if not _failed.has(key):
		_want(key)
	return false


## Кончик удочки относительно ступней (пиксели экрана) или null.
func tool_tip(pose: String, h: float, looks: Dictionary, tool: String):
	if not tool_ready(looks, tool, pose):
		return null
	var s: Dictionary = sheets[tool_key(looks, tool)]
	var f := _frame(s, base_pose(pose))
	return (f["tip"] as Vector2) * (h / HEIGHT / float(s["ppm"])) if f.has("tip") else null


## Нарисовать гаврика-модель: ступни в at, h — его высота в пикселях. Слои — по порядку,
## инструмент («@…» в позе) — поверх. Грустное лицо («|sad») снимается отдельно; пока его нет — обычное.
func draw(ci: CanvasItem, pose: String, at: Vector2, h: float, looks: Dictionary) -> void:
	var sad := pose.ends_with("|sad")
	var tool := tool_of(pose)
	pose = base_pose(pose)
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
		var tint := col if l[1] == Tint.BODY else hair if l[1] == Tint.HAIR \
			else (looks.get("pattern_color", col) as Color) if l[1] == Tint.PATTERN else Color.WHITE
		ci.draw_texture_rect_region(s["tex"], Rect2(at - (f["foot"] as Vector2) * k, region.size * k), region, tint)
		if key.begins_with("face/"):
			face = f
			face_k = k
	if POSES.get(pose, {}).get("closed", false) and not face.is_empty():
		# Закрытые глаза: веки цвета тела (в листе) и дуги ресниц.
		var r := float(face["eye_r"]) * face_k
		for e: Vector2 in face["eyes"]:
			ci.draw_arc(at + e * face_k + Vector2(0, -r * 0.35), r * 0.85, 0.35, PI - 0.35, 12, CreatureArt.PUPIL, maxf(1.0, r * 0.22), true)
	if tool_ready(looks, tool, pose):
		var s: Dictionary = sheets[tool_key(looks, tool)]
		var f := _frame(s, pose)
		var k := h / HEIGHT / float(s["ppm"])
		var region: Rect2 = f["region"]
		ci.draw_texture_rect_region(s["tex"], Rect2(at - (f["foot"] as Vector2) * k, region.size * k), region, Color.WHITE)


## Где правая кисть относительно ступней (пиксели экрана) — для инструмента в руке.
func hand_pos(pose: String, h: float, looks: Dictionary) -> Vector2:
	pose = base_pose(pose)
	var s: Dictionary = sheets.get(body_key(looks), sheets["body/%d/0/4/0" % CreatureArt.Shape.TRIANGLE])
	return (_frame(s, pose)["hand"] as Vector2) * (h / HEIGHT / float(s["ppm"]))


static func _frame(sheet: Dictionary, pose: String) -> Dictionary:
	var frames: Dictionary = sheet["frames"]
	if frames.has(pose):
		return frames[pose]
	return frames["idle"] if frames.has("idle") else frames.values()[0]
