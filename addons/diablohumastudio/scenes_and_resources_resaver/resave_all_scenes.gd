@tool
class_name ScenesResaver
extends EditorScript

## Script to resave all .tscn files in the project
## This updates them to the current Godot version format
## Run this from: File → Run (in the script editor)

func _run() -> void:
	resave_all_scenes_in_project()

static func resave_all_scenes_in_project():
	var all_project_scene_paths = _get_scene_paths_from_dir("res://")
	_resave_scenes(all_project_scene_paths)

static func _resave_scenes(_scene_paths: Array[String]):
	print("=== Starting scene resave process ===")
	print("Found ", _scene_paths.size(), " scene files")

	var count = 0
	for scene_path in _scene_paths:
		if _resave_scene(scene_path):
			count += 1
			print("[", count, "/", _scene_paths.size(), "] Resaved: ", scene_path)
		else:
			print("[SKIP] ", scene_path)

	print("=== Completed! Resaved ", count, " scenes ===")

static func _get_scene_paths_from_dir(_path_dir) -> Array[String]:
	var files: Array[String] = []
	var dir = DirAccess.open(_path_dir)

	if dir == null:
		return files

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		var full_path = _path_dir + "/" + file_name if _path_dir != "res://" else _path_dir + file_name

		# Skip hidden folders and addons
		if file_name.begins_with("."):
			file_name = dir.get_next()
			continue

		if dir.current_is_dir():
			# Recursively search subdirectories
			files.append_array(_get_scene_paths_from_dir(full_path))
		elif file_name.ends_with(".tscn"):
			files.append(full_path)

		file_name = dir.get_next()

	return files

static func _resave_scene(scene_path: String) -> bool:
	# Load the scene
	var packed_scene = load(scene_path) as PackedScene
	if packed_scene == null:
		push_error("Failed to load: " + scene_path)
		return false

	# Resave it
	var error = ResourceSaver.save(packed_scene, scene_path)
	if error != OK:
		push_error("Failed to save: " + scene_path)
		return false

	return true
