@tool
class_name ToolbarVM
extends RefCounted

signal actions_availability_changed()
signal create_requested()
signal refresh_requested()

var _resource_repo: ResourceRepository
var _selection_manager: SelectionManager


func _init(p_resource_repo: ResourceRepository, p_selection_manager: SelectionManager) -> void:
	_resource_repo = p_resource_repo
	_selection_manager = p_selection_manager
	_selection_manager.selection_changed.connect(_on_selection_changed)
	_resource_repo.selected_class_changed.connect(_on_class_changed)


func _on_selection_changed(_paths: Array[String]) -> void:
	actions_availability_changed.emit()


func _on_class_changed(_class_name_: String) -> void:
	actions_availability_changed.emit()


func get_selected_count() -> int:
	return _selection_manager.selected_paths.size()


func is_delete_enabled() -> bool:
	return _selection_manager.selected_paths.size() > 0


func is_create_enabled() -> bool:
	return not _resource_repo.selected_class.is_empty()


func is_refresh_enabled() -> bool:
	return not _resource_repo.selected_class.is_empty()


func request_create() -> void:
	create_requested.emit()


func request_delete() -> void:
	_resource_repo.request_delete(_selection_manager.selected_paths.duplicate())


func request_refresh() -> void:
	refresh_requested.emit()
