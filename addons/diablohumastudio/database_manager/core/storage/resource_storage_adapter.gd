@tool
class_name ResourceStorageAdapter
extends StorageAdapter

## Godot Resource (.tres) storage implementation.


func load_database(path: String) -> Database:
	var dir_path := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	if ResourceLoader.exists(path):
		var db = ResourceLoader.load(path)
		if db == null or not db is Database:
			push_error("[ResourceStorageAdapter] Failed to load database at: %s" % path)
			return Database.new()
		return db
	else:
		print("[ResourceStorageAdapter] Creating new database at: %s" % path)
		var db := Database.new()
		ResourceSaver.save(db, path)
		return db


func save_database(database: Database, path: String) -> Error:
	var dir_path := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var err := ResourceSaver.save(database, path)
	if err != OK:
		push_error("[ResourceStorageAdapter] Failed to save database (Error: %d)" % err)
	return err
