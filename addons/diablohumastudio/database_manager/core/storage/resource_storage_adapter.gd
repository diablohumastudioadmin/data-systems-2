@tool
class_name ResourceStorageAdapter
extends StorageAdapter

## Godot Resource (.tres) storage implementation.
## Stores the entire database in a single file: res://data/res/database.tres

const DATABASE_PATH := "res://data/res/database.tres"

var _database: Database
var _is_loaded: bool = false


func _init() -> void:
	_ensure_loaded()


func _ensure_loaded() -> void:
	if _is_loaded:
		return

	var dir_path := DATABASE_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	if ResourceLoader.exists(DATABASE_PATH):
		_database = ResourceLoader.load(DATABASE_PATH)
		if _database == null or not _database is Database:
			push_error("[ResourceStorageAdapter] Failed to load database, creating new one")
			_database = Database.new()
	else:
		print("[ResourceStorageAdapter] Creating new database at: %s" % DATABASE_PATH)
		_database = Database.new()
		ResourceSaver.save(_database, DATABASE_PATH)

	_is_loaded = true


func load_database() -> Database:
	_ensure_loaded()
	return _database


func save_database(database: Database) -> Error:
	_database = database
	var err := ResourceSaver.save(_database, DATABASE_PATH)
	if err != OK:
		push_error("[ResourceStorageAdapter] Failed to save database (Error: %d)" % err)
	return err


func reload() -> void:
	_is_loaded = false
	_ensure_loaded()
