extends SceneTree
## Долгая игра ботом-«вовлечённым игроком» (tests/bot_player.gd): на Земле, а если бот
## соберёт ракету и долетит — и на планетах (миры идут одновременно). Пишет вехи, срезы
## каждые 10 минут и «пустые» отрезки, итог по каждому миру.
##   godot --headless --path . -s res://tests/longplay.gd -- <seed> <минут>

const BotPlayer := preload("res://tests/bot_player.gd")

var universe := Universe.new()
## Планета -> бот этой колонии.
var bots := {}
var t := 0.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_value := int(args[0]) if args.size() > 0 else 4242
	var minutes := int(args[1]) if args.size() > 1 else 240
	var world := WorldData.new(WorldGen.new(seed_value))
	var colony := Colony.new(world)
	colony.start_new(0)
	universe.base_seed = seed_value
	universe.add_world("earth", world, colony)
	universe.arrived.connect(_on_arrived)
	bots["earth"] = BotPlayer.new(colony)
	# Куда бот отправит ракету (TARGET=mars и т. п.).
	var target := OS.get_environment("TARGET")
	bots["earth"].target_planet = target if not target.is_empty() else "mars"
	bots["earth"].on_launch = func(f: Dictionary) -> void:
		universe.send(f)
		print("%s: ракета улетела на %s" % [bots["earth"]._time(), Planet.planet_name(f["planet"])])
	var next_slice := 600.0
	var think := 0.0
	print("=== Мир %d, %d минут игры ===" % [seed_value, minutes])
	while t < minutes * 60.0:
		for e in universe.worlds:
			(e["colony"] as Colony).update(0.5)
		universe.update(0.5)
		t += 0.5
		think += 0.5
		for b in bots.values():
			b.t = t
		if think >= 5.0:
			think = 0.0
			for b in bots.values():
				b.think()
				if b.planet == "earth":
					var dbg := OS.get_environment("DEBUG_FROM")
					if not dbg.is_empty() and t >= float(dbg) * 60.0 and int(t) % 20 == 0:
						b._debug()
			# Вымершие колонии на планетах убираются, как в игре.
			for gone in universe.prune_dead():
				print("%s: колония на планете %s погибла" % [bots["earth"]._time(), Planet.planet_name(gone)])
		if t >= next_slice:
			next_slice += 600.0
			for b in bots.values():
				b._slice()
	for b in bots.values():
		b.report()
	print("\nПолётов в пути: %d" % universe.flights.size())
	quit()


func _on_arrived(planet: String, colony: Colony, new_world: bool) -> void:
	print("%s: ракета села на %s (%s)" % [bots["earth"]._time(), Planet.planet_name(planet), "новая колония" if new_world else "к колонии"])
	if new_world:
		var b = BotPlayer.new(colony)
		b.t = t
		bots[planet] = b
