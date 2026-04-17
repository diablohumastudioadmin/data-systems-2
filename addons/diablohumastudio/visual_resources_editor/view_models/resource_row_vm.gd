@tool
class_name ResourceRowVM
extends RefCounted

signal is_selected_changed(is_selected: bool)

var resource: Resource
var _model: VREModel

func _init(p_resource: Resource, p_model: VREModel) -> void:
	resource = p_resource
	_model = p_model
	_model.selection_changed.connect(_on_selection_changed)

func get_property_value(property_name: String) -> Variant:
	if resource == null:
		return null
	return resource.get(property_name)

func is_selected() -> bool:
	return _model.session.selected_paths.has(resource.resource_path)

func select(ctrl_held: bool = false, shift_held: bool = false) -> void:
	_model.set_selected_by_path(resource.resource_path, ctrl_held, shift_held)

func request_delete() -> void:
	_model.request_delete_selected_resources([resource.resource_path])

func _on_selection_changed(paths: Array[String]) -> void:
	is_selected_changed.emit(paths.has(resource.resource_path))


func dispose() -> void:
	if _model and _model.selection_changed.is_connected(_on_selection_changed):
		_model.selection_changed.disconnect(_on_selection_changed)
