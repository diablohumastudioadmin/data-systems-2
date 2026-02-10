class_name JSONPersistence
extends RefCounted

## Utility class for saving and loading JSON files
## Handles error checking and directory creation

## Save data to JSON file
static func save_json(file_path: String, data: Variant) -> Error:
	# Ensure directory exists
	var dir_path = file_path.get_base_dir()
	if !DirAccess.dir_exists_absolute(dir_path):
		var error = DirAccess.make_dir_recursive_absolute(dir_path)
		if error != OK:
			push_error("Failed to create directory: %s (Error: %d)" % [dir_path, error])
			return error

	# Convert to JSON string
	var json_string = JSON.stringify(data, "\t")  # Pretty print with tabs

	# Write to file
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		var error = FileAccess.get_open_error()
		push_error("Failed to open file for writing: %s (Error: %d)" % [file_path, error])
		return error

	file.store_string(json_string)
	file.close()

	return OK


## Load data from JSON file
static func load_json(file_path: String) -> Variant:
	# Check if file exists
	if !FileAccess.file_exists(file_path):
		push_warning("JSON file does not exist: %s" % file_path)
		return null

	# Read file
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		var error = FileAccess.get_open_error()
		push_error("Failed to open file for reading: %s (Error: %d)" % [file_path, error])
		return null

	var json_string = file.get_as_text()
	file.close()

	# Parse JSON
	var json = JSON.new()
	var parse_error = json.parse(json_string)

	if parse_error != OK:
		push_error("Failed to parse JSON: %s (Line: %d)" % [file_path, json.get_error_line()])
		return null

	return json.get_data()


## Check if JSON file exists
static func file_exists(file_path: String) -> bool:
	return FileAccess.file_exists(file_path)


## Delete JSON file
static func delete_file(file_path: String) -> Error:
	if !FileAccess.file_exists(file_path):
		return ERR_FILE_NOT_FOUND

	var dir = DirAccess.open(file_path.get_base_dir())
	if dir == null:
		return DirAccess.get_open_error()

	return dir.remove(file_path.get_file())


## Get user data directory path
static func get_user_data_path(subpath: String = "") -> String:
	var base_path = "user://data_systems"
	if subpath.is_empty():
		return base_path
	return base_path.path_join(subpath)


## Get master data directory path
static func get_master_data_path(subpath: String = "") -> String:
	var base_path = "res://data"
	if subpath.is_empty():
		return base_path
	return base_path.path_join(subpath)


## Create backup of a file
static func create_backup(file_path: String) -> Error:
	if !FileAccess.file_exists(file_path):
		return ERR_FILE_NOT_FOUND

	var backup_path = file_path + ".backup"
	var dir = DirAccess.open(file_path.get_base_dir())
	if dir == null:
		return DirAccess.get_open_error()

	return dir.copy(file_path.get_file(), backup_path.get_file())


## Restore from backup
static func restore_backup(file_path: String) -> Error:
	var backup_path = file_path + ".backup"
	if !FileAccess.file_exists(backup_path):
		return ERR_FILE_NOT_FOUND

	var dir = DirAccess.open(file_path.get_base_dir())
	if dir == null:
		return DirAccess.get_open_error()

	# Delete original if it exists
	if FileAccess.file_exists(file_path):
		dir.remove(file_path.get_file())

	return dir.copy(backup_path.get_file(), file_path.get_file())


## List all JSON files in a directory
static func list_json_files(dir_path: String) -> Array[String]:
	var files: Array[String] = []

	if !DirAccess.dir_exists_absolute(dir_path):
		return files

	var dir = DirAccess.open(dir_path)
	if dir == null:
		return files

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if !dir.current_is_dir() and file_name.ends_with(".json"):
			files.append(file_name)
		file_name = dir.get_next()

	dir.list_dir_end()
	return files


## Ensure directory exists
static func ensure_directory(dir_path: String) -> Error:
	if DirAccess.dir_exists_absolute(dir_path):
		return OK

	return DirAccess.make_dir_recursive_absolute(dir_path)
