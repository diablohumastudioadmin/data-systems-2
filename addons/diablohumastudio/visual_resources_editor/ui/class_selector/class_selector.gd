@tool
extends HBoxContainer

const PLACEHOLDER_TEXT: String = "-- Select a class --"

var vm: ClassSelectorVM = null:
	set(value):
		vm = value
		if is_node_ready():
			_connect_vm()


func _ready() -> void:
	if vm:
		_connect_vm()


func _connect_vm() -> void:
	vm.browsable_classes_changed.connect(set_classes_in_dropdown)
	vm.selected_class_changed.connect(select_class)
	set_classes_in_dropdown(vm.get_browsable_classes())


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
	vm.set_selected_class(%ClassDropdown.get_item_text(index))
