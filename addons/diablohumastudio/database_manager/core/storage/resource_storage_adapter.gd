@tool
class_name ResourceStorageAdapter
extends StorageAdapter

## Per-instance Godot Resource (.tres) storage implementation.
## Each DataItem is saved as an individual file in instances/<table_name>/.


func save_instance(item: DataItem, table_name: String, base_path: String) -> Error:
	var dir_path := _instances_dir(table_name, base_path)
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var desired_name := _sanitize_filename(item.name)
	var desired_path := dir_path.path_join("%s.tres" % desired_name)
	var old_path := item.resource_path

	var file_path: String
	if old_path.is_empty():
		# New item — derive filename from name
		file_path = desired_path
		# Handle filename collision: append _<id> if another item occupies this path
		if ResourceLoader.exists(file_path):
			file_path = dir_path.path_join("%s_%d.tres" % [desired_name, item.id])
	elif old_path != desired_path:
		# Name changed — save to new path, then delete old file
		file_path = desired_path
		if ResourceLoader.exists(file_path) and file_path != old_path:
			file_path = dir_path.path_join("%s_%d.tres" % [desired_name, item.id])
	else:
		# No name change — re-save in place
		file_path = old_path

	var err := ResourceSaver.save(item, file_path)
	if err != OK:
		push_error("[ResourceStorageAdapter] Failed to save instance: %s (Error: %d)" % [file_path, err])
		return err

	# If we saved to a new path, delete the old file
	if not old_path.is_empty() and old_path != file_path:
		DirAccess.remove_absolute(old_path)

	return OK


func load_instances(table_name: String, base_path: String) -> Array[DataItem]:
	var dir_path := _instances_dir(table_name, base_path)
	var items: Array[DataItem] = []

	if not DirAccess.dir_exists_absolute(dir_path):
		return items

	var dir := DirAccess.open(dir_path)
	if dir == null:
		return items

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var file_path := dir_path.path_join(file_name)
			var res = ResourceLoader.load(file_path, "", ResourceLoader.CACHE_MODE_REUSE)
			if res is DataItem:
				items.append(res)
		file_name = dir.get_next()
	dir.list_dir_end()

	return items


func delete_instance(item: DataItem, table_name: String, base_path: String) -> Error:
	var file_path := item.resource_path
	if file_path.is_empty():
		# Try to find it by name
		var dir_path := _instances_dir(table_name, base_path)
		file_path = dir_path.path_join("%s.tres" % _sanitize_filename(item.name))

	if not FileAccess.file_exists(file_path):
		return ERR_FILE_NOT_FOUND

	return DirAccess.remove_absolute(file_path)


func rename_instance_file(item: DataItem, old_name: String, table_name: String, base_path: String) -> Error:
	var dir_path := _instances_dir(table_name, base_path)
	var old_file := dir_path.path_join("%s.tres" % _sanitize_filename(old_name))
	var new_file := dir_path.path_join("%s.tres" % _sanitize_filename(item.name))

	if old_file == new_file:
		return OK
	if not FileAccess.file_exists(old_file):
		return ERR_FILE_NOT_FOUND

	# Save to new path, then delete old
	var err := ResourceSaver.save(item, new_file)
	if err != OK:
		return err
	return DirAccess.remove_absolute(old_file)


func delete_table_instances_dir(table_name: String, base_path: String) -> Error:
	var dir_path := _instances_dir(table_name, base_path)
	if not DirAccess.dir_exists_absolute(dir_path):
		return OK

	# Delete all files in the directory first
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return DirAccess.get_open_error()

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir():
			DirAccess.remove_absolute(dir_path.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()

	return DirAccess.remove_absolute(dir_path)


## Get the instances directory path for a table
func _instances_dir(table_name: String, base_path: String) -> String:
	return base_path.path_join("instances/").path_join(table_name.to_lower())


## Convert a name to a safe filename: snake_case, strip special chars
func _sanitize_filename(name_str: String) -> String:
	var result := name_str.strip_edges().to_lower()
	result = result.replace(" ", "_")
	result = result.replace("-", "_")
	var sanitized := ""
	for i in range(result.length()):
		var c := result[i]
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_":
			sanitized += c
	# Collapse multiple underscores
	while sanitized.contains("__"):
		sanitized = sanitized.replace("__", "_")
	if sanitized.is_empty():
		sanitized = "unnamed"
	return sanitized
