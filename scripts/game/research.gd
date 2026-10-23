class_name Research
extends RefCounted
## Исследования: учёные в лаборатории копят очки, очки открывают технологии.
## Четыре ветки: Наука, Транспорт, Добыча, Строительство — связаны только соседние.
## Переключились на другую технологию — накопленное по прежней не пропадает (пауза).

const BRANCHES := ["Наука", "Транспорт", "Добыча", "Строительство"]

## id -> [название, что даёт, очки, требуется, ветка, ряд, колонка]
## Ряд — от верха экрана «Наука», колонка — ступень (слева — основы).
const TECHS := {
	# Наука
	"mushrooms": ["Грибоводство", "Грибные фермы дают на четверть больше еды", 40.0, [], 0, 0, 0],
	"hydroponics": ["Гидропоника", "Фермы с энергией дают в полтора раза больше еды", 180.0, ["mushrooms", "electricity"], 0, 0, 3],
	"apprentice": ["Ученичество", "Дети учатся у родителей: пока родитель работает, у ребёнка растёт навык этой работы", 40.0, [], 0, 1, 0],
	"nature": ["Естествознание", "Учёные открывают на четверть быстрее", 80.0, ["apprentice"], 0, 1, 1],
	"electricity": ["Электричество", "Генератор на угле или дровах, свет в комнатах и ходах (в темноте работа медленнее), энергия насосам, вентиляции и лабораториям. Генератор — из железа и меди", 120.0, ["nature"], 0, 1, 2],
	"mechanics": ["Механика", "Паровые машины: генераторы дают в полтора раза больше энергии", 180.0, ["electricity"], 0, 1, 3],
	"chemistry": ["Химия", "Газовый генератор: энергия из метана, который собирает дегазация", 240.0, ["mechanics"], 0, 1, 4],
	"electronics": ["Электроника", "Автоматы: лаборатории и мастерские работают в полтора раза быстрее", 300.0, ["chemistry"], 0, 1, 5],
	"nuclear": ["Ядерная физика", "Обогатительная фабрика: 1 урановая руда → 3 урана. Уран радиоактивен", 380.0, ["electronics"], 0, 1, 6],
	# Транспорт
	"carts": ["Тачки", "Гаврики носят по 8 единиц вместо 5", 40.0, [], 1, 2, 0],
	"ropes": ["Канаты и блоки", "По лестницам лазают в полтора раза быстрее", 80.0, ["carts"], 1, 2, 1],
	"lifts": ["Электролифт", "Пассажирский лифт: строго вертикальная шахта 2 м или горизонтальный ход; кабина на 6 человек ездит втрое быстрее пешехода. Нужны железо, медь и энергия", 180.0, ["ropes", "electricity"], 1, 2, 3],
	"cargo_lifts": ["Грузовой лифт", "Грузовой лифт: шахта 3 м, возит только грузы; у склада вплотную сам разгружается и сам берёт материалы для строек у другого конца", 240.0, ["lifts"], 1, 2, 4],
	"fast_lifts": ["Скоростной лифт", "Лифты ездят вдвое быстрее", 300.0, ["cargo_lifts"], 1, 2, 5],
	"rails": ["Рельсы", "Вагонетки: с грузом по шахтам и горизонтальным тоннелям — в полтора раза быстрее", 120.0, ["carts", "smelting"], 1, 3, 2],
	"combustion": ["Двигатель", "Дизельный генератор (в полтора раза мощнее и вдвое дольше на единице топлива) и бур на дизеле — идёт и без электричества", 380.0, ["rails", "refining"], 1, 3, 6],
	"rocketry": ["Ракета", "Космодром и ракета на дизеле: экспедиция до 10 гавриков и 200 груза на Меркурий, Венеру или Марс", 450.0, ["combustion"], 1, 3, 7],
	"nuclear_engine": ["Ядерный двигатель", "Ракета на уране долетит до Юпитера, Сатурна, Урана и Нептуна", 500.0, ["rocketry", "nuclear"], 1, 2, 8],
	# Добыча
	"geology": ["Геологоразведка I", "Видно на 2 клетки в глубь породы от выработок (было 1); геолог чует воду, газ и магму за 4 клетки", 40.0, [], 2, 4, 0],
	"smelting": ["Плавка руды", "Кузница: 1 руда — 3 железа, меди, серебра или золота", 80.0, ["geology"], 2, 4, 1],
	"tools": ["Железный инструмент", "Копают в полтора раза быстрее", 120.0, ["smelting"], 2, 4, 2],
	"drill_rig": ["Буровая установка", "Бур сам проходит ход 3 м шириной строго вниз или вбок — втрое быстрее гаврика, на энергии. Готовый ход — тоннель (вниз) или шахта (вбок)", 180.0, ["tools"], 2, 4, 3],
	"oil_drilling": ["Нефтедобыча", "Нефтекачалка тянет нефть из пластов вокруг (10, 20 или 40 м) по трубам в нефтехранилище. Хранилище взрывается, если рухнет", 240.0, ["drill_rig"], 2, 4, 4],
	"refining": ["Переработка нефти", "Нефтезавод: мастер перегоняет 2 нефти в 1 дизельное топливо (по трубам)", 300.0, ["oil_drilling"], 2, 4, 5],
	"geology2": ["Геологоразведка II", "Видно на 3 клетки в глубь породы; геолог чует опасность за 6 клеток", 80.0, ["geology"], 2, 5, 1],
	"geology3": ["Геологоразведка III", "Видно на 4 клетки в глубь породы; геолог чует опасность за 8 клеток", 120.0, ["geology2"], 2, 5, 2],
	"geology4": ["Геологоразведка IV", "Видно на 5 клеток в глубь породы; геолог чует опасность за 10 клеток", 180.0, ["geology3"], 2, 5, 3],
	"diamond_bits": ["Алмазный бур", "Бур идёт вдвое быстрее", 240.0, ["drill_rig"], 2, 5, 4],
	"gas_masks": ["Противогазы", "Метан душит вдвое слабее: удушье только при вдвое большей концентрации", 40.0, [], 2, 6, 0],
	"gas_collector": ["Газосборник", "Дегазация собирает вдвое больше метана", 80.0, ["gas_masks"], 2, 6, 1],
	"drainage": ["Дренаж", "Насосы откачивают воду вдвое быстрее", 180.0, ["smelting"], 2, 6, 2],
	# Строительство
	"pottery": ["Гончарное дело", "Печь: кирпич из глины; кирпичные стены (прочнее, служат 70 лет) и кирпичные печи в очаге", 40.0, [], 3, 7, 0],
	"gas_heating": ["Газовое отопление", "Кирпичные газовые котлы для очагов: жгут метан от дегазации (1 метан — как 3 полена), на газу греют на 1–2 м дальше", 120.0, ["pottery", "gas_collector"], 3, 7, 2],
	"steel_frame": ["Железный каркас", "Железные стены (самые прочные) и железная крепь (её вдвое меньше на срез, чем дерева)", 180.0, ["smelting"], 3, 7, 3],
	"heatproof": ["Жаростойкие стены", "Жара не изнашивает постройки быстрее — для горячих глубин и планет", 240.0, ["steel_frame"], 3, 7, 4],
	"scaffolding": ["Строительные леса", "Стройка и ремонт идут в полтора раза быстрее", 40.0, [], 3, 8, 0],
	"shelving": ["Стеллажи", "Склады вмещают в полтора раза больше", 80.0, ["scaffolding"], 3, 8, 1],
	"insulation": ["Теплоизоляция", "Очаги греют вдвое дальше", 180.0, ["gas_heating"], 3, 8, 3],
	"climate": ["Климат-контроль", "Вентиляция охлаждает вдвое сильнее, жару терпят на 15 °C дольше", 240.0, ["insulation"], 3, 8, 4],
}
## Очков в секунду от одного обычного учёного: на первые технологии — около двух игровых месяцев.
const POINTS_PER_SEC := 0.03
## Старые технологии (до новой науки) → новые: изученное в старом сохранении не пропадает.
const OLD := {
	"agronomy": ["mushrooms"], "medicine": [], "education": ["apprentice"], "carts": ["carts"],
	"carpentry": ["scaffolding"], "shelving": ["shelving"], "maintenance": ["scaffolding"],
	"bricks": ["pottery"], "metallurgy": ["smelting", "steel_frame"], "drilling": ["tools"],
	"deep_drilling": ["tools"], "electricity": ["electricity"], "steam": ["mechanics"],
	"cooling": ["climate"], "hydroponics": ["hydroponics"], "gas_masks": ["gas_masks"],
	"gas_heating": ["gas_heating"], "automation": ["electronics"], "lifts": ["lifts"],
	"cargo_lifts": ["cargo_lifts"], "fast_lifts": ["fast_lifts"], "fast_lifts2": ["fast_lifts"],
	"drill_rig": ["drill_rig"], "diamond_bits": ["diamond_bits"], "heavy_drill": ["diamond_bits"],
	"oil_drilling": ["oil_drilling"], "refining": ["refining"], "combustion": ["combustion"],
	"rocketry": ["rocketry"], "nuclear_engine": ["nuclear_engine", "nuclear"],
	"geology": ["geology"], "geology2": ["geology2"], "geology3": ["geology3"], "geology4": ["geology4"],
}

