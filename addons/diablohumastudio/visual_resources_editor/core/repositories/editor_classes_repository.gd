@tool
class_name EditorClassesRepository
extends IClassesRepository


func _init() -> void:
	_rebuild_maps()


func rebuild() -> void:
	var previous_classes: Array[String] = class_name_list.duplicate()
	_rebuild_maps()
	updated.emit()

	if previous_classes == class_name_list:
		_check_property_changes()
		return

	_handle_orphans(previous_classes)
	class_list_changed.emit(class_name_list)


func resolve_included_classes(base_class: String, include_subclasses: bool) -> Array[String]:
	if include_subclasses:
		return ProjectScanner.get_descendant_classes(base_class, class_to_parent_map)
	return [base_class]


func scan_properties(base_class: String, included_classes: Array[String]) -> void:
	current_class_script = get_class_script(base_class)
	included_class_property_lists = ProjectScanner.get_properties_from_script_names(included_classes)
	var empty_props: Array[ResourceProperty] = []
	current_class_property_list = included_class_property_lists.get(base_class, empty_props)
	shared_property_list = ProjectScanner.unite_classes_properties(included_classes, class_to_path_map)


func get_class_script(class_name_str: String) -> GDScript:
	var path: String = class_to_path_map.get(class_name_str, "")
	if not path.is_empty():
		return load(path)
	return null


# ── Private ────────────────────────────────────────────────────────────────────

func _rebuild_maps() -> void:
	global_class_map = ProjectScanner.build_global_classes_map()
	class_to_parent_map = ProjectScanner.build_project_classes_parent_map(global_class_map)
	class_to_path_map = ProjectScanner.build_class_to_path_map(global_class_map)
	class_name_list = ProjectScanner.get_project_resource_classes(global_class_map)


func _check_property_changes() -> void:
	_property_list_changed.emit()


func _handle_orphans(previous_classes: Array[String]) -> void:
	var removed_classes: Array[String] = []
	for cls: String in previous_classes:
		if not class_name_list.has(cls):
			removed_classes.append(cls)
	if removed_classes.is_empty():
		return
	var orphaned: Array[Resource] = ProjectScanner.load_classed_resources_from_dir(removed_classes)
	if not orphaned.is_empty():
		orphaned_resources_found.emit(orphaned)
