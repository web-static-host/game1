class_name Project
extends RefCounted
## Стройка: тоннель или комната. Этап 1 — выкопать твёрдые клетки,
## этап 2 — построить (нужны ресурсы). Можно поставить на паузу.

## BRIDGE — мостик над водой (переход и рыбалка), PIER — рыболовная пристань.
## MINE — шахта: горизонтальная выработка в 3 м высотой для добычи (копают шахтёры);
## на её месте потом можно ставить комнаты.
## LIFT — лифт: строго вертикальная шахта (пассажирский — 2 м, грузовой — 3 м шириной)
## или горизонтальный ход в 3 м высотой; строится как тоннель, потом ставят кабину.
## DRILL — бур: сам проходит ход в 3 м шириной строго вниз или вбок; готовый ход
## становится тоннелем (вниз) или шахтой (вбок).
enum Kind { TUNNEL, ROOM, BRIDGE, PIER, MINE, LIFT, DRILL }
## EQUIP — готовая комната оборудуется под назначение.
enum Phase { DIG, BUILD, DONE, EQUIP }

const ROOM_MIN := Vector2i(3, 3)
const ROOM_MAX := Vector2i(24, 3)
## Все комнаты одной высоты — как этажи.
const ROOM_HEIGHT := 3
## Шахта — как этаж комнаты, чтобы на её месте потом встали комнаты.
const MINE_HEIGHT := 3
## Размеры на выбор при закладке.
const ROOM_WIDTHS := [3, 6, 9]
const TUNNEL_MAX_LEN := 64
const TUNNEL_MAX_WIDTH := 3
## Материалы стен комнат: ключ -> [название, множитель времени стройки].
const MATERIALS := {
	"wood": ["Дерево", 1.0],
	"stone": ["Камень", 1.5],
	"brick": ["Кирпич", 1.3],
	"metal": ["Сталь", 1.6],
}

var id := 0
var kind := Kind.TUNNEL
var rect := Rect2i()
var phase := Phase.DIG
var paused := false
## Ресурсы на этап строительства уже списаны со склада.
var paid := false
var build_done := 0.0
## Ресурсы, найденные при раскопке: ключ -> количество.
var found := {}
## Почему стройка стоит (пусто — всё в порядке).
var blocked := ""
## Сколько жителей одновременно работает на стройке.
var workers := 1
## Лестница у левой стены (нужна, если пол комнаты ниже поверхности).
var ladder := false
## Материал стен комнаты: ключ ресурса ("wood", "stone", "brick", "metal").
var material := "wood"
## Назначение комнаты (RoomType) и оборудование.
var purpose := 0
var equip_target := 0
var equip_paid := false
var equip_done := 0.0
## Прогресс фермы до следующей единицы еды.
var farm_progress := 0.0
## Обустройство — это постройка лестницы (назначение не меняется).
var equip_ladder := false
## Лифт: грузовой (только грузы) или пассажирский.
var cargo := false
## Кабина лифта: где она (координата по оси шахты; -1 — ещё не ставили), груз в ней,
## сколько стоит на остановке, грузы, ждущие у концов шахты [начало, конец].
var lift_pos := -1.0
## Бур: идёт от конца (низ/право), а не от начала; сколько уже сверлит текущий срез.
var drill_rev := false
var drill_t := 0.0
var lift_load := {}
var lift_dwell := 0.0
## Грузовой лифт едет к концу (0 — начало, 1 — конец; -1 — стоит).
var lift_goal := -1
var lift_buf: Array = [{}, {}]
## Перестройка стен из другого материала (пусто — не перестраивают).
var equip_material := ""
## Под что строят комнату (выбрано в меню стройки): после постройки сразу обустраивается.
var plan_purpose := 0
## Очаг с кирпичными печами (иначе — каменные).
var brick_stoves := false
## Очаг сейчас горит на метане (газовое отопление).
var on_gas := false
## Над печами очага стоят железные газовые котлы (жгут метан).
var gas_boiler := false
## Объекты поверхности (столбцы x), которые надо убрать на этапе 1.
var clear_x: Array[int] = []
## Что хранит склад (пусто — всё; из старых сохранений, теперь — store_off).
var store_filter: Array[String] = []
## Что игрок снял галочкой: этого склад (амбар) не хранит.
var store_off: Array[String] = []
## Предел хранения по ресурсу (нет ключа — сколько влезет).
var limits := {}
## Сколько секунд выработка простаивает без крепи (пауза, ждёт материалы).
var exposed_t := 0.0
## Дополнительная крепь (дерево), если пролёт шире, чем держит порода.
var support_wood := 0
## Копка по срезам: срез выкопали — закрепили — следующий.
## Срезы, где есть порода (их надо крепить), и уже закреплённые.
var needs_support: Array[int] = []
var supported: Array[int] = []
## Крепь текущего среза: номер, оплачена ли, прогресс работ.
var support_slice := -1
var support_paid := false
var support_progress := 0.0
## Материалы, уже принесённые на стройку: ключ -> количество.
var delivered := {}
## Сырьё, которое подсобные рабочие уже принесли в мастерскую.
var stock := {}
## Сколько циклов обжига ещё горит заложенное топливо (печь для кирпича).
var fuel := 0.0
## Горит ли огонь (очаг, генератор) — греет всё вокруг. Не сохраняется: пересчитывается.
var burning := false
## Свет в комнате: -1 — сам (по умолчанию горит в ближних к генератору, пока хватает энергии),
## 0 — выключен, 1 — включён. lit — горит ли сейчас (пересчитывается, не сохраняется).
var light := -1
var lit := false
## Износ готовой постройки 0..1 (1 — разрушается) и уровень последнего предупреждения.
var wear := 0.0
var wear_warned := 0
## Ремонт: идёт ли, оплачен ли (материалы принесены), прогресс и сколько нужно.
var repairing := false
var repair_paid := false
var repair_done := 0.0
var repair_need := {}
var repair_work := 0.0
## Склад: сколько жителей сами добывают ресурсы и какой запас держать.
var gatherers := 0
var targets := {}
## Что лежит именно в этом складе/амбаре (в дегазации — метан в баке): ключ -> количество.
var held := {}
## Предупреждения геолога: опасности, на которые игрок разрешил копать, и текущее.
var hazard_ack: Array[String] = []
var hazard_pending := ""


