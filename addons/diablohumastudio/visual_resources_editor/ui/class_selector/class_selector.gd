@tool
extends HBoxContainer

signal class_selected(class_name_str: String, script_path: String)

## Cached list of {name: String, path: String} for all user Resource classes.
var _all_classes: Array[Dictionary] = []
var _filtered_classes: Array[Dictionary] = []


func _ready() -> void:
	%SearchField.text_changed.connect(_on_search_text_changed)
	%SearchField.text_submitted.connect(_on_search_submitted)
	%ClassList.id_pressed.connect(_on_class_list_id_pressed)
	_gather_classes()


func _gather_classes() -> void:
	_all_classes.clear()
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		var cls_name: String = entry.get("class", "")
		var cls_path: String = entry.get("path", "")
		if cls_name.is_empty() or cls_path.is_empty():
			continue
		if _is_resource_descendant(entry):
			_all_classes.append({"name": cls_name, "path": cls_path})
	_all_classes.sort_custom(func(a, b): return a.name.nocasecmp_to(b.name) < 0)


func _is_resource_descendant(entry: Dictionary) -> bool:
	## Walk the base chain to check if this class ultimately extends Resource.
	var base: String = entry.get("base", "")
	var visited: Dictionary = {}
	while not base.is_empty() and base not in visited:
		visited[base] = true
		if base == "Resource":
			return true
		# Check if base is a built-in class
		if ClassDB.class_exists(base):
			return ClassDB.is_parent_class(base, "Resource")
		# Otherwise look for it in the global class list
		var found: bool = false
		for other: Dictionary in ProjectSettings.get_global_class_list():
			if other.get("class", "") == base:
				base = other.get("base", "")
				found = true
				break
		if not found:
			break
	return false


func refresh_classes() -> void:
	_gather_classes()


func _on_search_text_changed(query: String) -> void:
	_filtered_classes.clear()
	var lower_query: String = query.to_lower()

	if lower_query.is_empty():
		%ClassList.clear()
		%ClassList.hide()
		return

	for entry: Dictionary in _all_classes:
		if entry.name.to_lower().contains(lower_query):
			_filtered_classes.append(entry)

	_show_popup()


func _on_search_submitted(_text: String) -> void:
	if _filtered_classes.size() > 0:
		_select_class(_filtered_classes[0])


func _on_class_list_id_pressed(id: int) -> void:
	if id >= 0 and id < _filtered_classes.size():
		_select_class(_filtered_classes[id])


func _select_class(entry: Dictionary) -> void:
	%SearchField.text = entry.name
	%ClassList.hide()
	class_selected.emit(entry.name, entry.path)


func _show_popup() -> void:
	%ClassList.clear()
	for i in range(_filtered_classes.size()):
		%ClassList.add_item(_filtered_classes[i].name, i)

	if _filtered_classes.is_empty():
		%ClassList.hide()
		return

	var global_pos: Vector2 = %SearchField.global_position
	var field_size: Vector2 = %SearchField.size
	%ClassList.position = Vector2i(int(global_pos.x), int(global_pos.y + field_size.y))
	%ClassList.size = Vector2i(int(field_size.x), min(_filtered_classes.size() * 28, 300))
	%ClassList.show()
