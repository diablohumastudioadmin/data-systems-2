@tool
class_name ToolbarVM
extends RefCounted

signal actions_availability_changed()

var _model: VREModel

func _init(p_model: VREModel) -> void:
	_model = p_model
	_model.selection_changed.connect(_on_selection_changed)
	_model.session.selected_class_changed.connect(_on_class_changed)

func _on_selection_changed(_resources: Array[Resource]) -> void:
	actions_availability_changed.emit()

func _on_class_changed(_class_name_: String) -> void:
	actions_availability_changed.emit()

func is_delete_enabled() -> bool:
	return _model.session.selected_resources.size() > 0

func is_create_enabled() -> bool:
	return not _model.session.selected_class.is_empty()

func is_refresh_enabled() -> bool:
	return not _model.session.selected_class.is_empty()

func request_create() -> void:
	_model.request_create_new_resouce()

func request_delete() -> void:
	var paths: Array[String] = []
	for res in _model.session.selected_resources:
		paths.append(res.resource_path)
	_model.request_delete_selected_resources(paths)

func request_refresh() -> void:
	_model.refresh_resource_list_values()
