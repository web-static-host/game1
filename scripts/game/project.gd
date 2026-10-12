class_name Project
extends RefCounted
## Стройка: тоннель или комната. Этап 1 — выкопать твёрдые клетки,
## этап 2 — построить (нужны ресурсы). Можно поставить на паузу.

enum Kind { TUNNEL, ROOM }
## EQUIP — готовая комната оборудуется под назначение.
enum Phase { DIG, BUILD, DONE, EQUIP }

const ROOM_MIN := Vector2i(3, 3)
const ROOM_MAX := Vector2i(24, 8)
const TUNNEL_MAX_LEN := 64
const TUNNEL_MAX_WIDTH := 3
## Материалы стен комнат: ключ -> [название, множитель времени стройки].
const MATERIALS := {
	"wood": ["Дерево", 1.0],
	"clay": ["Глина", 1.2],
	"stone": ["Камень", 1.5],
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
## Материал стен комнаты: ключ ресурса ("wood", "clay", "stone").
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
## Объекты поверхности (столбцы x), которые надо убрать на этапе 1.
var clear_x: Array[int] = []
## Что хранит склад (пусто — всё).
var store_filter: Array[String] = []


func title() -> String:
	if kind == Kind.ROOM and purpose != RoomType.NONE:
		return "%s %d×%d" % [RoomType.NAMES[purpose], rect.size.x, rect.size.y]
	return "%s %d×%d" % [kind_name(kind), rect.size.x, rect.size.y]


static func kind_name(k: int) -> String:
	return "Комната" if k == Kind.ROOM else "Тоннель"


func phase_name() -> String:
	match phase:
		Phase.DIG:
			return "копка"
		Phase.BUILD:
			return "строительство" if paid else "ждёт ресурсы"
		Phase.EQUIP:
			if equip_ladder:
				return "строится лестница" if equip_paid else "лестница ждёт ресурсы"
			return "обустройство" if equip_paid else "обустройство ждёт ресурсы"
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
	return {"wood": ceili(cells_n / 4.0)}


## Объём работ второго этапа, сек (для жителя с навыком 1).
static func work_for(k: int, r: Rect2i, mat := "wood") -> float:
	var cells_n := r.size.x * r.size.y
	if k == Kind.ROOM:
		return cells_n * 5.0 * MATERIALS.get(mat, ["", 1.0])[1]
	return cells_n * 2.0


func cost() -> Dictionary:
	return cost_for(kind, rect, material)


func build_work() -> float:
	return work_for(kind, rect, material)


func material_name() -> String:
	return MATERIALS.get(material, ["?"])[0]


## Рекомендуемое число рабочих: примерно один на 6–8 клеток площади.
static func recommended_workers(k: int, r: Rect2i, max_workers: int) -> int:
	var per := 8.0 if k == Kind.ROOM else 6.0
	return clampi(ceili(r.size.x * r.size.y / per), 1, maxi(1, max_workers))


## Проверка размеров. Остальные проверки (пересечения, опора) — в Colony.
static func size_error(k: int, r: Rect2i) -> String:
	var w := r.size.x
	var h := r.size.y
	if k == Kind.ROOM:
		if w < ROOM_MIN.x or h < ROOM_MIN.y:
			return "Комната — минимум %d×%d" % [ROOM_MIN.x, ROOM_MIN.y]
		if w > ROOM_MAX.x or h > ROOM_MAX.y:
			return "Комната — максимум %d×%d" % [ROOM_MAX.x, ROOM_MAX.y]
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
		"clear_x": clear_x,
		"store_filter": store_filter,
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
	p.purpose = int(d.get("purpose", 0))
	p.equip_target = int(d.get("equip_target", 0))
	p.equip_paid = bool(d.get("equip_paid", false))
	p.equip_done = float(d.get("equip_done", 0.0))
	p.farm_progress = float(d.get("farm_progress", 0.0))
	p.equip_ladder = bool(d.get("equip_ladder", false))
	for x in d.get("clear_x", []):
		p.clear_x.append(int(x))
	for k in d.get("store_filter", []):
		p.store_filter.append(str(k))
	return p
