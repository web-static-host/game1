class_name Planet
extends RefCounted
## Планеты Солнечной системы: условия, недра, полёт. Земля — дом колонии.
## На других планетах дышать нечем: живут в корабле и под землёй (корабль держит
## воздух в своих выработках), а на поверхность не выходят.

## id -> параметры:
##  name, desc — название и коротко об условиях;
##  travel — сколько месяцев лететь с Земли; engine — какой двигатель нужен ("chem"/"nuclear");
##  surf, under — температура у поверхности и в недрах (на 15–20 м), °C;
##  air, plants, lakes — воздух, растения, озёра;
##  atm — что над поверхностью: "air" (дышат), "vacuum" (пустота — выходят только в постройках),
##  "gas" (ядовитый газ — дегазация, достающая до поверхности, очищает воздух над собой);
##  ore — насколько богаче рудные жилы; ores — свой набор руд [[доля, материал], ...];
##  kimberlite, gas, oil — пороги алмазных трубок, газовых карманов и нефти (меньше — чаще);
##  quakes — множитель землетрясений; sky — оттенок неба;
##  geo — облик планеты (миры версии 8 и новее): relief — рельеф ("craters" — кратеры, "volcanic" —
##  вулканические холмы, "mesas" — столовые горы и уступы, "ice" — ровные ледяные равнины);
##  regolith — грунт сверху; sed — толщина осадочных пород (доля земной); basalt — с какой глубины
##  начинается базальт; magma — глубина магмы; ores — как залегают руды ("veins" — жилы, как на
##  Земле; "blobs" — крупные гнёзда у поверхности; "layers" — тонкие пласты, каждый своей руды;
##  "deep" — бедно у поверхности, богато глубже 250 м; "pockets" — редкие богатые гнёзда);
##  caves — сколько пещер (доля земного); tubes — пещеры вытянуты по горизонтали (лавовые
##  трубки); ice — толщина ледяной коры, м; palette — оттенок пород; leaf — цвет листвы деревьев;
##  trees — доля столбцов с деревьями там, где растений нет (Венера: свои деревья).
const DATA := {
	"earth": {"atm": "air", "name": "Земля", "desc": "Дом колонии: воздух, леса, озёра, времена года.",
		"travel": 0, "engine": "", "surf": 9.0, "under": 9.0, "air": true, "plants": true, "lakes": true,
		"ore": 1.0, "ores": [], "kimberlite": 0.62, "gas": 0.62, "oil": 0.66, "oil_depth": 200,
		"quakes": 1.0, "sky": Color(1, 1, 1)},
	"mercury": {"absent": ["clay", "oil"],
		"rocks": {Mat.SANDSTONE: Mat.GRAPHITE, Mat.SHALE: Mat.GRAPHITE, Mat.GRANITE: Mat.GRAPHITE, Mat.GNEISS: Mat.BASALT,
			Mat.LIMESTONE: Mat.SULFUR, Mat.ROCK_SALT: Mat.SULFUR, Mat.CLAY: Mat.GRAVEL, Mat.OIL: Mat.GRAPHITE},
		"hints": {
			"stone": "Камень на Меркурии — из тёмной графитовой породы (она сверху, копается легко) и из базальта глубже 120 м. Сера (жёлтая) — пустая порода, ничего не даёт.",
			"coal": "Уголь — тонкими пластами в верхних 15–60 м, в графитовой породе: слой осадочных пород на Меркурии тонкий. Копайте вдоль пласта.",
			"methane": "Метан — от открытого угля и из газовых карманов в верхних десятках метров. Пластов угля мало — и газа немного.",
		},
		"geo": {"relief": "craters", "regolith": [Mat.GRAVEL, Mat.BASALT], "sed": 0.15, "basalt": 120, "magma": 2500, "ores": "blobs", "caves": 0.5, "tubes": false, "ice": 0, "palette": Color(0.78, 0.74, 0.72), "leaf": Color(0, 0, 0, 0)}, "atm": "vacuum", "name": "Меркурий", "desc": "Горячая поверхность (+60 °C), воздуха нет. Под землёй прохладнее (+24 °C). Много железа и серебра. Редкий аметист — для ядерной ракеты. Изрыт кратерами; руда — крупными гнёздами у самой поверхности.",
		"travel": 4, "engine": "chem", "surf": 60.0, "under": 24.0, "air": false, "plants": false, "lakes": false,
		"ore": 1.8, "ores": [[0.45, Mat.IRON_ORE], [0.65, Mat.COPPER_ORE], [0.95, Mat.SILVER_ORE], [1.0, Mat.GOLD_ORE]],
		"amethyst": 0.04, "kimberlite": 0.62, "gas": 0.75, "oil": 0.9, "oil_depth": 200, "quakes": 1.0, "sky": Color(0.75, 0.62, 0.5)},
	"venus": {"trees": 0.18, "geo": {"relief": "volcanic", "regolith": [Mat.GRAVEL, Mat.BASALT], "sed": 0.35, "basalt": 50, "magma": 300, "ores": "deep", "caves": 1.3, "tubes": true, "ice": 0, "palette": Color(1.18, 0.92, 0.55), "leaf": Color(0.95, 0.42, 0.12)}, "atm": "gas", "name": "Венера", "desc": "Жара (+75 °C у поверхности, около +58 °C в недрах, в корабле +55 °C). Красным нормально; обычным нужен «Климат-контроль» или вентиляция; синие выживут только второй партией, когда вентиляция уже стоит (и с «Климат-контролем»). Много золота и урана, нефть — неглубоко в песчанике. Редкий аметист — для ядерной ракеты. Ядовитый газ: наружу — только где дегазация очистила воздух, там растут свои деревья. Вулканы: базальт и магма неглубоко, лавовые трубки; руда бедна у поверхности, богата глубже 250 м.",
		"travel": 3, "engine": "chem", "surf": 75.0, "under": 58.0, "air": false, "plants": false, "lakes": false,
		"ore": 1.4, "ores": [[0.3, Mat.IRON_ORE], [0.5, Mat.COPPER_ORE], [0.8, Mat.GOLD_ORE], [1.0, Mat.URANIUM_ORE]],
		"amethyst": 0.04, "kimberlite": 0.62, "gas": 0.62, "oil": 0.6, "oil_depth": 40, "quakes": 1.0, "sky": Color(0.95, 0.72, 0.4)},
	"mars": {"absent": ["coal", "oil"],
		"rocks": {Mat.LIMESTONE: [Mat.GYPSUM, 0.1], Mat.COAL: Mat.SHALE, Mat.OIL: Mat.SANDSTONE, Mat.GRANITE: Mat.BASALT},
		"hints": {
			"stone": "Камень на Марсе — песчаник и сланец (толстый осадочный слой, до 150–650 м), ниже — базальт. Гипс (белый) — пустая порода, ничего не даёт; известняк встречается редко.",
			"methane": "Метан — только из газовых карманов в сланце глубже 40 м (угля на Марсе нет). Его собирает дегазация — это главное топливо: газовые котлы в очагах и газовый генератор.",
			"clay": "Глина — 2–11 м, пятнами среди песка (как на Земле): кирпич делать можно.",
		},
		"geo": {"relief": "mesas", "regolith": [Mat.SAND, Mat.GRAVEL], "sed": 1.6, "basalt": 900, "magma": 3000, "ores": "layers", "caves": 1.5, "tubes": true, "ice": 0, "palette": Color(1.32, 0.72, 0.52), "leaf": Color(0, 0, 0, 0)}, "atm": "vacuum", "name": "Марс", "desc": "Холодно (−30 °C у поверхности, около −12 °C в недрах, в корабле около 0 °C), воздуха нет. Синим нормально; обычным нужны очаги (два рядом греют вдвое); красные выживут только второй партией, когда очаги уже горят. Много железа и меди. Редкий аметист — для ядерной ракеты. Столовые горы и толстые слои пород; руда — тонкими пластами, лавовые трубки.",
		"travel": 3, "engine": "chem", "surf": -30.0, "under": -12.0, "air": false, "plants": false, "lakes": false,
		"ore": 1.4, "ores": [[0.6, Mat.IRON_ORE], [0.95, Mat.COPPER_ORE], [1.0, Mat.SILVER_ORE]],
		"amethyst": 0.04, "kimberlite": 0.62, "gas": 0.7, "oil": 0.9, "oil_depth": 200, "quakes": 0.5, "sky": Color(0.9, 0.55, 0.4)},
	"jupiter": {"ruby": 0.0015, "rocks": {Mat.OIL: Mat.SANDSTONE}, "geo": {"relief": "ice", "regolith": [Mat.ICE, Mat.ICE], "sed": 1.0, "basalt": 2500, "magma": 1200, "ores": "pockets", "caves": 0.8, "tubes": false, "ice": 45, "palette": Color(1.15, 0.92, 0.72), "leaf": Color(0, 0, 0, 0)}, "atm": "gas", "name": "Юпитер", "desc": "Ледяная корка (−40 °C) над тёплыми недрами (около +15 °C). Частые землетрясения. Богат ураном. Ледяная кора ~45 м; руда — редкими богатыми гнёздами. Ядовитый газ: наружу — где дегазация очистила воздух. В корабле около −10 °C: синим терпимо, остальным — к очагам; красные выживут только второй партией.",
		"travel": 6, "engine": "nuclear", "surf": -40.0, "under": 15.0, "air": false, "plants": false, "lakes": false,
		"ore": 1.5, "ores": [[0.3, Mat.IRON_ORE], [0.5, Mat.COPPER_ORE], [0.6, Mat.SILVER_ORE], [0.7, Mat.GOLD_ORE], [1.0, Mat.URANIUM_ORE]],
		"kimberlite": 0.62, "gas": 0.6, "oil": 0.8, "oil_depth": 200, "quakes": 3.0, "sky": Color(0.85, 0.68, 0.5)},
	"saturn": {"ruby": 0.0015, "geo": {"relief": "ice", "regolith": [Mat.ICE, Mat.ICE], "sed": 1.4, "basalt": 4000, "magma": 2000, "ores": "veins", "caves": 1.0, "tubes": false, "ice": 25, "palette": Color(1.12, 1.02, 0.74), "leaf": Color(0, 0, 0, 0)}, "atm": "gas", "name": "Сатурн", "desc": "Холодный (−45 °C у поверхности, около +5 °C в недрах), недра пропитаны нефтью — неглубоко и много. Ледяная кора ~25 м, ядовитый газ над ней. В корабле около −15 °C: синим терпимо, остальным — к очагам; красные выживут только второй партией.",
		"travel": 8, "engine": "nuclear", "surf": -45.0, "under": 5.0, "air": false, "plants": false, "lakes": false,
		"ore": 1.0, "ores": [], "kimberlite": 0.62, "gas": 0.55, "oil": 0.35, "oil_depth": 40, "quakes": 1.0,
		"sky": Color(0.92, 0.85, 0.6)},
	"uranus": {"ruby": 0.0015, "rocks": {Mat.OIL: Mat.SANDSTONE}, "geo": {"relief": "ice", "regolith": [Mat.ICE, Mat.ICE], "sed": 0.6, "basalt": 3000, "magma": 2500, "ores": "pockets", "caves": 0.7, "tubes": false, "ice": 80, "palette": Color(0.76, 1.04, 1.1), "leaf": Color(0, 0, 0, 0)}, "atm": "gas", "name": "Уран", "desc": "Очень холодно (−50 °C у поверхности, около −18 °C в недрах). Алмазные дожди: алмазов в недрах во много раз больше. Богаче всех ураном — его гнёзда тут на каждом шагу. Толстая ледяная кора ~80 м; руда — редкими гнёздами; ядовитый газ. В корабле около −20 °C: синим терпимо, остальным — к очагам; красные выживут только второй партией.",
		"travel": 10, "engine": "nuclear", "surf": -50.0, "under": -18.0, "air": false, "plants": false, "lakes": false,
		"ore": 6.0, "ores": [[0.1, Mat.IRON_ORE], [0.2, Mat.COPPER_ORE], [0.25, Mat.SILVER_ORE], [0.3, Mat.GOLD_ORE], [1.0, Mat.URANIUM_ORE]],
		"kimberlite": 0.15, "gas": 0.62, "oil": 0.9, "oil_depth": 200, "quakes": 1.0,
		"sky": Color(0.6, 0.9, 0.95)},
	"neptune": {"ruby": 0.0015, "amethyst": 0.03, "rocks": {Mat.SHALE: [Mat.CLAY, 0.8]},
		"hints": {"clay": "Глина — только под ледяной корой: пятнами в сланце, с ~100 м. Кирпич сделать можно, но глину придётся поискать."},
		"geo": {"relief": "ice", "regolith": [Mat.ICE, Mat.ICE], "sed": 1.2, "basalt": 3500, "magma": 800, "ores": "veins", "caves": 1.4, "tubes": false, "ice": 100, "palette": Color(0.62, 0.76, 1.22), "leaf": Color(0, 0, 0, 0)}, "atm": "gas", "name": "Нептун", "desc": "Самая дальняя и самая трудная. Лютый холод: −65 °C у поверхности, около −35 °C в недрах, в корабле около −35 °C — без очагов не выживет никто, даже синие (везите дрова и кирпич). Ледяная кора ~100 м, ядовитый газ над ней, частые сильные землетрясения, недра полны метана, магма неглубоко. Зато здесь есть всё: уголь, нефть, глина, газ, все руды и уран, алмазы, аметист.",
		"travel": 12, "engine": "nuclear", "surf": -65.0, "under": -35.0, "air": false, "plants": false, "lakes": false,
		"ore": 1.3, "ores": [], "kimberlite": 0.62, "gas": 0.3, "oil": 0.62, "oil_depth": 120, "quakes": 3.0,
		"sky": Color(0.45, 0.6, 0.98)},
}
## Чего на планете нет и что из этого следует (перед полётом).
const ABSENT_NOTES := {
	"coal": "угля — печи и генераторы топить нечем, кроме дров и метана: берите газовые котлы и газовый генератор, дрова везите с собой",
	"oil": "нефти — дизель только привезённый: на ракету обратно его нужно доставить",
	"clay": "глины — кирпича не сделать, стройте из камня и железа (или везите глину)",
}


