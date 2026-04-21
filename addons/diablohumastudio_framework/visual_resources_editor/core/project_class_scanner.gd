@tool
class_name DH_VRE_ProjectClassScanner


static func scan_folder_for_classed_tres_paths(
		classes: Array[String],
		dir: EditorFileSystemDirectory = EditorInterface.get_resource_filesystem().get_filesystem()
		) -> Array[String]:

	if dir == null or not is_instance_valid(dir):
		push_warning("ProjectScaner: filesystem directory is not valid, skipping resource scan.")
		return []

	var results: Array[String]
	if dir == null or not is_instance_valid(dir):
		return []

	if dir.get_path() == "res://addons/":
		return []

	for i: int in dir.get_file_count():
		var path: String = dir.get_file_path(i)
		if not path.ends_with(".tres"):
			continue
		var cls: String = get_class_from_tres_file(path)
		if classes.has(cls):
			results.append(path)

	for i: int in dir.get_subdir_count():
		results.append_array(scan_folder_for_classed_tres_paths(classes, dir.get_subdir(i)))

	return results


static func get_class_from_tres_file(tres_file_path: String) -> String:
	var file: FileAccess = FileAccess.open(tres_file_path, FileAccess.READ)
	if file == null: return ""
	var first_line: String = file.get_line()
	var key: String = "script_class=\""
	var start: int = first_line.find(key)
	if start == -1: return ""
	start += key.length()
	var end: int = first_line.find("\"", start)
	if end == -1: return ""
	return first_line.substr(start, end - start)


static func load_classed_resources_from_dir(
	classes: Array[String], dir: EditorFileSystemDirectory = EditorInterface.get_resource_filesystem().get_filesystem()
	) -> Array[Resource]:

	if dir == null or not is_instance_valid(dir):
		push_warning("ProjectScaner: filesystem directory is not valid, skipping resource scan.")
		return []

	var paths: Array[String] = DH_VRE_ProjectClassScanner.scan_folder_for_classed_tres_paths(classes, dir)
	paths.sort()
	var resources: Array[Resource] = []
	for path: String in paths:
		var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
		if res:
			resources.append(res)
	return resources
