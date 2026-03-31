@tool
extends HBoxContainer

const PLACEHOLDER_TEXT: String = "-- Select a class --"

var state_manager: VREStateManager = null:
	set(value):
		state_manager = value
		if is_node_ready():
			_connect_state()


func _ready() -> void:
	if state_manager:
		_connect_state()


func _connect_state() -> void:
	state_manager.project_classes_changed.connect(set_classes_in_dropdown)
	state_manager.current_class_renamed.connect(select_class)
	set_classes_in_dropdown(state_manager.global_class_name_list)


func set_classes_in_dropdown(classes: Array[String]) -> void:
	var selected_text: String = ""
	if %ClassDropdown.selected > 0:
		selected_text = %ClassDropdown.get_item_text(%ClassDropdown.selected)

	%ClassDropdown.clear()
	%ClassDropdown.add_item(PLACEHOLDER_TEXT, 0)

	var sorted: Array[String] = classes.duplicate()
	sorted.sort_custom(func(a: String, b: String) -> bool: return a.nocasecmp_to(b) < 0)

	for i: int in sorted.size():
		%ClassDropdown.add_item(sorted[i], i + 1)

	if not selected_text.is_empty():
		select_class(selected_text)


func select_class(class_name_str: String) -> void:
	for i: int in %ClassDropdown.item_count:
		if %ClassDropdown.get_item_text(i) == class_name_str:
			%ClassDropdown.select(i)
			return


func _on_class_dropdown_item_selected(index: int) -> void:
	if index == 0: return
	state_manager.set_current_class(%ClassDropdown.get_item_text(index))
