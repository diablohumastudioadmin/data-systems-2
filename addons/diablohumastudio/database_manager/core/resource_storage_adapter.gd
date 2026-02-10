@tool
class_name ResourceStorageAdapter
extends StorageAdapter

## Godot Resource (.tres) storage implementation
## Stores all data in a single centralized database file: res://data/database.tres

const DATABASE_PATH := "res://data/database.tres"

var _database: GameDatabase
var _is_loaded: bool = false


func _init() -> void:
	_ensure_database_loaded()


## Ensure the database is loaded (lazy loading)
func _ensure_database_loaded() -> void:
	if _is_loaded:
		return

	# Auto-create data directory if it doesn't exist
	var dir_path := DATABASE_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var err := DirAccess.make_dir_recursive_absolute(dir_path)
		if err != OK:
			push_error("[ResourceStorageAdapter] Failed to create data directory: %s" % dir_path)

	# Load existing database or create new one
	if ResourceLoader.exists(DATABASE_PATH):
		_database = ResourceLoader.load(DATABASE_PATH)
		if _database == null or not _database is GameDatabase:
			push_error("[ResourceStorageAdapter] Failed to load database, creating new one")
			_database = GameDatabase.new()
	else:
		print("[ResourceStorageAdapter] Creating new database at: %s" % DATABASE_PATH)
		_database = GameDatabase.new()
		_save_database()

	_is_loaded = true


## Save the entire database to disk
func _save_database() -> Error:
	var err := ResourceSaver.save(_database, DATABASE_PATH)
	if err != OK:
		push_error("[ResourceStorageAdapter] Failed to save database (Error: %d)" % err)
	return err


## Load all instances for a data type
func load_instances(type_name: String) -> Array[DataItem]:
	_ensure_database_loaded()
	return _database.get_instances(type_name)


## Save all instances for a data type
func save_instances(type_name: String, instances: Array[DataItem]) -> Error:
	_ensure_database_loaded()
	_database.set_instances(type_name, instances)
	return _save_database()


## Check if data file exists for type
func has_data(type_name: String) -> bool:
	_ensure_database_loaded()
	return _database.has_instances(type_name)


## Delete data file for type
func delete_data(type_name: String) -> Error:
	_ensure_database_loaded()
	_database.set_instances(type_name, [])
	return _save_database()


## Get file path (for debugging)
func get_data_path(type_name: String) -> String:
	return DATABASE_PATH


## Get the centralized database (for DataTypeRegistry to access schemas)
func get_database() -> GameDatabase:
	_ensure_database_loaded()
	return _database


## Load schema from database
func load_schema(type_name: String) -> Dictionary:
	_ensure_database_loaded()
	return _database.get_schema(type_name)


## Save schema to database
func save_schema(type_name: String, schema_data: Dictionary) -> Error:
	_ensure_database_loaded()
	_database.set_schema(type_name, schema_data)
	return _save_database()


## Get all schema names
func get_all_schema_names() -> Array[String]:
	_ensure_database_loaded()
	return _database.get_schema_names()


## Remove schema from database
func remove_schema(type_name: String) -> Error:
	_ensure_database_loaded()
	_database.remove_schema(type_name)
	return _save_database()


## Check if schema exists
func has_schema(type_name: String) -> bool:
	_ensure_database_loaded()
	return _database.has_schema(type_name)


## Reload database from disk (useful for testing/debugging)
func reload() -> void:
	_is_loaded = false
	_ensure_database_loaded()