func title() -> String:
	if kind == Kind.LIFT:
		return "%s %d м" % ["Грузовой лифт" if cargo else "Лифт", maxi(rect.size.x, rect.size.y)]
	if kind == Kind.DRILL:
		return "Бур %d м" % maxi(rect.size.x, rect.size.y)
	if kind == Kind.ROOM and purpose != RoomType.NONE:
		return "%s %d×%d" % [RoomType.NAMES[purpose], rect.size.x, rect.size.y]
	return "%s %d×%d" % [kind_name(kind), rect.size.x, rect.size.y]


static func kind_name(k: int) -> String:
	return ["Тоннель", "Комната", "Мостик", "Пристань", "Шахта", "Лифт", "Бур"][k]


## Лифт вертикальный (иначе — горизонтальный).
func lift_vertical() -> bool:
	return rect.size.y > rect.size.x


## Материалы на лифт: железо на каркас и рельсы, медь на провода, плюс кабина.
## Бур: железо на обсадку хода (по 1 на 4 м) и медь на мотор.
static func drill_cost(r: Rect2i) -> Dictionary:
	return {"iron": ceili(maxi(r.size.x, r.size.y) / 4.0) + 4, "copper": 2}


static func lift_cost(r: Rect2i, is_cargo: bool) -> Dictionary:
	var n := maxi(r.size.x, r.size.y)
	return {"iron": n * (2 if is_cargo else 1) + (10 if is_cargo else 6), "copper": ceili(n / 2.0) + 4}


func is_water_structure() -> bool:
	return kind == Kind.BRIDGE or kind == Kind.PIER


func phase_name() -> String:
	match phase:
		Phase.DIG:
			return "копка"
		Phase.BUILD:
			return "строительство" if paid else "доставка материалов"
		Phase.EQUIP:
			if equip_ladder:
				return "строится лестница" if equip_paid else "лестница: доставка материалов"
			return "обустройство" if equip_paid else "обустройство: доставка материалов"
	if repairing:
		return "ремонт" if repair_paid else "ремонт: доставка материалов"
	return "готово"