var done: Array[String] = []
var current := ""
## Накоплено очков по каждой начатой технологии (и по текущей).
var spent := {}
## Очки текущей технологии.
var progress: float:
	get:
		return float(spent.get(current, 0.0))
	set(v):
		if not current.is_empty():
			spent[current] = v


func has(id: String) -> bool:
	return id.is_empty() or done.has(id)


static func tech_name(id: String) -> String:
	return TECHS[id][0]


static func branch_of(id: String) -> String:
	return BRANCHES[TECHS[id][4]]


func cost(id: String) -> float:
	return TECHS[id][2]


## Сколько уже накоплено по технологии (в том числе на паузе).
func points(id: String) -> float:
	return float(spent.get(id, 0.0))


## Можно начать: не изучено и все требования выполнены.
func available(id: String) -> bool:
	if not TECHS.has(id) or done.has(id):
		return false
	for need in TECHS[id][3]:
		if not done.has(need):
			return false
	return true


## Начать (или продолжить) технологию; прежняя ставится на паузу со своими очками.
func start(id: String) -> bool:
	if not available(id):
		return false
	current = id
	return true


## Добавляет очки; возвращает id завершённой технологии или "".
func add(amount: float) -> String:
	if current.is_empty():
		return ""
	progress += amount
	if progress < cost(current):
		return ""
	var finished := current
	learn(finished)
	# Следующую выбирает игрок — сама наука дальше не идёт.
	current = ""
	return finished


## Отметить изученной (вместе со всем, что ей требовалось).
func learn(id: String) -> void:
	if not TECHS.has(id) or done.has(id):
		return
	for need in TECHS[id][3]:
		learn(need)
	done.append(id)
	spent.erase(id)


func to_dict() -> Dictionary:
	return {"done": done, "current": current, "spent": spent, "v": 2}


func load_dict(d: Dictionary) -> void:
	done.clear()
	spent.clear()
	var old := int(d.get("v", 1)) < 2
	for id in d.get("done", []):
		var key := str(id)
		if old:
			for n in OLD.get(key, []):
				learn(n)
		elif TECHS.has(key):
			learn(key)
	current = str(d.get("current", ""))
	if old:
		var mapped: Array = OLD.get(current, [])
		current = ""
		for n in mapped:
			if available(n):
				current = n
				spent[n] = float(d.get("progress", 0.0))
				break
	else:
		var sp: Dictionary = d.get("spent", {})
		for k in sp:
			if TECHS.has(str(k)) and not done.has(str(k)):
				spent[str(k)] = float(sp[k])
	if not current.is_empty() and (not TECHS.has(current) or done.has(current)):
		current = ""
