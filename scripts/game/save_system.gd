class_name SaveSystem
extends RefCounted
## Сохранение: seed мира + только изменённые чанки + очередь работ + склад.

const VERSION := 1
const DEFAULT_PATH := "user://save.json"


static func serialize(world: WorldData, dig: DigSystem, camera_cell: Vector2i) -> Dictionary:
	var chunks := {}
	var flags_by_chunk := world.modified_flags()
	for key in flags_by_chunk:
		var raw: PackedByteArray = flags_by_chunk[key]
		chunks["%d,%d" % [key.x, key.y]] = Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE))
	var jobs := []
	for c in dig.order:
		jobs.append([c.x, c.y, dig.progress[c]])
	var discovered := []
	for m in dig.discovered:
		discovered.append(m)
	return {
		"version": VERSION,
		"seed": world.gen.world_seed,
		"saved_at": Time.get_unix_time_from_system(),
		"camera": [camera_cell.x, camera_cell.y],
		"inventory": dig.inventory,
		"cells_dug": dig.cells_dug,
		"discovered": discovered,
		"jobs": jobs,
		"chunks": chunks,
	}


static func save(world: WorldData, dig: DigSystem, camera_cell: Vector2i, path := DEFAULT_PATH) -> bool:
	var data := serialize(world, dig, camera_cell)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Не удалось сохранить игру: %s" % FileAccess.get_open_error())
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	# Атомарная замена: при сбое не останемся с битым сохранением.
	return DirAccess.rename_absolute(tmp, path) == OK


static func load_data(path := DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != VERSION:
		push_warning("Сохранение повреждено или устарело — начинаем новую игру")
		return {}
	return data


## Восстанавливает состояние в уже созданные world (с нужным seed) и dig.
static func apply(data: Dictionary, world: WorldData, dig: DigSystem) -> void:
	var size := ChunkData.SIZE * ChunkData.SIZE
	var chunks: Dictionary = data.get("chunks", {})
	for k in chunks:
		var parts: PackedStringArray = k.split(",")
		var key := Vector2i(int(parts[0]), int(parts[1]))
		var raw := Marshalls.base64_to_raw(chunks[k]).decompress(size, FileAccess.COMPRESSION_DEFLATE)
		if raw.size() == size:
			world.pending_flags[key] = raw
	dig.inventory.clear()
	var inv: Dictionary = data.get("inventory", {})
	for k in inv:
		dig.inventory[k] = int(inv[k])
	dig.cells_dug = int(data.get("cells_dug", 0))
	for m in data.get("discovered", []):
		dig.discovered[int(m)] = true
	for j in data.get("jobs", []):
		var c := Vector2i(int(j[0]), int(j[1]))
		dig.order.append(c)
		dig.progress[c] = float(j[2])
