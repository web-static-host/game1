class_name Project
extends RefCounted
## Стройка: тоннель или комната. Этап 1 — выкопать твёрдые клетки,
## этап 2 — построить (нужны ресурсы). Можно поставить на паузу.

enum Kind { TUNNEL, ROOM }
enum Phase { DIG, BUILD, DONE }

const ROOM_MIN := Vector2i(3, 3)
const ROOM_MAX := Vector2i(24, 8)
const TUNNEL_MAX_LEN := 64
const TUNNEL_MAX_WIDTH := 3

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


func title() -> String:
	return "%s %d×%d" % [kind_name(kind), rect.size.x, rect.size.y]


static func kind_name(k: int) -> String:
	return "Комната" if k == Kind.ROOM else "Тоннель"


func phase_name() -> String:
	match phase:
		Phase.DIG:
			return "копка"
		Phase.BUILD:
			return "строительство" if paid else "ждёт ресурсы"
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
## комнате — ещё и камень на стены, пол и потолок.
static func cost_for(k: int, r: Rect2i) -> Dictionary:
	var cells_n := r.size.x * r.size.y
	if k == Kind.ROOM:
		return {"wood": ceili(cells_n / 4.0) + 2, "stone": r.size.x + r.size.y}
	return {"wood": ceili(cells_n / 4.0)}


## Объём работ второго этапа, сек (для жителя с навыком 1).
static func work_for(k: int, r: Rect2i) -> float:
	var cells_n := r.size.x * r.size.y
	return cells_n * (5.0 if k == Kind.ROOM else 2.0)


func cost() -> Dictionary:
	return cost_for(kind, rect)


func build_work() -> float:
	return work_for(kind, rect)


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
	return p
