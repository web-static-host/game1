class_name SaveSystem
extends RefCounted
## Сохранение: seed мира + изменённые чанки + колония (жители, стройки, склад).

const VERSION := 2
const DEFAULT_PATH := "user://save.json"


static func serialize(world: WorldData, colony: Colony, camera_cell: Vector2i) -> Dictionary:
	var chunks := {}
	var flags_by_chunk := world.modified_flags()
	for key in flags_by_chunk:
		var raw: PackedByteArray = flags_by_chunk[key]
		chunks["%d,%d" % [key.x, key.y]] = Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE))
	var mats := {}
	var mats_by_chunk := world.modified_mats()
	for key in mats_by_chunk:
		var raw: PackedByteArray = mats_by_chunk[key]
		mats["%d,%d" % [key.x, key.y]] = Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE))
	return {
		"version": VERSION,
		"mats": mats,
		"seed": world.gen.world_seed,
		"saved_at": Time.get_unix_time_from_system(),
		"camera": [camera_cell.x, camera_cell.y],
		"chunks": chunks,
		"removed_features": world.removed_features.keys(),
		"feature_marks": world.feature_marks.keys(),
		"colony": colony.to_dict(),
	}


static func save(world: WorldData, colony: Colony, camera_cell: Vector2i, path := DEFAULT_PATH) -> bool:
	var data := serialize(world, colony, camera_cell)
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
		push_warning("Сохранение повреждено или от старой версии — начинаем новую игру")
		return {}
	return data


## Восстанавливает состояние в уже созданные world (с нужным seed) и colony.
static func apply(data: Dictionary, world: WorldData, colony: Colony) -> void:
	var size := ChunkData.SIZE * ChunkData.SIZE
	var chunks: Dictionary = data.get("chunks", {})
	for k in chunks:
		var parts: PackedStringArray = k.split(",")
		var key := Vector2i(int(parts[0]), int(parts[1]))
		var raw := Marshalls.base64_to_raw(chunks[k]).decompress(size, FileAccess.COMPRESSION_DEFLATE)
		if raw.size() == size:
			world.pending_flags[key] = raw
	var mats: Dictionary = data.get("mats", {})
	for k in mats:
		var parts: PackedStringArray = k.split(",")
		var key := Vector2i(int(parts[0]), int(parts[1]))
		var raw := Marshalls.base64_to_raw(mats[k]).decompress(size, FileAccess.COMPRESSION_DEFLATE)
		if raw.size() == size:
			world.pending_mats[key] = raw
	for x in data.get("removed_features", []):
		world.removed_features[int(x)] = true
	for x in data.get("feature_marks", []):
		world.feature_marks[int(x)] = true
	colony.load_dict(data.get("colony", {}))
