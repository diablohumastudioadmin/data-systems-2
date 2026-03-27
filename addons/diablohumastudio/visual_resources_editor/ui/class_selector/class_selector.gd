@tool
extends HBoxContainer

signal class_selected(class_name_str: String)
signal include_subclasses_toggled(pressed: bool)

const PLACEHOLDER_TEXT: String = "-- Select a class --"

var _classes_names: Array[String] = []


func _ready() -> void:
	set_classes_in_dropdown()


func initialize(state: VREStateManager) -> void:
	class_selected.connect(state.set_current_class)
	include_subclasses_toggled.connect(state.set_include_subclasses)
	state.project_classes_changed.connect(set_classes)
	state.current_class_renamed.connect(select_class)
	set_classes(state.classes_repo.class_name_list)


func set_classes_in_dropdown() -> void:
	var selected_index: int = %ClassDropdown.selected
	var selected_text: String = %ClassDropdown.get_item_text(selected_index) if selected_index > 0 else ""

	%ClassDropdown.clear()
	%ClassDropdown.add_item(PLACEHOLDER_TEXT, 0)

	_classes_names.sort_custom(func(a: String, b: String): return a.nocasecmp_to(b) < 0)

	for i: int in _classes_names.size():
		%ClassDropdown.add_item(_classes_names[i], i + 1)

	if not selected_text.is_empty():
		var new_index: int = _classes_names.find(selected_text)
		if new_index != -1:
			%ClassDropdown.select(new_index + 1)


func set_classes(classes: Array[String]) -> void:
	_classes_names = classes
	if is_node_ready():
		set_classes_in_dropdown()


func select_class(class_name_str: String) -> void:
	var index: int = _classes_names.find(class_name_str)
	if index != -1:
		%ClassDropdown.select(index + 1)


func _on_class_dropdown_item_selected(index: int) -> void:
	if index == 0: return
	var class_name_index: int = index - 1
	if class_name_index >= 0 and class_name_index < _classes_names.size():
		var _class_name: String = _classes_names[class_name_index]
		class_selected.emit(_class_name)


func _on_include_subclasses_toggled(pressed: bool) -> void:
	%SubclassWarningLabel.visible = pressed
	include_subclasses_toggled.emit(pressed)
