class_name Universe
extends RefCounted
## Все миры игры: Земля и колонии на других планетах, плюс ракеты в полёте.
## Время идёт во всех мирах одновременно; переключается только то, что на экране.

## Ракета долетела: колония на планете (новая или та же).
signal arrived(planet: String, colony: Colony, new_world: bool)

## [{"planet": id, "world": WorldData, "colony": Colony}] — Земля всегда первая.
var worlds: Array = []
## Полёты: {"planet", "crew": [гаврики], "cargo": {ресурс: n}, "research": [...], "left": сек}.
var flights: Array = []
## Семя Земли — от него семена других планет.
var base_seed := 0


func add_world(planet: String, world: WorldData, colony: Colony) -> Dictionary:
	var e := {"planet": planet, "world": world, "colony": colony}
	worlds.append(e)
	return e


func entry(planet: String) -> Dictionary:
	for e in worlds:
		if e["planet"] == planet:
			return e
	return {}


## Семя мира планеты: своё, но всегда одно и то же для этой игры.
func seed_for(planet: String) -> int:
	return (base_seed * 1103515245 + planet.hash()) & 0x7FFFFFFF


func send(flight: Dictionary) -> void:
	flights.append(flight)


## Время идёт: ракеты летят и садятся.
func update(dt: float) -> void:
	for f in flights.duplicate():
		f["left"] = float(f["left"]) - dt
		if f["left"] <= 0.0:
			flights.erase(f)
			_arrive(f)


func _arrive(f: Dictionary) -> void:
	var planet: String = f["planet"]
	var e := entry(planet)
	if e.is_empty():
		var world := WorldData.new(WorldGen.new(seed_for(planet), WorldGen.LATEST, planet))
		var colony := Colony.new(world)
		colony.start_planet(0, f)
		add_world(planet, world, colony)
		arrived.emit(planet, colony, true)
	else:
		(e["colony"] as Colony).receive_flight(f)
		arrived.emit(planet, e["colony"], false)


## Колонии на планетах, где не осталось ни одного гаврика (и туда никто не летит), убираем.
func prune_dead() -> Array[String]:
	var gone: Array[String] = []
	for e in worlds.duplicate():
		if e["planet"] == "earth" or not (e["colony"] as Colony).units.is_empty():
			continue
		var coming := false
		for f in flights:
			if f["planet"] == e["planet"]:
				coming = true
		if not coming:
			worlds.erase(e)
			gone.append(e["planet"])
	return gone


## Сохранение миров кроме Земли (она — в основной части сохранения) и полётов.
func to_dict(cameras: Dictionary) -> Dictionary:
	var ws := []
	for e in worlds:
		if e["planet"] == "earth":
			continue
		var d := SaveSystem.serialize(e["world"], e["colony"], cameras.get(e["planet"], Vector2i.ZERO))
		d["planet"] = e["planet"]
		ws.append(d)
	return {"worlds": ws, "flights": flights.duplicate(true)}


func load_dict(d: Dictionary) -> void:
	for wd in d.get("worlds", []):
		var planet := str(wd.get("planet", "mars"))
		var world := WorldData.new(WorldGen.new(int(wd["seed"]), int(wd.get("gen", WorldGen.LATEST)), planet))
		var colony := Colony.new(world)
		SaveSystem.apply(wd, world, colony)
		add_world(planet, world, colony)
	for f in d.get("flights", []):
		# Стали больше нет: в грузе старых полётов она — железо.
		# Ракеты летят мгновенно: летевшие в старом сохранении садятся сразу.
		var fl: Dictionary = Colony.steel_to_iron(f)
		fl["left"] = 0.0
		flights.append(fl)
