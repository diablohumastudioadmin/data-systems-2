@tool
class_name DH_VRE_ResourceClassMap
extends RefCounted

signal classes_changed(previous: Array[String], current: Array[String])

var names: Array[String] = []
var to_path: Dictionary[String, String] = {}
var to_parent: Dictionary[String, String] = {}


## Rebuilds all maps from ProjectSettings (Resource subclasses only).
## Returns true if the class name list changed. Emits classes_changed only when the list changes.
func rebuild() -> bool:
	var entries: Array[Dictionary] = _resource_entries()
	var previous: Array[String] = names.duplicate()
	names = []
	for e: Dictionary in entries:
		var cls: String = e.get("class", "")
		if not cls.is_empty():
			names.append(cls)
	to_path = _build_to_path(entries)
	to_parent = _build_to_parent(entries)
	var changed: bool = previous != names
	if changed:
		classes_changed.emit(previous, names)
	return changed


func get_descendant_classes(base_class: String, include_subclasses: bool = true, include_base: bool = true) -> Array[String]:
	if base_class.is_empty():
		return []
	var returned_array: Array[String] = Array([], TYPE_STRING, "", null) 
	if include_base: 
		returned_array.append(base_class)
	if include_subclasses:
		for cls: String in to_parent:
			if to_parent[cls] == base_class:
				returned_array.append(cls)
				returned_array.append_array(get_descendant_classes(cls))
	return returned_array


func get_class_name_from_path(script_path: String) -> String:
	if script_path.is_empty():
		return ""
	for cls: String in to_path:
		if to_path[cls] == script_path:
			return cls
	return ""


func get_script_path_from_class_name(class_name_str: String) -> String:
	return to_path.get(class_name_str, "")


func get_script_from_class_name(class_name_str: String) -> GDScript:
	var path: String = get_script_path_from_class_name(class_name_str)
	if path.is_empty():
		return null
	return load(path)

func get_properties_from_class_names(
		cls_names: Array[String],
		global_class_to_path_map: Dictionary[String, String] = {}) -> Dictionary:
	var property_lists: Dictionary = {}
	for cls_name: String in cls_names:
		property_lists[cls_name] = get_properties_from_class_name(cls_name)
	return property_lists


func get_properties_from_class_name(class_name_str: String) -> Array[DH_VRE_ResourceProperty]:
	var path: String = get_script_path_from_class_name(class_name_str)
	if path.is_empty():
		return Array([],TYPE_OBJECT, "RefCounted", DH_VRE_ResourceProperty)
	return get_properties_from_script_path(path)


func get_shared_properties(class_names: Array[String]) -> Array[DH_VRE_ResourceProperty]:
	var properties: Array[DH_VRE_ResourceProperty] = []
	var seen_names: Dictionary[String, bool] = {}
	for cls_name: String in class_names:
		var script_path: String = to_path.get(cls_name, "")
		if script_path.is_empty():
			continue
		for prop: DH_VRE_ResourceProperty in get_properties_from_script_path(script_path):
			if not seen_names.has(prop.name):
				seen_names[prop.name] = true
				properties.append(prop)
	return properties


func get_properties_from_script_path(script_path: String) -> Array[DH_VRE_ResourceProperty]:
	var properties: Array[DH_VRE_ResourceProperty] = []
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
		properties.append(DH_VRE_ResourceProperty.new(
			prop_name,
			prop.type,
			prop.get("hint", PROPERTY_HINT_NONE),
			prop.get("hint_string", ""),
		))

	return properties

# --- private ---

static func _resource_entries() -> Array[Dictionary]:
	var all: Array[Dictionary] = ProjectSettings.get_global_class_list()
	var all_to_parent: Dictionary[String, String] = _build_to_parent(all)
	var result: Array[Dictionary] = []
	for e: Dictionary in all:
		var cls: String = e.get("class", "")
		var path: String = e.get("path", "")
		if cls.is_empty() or path.is_empty() or path.contains("addons/"):
			continue
		if _is_resource_descendant(cls, all_to_parent):
			result.append(e)
	return result


static func _build_to_path(entries: Array[Dictionary]) -> Dictionary[String, String]:
	var map: Dictionary[String, String] = {}
	for e: Dictionary in entries:
		var cls: String = e.get("class", "")
		var path: String = e.get("path", "")
		if not cls.is_empty() and not path.is_empty():
			map[cls] = path
	return map


static func _build_to_parent(entries: Array[Dictionary]) -> Dictionary[String, String]:
	var map: Dictionary[String, String] = {}
	for e: Dictionary in entries:
		var cls: String = e.get("class", "")
		if cls.is_empty():
			continue
		map[cls] = e.get("base", "")
	return map


static func _is_resource_descendant(cls_name: String, parent_map: Dictionary[String, String]) -> bool:
	var base: String = parent_map.get(cls_name, "")
	if base.is_empty():
		return false
	elif base == "Resource":
		return true
	elif ClassDB.class_exists(base):
		return ClassDB.is_parent_class(base, "Resource")
	else:
		return _is_resource_descendant(base, parent_map)
