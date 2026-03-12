@tool
class_name ProjectClassScanner

static func get_resource_classes_in_folder(included_folder_paths: Array[String], excluded_folder_paths: Array[String]) -> Array[Dictionary]:
	var resource_classes: Array[Dictionary]
	var parent_map: Dictionary = build_project_classes_parent_map()

	for entry: Dictionary in ProjectSettings.get_global_class_list():
		var cls_name: String = entry.get("class", "")
		var cls_path: String = entry.get("path", "")

		if cls_name.is_empty() or cls_path.is_empty() or cls_path.contains("addons/"):
			continue

		if class_is_resource_descendant(cls_name, parent_map):
			resource_classes.append({"name": cls_name, "path": cls_path})
	return resource_classes


static func build_project_classes_parent_map() -> Dictionary:
	var map: Dictionary = {}
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		var cls: String = entry.get("class", "")
		if cls.is_empty(): continue
		var base: String = entry.get("base", "")
		map[cls] = base
	return map


static func class_is_resource_descendant(cls_name: String, classes_parent_map: Dictionary = {}) -> bool:
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
	base_class: String, classes_parent_map: Dictionary = {}
) -> Array[String]:
	if classes_parent_map.is_empty():
		classes_parent_map = build_project_classes_parent_map()

	var descendants: Array[String] = []
	for cls: String in classes_parent_map:
		if classes_parent_map[cls] == base_class:
			descendants.append(cls)
			descendants.append_array(get_descendant_classes(cls, classes_parent_map))
	return descendants


static func scan_folder_for_classed_tres(
	dir: EditorFileSystemDirectory, classes: Array) -> Array[String]:

	var results: Array[String]
	if dir == null:
		return []

	if dir.get_path() == "res://addons/":
		return []

	for i in range(dir.get_file_count()):
		var path: String = dir.get_file_path(i)
		if not path.ends_with(".tres"):
			continue
		var cls: String = get_class_from_tres_file(path)
		if classes.has(cls):
			results.append(path)

	for i in range(dir.get_subdir_count()):
		results.append_array(scan_folder_for_classed_tres(dir.get_subdir(i), classes))

	return results


static func get_class_from_tres_file(tres_file_path: String) -> String:
	var loaded_resource: Resource = ResourceLoader.load(tres_file_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if loaded_resource == null: return ""
	var resource_script: Script = loaded_resource.get_script()
	if resource_script == null: return ""
	return resource_script.get_global_name()


static func get_properties_from_script_path(script_path: String) -> Array[Dictionary]:
	var properties: Array[Dictionary] = []
	if script_path.is_empty():
		return properties

	var script: GDScript = load(script_path)
	if script == null:
		return properties

	for prop: Dictionary in script.get_script_property_list():
		if not (prop.usage & PROPERTY_USAGE_EDITOR):
			continue
		var prop_name: String = prop.name
		print(prop_name)
		if prop_name.begins_with("resource_") or prop_name.begins_with("metadata/"):
			continue
		if prop_name in ["script", "resource_local_to_scene"]:
			continue
		properties.append({
			"name": prop_name,
			"type": prop.type,
			"hint": prop.get("hint", PROPERTY_HINT_NONE),
			"hint_string": prop.get("hint_string", ""),
		})

	return properties
