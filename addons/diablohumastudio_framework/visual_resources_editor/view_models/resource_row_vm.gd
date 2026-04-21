@tool
class_name ResourceRowVM
extends RefCounted

signal is_selected_changed(is_selected: bool)

var resource: Resource
var _list_vm: ResourceListVM
var _is_selected: bool = false


func _init(p_resource: Resource, p_list_vm: ResourceListVM) -> void:
	resource = p_resource
	_list_vm = p_list_vm


func get_property_value(property_name: String) -> Variant:
	if resource == null:
		return null
	return resource.get(property_name)


func is_selected() -> bool:
	return _is_selected


func set_selected_state(selected: bool) -> void:
	if _is_selected == selected:
		return
	_is_selected = selected
	is_selected_changed.emit(selected)


func select(ctrl_held: bool = false, shift_held: bool = false) -> void:
	_list_vm.handle_row_click(resource.resource_path, ctrl_held, shift_held)


func request_delete() -> void:
	_list_vm.request_delete([resource.resource_path])
