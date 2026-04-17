@tool
class_name ToolbarVM
extends RefCounted

signal actions_availability_changed()

var _model: VREModel

func _init(p_model: VREModel) -> void:
	_model = p_model
	_model.selection_changed.connect(_on_selection_changed)
	_model.session.selected_class_changed.connect(_on_class_changed)

func _on_selection_changed(_paths: Array[String]) -> void:
	actions_availability_changed.emit()

func _on_class_changed(_class_name_: String) -> void:
	actions_availability_changed.emit()

func get_selected_count() -> int:
	return _model.session.selected_paths.size()

func is_delete_enabled() -> bool:
	return _model.session.selected_paths.size() > 0

func is_create_enabled() -> bool:
	return not _model.session.selected_class.is_empty()

func is_refresh_enabled() -> bool:
	return not _model.session.selected_class.is_empty()

func request_create() -> void:
	_model.request_create_new_resource()

func request_delete() -> void:
	_model.request_delete_selected_resources(_model.session.selected_paths.duplicate())

func request_refresh() -> void:
	_model.refresh_resource_list_values()