func area() -> int:
	return rect.size.x * rect.size.y


func cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			out.append(Vector2i(x, y))
	return out


func has_cell(c: Vector2i) -> bool:
	return rect.has_point(c)


## Стоимость второго этапа. Тоннелю нужна крепь и лестницы (дерево),
## комнате — стены из выбранного материала и деревянные балки перекрытий.
static func cost_for(k: int, r: Rect2i, mat := "wood") -> Dictionary:
	var cells_n := r.size.x * r.size.y
	if k == Kind.ROOM:
		var out := {"wood": ceili(cells_n / 6.0)}
		out[mat] = out.get(mat, 0) + r.size.x + r.size.y
		return out
	if k == Kind.BRIDGE:
		return {"wood": 2 * r.size.x}
	if k == Kind.PIER:
		return {"wood": 4 * r.size.x, "stone": 4}
	# Тоннель крепится по ходу копки — на втором этапе только отделка.
	return {}


## Объём работ второго этапа, сек (для жителя с навыком 1).
static func work_for(k: int, r: Rect2i, mat := "wood") -> float:
	var cells_n := r.size.x * r.size.y
	if k == Kind.ROOM:
		return cells_n * 5.0 * MATERIALS.get(mat, ["", 1.0])[1]
	if k == Kind.BRIDGE:
		return r.size.x * 4.0
	if k == Kind.PIER:
		return r.size.x * 8.0
	if k == Kind.LIFT:
		return maxi(r.size.x, r.size.y) * 4.0
	return cells_n * 1.0


func cost() -> Dictionary:
	if kind == Kind.LIFT:
		return lift_cost(rect, cargo)
	if kind == Kind.DRILL:
		return drill_cost(rect)
	return cost_for(kind, rect, material)


## --- Срезы копки -------------------------------------------------------------

## Вертикальная шахта крепится по 2 ряда, остальное — по столбцам.
func vertical() -> bool:
	return (kind == Kind.TUNNEL or kind == Kind.LIFT) and rect.size.y > rect.size.x


func slice_count() -> int:
	return ceili(rect.size.y / 2.0) if vertical() else rect.size.x


func slice_of(c: Vector2i) -> int:
	return (c.y - rect.position.y) / 2 if vertical() else c.x - rect.position.x


