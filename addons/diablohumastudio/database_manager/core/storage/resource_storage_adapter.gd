@tool
class_name ResourceStorageAdapter
extends StorageAdapter

## Per-instance Godot Resource (.tres) storage implementation.
## Each DataItem is saved as an individual file in instances/<table_name>/.

func save_instance(item: DataItem, table_name: String, base_path: String) -> Error:
	if item._is_deleted:
		return OK # Don't save if deleted

	var dir_path := _instances_dir(table_name, base_path)
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	# 1. Calculate the ideal path based on the item's current name
	var desired_name := _sanitize_filename(item.name)
	var desired_path := ProjectSettings.localize_path(dir_path.path_join("%s.tres" % desired_name))
	
	# 2. Get the current physical path of the resource (if any)
	var current_path := ProjectSettings.localize_path(item.resource_path)
	
	var final_path: String = ""
	var is_rename: bool = false
	
	if current_path.is_empty():
		# Case A: New Item (never saved)
		# Check for collision at desired_path
		if FileAccess.file_exists(desired_path):
			# Collision! Append ID to make unique
			final_path = ProjectSettings.localize_path(dir_path.path_join("%s_%d.tres" % [desired_name, item.id]))
		else:
			final_path = desired_path
			
	elif current_path == desired_path:
		# Case B: Saving in place (no name change, no path change)
		final_path = current_path
		
	else:
		# Case C: Rename (current path exists, but differs from desired path)
		is_rename = true
		
		# Does the new desired path exist?
		if FileAccess.file_exists(desired_path):
			# Collision at new name!
			# But wait, is it a collision with ITSELF? (e.g. case change on Windows)
			var current_global := ProjectSettings.globalize_path(current_path).to_lower()
			var desired_global := ProjectSettings.globalize_path(desired_path).to_lower()
			
			if current_global == desired_global:
				# It's the same file, just casing changed. Treat as in-place save.
				final_path = desired_path # Update casing
				is_rename = false # Not a "move" operation
			else:
				# Real collision with another file. Append ID.
				final_path = ProjectSettings.localize_path(dir_path.path_join("%s_%d.tres" % [desired_name, item.id]))
		else:
			final_path = desired_path

	# 3. Save the resource to the determined final_path
	var err := ResourceSaver.save(item, final_path)
	if err != OK:
		push_error("[ResourceStorageAdapter] Failed to save instance: %s (Error: %d)" % [final_path, err])
		return err
	
	# 4. CRITICAL: Force the resource to acknowledge its new path immediately.
	# This prevents the "new file" logic from triggering on the next save.
	item.take_over_path(final_path)

	# 5. Handle cleanup if it was a rename
	if is_rename and not current_path.is_empty():
		if FileAccess.file_exists(current_path):
			var err_del := DirAccess.remove_absolute(current_path)
			if err_del != OK:
				push_warning("[ResourceStorageAdapter] Failed to delete old instance file: %s (Error: %d)" % [current_path, err_del])

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
	var file_path := ProjectSettings.localize_path(item.resource_path)
	if file_path.is_empty():
		# Try to find it by name
		var dir_path := _instances_dir(table_name, base_path)
		file_path = ProjectSettings.localize_path(dir_path.path_join("%s.tres" % _sanitize_filename(item.name)))

	if not FileAccess.file_exists(file_path):
		return ERR_FILE_NOT_FOUND

	var err := DirAccess.remove_absolute(file_path)
	if err != OK:
		push_warning("[ResourceStorageAdapter] Failed to delete instance file: %s (Error: %d)" % [file_path, err])
	return err


func rename_instance_file(item: DataItem, old_name: String, table_name: String, base_path: String) -> Error:
	# This might be redundant now that save_instance handles renames intelligently,
	# but we keep it for the interface contract.
	# The logic is effectively covered by save_instance(item...) if called with the new name.
	return save_instance(item, table_name, base_path)


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
