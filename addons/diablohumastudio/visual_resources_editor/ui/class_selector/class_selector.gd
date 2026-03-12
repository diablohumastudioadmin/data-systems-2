@tool
extends HBoxContainer

signal class_selected(class_name_str: String, script_path: String)

var _all_classes: Array[Dictionary] = []


func _ready() -> void:
	%ClassDropdown.item_selected.connect(_on_item_selected)
	set_classes_in_dropdown()


func set_classes_in_dropdown() -> void:
	_all_classes.clear()
	%ClassDropdown.clear()
	%ClassDropdown.add_item("-- Select a class --", 0)

	var parent_map: Dictionary = ProjectClassScanner.build_project_classes_parent_map()

	for entry: Dictionary in ProjectSettings.get_global_class_list():
		var cls_name: String = entry.get("class", "")
		var cls_path: String = entry.get("path", "")
		if cls_name.is_empty() or cls_path.is_empty() or cls_path.contains("addons/"):
			continue
		if ProjectClassScanner.class_is_resource_descendant(cls_name, parent_map):
			_all_classes.append({"name": cls_name, "path": cls_path})

	_all_classes.sort_custom(func(a, b): return a.name.nocasecmp_to(b.name) < 0)

	for i in range(_all_classes.size()):
		%ClassDropdown.add_item(_all_classes[i].name, i + 1)


func refresh() -> void:
	set_classes_in_dropdown()


func _on_item_selected(index: int) -> void:
	if index == 0:
		return
	var entry_index: int = index - 1
	if entry_index >= 0 and entry_index < _all_classes.size():
		var entry: Dictionary = _all_classes[entry_index]
		class_selected.emit(entry.name, entry.path)
