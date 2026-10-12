class_name Unit
extends RefCounted
## Житель колонии. Позиция — клетка, где стоят ноги (рост ~2 клетки).

enum Sex { MALE, FEMALE }
enum State { IDLE, MOVE, WORK, FALL, SWIM }
enum Task { NONE, DIG, BUILD, HARVEST, SLEEP, EAT, FARM, EQUIP, FISH, SUPPORT, HAUL, REPAIR, CRAFT, RESEARCH }
enum Prof { ANY, DIGGER, BUILDER, GATHERER, FARMER, SCIENTIST }

const MALE_NAMES := ["Иван", "Пётр", "Алексей", "Дмитрий", "Сергей", "Николай", "Михаил", "Андрей", "Егор", "Павел",
	"Тимофей", "Глеб", "Лев", "Матвей", "Фёдор", "Роман", "Кирилл", "Олег", "Степан", "Юрий"]
const FEMALE_NAMES := ["Анна", "Мария", "Елена", "Ольга", "Наталья", "Татьяна", "Ирина", "Светлана", "Дарья", "Вера",
	"Алиса", "Ева", "Мила", "Варвара", "Полина", "Софья", "Нина", "Зоя", "Лидия", "Яна"]
const SKILL_NAMES := {"dig": "Копка", "build": "Стройка", "gather": "Сбор", "farm": "Ферма", "science": "Наука"}
const TASK_NAMES := ["отдыхает", "копает", "строит", "собирает ресурсы", "спит", "ест", "работает на ферме", "обустраивает комнату", "рыбачит", "ставит крепь", "носит материалы", "ремонтирует", "работает в мастерской", "исследует"]
const PROF_NAMES := ["Разнорабочий", "Копатель", "Строитель", "Сборщик", "Фермер", "Учёный"]
## Сколько секунд длится детство.
const CHILD_TIME := 1800.0


## Рост ребёнка 0..1 (для размера фигуры).
func growth() -> float:
	return clampf(age / CHILD_TIME, 0.0, 1.0) if child else 1.0

var id := 0
var name := ""
var sex := Sex.MALE
var pos := Vector2.ZERO
## Опыт навыков в секундах работы.
var skills := {"dig": 0.0, "build": 0.0, "gather": 0.0, "farm": 0.0, "science": 0.0}
## Внешность (детерминирована от id).
var look := 0.0
## Потребности 0..100.
var energy := 100.0
var satiety := 100.0
## Здоровье 0..100: травмы от обвалов, восстанавливается отдыхом.
var health := 100.0
var profession := Prof.ANY
## Возраст в секундах игры (для детей), дети не работают.
var child := false
var age := 0.0
var partner_id := 0
## Срок беременности в секундах (-1 — не беременна).
var pregnancy := -1.0
## Кровать: id жилой комнаты и номер кровати (0 — нет).
var bed_room := 0
var bed_index := 0
## Таймер текущего действия (еда).
var work_t := 0.0
## Переноска: что и сколько несёт (или собирается взять), этап: 0 — к складу, 1 — к цели.
var carry_key := ""
var carry_amount := 0
var haul_stage := 0
## Работает на склад: id склада, для которого добывает ресурсы (0 — нет).
var gather_room := 0

var state := State.IDLE
var task := Task.NONE
var target := Vector2i.ZERO
var project_id := 0
var path: Array[Vector2i] = []
var path_i := 0
var retry := 0.0
var facing := 1
var anim := 0.0


func cell() -> Vector2i:
	return Vector2i(roundi(pos.x), roundi(pos.y))


func level(skill: String) -> int:
	return 1 + int(sqrt(skills.get(skill, 0.0) / 120.0))


## Множитель скорости работы от навыка.
func speed(skill: String) -> float:
	return 1.0 + 0.15 * (level(skill) - 1)


static func skill_for(t: int) -> String:
	match t:
		Task.DIG:
			return "dig"
		Task.BUILD:
			return "build"
		Task.HARVEST:
			return "gather"
		Task.FARM:
			return "farm"
		Task.EQUIP:
			return "build"
		Task.FISH:
			return "gather"
		Task.SUPPORT:
			return "build"
		Task.REPAIR:
			return "build"
		Task.CRAFT:
			return "build"
		Task.RESEARCH:
			return "science"
	return ""


## Настроение 0..100 из сытости, бодрости и наличия кровати.
func mood() -> float:
	var m := 50.0 + (satiety - 50.0) * 0.4 + (energy - 50.0) * 0.3 + (10.0 if bed_room != 0 else -10.0)
	return clampf(m, 0.0, 100.0)


## Множитель скорости работы от потребностей.
func need_factor() -> float:
	var f := 1.0
	if satiety < 15.0:
		f *= 0.5
	if energy < 10.0:
		f *= 0.6
	if mood() < 30.0:
		f *= 0.85
	if health < 50.0:
		f *= 0.7
	return f


func status_text() -> String:
	var parts: PackedStringArray = []
	for k in ["dig", "build", "gather", "farm"]:
		parts.append("%s %d" % [SKILL_NAMES[k], level(k)])
	var who := "муж." if sex == Sex.MALE else "жен."
	if child:
		who = "%s, вырастет через %s, ест вдвое больше" % [
			"малыш" if age < CHILD_TIME * 0.5 else "подросток", Fmt.duration(CHILD_TIME - age)]
	var lines: PackedStringArray = ["%s (%s) — %s" % [name, who, TASK_NAMES[task]]]
	var needs := "Сытость %d%% · бодрость %d%% · настроение %d%%" % [roundi(satiety), roundi(energy), roundi(mood())]
	if health < 99.5:
		needs += " · здоровье %d%%" % roundi(health)
	lines.append(needs)
	if not child:
		lines.append(" · ".join(parts))
	var extra: PackedStringArray = []
	extra.append("кровать есть" if bed_room != 0 else "нет кровати")
	if pregnancy >= 0.0:
		extra.append("ждёт ребёнка")
	lines.append(", ".join(extra))
	return "\n".join(lines)


func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "sex": sex, "pos": [pos.x, pos.y], "skills": skills, "look": look,
		"energy": energy, "satiety": satiety, "profession": profession, "child": child, "age": age,
		"partner_id": partner_id, "pregnancy": pregnancy, "bed_room": bed_room, "bed_index": bed_index,
		"health": health,
	}


static func from_dict(d: Dictionary) -> Unit:
	var u := Unit.new()
	u.id = int(d["id"])
	u.name = str(d["name"])
	u.sex = int(d["sex"])
	var p: Array = d["pos"]
	u.pos = Vector2(float(p[0]), float(p[1]))
	var s: Dictionary = d.get("skills", {})
	for k in u.skills:
		u.skills[k] = float(s.get(k, 0.0))
	u.look = float(d.get("look", 0.0))
	u.energy = float(d.get("energy", 100.0))
	u.satiety = float(d.get("satiety", 100.0))
	u.profession = int(d.get("profession", Prof.ANY))
	u.child = bool(d.get("child", false))
	u.age = float(d.get("age", 0.0))
	u.partner_id = int(d.get("partner_id", 0))
	u.pregnancy = float(d.get("pregnancy", -1.0))
	u.bed_room = int(d.get("bed_room", 0))
	u.bed_index = int(d.get("bed_index", 0))
	u.health = float(d.get("health", 100.0))
	return u