func slice_cells(i: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in cells():
		if slice_of(c) == i:
			out.append(c)
	return out


## Дерево на крепь одного среза (у широкой комнаты в слабой породе — больше).
func slice_wood() -> int:
	if kind == Kind.ROOM:
		return 1 + ceili(support_wood / float(maxi(1, needs_support.size())))
	return 1


func slice_work() -> float:
	return rect.size.y * 3.0 if kind == Kind.ROOM else 6.0


func support_total() -> int:
	return slice_wood() * needs_support.size()


## Клетка под закреплённым срезом.
func cell_supported(c: Vector2i) -> bool:
	var i := slice_of(c)
	return supported.has(i) and needs_support.has(i)


func build_work() -> float:
	return work_for(kind, rect, material)


func material_name() -> String:
	return MATERIALS.get(material, ["?"])[0]


## Сколько рыбаков одновременно и сколько секунд на улов.
func fish_slots() -> int:
	return maxi(1, rect.size.x / (2 if kind == Kind.PIER else 4))


func fish_time() -> float:
	return 15.0 if kind == Kind.PIER else 40.0


## Рекомендуемое число рабочих: примерно один на 6–8 клеток площади.
static func recommended_workers(k: int, r: Rect2i, max_workers: int) -> int:
	var per := 8.0 if k == Kind.ROOM else 6.0
	return clampi(ceili(r.size.x * r.size.y / per), 1, maxi(1, max_workers))


## Проверка размеров. Остальные проверки (пересечения, опора) — в Colony.
static func size_error(k: int, r: Rect2i) -> String:
	var w := r.size.x
	var h := r.size.y
	if k == Kind.BRIDGE or k == Kind.PIER:
		if h != 1:
			return "Мост и пристань — по одному ряду над водой"
		if k == Kind.BRIDGE and (w < 2 or w > 40):
			return "Мостик — от 2 до 40 м"
		if k == Kind.PIER and (w < 3 or w > 10):
			return "Пристань — от 3 до 10 м"
		return ""
	if k == Kind.ROOM:
		if w < ROOM_MIN.x or h < ROOM_MIN.y:
			return "Комната — минимум %d×%d" % [ROOM_MIN.x, ROOM_MIN.y]
		if w > ROOM_MAX.x:
			return "Комната — не шире %d м" % ROOM_MAX.x
		if h != ROOM_HEIGHT:
			return "Комната — %d м в высоту" % ROOM_HEIGHT
		return ""
	if k == Kind.DRILL:
		if h > w:
			if w != 3 or h < 4:
				return "Бур вниз проходит ход 3 м шириной, от 4 м"
		elif h != 3 or w < 4:
			return "Бур вбок проходит ход 3 м высотой, от 4 м"
		if maxi(w, h) > TUNNEL_MAX_LEN:
			return "Бур — не длиннее %d м за раз" % TUNNEL_MAX_LEN
		return ""
	if k == Kind.LIFT:
		# Строго вертикально (2–3 м шириной) или строго горизонтально (3 м высотой).
		if h > w:
			if w < 2 or w > 3 or h < 4:
				return "Лифт по вертикали — шахта 2 м (пассажирский) или 3 м (грузовой) шириной, от 4 м"
		elif h != 3 or w < 4:
			return "Лифт по горизонтали — ход в 3 м высотой, от 4 м длиной"
		if maxi(w, h) > TUNNEL_MAX_LEN:
			return "Лифт — не длиннее %d м" % TUNNEL_MAX_LEN
		return ""
	if k == Kind.MINE:
		if h != MINE_HEIGHT:
			return "Шахта — всегда %d м в высоту" % MINE_HEIGHT
		if w < 2:
			return "Шахта — от 2 м в длину"
		if w > TUNNEL_MAX_LEN:
			return "Шахта — не длиннее %d м" % TUNNEL_MAX_LEN
		return ""
	if h < 2:
		return "Тоннель — высотой от 2 м, иначе человек не пройдёт"
	if mini(w, h) > TUNNEL_MAX_WIDTH:
		return "Слишком широко для тоннеля — стройте комнату"
	if maxi(w, h) > TUNNEL_MAX_LEN:
		return "Тоннель — не длиннее %d м" % TUNNEL_MAX_LEN
	return ""


func to_dict() -> Dictionary:
	return {
		"id": id,
		"kind": kind,
		"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
		"phase": phase,
		"paused": paused,
		"paid": paid,
		"build_done": build_done,
		"found": found,
		"blocked": blocked,
		"workers": workers,
		"ladder": ladder,
		"material": material,
		"purpose": purpose,
		"equip_target": equip_target,
		"equip_paid": equip_paid,
		"equip_done": equip_done,
		"farm_progress": farm_progress,
		"equip_ladder": equip_ladder,
		"equip_material": equip_material,
		"plan_purpose": plan_purpose,
		"brick_stoves": brick_stoves,
		"gas_boiler": gas_boiler,
		"light": light,
		"fuel": fuel,
		"clear_x": clear_x,
		"store_filter": store_filter,
		"store_off": store_off,
		"cargo": cargo,
		"lift_pos": lift_pos,
		"lift_load": lift_load,
		"lift_buf": lift_buf,
		"lift_goal": lift_goal,
		"drill_rev": drill_rev,
		"drill_t": drill_t,
		"limits": limits,
		"exposed_t": exposed_t,
		"support_wood": support_wood,
		"needs_support": needs_support,
		"supported": supported,
		"support_slice": support_slice,
		"support_paid": support_paid,
		"support_progress": support_progress,
		"delivered": delivered,
		"stock": stock,
		"wear": wear,
		"wear_warned": wear_warned,
		"repairing": repairing,
		"repair_paid": repair_paid,
		"repair_done": repair_done,
		"repair_need": repair_need,
		"repair_work": repair_work,
		"gatherers": gatherers,
		"targets": targets,
		"held": held,
		"hazard_ack": hazard_ack,
		"hazard_pending": hazard_pending,
	}


static func from_dict(d: Dictionary) -> Project:
	var p := Project.new()
	p.id = int(d["id"])
	p.kind = int(d["kind"])
	var r: Array = d["rect"]
	p.rect = Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
	p.phase = int(d["phase"])
	p.paused = bool(d.get("paused", false))
	p.paid = bool(d.get("paid", false))
	p.build_done = float(d.get("build_done", 0.0))
	var f: Dictionary = d.get("found", {})
	for k in f:
		p.found[k] = int(f[k])
	p.blocked = str(d.get("blocked", ""))
	p.workers = int(d.get("workers", 2))
	p.ladder = bool(d.get("ladder", false))
	p.material = str(d.get("material", "wood"))
	# Глиняных комнат больше нет (глина — только сырьё для кирпича): старые стали кирпичными.
	if p.material == "clay":
		p.material = "brick"
	p.purpose = int(d.get("purpose", 0))
	p.equip_target = int(d.get("equip_target", 0))
	p.equip_paid = bool(d.get("equip_paid", false))
	p.equip_done = float(d.get("equip_done", 0.0))
	p.farm_progress = float(d.get("farm_progress", 0.0))
	p.equip_ladder = bool(d.get("equip_ladder", false))
	p.equip_material = str(d.get("equip_material", ""))
	p.cargo = bool(d.get("cargo", false))
	p.lift_pos = float(d.get("lift_pos", -1.0))
	p.lift_goal = int(d.get("lift_goal", -1))
	p.drill_rev = bool(d.get("drill_rev", false))
	p.drill_t = float(d.get("drill_t", 0.0))
	for k in d.get("lift_load", {}):
		p.lift_load[str(k)] = int(d["lift_load"][k])
	var bufs: Array = d.get("lift_buf", [{}, {}])
	for i in mini(2, bufs.size()):
		for k in bufs[i]:
			p.lift_buf[i][str(k)] = int(bufs[i][k])
	p.plan_purpose = int(d.get("plan_purpose", 0))
	p.brick_stoves = bool(d.get("brick_stoves", false))
	p.gas_boiler = bool(d.get("gas_boiler", false))
	p.light = int(d.get("light", -1))
	p.fuel = float(d.get("fuel", 0.0))
	for x in d.get("clear_x", []):
		p.clear_x.append(int(x))
	# Мосту и пристани расчистка не нужна (раньше ждали дерево на дальнем берегу).
	if p.is_water_structure():
		p.clear_x.clear()
	for k in d.get("store_filter", []):
		p.store_filter.append(str(k))
	for k in d.get("store_off", []):
		p.store_off.append(str(k))
	for k in d.get("limits", {}):
		p.limits[str(k)] = int(d["limits"][k])
	p.exposed_t = float(d.get("exposed_t", 0.0))
	p.support_wood = int(d.get("support_wood", 0))
	for i in d.get("needs_support", []):
		p.needs_support.append(int(i))
	for i in d.get("supported", []):
		p.supported.append(int(i))
	p.support_slice = int(d.get("support_slice", -1))
	p.support_paid = bool(d.get("support_paid", false))
	p.support_progress = float(d.get("support_progress", 0.0))
	p.delivered = _int_dict(d.get("delivered", {}))
	p.stock = _int_dict(d.get("stock", {}))
	p.wear = float(d.get("wear", 0.0))
	p.wear_warned = int(d.get("wear_warned", 0))
	p.repairing = bool(d.get("repairing", false))
	p.repair_paid = bool(d.get("repair_paid", false))
	p.repair_done = float(d.get("repair_done", 0.0))
	p.repair_need = _int_dict(d.get("repair_need", {}))
	p.repair_work = float(d.get("repair_work", 0.0))
	p.gatherers = int(d.get("gatherers", 0))
	p.targets = _int_dict(d.get("targets", {}))
	p.held = _int_dict(d.get("held", {}))
	for k in d.get("hazard_ack", []):
		p.hazard_ack.append(str(k))
	p.hazard_pending = str(d.get("hazard_pending", ""))
	return p


static func _int_dict(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[str(k)] = int(d[k])
	return out
