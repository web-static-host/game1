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
	"mercury": {"geo": {"relief": "craters", "regolith": [Mat.GRAVEL, Mat.BASALT], "sed": 0.15, "basalt": 120, "magma": 2500, "ores": "blobs", "caves": 0.5, "tubes": false, "ice": 0, "palette": Color(0.78, 0.74, 0.72), "leaf": Color(0, 0, 0, 0)}, "atm": "vacuum", "name": "Меркурий", "desc": "Горячая поверхность (+60 °C), воздуха нет. Под землёй прохладнее (+24 °C). Много железа и серебра. Редкий аметист — для ядерной ракеты. Изрыт кратерами; руда — крупными гнёздами у самой поверхности.",
		"travel": 4, "engine": "chem", "surf": 60.0, "under": 24.0, "air": false, "plants": false, "lakes": false,
		"ore": 1.8, "ores": [[0.45, Mat.IRON_ORE], [0.65, Mat.COPPER_ORE], [0.95, Mat.SILVER_ORE], [1.0, Mat.GOLD_ORE]],
		"amethyst": 0.04, "kimberlite": 0.62, "gas": 0.75, "oil": 0.9, "oil_depth": 200, "quakes": 1.0, "sky": Color(0.75, 0.62, 0.5)},
	"venus": {"trees": 0.18, "geo": {"relief": "volcanic", "regolith": [Mat.GRAVEL, Mat.BASALT], "sed": 0.35, "basalt": 50, "magma": 300, "ores": "deep", "caves": 1.3, "tubes": true, "ice": 0, "palette": Color(1.18, 0.92, 0.55), "leaf": Color(0.95, 0.42, 0.12)}, "atm": "gas", "name": "Венера", "desc": "Жара (+75 °C у поверхности, около +38 °C в недрах). Нужны вентиляция и стойкие к жаре (красные). Много золота и урана. Редкий аметист — для ядерной ракеты. Ядовитый газ: наружу — только где дегазация очистила воздух, там растут свои деревья. Вулканы: базальт и магма неглубоко, лавовые трубки; руда бедна у поверхности, богата глубже 250 м.",
		"travel": 3, "engine": "chem", "surf": 75.0, "under": 38.0, "air": false, "plants": false, "lakes": false,
		"ore": 1.4, "ores": [[0.3, Mat.IRON_ORE], [0.5, Mat.COPPER_ORE], [0.8, Mat.GOLD_ORE], [1.0, Mat.URANIUM_ORE]],
		"amethyst": 0.04, "kimberlite": 0.62, "gas": 0.62, "oil": 0.9, "oil_depth": 200, "quakes": 1.0, "sky": Color(0.95, 0.72, 0.4)},
	"mars": {"geo": {"relief": "mesas", "regolith": [Mat.SAND, Mat.GRAVEL], "sed": 1.6, "basalt": 900, "magma": 3000, "ores": "layers", "caves": 1.5, "tubes": true, "ice": 0, "palette": Color(1.32, 0.72, 0.52), "leaf": Color(0, 0, 0, 0)}, "atm": "vacuum", "name": "Марс", "desc": "Холодно (−30 °C у поверхности, около −12 °C в недрах), воздуха нет. Нужны очаги (два рядом греют вдвое) и стойкие к холоду (синие). Много железа и меди. Редкий аметист — для ядерной ракеты. Столовые горы и толстые слои пород; руда — тонкими пластами, лавовые трубки.",
		"travel": 3, "engine": "chem", "surf": -30.0, "under": -12.0, "air": false, "plants": false, "lakes": false,
		"ore": 1.4, "ores": [[0.6, Mat.IRON_ORE], [0.95, Mat.COPPER_ORE], [1.0, Mat.SILVER_ORE]],
		"amethyst": 0.04, "kimberlite": 0.62, "gas": 0.7, "oil": 0.9, "oil_depth": 200, "quakes": 0.5, "sky": Color(0.9, 0.55, 0.4)},
	"jupiter": {"geo": {"relief": "ice", "regolith": [Mat.ICE, Mat.ICE], "sed": 1.0, "basalt": 2500, "magma": 1200, "ores": "pockets", "caves": 0.8, "tubes": false, "ice": 45, "palette": Color(1.15, 0.92, 0.72), "leaf": Color(0, 0, 0, 0)}, "atm": "gas", "name": "Юпитер", "desc": "Ледяная корка (−40 °C) над тёплыми недрами (около +15 °C). Частые землетрясения. Богат ураном. Ледяная кора ~45 м; руда — редкими богатыми гнёздами. Ядовитый газ: наружу — где дегазация очистила воздух.",
		"travel": 6, "engine": "nuclear", "surf": -40.0, "under": 15.0, "air": false, "plants": false, "lakes": false,
		"ore": 1.5, "ores": [[0.3, Mat.IRON_ORE], [0.5, Mat.COPPER_ORE], [0.6, Mat.SILVER_ORE], [0.7, Mat.GOLD_ORE], [1.0, Mat.URANIUM_ORE]],
		"kimberlite": 0.62, "gas": 0.6, "oil": 0.8, "oil_depth": 200, "quakes": 3.0, "sky": Color(0.85, 0.68, 0.5)},
	"saturn": {"geo": {"relief": "ice", "regolith": [Mat.ICE, Mat.ICE], "sed": 1.4, "basalt": 4000, "magma": 2000, "ores": "veins", "caves": 1.0, "tubes": false, "ice": 25, "palette": Color(1.12, 1.02, 0.74), "leaf": Color(0, 0, 0, 0)}, "atm": "gas", "name": "Сатурн", "desc": "Холодный (−45 °C у поверхности, около +5 °C в недрах), недра пропитаны нефтью — неглубоко и много. Ледяная кора ~25 м, ядовитый газ над ней.",
		"travel": 8, "engine": "nuclear", "surf": -45.0, "under": 5.0, "air": false, "plants": false, "lakes": false,
		"ore": 1.0, "ores": [], "kimberlite": 0.62, "gas": 0.55, "oil": 0.35, "oil_depth": 40, "quakes": 1.0,
		"sky": Color(0.92, 0.85, 0.6)},
	"uranus": {"geo": {"relief": "ice", "regolith": [Mat.ICE, Mat.ICE], "sed": 0.6, "basalt": 3000, "magma": 2500, "ores": "pockets", "caves": 0.7, "tubes": false, "ice": 80, "palette": Color(0.76, 1.04, 1.1), "leaf": Color(0, 0, 0, 0)}, "atm": "gas", "name": "Уран", "desc": "Очень холодно (−50 °C у поверхности, около −18 °C в недрах). Алмазные дожди: алмазов в недрах во много раз больше. Толстая ледяная кора ~80 м; руда — редкими гнёздами; ядовитый газ.",
		"travel": 10, "engine": "nuclear", "surf": -50.0, "under": -18.0, "air": false, "plants": false, "lakes": false,
		"ore": 1.0, "ores": [], "kimberlite": 0.15, "gas": 0.62, "oil": 0.9, "oil_depth": 200, "quakes": 1.0,
		"sky": Color(0.6, 0.9, 0.95)},
	"neptune": {"geo": {"relief": "ice", "regolith": [Mat.ICE, Mat.ICE], "sed": 1.2, "basalt": 3500, "magma": 2500, "ores": "veins", "caves": 1.0, "tubes": false, "ice": 40, "palette": Color(0.62, 0.76, 1.22), "leaf": Color(0, 0, 0, 0)}, "atm": "gas", "name": "Нептун", "desc": "Самый холодный (−55 °C у поверхности, около −25 °C в недрах). Недра полны метана — энергии хватит, но газ опасен. Ледяная кора ~40 м, ядовитый газ над ней.",
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
