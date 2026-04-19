@tool
class_name ToolbarVM
extends RefCounted

signal actions_availability_changed()
signal create_requested()
signal delete_requested(paths: Array[String])
signal refresh_requested()

var _resource_repo: ResourceRepository
var _session: SessionStateModel


func _init(p_resource_repo: ResourceRepository, p_session: SessionStateModel) -> void:
	_resource_repo = p_resource_repo
	_session = p_session
	_session.selected_paths_changed.connect(_on_selection_changed)
	_resource_repo.selected_class_changed.connect(_on_class_changed)


func _on_selection_changed(_paths: Array[String]) -> void:
	actions_availability_changed.emit()


func _on_class_changed(_class_name_: String) -> void:
	actions_availability_changed.emit()


func get_selected_count() -> int:
	return _session.selected_paths.size()


func is_delete_enabled() -> bool:
	return _session.selected_paths.size() > 0


func is_create_enabled() -> bool:
	return not _resource_repo.selected_class.is_empty()


func is_refresh_enabled() -> bool:
	return not _resource_repo.selected_class.is_empty()


func request_create() -> void:
	create_requested.emit()


func request_delete() -> void:
	delete_requested.emit(_session.selected_paths.duplicate())


func request_refresh() -> void:
	refresh_requested.emit()
