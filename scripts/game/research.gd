class_name Research
extends RefCounted
## Исследования: учёные в лаборатории копят очки, очки открывают технологии.

## id -> [название, что даёт, очки, требуется]
const TECHS := {
	"agronomy": ["Агрономия", "Фермы дают на четверть больше еды", 40.0, []],
	"carts": ["Тачки", "Жители носят по 8 единиц вместо 5", 40.0, []],
	"bricks": ["Обжиг кирпича", "Печь: кирпич из глины; кирпичные стены (прочнее глины, служат 70 лет)", 30.0, []],
	"geology": ["Геологоразведка", "Геолог чует воду, газ и магму за 4 клетки вместо 2", 60.0, []],
	"electricity": ["Электричество", "Генератор на угле или дровах: свет в комнатах и ходах (в темноте работа идёт медленнее), насосы, вентиляция и лаборатория с энергией работают сильнее", 60.0, []],
	"carpentry": ["Плотницкое дело", "Стройка и ремонт идут в полтора раза быстрее", 80.0, ["carts"]],
	"medicine": ["Медицина", "Раны и истощение заживают вдвое быстрее", 90.0, ["agronomy"]],
	"metallurgy": ["Металлургия", "Кузница: сталь из железа и угля; стальные конструкции — лёгкие и очень прочные", 80.0, ["bricks"]],
	"hydroponics": ["Гидропоника", "Фермы с энергией дают в полтора раза больше еды", 60.0, ["electricity"]],
	"shelving": ["Стеллажи", "Склады вмещают в полтора раза больше", 90.0, ["carpentry"]],
	"gas_masks": ["Противогазы", "Метан душит слабее: удушье только при вдвое большей концентрации", 110.0, ["geology", "medicine"]],
	"education": ["Обучение", "Навыки растут вдвое быстрее", 130.0, ["medicine"]],
	"drilling": ["Бурение", "Стальной инструмент: копка в полтора раза быстрее", 120.0, ["metallurgy"]],
	"steam": ["Паровые турбины", "Генераторы дают в полтора раза больше энергии", 160.0, ["electricity", "metallurgy"]],
	"maintenance": ["Пропитка и крепёж", "Постройки изнашиваются на 30% медленнее", 170.0, ["carpentry", "metallurgy"]],
	"cooling": ["Кондиционирование", "Вентиляция охлаждает вдвое сильнее, жару терпят на 15 °C дольше", 200.0, ["steam"]],
	"deep_drilling": ["Глубинное бурение", "Копка вдвое быстрее, чем вручную (вместо полутора)", 260.0, ["drilling", "cooling"]],
	"automation": ["Автоматика", "Лаборатории и мастерские работают в полтора раза быстрее", 320.0, ["steam", "education"]],
}
## Очков за секунду работы учёного (с навыком 1).
const POINTS_PER_SEC := 0.1

var done: Array[String] = []
var current := ""
var progress := 0.0


func has(id: String) -> bool:
	return id.is_empty() or done.has(id)


static func tech_name(id: String) -> String:
	return TECHS[id][0]


func cost(id: String) -> float:
	return TECHS[id][2]


## Можно начать: не изучено и все требования выполнены.
func available(id: String) -> bool:
	if done.has(id):
		return false
	for need in TECHS[id][3]:
		if not done.has(need):
			return false
	return true


func start(id: String) -> bool:
	if not available(id):
		return false
	if current != id:
		current = id
		progress = 0.0
	return true


## Добавляет очки; возвращает id завершённой технологии или "".
func add(points: float) -> String:
	if current.is_empty():
		return ""
	progress += points
	if progress < cost(current):
		return ""
	var finished := current
	done.append(finished)
	current = ""
	progress = 0.0
	# Следующая доступная — сама, чтобы учёные не простаивали.
	for id in TECHS:
		if available(id):
			current = id
			break
	return finished


func to_dict() -> Dictionary:
	return {"done": done, "current": current, "progress": progress}


func load_dict(d: Dictionary) -> void:
	done.clear()
	for id in d.get("done", []):
		if TECHS.has(str(id)):
			done.append(str(id))
	current = str(d.get("current", ""))
	if not current.is_empty() and not TECHS.has(current):
		current = ""
	progress = float(d.get("progress", 0.0))
