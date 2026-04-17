@tool
class_name ClassRegistry
extends RefCounted

## Emitted when the project resource class list changes (names added or removed).
## Not emitted if the list is identical after a rebuild.
signal classes_changed(previous: Array[String], current: Array[String])

var global_class_map: Array[Dictionary] = []
var global_class_to_path_map: Dictionary[String, String] = {}
var global_class_to_parent_map: Dictionary[String, String] = {}
var global_class_name_list: Array[String] = []


## Rebuilds all maps from ProjectSettings.
## Returns true if the class name list changed, false if identical.
## Emits classes_changed only when the list changes.
func rebuild() -> bool:
	var previous: Array[String] = global_class_name_list.duplicate()
	global_class_map = ProjectClassScanner.build_global_classes_map()
	global_class_to_parent_map = ProjectClassScanner.build_project_classes_parent_map(global_class_map)
	global_class_to_path_map = ProjectClassScanner.build_class_to_path_map(global_class_map)
	global_class_name_list = ProjectClassScanner.get_project_resource_classes(global_class_map)
	var changed: bool = previous != global_class_name_list
	if changed:
		classes_changed.emit(previous, global_class_name_list)
	return changed


## Returns the set of class names to include for a given base class.
## If include_subclasses is true, includes all descendant classes.
func get_included_classes(class_name_str: String, include_subclasses: bool) -> Array[String]:
	if class_name_str.is_empty():
		return []
	if include_subclasses:
		return ProjectClassScanner.get_descendant_classes(class_name_str, global_class_to_parent_map)
	return [class_name_str]


## Returns true if any class in included_classes has appeared or disappeared
## compared to previous_classes. Used by the coordinator to decide whether
## the current resource list needs a full reload.
func has_class_set_changed(previous_classes: Array[String], included_classes: Array[String]) -> bool:
	for cls: String in included_classes:
		if not previous_classes.has(cls) or not global_class_name_list.has(cls):
			return true
	return false


## Checks whether any class in the current map maps to old_script_path.
## Returns the new class name if a rename is detected, or "" if the class was deleted.
func detect_rename(old_script_path: String) -> String:
	if old_script_path.is_empty():
		return ""
	for cls: String in global_class_to_path_map:
		if global_class_to_path_map[cls] == old_script_path:
			return cls
	return ""


func get_script_path(class_name_str: String) -> String:
	return global_class_to_path_map.get(class_name_str, "")


func get_class_script(class_name_str: String) -> GDScript:
	var path: String = get_script_path(class_name_str)
	if path.is_empty():
		return null
	return load(path)


## Returns the editor-visible property list for a single class, or [] if not found.
func get_properties(class_name_str: String) -> Array[ResourceProperty]:
	var path: String = get_script_path(class_name_str)
	if path.is_empty():
		var empty: Array[ResourceProperty] = []
		return empty
	return ProjectClassScanner.get_properties_from_script_path(path)


## Returns { class_name: Array[ResourceProperty] } for each class in class_names.
## Classes with no registered script path map to an empty array.
func get_properties_for(class_names: Array[String]) -> Dictionary:
	return ProjectClassScanner.get_properties_from_script_names(
		class_names, global_class_to_path_map)


## Returns the union of editor-visible properties across class_names,
## preserving first-seen order and deduplicating by property name.
func get_shared_properties(class_names: Array[String]) -> Array[ResourceProperty]:
	return ProjectClassScanner.unite_classes_properties(
		class_names, global_class_to_path_map)