## Что на планете отсутствует (ключи ресурсов): записанное и чего нет по обследованию недр.
static func absent(id: String) -> Array:
	var out: Array = data(id).get("absent", []).duplicate()
	if id == "earth":
		return out
	var sv: Dictionary = PlanetSurvey.SURVEY.get(id, {})
	for k in ["coal", "oil", "clay"]:
		if not sv.has(k) and not out.has(k):
			out.append(k)
	return out


## Строка для экрана полёта: «Нет: угля — …; нефти — …» (пусто — всё есть).
static func absent_text(id: String) -> String:
	var parts: PackedStringArray = []
	for k in absent(id):
		parts.append(ABSENT_NOTES.get(k, k))
	return "Нет " + "; ".join(parts) + "." if not parts.is_empty() else ""


## Порядок в списке полёта.
const ORDER := ["mercury", "venus", "mars", "jupiter", "saturn", "uranus", "neptune"]
## На сколько метров вглубь холод или жар поверхности сменяется температурой недр.
const SKIN := 6.0


static func data(id: String) -> Dictionary:
	return DATA.get(id, DATA["earth"])


static func planet_name(id: String) -> String:
	return data(id)["name"]


## Двигатель, нужный для полёта: "chem" — химический (на дизеле), "nuclear" — ядерный.
static func engine_name(e: String) -> String:
	return {"chem": "химический", "nuclear": "ядерный"}.get(e, "")
