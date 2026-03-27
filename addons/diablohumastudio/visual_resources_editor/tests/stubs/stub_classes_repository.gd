@tool
class_name StubClassesRepository
extends IClassesRepository


func rebuild() -> void:
	updated.emit()


func resolve_included_classes(base_class: String, include_subclasses: bool) -> Array[String]:
	if not include_subclasses:
		return [base_class]
	var result: Array[String] = [base_class]
	for cls: String in class_to_parent_map:
		if class_to_parent_map[cls] == base_class:
			result.append(cls)
	return result


func scan_properties(_base_class: String, _included_classes: Array[String]) -> void:
	pass


func get_class_script(class_name_str: String) -> GDScript:
	var path: String = class_to_path_map.get(class_name_str, "")
	if not path.is_empty():
		return load(path)
	return null
