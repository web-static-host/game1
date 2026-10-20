extends SceneTree
## Высадка на планету: экспедиция из 10 жителей с грузом прилетает, бот (tests/bot_player.gd)
## ведёт колонию. Проверка, можно ли там обосноваться.
##   godot --headless --path . -s res://tests/planet_trial.gd -- <планета> <seed> <минут>

const BotPlayer := preload("res://tests/bot_player.gd")

## Что обычно изучено к запуску ракеты: вся цепочка до ракетостроения и кое-что рядом.
const RESEARCH := ["agronomy", "carts", "bricks", "geology", "geology2", "electricity", "carpentry", "medicine",
	"metallurgy", "hydroponics", "education", "drilling", "steam", "drill_rig", "oil_drilling", "refining",
	"combustion", "automation", "rocketry", "gas_masks", "maintenance", "shelving"]
## Груз (до 200): дерево, еда и сталь на крепь; на холодную — больше еды и кирпич на печи (жгут местный уголь), на жаркую — железо и медь.
const CARGO := {
	"mars": {"wood": 70, "food": 80, "brick": 24, "metal": 26},
	"venus": {"wood": 90, "food": 60, "metal": 30, "iron": 10, "copper": 10},
	"mercury": {"wood": 90, "food": 60, "metal": 30, "iron": 10, "copper": 10},
	"jupiter": {"wood": 70, "food": 80, "brick": 24, "metal": 26},
	"saturn": {"wood": 70, "food": 80, "brick": 24, "metal": 26},
	"uranus": {"wood": 70, "food": 80, "brick": 24, "metal": 26},
	"neptune": {"wood": 70, "food": 80, "brick": 24, "metal": 26},
}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var planet := args[0] if args.size() > 0 else "mars"
	var seed_value := int(args[1]) if args.size() > 1 else 7
	var minutes := int(args[2]) if args.size() > 2 else 120
	# Экипаж: 5 пар; на холодную планету — синие (стойкие к холоду), на жаркую — красные.
	var earth := Colony.new(WorldData.new(WorldGen.new(seed_value)))
	earth.rng.seed = seed_value
	var temp: float = Planet.data(planet)["under"]
	var hue := 0.62 if temp < 5.0 else (0.0 if temp > 35.0 else -1.0)
	var crew := []
	var units: Array[Unit] = []
	for i in 10:
		var g := Genetics.founder(earth.rng)
		g["female"] = i % 2 == 1
		if hue >= 0.0:
			g["color"] = [Color.from_hsv(hue, 1.0, 1.0), Color.from_hsv(hue, 1.0, 1.0)]
		var u := earth._new_unit(Unit.Sex.FEMALE if i % 2 == 1 else Unit.Sex.MALE, Vector2.ZERO, g)
		u.id = i + 1
		u.age = Unit.CHILD_TIME + earth.rng.randf_range(0.1, 0.6) * Colony.YEAR
		for k in u.skills:
			u.skills[k] = earth.rng.randf_range(50.0, 300.0)
		units.append(u)
	for i in range(0, 10, 2):
		units[i].partner_id = units[i + 1].id
		units[i + 1].partner_id = units[i].id
	for u in units:
		crew.append(u.to_dict())
	var flight := {"planet": planet, "crew": crew, "cargo": CARGO.get(planet, CARGO["mars"]), "research": RESEARCH, "left": 0.0}
	var world := WorldData.new(WorldGen.new(seed_value * 7919 + planet.hash(), WorldGen.LATEST, planet))
	var colony := Colony.new(world)
	colony.start_planet(0, flight)
	var bot = BotPlayer.new(colony)
	print("=== %s, мир %d, %d минут; экипаж %s, груз %s ===" % [Planet.planet_name(planet), seed_value, minutes,
		"синие" if hue == 0.62 else ("красные" if hue == 0.0 else "разные"), flight["cargo"]])
	var t := 0.0
	var think := 0.0
	var next_slice := 600.0
	while t < minutes * 60.0 and not colony.units.is_empty():
		colony.update(0.5)
		t += 0.5
		think += 0.5
		bot.t = t
		if think >= 5.0:
			think = 0.0
			bot.think()
			var dbg := OS.get_environment("DEBUG_FROM")
			if not dbg.is_empty() and t >= float(dbg) * 60.0 and int(t) % 60 == 0:
				bot._debug()
		if t >= next_slice:
			next_slice += 600.0
			bot._slice()
	if colony.units.is_empty():
		print("\nКОЛОНИЯ ПОГИБЛА на %d мин" % int(t / 60.0))
	bot.report()
	quit()
