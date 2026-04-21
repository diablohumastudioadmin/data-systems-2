@tool
extends HBoxContainer

const HEADER_FIELD_LABEL_SCENE: PackedScene = preload("uid://ufyx2ezw09xlg")
const FIELD_SEPARATOR_SCENE: PackedScene = preload("uid://y2kj6h91hm8r6")

const ARROW_UP: String = " ↑"
const ARROW_DOWN: String = " ↓"

var _vm: DH_VRE_ResourceListVM = null
var _field_buttons: Array[Button] = []
var _column_names: Array[String] = []

var current_shared_property_list: Array[DH_VRE_ResourceProperty] = []:
	set(value):
		current_shared_property_list = value
		if is_inside_tree():
			_rebuild_labels()


func set_view_model(vm: DH_VRE_ResourceListVM) -> void:
	_vm = vm
	%FileLabel.pressed.connect(func() -> void: _vm.request_sort(""))
	_vm.sort_state_changed.connect(_on_sort_state_changed)
	_update_sort_indicators(_vm.sort_column, _vm.sort_ascending)


func _rebuild_labels() -> void:
	_field_buttons.clear()
	_column_names.clear()

	for child: Node in %FieldsContainer.get_children():
		child.queue_free()

	for i: int in current_shared_property_list.size():
		if i > 0:
			var sep: VSeparator = FIELD_SEPARATOR_SCENE.instantiate()
			%FieldsContainer.add_child(sep)
		var btn: Button = HEADER_FIELD_LABEL_SCENE.instantiate()
		var col_name: String = current_shared_property_list[i].name
		btn.text = col_name
		%FieldsContainer.add_child(btn)
		_field_buttons.append(btn)
		_column_names.append(col_name)
		if _vm:
			btn.pressed.connect(_vm.request_sort.bind(col_name))

	if _vm:
		_update_sort_indicators(_vm.sort_column, _vm.sort_ascending)


func _on_sort_state_changed(column: String, ascending: bool) -> void:
	_update_sort_indicators(column, ascending)


func _update_sort_indicators(column: String, ascending: bool) -> void:
	var arrow: String = ARROW_UP if ascending else ARROW_DOWN

	# File button
	if column.is_empty():
		%FileLabel.text = "File" + arrow
	else:
		%FileLabel.text = "File"

	# Property buttons
	for i: int in _field_buttons.size():
		var btn: Button = _field_buttons[i]
		if not is_instance_valid(btn):
			continue
		if _column_names[i] == column:
			btn.text = _column_names[i] + arrow
		else:
			btn.text = _column_names[i]
