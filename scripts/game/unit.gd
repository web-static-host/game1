class_name Unit
extends RefCounted
## Житель колонии. Позиция — клетка, где стоят ноги (рост ~2 клетки).

enum Sex { MALE, FEMALE }
enum State { IDLE, MOVE, WORK, FALL }
enum Task { NONE, DIG, BUILD, HARVEST }

const MALE_NAMES := ["Иван", "Пётр", "Алексей", "Дмитрий", "Сергей", "Николай", "Михаил", "Андрей", "Егор", "Павел"]
const FEMALE_NAMES := ["Анна", "Мария", "Елена", "Ольга", "Наталья", "Татьяна", "Ирина", "Светлана", "Дарья", "Вера"]
const SKILL_NAMES := {"dig": "Копка", "build": "Стройка", "gather": "Сбор"}
const TASK_NAMES := ["отдыхает", "копает", "строит", "собирает ресурсы"]

var id := 0
var name := ""
var sex := Sex.MALE
var pos := Vector2.ZERO
## Опыт навыков в секундах работы.
var skills := {"dig": 0.0, "build": 0.0, "gather": 0.0}
## Внешность (детерминирована от id).
var look := 0.0

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
	return ""


func status_text() -> String:
	var parts: PackedStringArray = []
	for k in ["dig", "build", "gather"]:
		parts.append("%s %d" % [SKILL_NAMES[k], level(k)])
	return "%s (%s) — %s\n%s" % [
		name, "муж." if sex == Sex.MALE else "жен.", TASK_NAMES[task], " · ".join(parts)]


func to_dict() -> Dictionary:
	return {"id": id, "name": name, "sex": sex, "pos": [pos.x, pos.y], "skills": skills, "look": look}


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
	return u
