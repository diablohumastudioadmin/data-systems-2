@tool
class_name ProjectClassScanner


static func build_project_classes_parent_map() -> Dictionary:
	var map: Dictionary = {}
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		var cls: String = entry.get("class", "")
		if not cls.is_empty():
			map[cls] = entry.get("base", "")
	return map


static func class_is_resource_descendant(cls_name: String, classes_parent_map: Dictionary = {}) -> bool:
	if classes_parent_map.is_empty():
		classes_parent_map = build_project_classes_parent_map()

	var base: String = classes_parent_map.get(cls_name, "")
	if base.is_empty():
		return false
	elif base == "Resource":
		return true
	elif ClassDB.class_exists(base): # if base hits a native class checks directly (not recursive) tiwh is_parent_class
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
	var header: String
	var tres_script_class: String
	var tres_type: String

	var f: FileAccess = FileAccess.open(tres_file_path, FileAccess.READ)
	if f == null:
		return ""
	header = f.get_buffer(500).get_string_from_utf8()
	f.close()

	var sc_idx: int = header.find('script_class="')
	if sc_idx >= 0:
		var start: int = sc_idx + 14
		var end: int = header.find('"', start)
		if end > start:
			tres_script_class = header.substr(start, end - start)

	var t_idx: int = header.find('type="')
	if t_idx >= 0:
		var start: int = t_idx + 6
		var end: int = header.find('"', start)
		if end > start:
			tres_type = header.substr(start, end - start)

	if tres_script_class: return tres_script_class
	if tres_type: return tres_type
	return ""


static func get_properties_from_script_path(script_path: String) -> Array[Dictionary]:
	var properties: Array[Dictionary] = []
	if script_path.is_empty():
		return properties

	var script: GDScript = load(script_path)
	if script == null:
		return properties

	var temp_instance: Resource = script.new()
	if temp_instance == null:
		return properties

	for prop: Dictionary in temp_instance.get_property_list():
		if not (prop.usage & PROPERTY_USAGE_EDITOR):
			continue
		var prop_name: String = prop.name
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
