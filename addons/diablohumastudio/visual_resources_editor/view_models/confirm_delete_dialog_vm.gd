@tool
class_name ConfirmDeleteDialogVM
extends RefCounted

signal pending_deletions_changed(paths: Array[String])

var _resource_repo: ResourceRepository
var _pending_deletions: Array[String] = []


func _init(p_resource_repo: ResourceRepository, toolbar_vm: ToolbarVM) -> void:
	_resource_repo = p_resource_repo
	toolbar_vm.delete_requested.connect(_on_delete_requested)


func bind_resource_list(resource_list_vm: ResourceListVM) -> void:
	resource_list_vm.delete_requested.connect(_on_delete_requested)


func _on_delete_requested(paths: Array[String]) -> void:
	_pending_deletions = paths
	pending_deletions_changed.emit(paths)


func get_pending_deletions() -> Array[String]:
	return _pending_deletions


func delete(paths: Array[String]) -> void:
	_resource_repo.delete(paths)
