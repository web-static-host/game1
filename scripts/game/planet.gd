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
##  ore — насколько богаче рудные жилы; ores — свой набор руд [[доля, материал], ...];
##  kimberlite, gas, oil — пороги алмазных трубок, газовых карманов и нефти (меньше — чаще);
##  quakes — множитель землетрясений; sky — оттенок неба.
const DATA := {
	"earth": {"name": "Земля", "desc": "Дом колонии: воздух, леса, озёра, времена года.",
		"travel": 0, "engine": "", "surf": 9.0, "under": 9.0, "air": true, "plants": true, "lakes": true,
		"ore": 1.0, "ores": [], "kimberlite": 0.62, "gas": 0.62, "oil": 0.66, "oil_depth": 200,
		"quakes": 1.0, "sky": Color(1, 1, 1)},
	"mercury": {"name": "Меркурий", "desc": "Горячая поверхность (+60 °C), воздуха нет. Под землёй прохладнее (+24 °C). Много железа и серебра.",
		"travel": 4, "engine": "chem", "surf": 60.0, "under": 24.0, "air": false, "plants": false, "lakes": false,
		"ore": 1.8, "ores": [[0.45, Mat.IRON_ORE], [0.65, Mat.COPPER_ORE], [0.95, Mat.SILVER_ORE], [1.0, Mat.GOLD_ORE]],
		"kimberlite": 0.62, "gas": 0.75, "oil": 0.9, "oil_depth": 200, "quakes": 1.0, "sky": Color(0.75, 0.62, 0.5)},
	"venus": {"name": "Венера", "desc": "Жара (+75 °C у поверхности, около +38 °C в недрах). Нужны вентиляция и стойкие к жаре (красные). Много золота и урана.",
		"travel": 3, "engine": "chem", "surf": 75.0, "under": 38.0, "air": false, "plants": false, "lakes": false,
		"ore": 1.4, "ores": [[0.3, Mat.IRON_ORE], [0.5, Mat.COPPER_ORE], [0.8, Mat.GOLD_ORE], [1.0, Mat.URANIUM_ORE]],
		"kimberlite": 0.62, "gas": 0.62, "oil": 0.9, "oil_depth": 200, "quakes": 1.0, "sky": Color(0.95, 0.72, 0.4)},
	"mars": {"name": "Марс", "desc": "Холодно (−30 °C у поверхности, около −12 °C в недрах), воздуха нет. Нужны очаги (два рядом греют вдвое) и стойкие к холоду (синие). Много железа и меди.",
		"travel": 3, "engine": "chem", "surf": -30.0, "under": -12.0, "air": false, "plants": false, "lakes": false,
		"ore": 1.4, "ores": [[0.6, Mat.IRON_ORE], [0.95, Mat.COPPER_ORE], [1.0, Mat.SILVER_ORE]],
		"kimberlite": 0.62, "gas": 0.7, "oil": 0.9, "oil_depth": 200, "quakes": 0.5, "sky": Color(0.9, 0.55, 0.4)},
	"jupiter": {"name": "Юпитер", "desc": "Ледяная корка (−40 °C) над тёплыми недрами (около +15 °C). Частые землетрясения. Богат ураном.",
		"travel": 6, "engine": "nuclear", "surf": -40.0, "under": 15.0, "air": false, "plants": false, "lakes": false,
		"ore": 1.5, "ores": [[0.3, Mat.IRON_ORE], [0.5, Mat.COPPER_ORE], [0.6, Mat.SILVER_ORE], [0.7, Mat.GOLD_ORE], [1.0, Mat.URANIUM_ORE]],
		"kimberlite": 0.62, "gas": 0.6, "oil": 0.8, "oil_depth": 200, "quakes": 3.0, "sky": Color(0.85, 0.68, 0.5)},
	"saturn": {"name": "Сатурн", "desc": "Холодный (−45 °C у поверхности, около +5 °C в недрах), недра пропитаны нефтью — неглубоко и много.",
		"travel": 8, "engine": "nuclear", "surf": -45.0, "under": 5.0, "air": false, "plants": false, "lakes": false,
		"ore": 1.0, "ores": [], "kimberlite": 0.62, "gas": 0.55, "oil": 0.35, "oil_depth": 40, "quakes": 1.0,
		"sky": Color(0.92, 0.85, 0.6)},
	"uranus": {"name": "Уран", "desc": "Очень холодно (−50 °C у поверхности, около −18 °C в недрах). Алмазные дожди: алмазов в недрах во много раз больше.",
		"travel": 10, "engine": "nuclear", "surf": -50.0, "under": -18.0, "air": false, "plants": false, "lakes": false,
		"ore": 1.0, "ores": [], "kimberlite": 0.15, "gas": 0.62, "oil": 0.9, "oil_depth": 200, "quakes": 1.0,
		"sky": Color(0.6, 0.9, 0.95)},
	"neptune": {"name": "Нептун", "desc": "Самый холодный (−55 °C у поверхности, около −25 °C в недрах). Недра полны метана — энергии хватит, но газ опасен.",
		"travel": 12, "engine": "nuclear", "surf": -55.0, "under": -25.0, "air": false, "plants": false, "lakes": false,
		"ore": 1.0, "ores": [], "kimberlite": 0.62, "gas": 0.3, "oil": 0.9, "oil_depth": 200, "quakes": 1.0,
		"sky": Color(0.45, 0.6, 0.98)},
}
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
