class_name Settings
extends RefCounted
## Настройки игры (не мира): автосохранение, игра в фоне, 3D-модель гавриков.
## Хранятся в user://settings.json и переживают любые миры.

const PATH := "user://settings.json"
## Значения по умолчанию.
const DEFAULTS := {
	"autosave_min": 2,
	"save_on_exit": true,
	"background": false,
	"models": true,
}
## Как часто можно автосохранять, минут (0 — выключено).
const AUTOSAVE_CHOICES := [0, 1, 2, 5, 10]


static func get_value(key: String) -> Variant:
	return _load().get(key, DEFAULTS.get(key))


static func set_value(key: String, value: Variant) -> void:
	var d := _load()
	d[key] = value
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))


static func _load() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return d if typeof(d) == TYPE_DICTIONARY else {}
