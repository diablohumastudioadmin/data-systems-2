@tool
extends HBoxContainer

signal class_selected(class_name_str: String)

var _classes_names: Array = [] : 
	set(new_value):
		_classes_names = new_value
		if is_node_ready(): 
			set_classes_in_dropdown()


func _ready() -> void:
	set_classes_in_dropdown()


func set_classes_in_dropdown() -> void:
	%ClassDropdown.clear()
	%ClassDropdown.add_item("-- Select a class --", 0)

	_classes_names.sort_custom(func(a: String, b: String): return a.nocasecmp_to(b) < 0)

	for i in range(_classes_names.size()):
		%ClassDropdown.add_item(_classes_names[i], i + 1)


func refresh() -> void:
	set_classes_in_dropdown()


func _on_class_dropdown_item_selected(index: int) -> void:
	if index == 0: return
	var class_name_index: int = index - 1
	if class_name_index >= 0 and class_name_index < _classes_names.size():
		var _class_name: String = _classes_names[class_name_index]
		class_selected.emit(_class_name)
