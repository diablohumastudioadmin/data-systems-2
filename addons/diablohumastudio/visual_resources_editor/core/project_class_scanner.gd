@tool
class_name ProjectClassScanner

static func get_project_resource_classes(global_class_map: Array[Dictionary] = []) -> Array[String]:
	if global_class_map.is_empty():
		global_class_map = build_global_classes_map()
	var classes_parent_map: Dictionary[String, String] = build_project_classes_parent_map(global_class_map)

	var resource_classes: Array[String]
	for entry: Dictionary in global_class_map:
		var cls_name: String = entry.get("class", "")
		var cls_path: String = entry.get("path", "")

		if cls_name.is_empty() or cls_path.is_empty() or cls_path.contains("addons/"):
			continue

		if class_is_resource_descendant(cls_name, classes_parent_map):
			resource_classes.append(cls_name)
	return resource_classes

static func build_global_classes_map() -> Array[Dictionary]:
	return ProjectSettings.get_global_class_list()

static func build_class_to_path_map(global_class_map: Array[Dictionary] = []) -> Dictionary[String, String]:
	if global_class_map.is_empty(): global_class_map = build_global_classes_map()

	var global_class_to_path_map: Dictionary[String, String]
	for entry: Dictionary in global_class_map:
		var cls: String = entry.get("class", "")
		var path: String = entry.get("path", "")
		if not cls.is_empty() and not path.is_empty():
			global_class_to_path_map[cls] = path
	return global_class_to_path_map

static func build_project_classes_parent_map(global_class_map: Array[Dictionary] = []) -> Dictionary[String, String]:
	if global_class_map.is_empty(): global_class_map = build_global_classes_map()

	var classes_parent_map: Dictionary[String, String] = {}
	for entry: Dictionary in global_class_map:
		var cls: String = entry.get("class", "")
		if cls.is_empty(): continue
		var base: String = entry.get("base", "")
		classes_parent_map[cls] = base
	return classes_parent_map


static func class_is_resource_descendant(cls_name: String, classes_parent_map: Dictionary[String,String]  = {}) -> bool:
	if classes_parent_map.is_empty():
		classes_parent_map = build_project_classes_parent_map()

	var base: String = classes_parent_map.get(cls_name, "")
	if base.is_empty():
		return false
	elif base == "Resource":
		return true
	elif ClassDB.class_exists(base): # if base hits a native class checks directly (not recursive) what is_parent_class
		return ClassDB.is_parent_class(base, "Resource")
	else:
		return class_is_resource_descendant(base, classes_parent_map)


static func get_descendant_classes(
	base_class: String, classes_parent_map: Dictionary[String, String] = {}, include_base: bool = true
) -> Array[String]:

	if classes_parent_map.is_empty():
		classes_parent_map = build_project_classes_parent_map()

	var descendants: Array[String] = [base_class] as Array[String] if include_base else Array([], TYPE_STRING, "", null)
	for cls: String in classes_parent_map:
		if classes_parent_map[cls] == base_class:
			descendants.append(cls)
			descendants.append_array(get_descendant_classes(cls, classes_parent_map))
	return descendants


static func scan_folder_for_classed_tres_paths(
	classes: Array[String], dir: EditorFileSystemDirectory = EditorInterface.get_resource_filesystem().get_filesystem()) -> Array[String]:

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

static func get_properties_from_script_names(cls_names: Array[String], global_class_to_path_map: Dictionary[String, String] = {}) ->Dictionary:
	var property_lists: Dictionary = {}
	for cls_name: String in cls_names:
		property_lists[cls_name] = ProjectClassScanner.get_properties_from_script_name(cls_name, global_class_to_path_map)
	return property_lists

static func get_properties_from_script_name(cls_name: String, global_class_to_path_map: Dictionary[String, String] = {}) -> Array[ResourceProperty]:
	
	if global_class_to_path_map.is_empty():
		global_class_to_path_map = build_class_to_path_map()

	var script_path: String = global_class_to_path_map.get(cls_name, "")
	if not script_path.is_empty():
		return ProjectClassScanner.get_properties_from_script_path(script_path)
	else:
		push_warning("Script name doesnt correspond to any path. Returning empty properties")
		return []

static func get_properties_from_script_path(script_path: String) -> Array[ResourceProperty]:
	var properties: Array[ResourceProperty] = []
	if script_path.is_empty():
		return properties

	var script: GDScript = load(script_path)
	if script == null:
		return properties

	for prop: Dictionary in script.get_script_property_list():
		if not (prop.usage & PROPERTY_USAGE_EDITOR):
			continue
		var prop_name: String = prop.name
		if prop_name.begins_with("resource_") or prop_name.begins_with("metadata/"):
			continue
		if prop_name in ["script", "resource_local_to_scene"]:
			continue
		properties.append(ResourceProperty.new(
			prop_name,
			prop.type,
			prop.get("hint", PROPERTY_HINT_NONE),
			prop.get("hint_string", ""),
		))

	return properties


static func unite_classes_properties(
	class_names: Array[String], class_to_path: Dictionary[String, String] = {}
) -> Array[ResourceProperty]:
	var properties: Array[ResourceProperty] = []
	var seen_names: Dictionary[String, bool] = {}
	for cls_name: String in class_names:
		var script_path: String = class_to_path.get(cls_name, "")
		if script_path.is_empty():
			continue
		for prop: ResourceProperty in get_properties_from_script_path(script_path):
			if not seen_names.has(prop.name):
				seen_names[prop.name] = true
				properties.append(prop)
	return properties


static func load_classed_resources_from_dir(
	classes: Array[String], dir: EditorFileSystemDirectory = EditorInterface.get_resource_filesystem().get_filesystem()
	) -> Array[Resource]:

	if dir == null or not is_instance_valid(dir):
		push_warning("ProjectScaner: filesystem directory is not valid, skipping resource scan.")
		return []

	var paths: Array[String] = ProjectClassScanner.scan_folder_for_classed_tres_paths(classes, dir)
	paths.sort()
	var resources: Array[Resource] = []
	for path: String in paths:
		var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
		if res:
			resources.append(res)
	return resources
