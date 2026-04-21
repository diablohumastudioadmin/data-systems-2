@tool
class_name ResourceResaver
extends EditorScript

## Script to resave all .tres files in the project
## This updates them to the current Godot version format
## Run this from: File → Run (in the script editor)

func _run():
	resave_all_ressources_in_project()

static func resave_all_ressources_in_project():
	var all_project_resource_paths: Array[String] = _get_resource_file_paths_from_dir("res://")
	_resave_resources(all_project_resource_paths)

static func _resave_resources(resource_paths: Array[String]):
	print("=== Starting resource resave process ===")
	print("Found ", resource_paths.size(), " resource files")

	var count = 0
	for resource_path in resource_paths:
		if _resave_resource(resource_path):
			count += 1
			print("[", count, "/", resource_paths.size(), "] Resaved: ", resource_path)
		else:
			print("[SKIP] ", resource_path)

	print("=== Completed! Resaved ", count, " resources ===")

static func _get_resource_file_paths_from_dir(_dir_path: String) -> Array[String]:
	var file_paths: Array[String] = []
	var dir = DirAccess.open(_dir_path)

	if dir == null:
		return file_paths

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		var full_path = _dir_path + "/" + file_name if _dir_path != "res://" else _dir_path + file_name

		# Skip hidden folders, addons, and .godot
		if file_name.begins_with("."):
			file_name = dir.get_next()
			continue

		# Skip addons folder
		if file_name == "addons":
			file_name = dir.get_next()
			continue

		if dir.current_is_dir():
			# Recursively search subdirectories
			file_paths.append_array(_get_resource_file_paths_from_dir(full_path))
		elif file_name.ends_with(".tres"):
			file_paths.append(full_path)

		file_name = dir.get_next()

	return file_paths

static func _resave_resource(resource_path: String) -> bool:
	# Load the resource
	var resource = load(resource_path)
	if resource == null:
		push_error("Failed to load: " + resource_path)
		return false

	# Resave it 
	var error = ResourceSaver.save(resource, resource_path)
	if error != OK:
		push_error("Failed to save: " + resource_path)
		return false

	return true
