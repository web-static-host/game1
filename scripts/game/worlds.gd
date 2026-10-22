class_name Worlds
extends RefCounted
## Миры — отдельные игры (не путать с планетами внутри одной игры). У каждого мира свои
## сохранения: автосохранение (одно, перезаписывается) и сохранения игрока.
##   user://worlds/<id>/world.json        — имя, зерно мира, бедствия, когда играли
##   user://worlds/<id>/saves/<sid>.json  — само сохранение (SaveSystem)
##   user://worlds/<id>/saves/<sid>.meta.json — подпись для списка: имя, время, итоги

const ROOT := "user://worlds"
const AUTO := "auto"

## Что запустить, когда откроется сцена игры: {"world": id, "save": sid или "" — новый мир,
## "offline": засчитать время отсутствия}. Пусто — старый режим одного файла (инструменты).
static var launch := {}


## Все миры, последние сыгранные — первыми.
static func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(ROOT)
	if dir == null:
		return out
	for wid in dir.get_directories():
		var m := meta(wid)
		if not m.is_empty():
			out.append(m)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("played", 0)) > float(b.get("played", 0)))
	return out


static func meta(wid: String) -> Dictionary:
	var d := _read_json(_dir(wid) + "/world.json")
	if d.is_empty():
		return {}
	d["id"] = wid
	return d


## Новый мир: имя, бедствия, своё зерно. Возвращает id.
static func create(name: String, disasters: bool, seed_value := -1) -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var wid := "w%d_%d" % [int(Time.get_unix_time_from_system()), rng.randi() % 100000]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir(wid) + "/saves"))
	var now := Time.get_unix_time_from_system()
	_write_json(_dir(wid) + "/world.json", {
		"name": name.strip_edges() if not name.strip_edges().is_empty() else default_name(),
		"seed": seed_value if seed_value >= 0 else rng.randi() & 0x7FFFFFFF,
		"disasters": disasters,
		"created": now,
		"played": now,
	})
	return wid


## «Мир 3» — первое свободное имя.
static func default_name() -> String:
	var used := {}
	for m in list():
		used[m.get("name", "")] = true
	var i := 1
	while used.has("Мир %d" % i):
		i += 1
	return "Мир %d" % i


static func rename(wid: String, name: String) -> void:
	var m := meta(wid)
	if m.is_empty() or name.strip_edges().is_empty():
		return
	m.erase("id")
	m["name"] = name.strip_edges()
	_write_json(_dir(wid) + "/world.json", m)


## Отметить, что в мир играли (он поднимется в списке).
static func touch(wid: String) -> void:
	var m := meta(wid)
	if m.is_empty():
		return
	m.erase("id")
	m["played"] = Time.get_unix_time_from_system()
	_write_json(_dir(wid) + "/world.json", m)


static func delete(wid: String) -> void:
	_remove_tree(ProjectSettings.globalize_path(_dir(wid)))


## Сохранения мира, новые — первыми.
static func saves(wid: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(_dir(wid) + "/saves")
	if dir == null:
		return out
	for f in dir.get_files():
		if not f.ends_with(".meta.json"):
			continue
		var sid := f.trim_suffix(".meta.json")
		if not FileAccess.file_exists(save_path(wid, sid)):
			continue
		var m := _read_json(_dir(wid) + "/saves/" + f)
		m["id"] = sid
		out.append(m)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("saved_at", 0)) > float(b.get("saved_at", 0)))
	return out


## Самое свежее сохранение во всех мирах (для «Продолжить»): {"world", "save", ...} или {}.
static func latest() -> Dictionary:
	var best := {}
	for m in list():
		var s := saves(m["id"])
		if not s.is_empty() and (best.is_empty() or float(s[0].get("saved_at", 0)) > float(best.get("saved_at", 0))):
			best = s[0].duplicate()
			best["world"] = m["id"]
			best["world_name"] = m.get("name", "")
	return best


static func save_path(wid: String, sid: String) -> String:
	return _dir(wid) + "/saves/" + sid + ".json"


## Записать сохранение sid (AUTO — автосохранение) с подписью info для списка.
static func write_save(wid: String, sid: String, data: Dictionary, info: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir(wid) + "/saves"))
	if not SaveSystem.write(data, save_path(wid, sid)):
		return false
	var m := info.duplicate()
	m["saved_at"] = Time.get_unix_time_from_system()
	_write_json(_dir(wid) + "/saves/" + sid + ".meta.json", m)
	touch(wid)
	return true


## Новое сохранение игрока: id и имя «Сохранение N».
static func new_save_id(wid: String) -> Array:
	var n := 1
	for s in saves(wid):
		if s["id"] != AUTO:
			n += 1
	return ["s%d" % int(Time.get_unix_time_from_system() * 1000.0), "Сохранение %d" % n]


static func load_save(wid: String, sid: String) -> Dictionary:
	return SaveSystem.load_data(save_path(wid, sid))


static func delete_save(wid: String, sid: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path(wid, sid)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_dir(wid) + "/saves/" + sid + ".meta.json"))


## Старое единственное сохранение (до миров) — становится миром «Мой мир».
static func migrate_legacy() -> void:
	if not FileAccess.file_exists(SaveSystem.DEFAULT_PATH):
		return
	var data := SaveSystem.load_data()
	if data.is_empty():
		return
	var colony: Dictionary = data.get("colony", {})
	var wid := create("Мой мир", bool(colony.get("disasters", true)), int(data.get("seed", 0)))
	var units: Array = colony.get("units", [])
	if write_save(wid, AUTO, data, {"name": "Автосохранение", "units": units.size()}):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveSystem.DEFAULT_PATH))


## Подпись времени: «сегодня 14:05», «вчера 09:30», «21.10 18:00».
static func when(unix: float) -> String:
	if unix <= 0.0:
		return ""
	var t := Time.get_datetime_dict_from_unix_time(int(unix + Time.get_time_zone_from_system()["bias"] * 60))
	var now := Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system() + Time.get_time_zone_from_system()["bias"] * 60))
	var hm := "%02d:%02d" % [t["hour"], t["minute"]]
	if t["year"] == now["year"] and t["month"] == now["month"] and t["day"] == now["day"]:
		return "сегодня " + hm
	var yesterday := Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system() + Time.get_time_zone_from_system()["bias"] * 60) - 86400)
	if t["year"] == yesterday["year"] and t["month"] == yesterday["month"] and t["day"] == yesterday["day"]:
		return "вчера " + hm
	return "%02d.%02d.%d %s" % [t["day"], t["month"], t["year"], hm]


static func _dir(wid: String) -> String:
	return ROOT + "/" + wid


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if typeof(d) == TYPE_DICTIONARY else {}


static func _write_json(path: String, d: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))


static func _remove_tree(abs_path: String) -> void:
	var dir := DirAccess.open(abs_path)
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)
	for d in dir.get_directories():
		_remove_tree(abs_path + "/" + d)
	DirAccess.remove_absolute(abs_path)
